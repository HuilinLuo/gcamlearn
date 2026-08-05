#' Compute (cumulative) generation capacity by learning component
#'
#' Pulls generation output and capacity factors for both the globally
#' aggregated (non-US) regions and the US-disaggregated regions, converts
#' physical output (EJ) to capacity (GW), and aggregates to whatever
#' "learning component" groupings are defined in the mapping files (e.g.
#' several technologies that share one learning curve, such as "PV").
#'
#' @param g A `gcamwrapper` session.
#' @param current_year Calendar year to aggregate through/at.
#' @param map_world_path,map_us_path CSV paths mapping `sector`,
#'   `subsector`, `technology` to a `learning_component` label, for the
#'   world and US region sets respectively.
#' @param US_regions Character vector of US region names (default
#'   [US_regions]); world results exclude these, US results are exactly
#'   these.
#' @param conv_kwh_ej Energy unit conversion factor from GCAM's native
#'   units to kWh-equivalent EJ (default matches GCAM's EJ output).
#' @param hours_per_yr Hours per year used to convert energy to capacity
#'   (default `8760`).
#' @param use_cumulative If `TRUE` (default), sums capacity for all years
#'   `<= current_year` (cumulative deployment). If `FALSE`, only
#'   `year == current_year` (new deployment that year).
#' @param queries Query list from [power_queries()].
#'
#' @return A list with:
#'   \describe{
#'     \item{capacities}{Raw capacity tables (`world`, `US`).}
#'     \item{cap_learning}{Capacity tables joined to `learning_component`
#'       (`world`, `US`), NA components dropped.}
#'     \item{total_cap_summary}{One row per `learning_component` with
#'       `US_total_cap`, `world_total_cap`, `total_cap`.}
#'   }
#' @export
compute_learning_capacity <- function(g, current_year,
                                       map_world_path, map_us_path,
                                       US_regions = gcamLearn::US_regions,
                                       conv_kwh_ej = 2.77778e-11,
                                       hours_per_yr = 8760,
                                       use_cumulative = TRUE,
                                       queries = power_queries()) {

  elec_service_data <- gcamwrapper::get_data(g, queries$gen_us)
  global_gen_vin_d  <- gcamwrapper::get_data(g, queries$gen_world)
  cap_fac_d_global  <- gcamwrapper::get_data(g, queries$cap_factor_world)
  cap_fac_d_us      <- gcamwrapper::get_data(g, queries$cap_factor_us)

  excels <- list(
    world = global_gen_vin_d %>% dplyr::filter(!.data$region %in% US_regions),
    US    = elec_service_data
  )
  gens_new <- lapply(excels, function(df) df %>% dplyr::filter(.data$period == .data$year))
  capfacs_new <- list(world = cap_fac_d_global, US = cap_fac_d_us)

  capacities_new <- list()
  capacities_new$world <- gens_new$world %>%
    dplyr::left_join(capfacs_new$world,
                      by = c("region", "sector", "subsector", "technology", "period")) %>%
    dplyr::mutate(
      capacity = `physical-output` / conv_kwh_ej / hours_per_yr / `capacity-factor`,
      capacity = dplyr::if_else(.data$capacity < 0, 0, .data$capacity)
    )
  capacities_new$US <- gens_new$US %>%
    dplyr::left_join(capfacs_new$US,
                      by = c("region", "sector", "subsector", "nested-subsector", "technology", "period")) %>%
    dplyr::mutate(
      capacity = `physical-output` / conv_kwh_ej / hours_per_yr / `capacity-factor`,
      capacity = dplyr::if_else(.data$capacity < 0, 0, .data$capacity)
    )

  learning_components_map_world <- readr::read_csv(map_world_path, show_col_types = FALSE)
  learning_components_map_us    <- readr::read_csv(map_us_path, show_col_types = FALSE)

  capacities_joined_world <- capacities_new$world %>%
    dplyr::left_join(learning_components_map_world, by = c("sector", "subsector", "technology")) %>%
    dplyr::filter(!is.na(.data$learning_component))
  capacities_joined_us <- capacities_new$US %>%
    dplyr::left_join(learning_components_map_us, by = c("sector", "subsector", "technology")) %>%
    dplyr::filter(!is.na(.data$learning_component))

  cap_learning <- list(world = capacities_joined_world, US = capacities_joined_us)

  year_filter <- function(df) {
    if (use_cumulative) df %>% dplyr::filter(.data$year <= current_year)
    else df %>% dplyr::filter(.data$year == current_year)
  }

  us_cap <- year_filter(capacities_joined_us) %>%
    dplyr::filter(!is.na(.data$learning_component)) %>%
    dplyr::group_by(.data$learning_component) %>%
    dplyr::summarise(US_total_cap = sum(.data$capacity, na.rm = TRUE), .groups = "drop")

  world_cap <- year_filter(capacities_joined_world) %>%
    dplyr::filter(!is.na(.data$learning_component)) %>%
    dplyr::group_by(.data$learning_component) %>%
    dplyr::summarise(world_total_cap = sum(.data$capacity, na.rm = TRUE), .groups = "drop")

  total_cap <- dplyr::full_join(us_cap, world_cap, by = "learning_component") %>%
    dplyr::mutate(
      US_total_cap    = tidyr::replace_na(.data$US_total_cap, 0),
      world_total_cap = tidyr::replace_na(.data$world_total_cap, 0),
      total_cap       = .data$US_total_cap + .data$world_total_cap
    )

  list(capacities = capacities_new, cap_learning = cap_learning, total_cap_summary = total_cap)
}

#' Compute learning-curve cost coefficients from a capacity result
#'
#' Compares cumulative capacity (from [compute_learning_capacity()]) to a
#' base-year ("t0") deployment level to get a deployment-multiple `A`, then
#' converts that into a cost coefficient via the standard two-factor
#' learning curve: `coeff = (1 - proportion) + proportion * A^log2(1-LR)`.
#'
#' @param cap_result Output of [compute_learning_capacity()].
#' @param t0_world_path,t0_us_path CSV paths with columns
#'   `learning_component`, `t0_deployment` giving base-year deployment for
#'   the world and US respectively.
#' @param region_scope Which deployment multiple to use when computing the
#'   coefficient: `"global"` uses total (US + world) deployment for both
#'   `world` and `US` component tables (learning is shared globally), or
#'   `"regional"` uses world-only deployment for the `world` table and
#'   US-only for the `US` table (learning is regional).
#' @param coeff_floor Minimum allowed cost coefficient (prevents costs from
#'   learning below this fraction of the base cost). Default `0.25`.
#'
#' @return `cap_result$cap_learning`, with `A`, `A_world`, `A_US`,
#'   `cost_coeff_world_high`, `cost_coeff_world_low`, `cost_coeff_US_high`,
#'   `cost_coeff_US_low` columns added to both the `world` and `US` tables.
#' @export
compute_learning_cost_coefficients <- function(cap_result, t0_world_path, t0_us_path,
                                                region_scope = c("global", "regional"),
                                                coeff_floor = 0.25) {
  region_scope <- match.arg(region_scope)

  t0_world <- readr::read_csv(t0_world_path, show_col_types = FALSE) %>%
    dplyr::select("learning_component", "t0_deployment") %>%
    dplyr::rename(t0_world = "t0_deployment")
  t0_us <- readr::read_csv(t0_us_path, show_col_types = FALSE) %>%
    dplyr::select("learning_component", "t0_deployment") %>%
    dplyr::rename(t0_US = "t0_deployment")

  clamp_ratio <- function(x) dplyr::case_when(is.nan(x) | is.infinite(x) | x <= 0 ~ 1, TRUE ~ x)

  calc_df <- cap_result$total_cap_summary %>%
    dplyr::left_join(t0_world, by = "learning_component") %>%
    dplyr::left_join(t0_us, by = "learning_component") %>%
    dplyr::mutate(
      A       = clamp_ratio(.data$total_cap / .data$t0_world),
      A_world = clamp_ratio(.data$world_total_cap / .data$t0_world),
      A_US    = clamp_ratio(.data$US_total_cap / .data$t0_US)
    ) %>%
    dplyr::select("learning_component", "A", "A_world", "A_US")

  cap_learning <- cap_result$cap_learning
  a_col_world <- if (region_scope == "global") "A" else "A_world"
  a_col_us    <- if (region_scope == "global") "A" else "A_US"

  cap_learning$world <- cap_learning$world %>%
    dplyr::left_join(calc_df, by = "learning_component") %>%
    dplyr::mutate(
      cost_coeff_world_high = (1 - .data$proportion) +
        .data$proportion * (.data[[a_col_world]] ^ log2(1 - .data$learnin_rate_high)),
      cost_coeff_world_low  = (1 - .data$proportion) +
        .data$proportion * (.data[[a_col_world]] ^ log2(1 - .data$learnin_rate_low)),
      cost_coeff_world_high = dplyr::if_else(is.infinite(.data$cost_coeff_world_high) | is.nan(.data$cost_coeff_world_high),
                                              1, .data$cost_coeff_world_high),
      cost_coeff_world_low  = dplyr::if_else(is.infinite(.data$cost_coeff_world_low) | is.nan(.data$cost_coeff_world_low),
                                              1, .data$cost_coeff_world_low),
      cost_coeff_world_high = pmax(.data$cost_coeff_world_high, coeff_floor),
      cost_coeff_world_low  = pmax(.data$cost_coeff_world_low, coeff_floor)
    )

  cap_learning$US <- cap_learning$US %>%
    dplyr::left_join(calc_df, by = "learning_component") %>%
    dplyr::mutate(
      cost_coeff_US_high = (1 - .data$proportion) +
        .data$proportion * (.data[[a_col_us]] ^ log2(1 - .data$learnin_rate_high)),
      cost_coeff_US_low  = (1 - .data$proportion) +
        .data$proportion * (.data[[a_col_us]] ^ log2(1 - .data$learnin_rate_low)),
      cost_coeff_US_high = dplyr::if_else(is.infinite(.data$cost_coeff_US_high) | is.nan(.data$cost_coeff_US_high),
                                           1, .data$cost_coeff_US_high),
      cost_coeff_US_low  = dplyr::if_else(is.infinite(.data$cost_coeff_US_low) | is.nan(.data$cost_coeff_US_low),
                                           1, .data$cost_coeff_US_low),
      cost_coeff_US_high = pmax(.data$cost_coeff_US_high, coeff_floor),
      cost_coeff_US_low  = pmax(.data$cost_coeff_US_low, coeff_floor)
    )

  cap_learning
}

#' Apply computed cost coefficients to capital costs and write to GCAM
#'
#' Joins `cost_coeff_*_high` onto the current capital-cost tables, scales
#' `next_year`'s capital cost by the coefficient, optionally zeroes
#' `OM-fixed` costs for `next_year` (learning technologies are commonly
#' modeled with fixed O&M rolled into the learning capital cost), and
#' writes the result back into the running GCAM session.
#'
#' @param g A `gcamwrapper` session.
#' @param cap_learning Output of [compute_learning_cost_coefficients()].
#' @param next_year Calendar year to write updated costs for.
#' @param US_regions Character vector of US region names.
#' @param queries Query list from [power_queries()].
#' @param zero_om_fixed If `TRUE` (default), sets `OM-fixed` input costs to
#'   `0` for `next_year` alongside the capital cost update.
#'
#' @return Invisibly, a list with the `US` and `world` cost tables that
#'   were written to GCAM.
#' @export
apply_power_cost_coefficients <- function(g, cap_learning, next_year,
                                           US_regions = gcamLearn::US_regions,
                                           queries = power_queries(),
                                           zero_om_fixed = TRUE) {

  cap_all_cost_d_us    <- gcamwrapper::get_data(g, queries$capital_cost_us)
  cap_all_cost_d_world <- gcamwrapper::get_data(g, queries$capital_cost_world)

  join_cols <- c("region", "sector", "subsector", "technology", "period")

  cost_adjust_world <- cap_all_cost_d_world %>%
    dplyr::filter(!.data$region %in% US_regions) %>%
    dplyr::left_join(
      cap_learning$world %>%
        dplyr::select("region", "sector", "subsector", "technology", "period", "year",
                      "cost_coeff_world_high", "cost_coeff_world_low"),
      by = join_cols
    )

  cost_adjust_us <- cap_all_cost_d_us %>%
    dplyr::filter(.data$region %in% US_regions) %>%
    dplyr::left_join(
      cap_learning$US %>%
        dplyr::select("region", "sector", "subsector", "technology", "period", "year",
                      "cost_coeff_US_high", "cost_coeff_US_low"),
      by = join_cols
    )

  apply_adjustment <- function(df, coeff_col) {
    df %>%
      dplyr::mutate(
        `adjusted-cost` = dplyr::case_when(
          .data$period == next_year & .data$input == "capital" ~
            dplyr::if_else(is.na(.data[[coeff_col]]), `adjusted-cost`, `adjusted-cost` * .data[[coeff_col]]),
          zero_om_fixed & .data$period == next_year & .data$input == "OM-fixed" ~ 0,
          TRUE ~ `adjusted-cost`
        )
      )
  }

  cost_adjust_world <- apply_adjustment(cost_adjust_world, "cost_coeff_world_high")
  cost_adjust_us    <- apply_adjustment(cost_adjust_us, "cost_coeff_US_high")

  merge_back <- function(original, adjusted) {
    original %>%
      dplyr::left_join(
        adjusted %>%
          dplyr::select("region", "sector", "subsector", "technology", "period",
                        year = "year.x", "input", "adjusted-cost") %>%
          dplyr::rename(adjusted_cost_new = "adjusted-cost"),
        by = c("region", "sector", "subsector", "technology", "period", "year", "input")
      ) %>%
      dplyr::mutate(`adjusted-cost` = dplyr::coalesce(.data$adjusted_cost_new, `adjusted-cost`)) %>%
      dplyr::select(-"adjusted_cost_new")
  }

  cap_all_cost_d_us_use    <- merge_back(cap_all_cost_d_us, cost_adjust_us)
  cap_all_cost_d_world_use <- merge_back(cap_all_cost_d_world, cost_adjust_world)

  gcamwrapper::set_data(g, cap_all_cost_d_us_use, queries$capital_cost_us)
  gcamwrapper::set_data(g, cap_all_cost_d_world_use, queries$capital_cost_world)

  invisible(list(US = cap_all_cost_d_us_use, world = cap_all_cost_d_world_use))
}

#' Run power sector endogenous learning to a target period
#'
#' Advances the GCAM session period-by-period; at the end of each period,
#' recomputes cumulative capacity by learning component, converts to cost
#' coefficients, and writes updated capital costs back into GCAM for the
#' next period.
#'
#' @param g A `gcamwrapper` session, already warmed up to the period
#'   *before* `end_period` (see [create_gcam_session()]).
#' @param end_period Target GCAM model period to run through.
#' @param map_world_path,map_us_path,t0_world_path,t0_us_path See
#'   [compute_learning_capacity()] / [compute_learning_cost_coefficients()].
#' @param US_regions Character vector of US region names.
#' @param conv_kwh_ej,hours_per_yr See [compute_learning_capacity()].
#' @param coeff_floor See [compute_learning_cost_coefficients()].
#' @param region_scope See [compute_learning_cost_coefficients()].
#' @param queries Query list from [power_queries()].
#' @param verbose If `TRUE` (default), prints progress messages.
#'
#' @return The (mutated) GCAM session `g`, invisibly.
#' @export
run_power_endo_learning <- function(g, end_period,
                                     map_world_path, map_us_path,
                                     t0_world_path, t0_us_path,
                                     US_regions = gcamLearn::US_regions,
                                     conv_kwh_ej = 2.77778e-11,
                                     hours_per_yr = 8760,
                                     coeff_floor = 0.25,
                                     region_scope = c("global", "regional"),
                                     queries = power_queries(),
                                     verbose = TRUE) {
  region_scope <- match.arg(region_scope)

  while (gcamwrapper::get_current_period(g) < end_period) {
    next_period <- gcamwrapper::get_current_period(g) + 1
    next_year <- gcamwrapper::get_current_year(g) + 5

    if (verbose) message(sprintf(">>> power learning: period %d (target year %d)", next_period, next_year))

    cap_result <- compute_learning_capacity(
      g = g, current_year = gcamwrapper::get_current_year(g),
      map_world_path = map_world_path, map_us_path = map_us_path,
      US_regions = US_regions, conv_kwh_ej = conv_kwh_ej, hours_per_yr = hours_per_yr,
      use_cumulative = TRUE, queries = queries
    )

    cap_learning <- compute_learning_cost_coefficients(
      cap_result, t0_world_path = t0_world_path, t0_us_path = t0_us_path,
      region_scope = region_scope, coeff_floor = coeff_floor
    )

    apply_power_cost_coefficients(
      g = g, cap_learning = cap_learning, next_year = next_year,
      US_regions = US_regions, queries = queries
    )

    gcamwrapper::run_period(g)
    if (verbose) message(sprintf("<<< period %d complete", next_period))
  }

  invisible(g)
}
