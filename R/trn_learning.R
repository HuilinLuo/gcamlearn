#' Map a transportation subsector to its GCAM sector name
#'
#' @param subsector_name Character subsector name, e.g. `"Car"`,
#'   `"Light truck"`.
#' @param sector_map Optional named character vector overriding/extending
#'   the default subsector -> sector mapping. Names are subsectors, values
#'   are sectors.
#'
#' @return The sector name as a single string.
#' @export
get_trn_sector <- function(subsector_name, sector_map = NULL) {
  default_map <- c(
    "Car"           = "trn_pass_road_LDV_4W",
    "Light truck"   = "trn_freight_road",
    "Medium truck"  = "trn_freight_road",
    "Heavy truck"   = "trn_freight_road"
  )
  full_map <- if (is.null(sector_map)) default_map else utils::modifyList(as.list(default_map), as.list(sector_map))
  full_map <- unlist(full_map)

  if (!subsector_name %in% names(full_map)) {
    stop("Unknown subsector: ", subsector_name,
         ". Pass `sector_map` to add it.", call. = FALSE)
  }
  unname(full_map[[subsector_name]])
}

#' Build a transportation learning-by-doing configuration table
#'
#' Each row describes one (subsector, technology) learning-enabled option,
#' e.g. `("Car", "BEV")`. Costs are modeled as a weighted sum of a
#' "learning" share (declines with cumulative deployment at the given
#' learning rate) and a "fixed" share (declines at `non_learning_rate`,
#' typically near zero -- i.e. roughly flat).
#'
#' @param specs A `list` of per-technology specs. Each element must be a
#'   named list with:
#'   \describe{
#'     \item{subsector}{Subsector name, e.g. `"Car"`.}
#'     \item{technology}{Technology name, e.g. `"BEV"`, `"FCEV"`.}
#'     \item{TD_init}{Initial (base-year) cumulative deployment.}
#'     \item{C0}{Base-year non-energy cost.}
#'     \item{fixed_ratio}{Share of cost that does *not* learn (0-1). The
#'       remainder (`1 - fixed_ratio`) is the learning share.}
#'     \item{learning_rate}{Fractional cost reduction per doubling of
#'       cumulative deployment, e.g. `0.19` for a 19% learning rate.}
#'     \item{learning_rate_low}{Optional second (low) learning-rate
#'       scenario; if given, the config includes both `b_high` (from
#'       `learning_rate`) and `b_low` columns.}
#'     \item{non_learning_rate}{Learning rate applied to the fixed share;
#'       defaults to `0.01` (near-flat).}
#'   }
#'
#' @return A [tibble::tibble()] with one row per (subsector, technology),
#'   ready to pass to [run_trn_endo_learning()].
#' @export
build_trn_learning_config <- function(specs) {
  rows <- lapply(specs, function(s) {
    non_learning_rate <- if (is.null(s$non_learning_rate)) 0.01 else s$non_learning_rate
    fixed_ratio <- s$fixed_ratio
    row <- tibble::tibble(
      subsector      = s$subsector,
      technology     = s$technology,
      TD_init        = s$TD_init,
      TD_current     = s$TD_init,
      C0             = s$C0,
      fixed_ratio    = fixed_ratio,
      learn_ratio    = 1 - fixed_ratio,
      b_non_learning = log2(1 - non_learning_rate)
    )
    if (!is.null(s$learning_rate_low)) {
      row$b_high <- log2(1 - s$learning_rate)
      row$b_low  <- log2(1 - s$learning_rate_low)
    } else {
      row$b <- log2(1 - s$learning_rate)
    }
    row
  })
  dplyr::bind_rows(rows)
}

#' Read a transportation learning configuration from CSV
#'
#' Convenience loader for a mapping file (e.g. produced once and reused
#' across scenarios) with the same columns as [build_trn_learning_config()]
#' produces: `subsector`, `technology`, `TD_init`, `TD_current`, `C0`,
#' `fixed_ratio`, `learn_ratio`, `b_non_learning`, and either `b` or both
#' `b_high`/`b_low`.
#'
#' @param path Path to the CSV file.
#' @return A tibble.
#' @export
read_trn_learning_config <- function(path) {
  tibble::as_tibble(utils::read.csv(path, stringsAsFactors = FALSE))
}

#' Update one technology's learning-based cost for the next model period
#'
#' Pulls current-period physical service (output) for `subsector_name` /
#' `tech_name`, updates cumulative deployment, computes the new
#' learning-curve cost, and builds the region-level cost table to write
#' back into GCAM for `next_year`.
#'
#' @param g A `gcamwrapper` session, e.g. from [create_gcam_session()].
#' @param subsector_name,tech_name Subsector and technology to update.
#' @param config_row A single-row slice of a learning config (see
#'   [build_trn_learning_config()]) for this subsector/technology.
#' @param all_cost_data The full technology cost table (as returned by
#'   `gcamwrapper::get_data(g, queries$input_cost)`), used as the join
#'   target/template for the updated rows.
#' @param current_year,next_year The model's current calendar year and the
#'   next period's calendar year (learning costs are written for
#'   `next_year`).
#' @param learning_regions Character vector of GCAM regions to apply the
#'   updated cost to (e.g. [US_regions] for a "local" run, or all regions
#'   for a "global" run).
#' @param queries Query list from [trn_queries()] (or a compatible custom
#'   list).
#' @param b_col Name of the learning-exponent column in `config_row` to use
#'   -- `"b"` for a single-scenario config, or `"b_high"`/`"b_low"` for a
#'   config built with `learning_rate_low`.
#' @param deployment_start_year The calendar year at which `TD_init` (base
#'   deployment) is first added to observed service, rather than
#'   `TD_current`. Defaults to `2021`.
#'
#' @return A list with:
#'   \describe{
#'     \item{service}{Total physical output this period.}
#'     \item{cost}{The newly computed non-energy cost.}
#'     \item{updated_df}{A cost-data slice ready to combine with other
#'       technologies and pass to `gcamwrapper::set_data()`.}
#'     \item{TD_new}{Updated cumulative deployment, to store back into the
#'       learning config for the next iteration.}
#'   }
#' @export
update_trn_tech_cost <- function(g, subsector_name, tech_name, config_row,
                                  all_cost_data, current_year, next_year,
                                  learning_regions,
                                  queries = trn_queries(),
                                  b_col = "b",
                                  deployment_start_year = 2021) {

  service_data <- gcamwrapper::get_data(g, queries$service) %>%
    dplyr::filter(
      .data$subsector == subsector_name,
      .data$technology == tech_name,
      .data$period == current_year,
      .data$year == current_year
    )
  service_this_year <- sum(service_data[["physical-output"]], na.rm = TRUE)

  TD_new <- if (current_year == deployment_start_year) {
    config_row$TD_init + service_this_year
  } else {
    config_row$TD_current + service_this_year
  }

  if (!b_col %in% names(config_row)) {
    stop("config_row has no column '", b_col, "'. Available: ",
         paste(names(config_row), collapse = ", "), call. = FALSE)
  }
  b_used <- config_row[[b_col]]

  cost <- config_row$C0 * config_row$learn_ratio * (TD_new / config_row$TD_init) ^ b_used +
    config_row$C0 * config_row$fixed_ratio * (TD_new / config_row$TD_init) ^ config_row$b_non_learning

  sector_name <- get_trn_sector(subsector_name)

  new_cost_df <- expand.grid(region = learning_regions, stringsAsFactors = FALSE) %>%
    dplyr::mutate(
      sector      = sector_name,
      subsector   = subsector_name,
      technology  = tech_name,
      period      = next_year,
      input       = "non-energy",
      `input-cost` = cost
    )

  updated_df <- all_cost_data %>%
    dplyr::filter(
      .data$period == next_year,
      .data$subsector == subsector_name,
      .data$technology == tech_name
    ) %>%
    dplyr::left_join(
      new_cost_df,
      by = c("region", "sector", "subsector", "technology", "period", "input")
    ) %>%
    dplyr::mutate(`input-cost` = dplyr::coalesce(`input-cost.y`, `input-cost.x`)) %>%
    dplyr::select(names(all_cost_data))

  list(service = service_this_year, cost = cost, updated_df = updated_df, TD_new = TD_new)
}

#' Run transportation endogenous learning to a target year
#'
#' Advances the GCAM session period-by-period; at the end of each period,
#' recomputes learning-curve costs for every (subsector, technology) row in
#' `learning_config` and writes them back into GCAM for the next period.
#'
#' @inheritParams update_trn_tech_cost
#' @param learning_config A learning configuration table, see
#'   [build_trn_learning_config()] / [read_trn_learning_config()]. Updated
#'   in place (a new copy is returned) as `TD_current` advances.
#' @param end_year Calendar year to run through (exclusive of the final
#'   `run_period()` call that reaches it), e.g. `2050`.
#' @param mode `"local"` to apply updated costs only to [US_regions], or
#'   `"global"` to apply to every region present in the cost data.
#' @param update_period_min Only recompute/write costs once
#'   `gcamwrapper::get_current_period(g) >= update_period_min` (skips very
#'   early calibration periods). Defaults to `4`.
#'
#' @return A list with:
#'   \describe{
#'     \item{g}{The (mutated) GCAM session.}
#'     \item{learning_config}{The learning config with final `TD_current`
#'       values.}
#'     \item{tracking}{A tibble with one row per model year and
#'       `<subsector>_<technology>_service` / `_cost` columns.}
#'   }
#' @export
run_trn_endo_learning <- function(g, learning_config, end_year,
                                   mode = c("local", "global"),
                                   queries = trn_queries(),
                                   b_col = "b",
                                   deployment_start_year = 2021,
                                   update_period_min = 4) {
  mode <- match.arg(mode)
  tracking_df <- tibble::tibble()

  while (gcamwrapper::get_current_year(g) < end_year) {
    gcamwrapper::run_period(g)

    current_year <- gcamwrapper::get_current_year(g)
    next_year <- current_year + 5
    message("=== trn learning: year ", current_year, " -> ", next_year)

    if (gcamwrapper::get_current_period(g) >= update_period_min) {
      all_cost_data <- gcamwrapper::get_data(g, queries$input_cost)

      learning_regions <- if (mode == "local") {
        US_regions
      } else {
        all_cost_data %>% dplyr::distinct(.data$region) %>% dplyr::pull(.data$region)
      }

      year_row <- tibble::tibble(Year = next_year)
      updated_dfs <- vector("list", nrow(learning_config))

      for (i in seq_len(nrow(learning_config))) {
        res <- update_trn_tech_cost(
          g = g,
          subsector_name = learning_config$subsector[i],
          tech_name = learning_config$technology[i],
          config_row = learning_config[i, ],
          all_cost_data = all_cost_data,
          current_year = current_year,
          next_year = next_year,
          learning_regions = learning_regions,
          queries = queries,
          b_col = b_col,
          deployment_start_year = deployment_start_year
        )

        prefix <- paste0(learning_config$subsector[i], "_", learning_config$technology[i])
        year_row[[paste0(prefix, "_service")]] <- res$service
        year_row[[paste0(prefix, "_cost")]] <- res$cost

        learning_config$TD_current[i] <- res$TD_new
        updated_dfs[[i]] <- res$updated_df
      }

      combined_updated <- dplyr::bind_rows(updated_dfs)
      if (nrow(combined_updated) > 0) {
        gcamwrapper::set_data(g, combined_updated, queries$input_cost, list("region" = "+"))
      }

      tracking_df <- dplyr::bind_rows(tracking_df, year_row)
    }
  }

  list(g = g, learning_config = learning_config, tracking = tracking_df)
}
