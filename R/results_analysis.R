#' Read and stack multiple scenario CSVs, tagging each with a scenario name
#'
#' @param csv_files Character vector of CSV file paths.
#' @param scenario_names Character vector of the same length, giving a
#'   scenario label for each file.
#' @param process_fn A function taking one data frame (already
#'   `read.csv()`'d) and returning the filtered/summarised data frame you
#'   want for that scenario.
#'
#' @return A single data frame with all scenarios stacked and a `scenario`
#'   factor column ordered as in `scenario_names`.
#' @keywords internal
#' @noRd
read_scenarios <- function(csv_files, scenario_names, process_fn) {
  stopifnot(length(csv_files) == length(scenario_names))
  out <- purrr::map2_dfr(csv_files, scenario_names, function(path, name) {
    df <- utils::read.csv(path)
    process_fn(df) %>% dplyr::mutate(scenario = name)
  })
  out$scenario <- factor(out$scenario, levels = scenario_names)
  out
}

#' Plot transportation service output by technology, faceted by scenario
#'
#' Reads one or more `trn_service`-style query CSVs (as written by
#' [run_trn_endo_learning()] / `gcamwrapper::get_data()` on the transport
#' service query), filters to given subsector(s)/regions/years, sums
#' physical output by (year, technology), and plots a stacked bar chart
#' faceted by scenario.
#'
#' @param csv_files Character vector of CSV paths (one per scenario).
#' @param scenario_names Character vector of scenario labels, same length
#'   as `csv_files`.
#' @param subsectors Character vector of subsectors to include, e.g.
#'   `"Car"` or `c("Light truck", "Medium truck", "Heavy truck")`.
#' @param region_filter Character vector of regions to include. Defaults to
#'   [US_regions].
#' @param year_range Length-2 numeric vector, `c(min_year, max_year)`.
#' @param ncol Number of facet columns. Default 3.
#'
#' @return A `ggplot` object.
#' @export
plot_trn_service_by_tech <- function(csv_files, scenario_names,
                                      subsectors = "Car",
                                      region_filter = gcamLearn::US_regions,
                                      year_range = c(2025, 2050),
                                      ncol = 3) {
  process_fn <- function(df) {
    df %>%
      dplyr::filter(
        .data$subsector %in% subsectors,
        .data$region %in% region_filter,
        .data$year >= year_range[1],
        .data$year <= year_range[2]
      ) %>%
      dplyr::group_by(.data$year, .data$technology) %>%
      dplyr::summarise(value = sum(.data$physical.output, na.rm = TRUE), .groups = "drop")
  }

  all_data <- read_scenarios(csv_files, scenario_names, process_fn)

  ggplot2::ggplot(all_data, ggplot2::aes(x = factor(.data$year), y = .data$value, fill = .data$technology)) +
    ggplot2::geom_bar(stat = "identity", position = "stack") +
    ggplot2::facet_wrap(~scenario, ncol = ncol) +
    ggplot2::labs(x = "Year", y = "Million passenger/ton km", fill = "Technology",
                  title = paste("Service Output by Technology,", year_range[1], "-", year_range[2])) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      strip.background = ggplot2::element_rect(fill = "lightblue"),
      strip.text = ggplot2::element_text(face = "bold"),
      legend.position = "bottom"
    ) +
    ggplot2::scale_fill_brewer(palette = "Set3")
}

#' Plot power generation output by technology, faceted by scenario
#'
#' Reads one or more generation-by-vintage query CSVs, groups CCS variants
#' separately (any `nested.subsector` containing `"CCS"` becomes
#' `<subsector>_CCS`), sums physical output by (year, technology), and
#' plots a stacked bar chart faceted by scenario.
#'
#' @inheritParams plot_trn_service_by_tech
#' @param tech_colors Optional named character vector mapping technology
#'   labels to colors. If `NULL`, a reasonable default power-tech palette
#'   is used for known names and `rainbow()` fills in the rest.
#'
#' @return A `ggplot` object.
#' @export
plot_power_generation_by_tech <- function(csv_files, scenario_names,
                                           region_filter = gcamLearn::US_regions,
                                           year_range = c(2025, 2050),
                                           tech_colors = NULL,
                                           ncol = 3) {
  process_fn <- function(df) {
    df %>%
      dplyr::filter(
        .data$region %in% region_filter,
        .data$year >= year_range[1],
        .data$year <= year_range[2]
      ) %>%
      dplyr::mutate(
        sub_new = ifelse(grepl("CCS", .data$nested.subsector, ignore.case = FALSE),
                          paste0(.data$subsector, "_CCS"), .data$subsector)
      ) %>%
      dplyr::group_by(.data$year, .data$sub_new) %>%
      dplyr::summarise(value = sum(.data$physical.output, na.rm = TRUE), .groups = "drop")
  }

  all_data <- read_scenarios(csv_files, scenario_names, process_fn)

  default_colors <- c(
    coal = "#8B4513", coal_CCS = "#D2691E", gas = "#537D90", gas_CCS = "#8eb1c2",
    biomass = "#228B22", biomass_CCS = "#90EE90", nuclear = "#e2619f",
    hydro = "#00B4D8", wind = "#00CED1", solar = "#FFD700", geothermal = "#FF8C00",
    `refined liquids` = "#4c4436", `refined liquids_CCS` = "#8a7b62",
    grid_storage = "purple", rooftop_pv = "#FDE992"
  )
  techs <- unique(all_data$sub_new)
  if (is.null(tech_colors)) tech_colors <- default_colors
  missing <- setdiff(techs, names(tech_colors))
  if (length(missing) > 0) {
    fill_colors <- stats::setNames(grDevices::rainbow(length(missing)), missing)
    tech_colors <- c(tech_colors, fill_colors)
  }
  tech_colors <- tech_colors[techs]

  ggplot2::ggplot(all_data, ggplot2::aes(x = factor(.data$year), y = .data$value, fill = .data$sub_new)) +
    ggplot2::geom_bar(stat = "identity", position = "stack") +
    ggplot2::facet_wrap(~scenario, ncol = ncol) +
    ggplot2::labs(x = "Year", y = "EJ", fill = "Technology",
                  title = paste("Generation Output by Technology,", year_range[1], "-", year_range[2])) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      strip.background = ggplot2::element_rect(fill = "lightblue"),
      strip.text = ggplot2::element_text(face = "bold"),
      legend.position = "bottom"
    ) +
    ggplot2::scale_fill_manual(values = tech_colors)
}

#' Plot transportation non-energy cost trajectories by scenario
#'
#' Reads one or more `input-cost`/`adjusted-cost` query CSVs and plots cost
#' vs. period, colored by technology, faceted by (subsector x scenario).
#'
#' @param csv_files,scenario_names See [plot_trn_service_by_tech()].
#' @param target_subsectors Character vector of subsectors to include.
#' @param target_technologies Character vector of technologies to include.
#' @param region Single region to plot (cost curves are usually compared
#'   for one representative region), default `"TX"`.
#' @param year_range Length-2 numeric vector of model periods to include.
#' @param tech_colors Optional named color vector; defaults to a
#'   BEV/FCEV/Liquids palette.
#'
#' @return A `ggplot` object.
#' @export
plot_trn_costs <- function(csv_files, scenario_names,
                            target_subsectors = c("Car", "Light truck", "Medium truck", "Heavy truck"),
                            target_technologies = c("BEV", "FCEV", "Liquids"),
                            region = "TX",
                            year_range = c(2021, 2050),
                            tech_colors = NULL) {
  if (is.null(tech_colors)) {
    tech_colors <- c(BEV = "#10b981", FCEV = "#3b82f6", Liquids = "#92400e")
  }

  trn_costs <- purrr::map2(csv_files, scenario_names, function(path, name) {
    readr::read_csv(path, show_col_types = FALSE) %>%
      dplyr::filter(
        .data$subsector %in% target_subsectors,
        .data$technology %in% target_technologies,
        .data$period >= year_range[1],
        .data$period <= year_range[2],
        .data$period == .data$year,
        .data$region == region,
        .data$input == "non-energy"
      ) %>%
      dplyr::mutate(scenario = name)
  })

  trn_costs_all <- dplyr::bind_rows(trn_costs) %>%
    dplyr::mutate(subsector = factor(.data$subsector, levels = target_subsectors))

  ggplot2::ggplot(trn_costs_all, ggplot2::aes(x = .data$period, y = `adjusted-cost`, color = .data$technology)) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_grid(subsector ~ scenario, scales = "free_y") +
    ggplot2::scale_color_manual(values = tech_colors) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.border = ggplot2::element_rect(color = "black", fill = NA, linewidth = 0.5))
}

#' Plot power sector capital cost trajectories by scenario
#'
#' @param csv_files,scenario_names See [plot_trn_costs()].
#' @param target_techs Character vector of technologies to include.
#' @param region Single region to plot, default `"TX"`.
#' @param year_range Length-2 numeric vector of model periods to include.
#' @param tech_colors Optional named color vector.
#'
#' @return A `ggplot` object.
#' @export
plot_power_costs <- function(csv_files, scenario_names,
                              target_techs,
                              region = "TX",
                              year_range = c(2021, 2050),
                              tech_colors = NULL) {
  power_cost <- purrr::map2(csv_files, scenario_names, function(path, name) {
    readr::read_csv(path, show_col_types = FALSE) %>%
      dplyr::filter(
        .data$region == region,
        .data$technology %in% target_techs,
        .data$period >= year_range[1],
        .data$period <= year_range[2],
        .data$period == .data$year
      ) %>%
      dplyr::mutate(scenario = name)
  })

  cost_all <- dplyr::bind_rows(power_cost)

  p <- ggplot2::ggplot(cost_all, ggplot2::aes(x = .data$period, y = `adjusted-cost`, color = .data$technology)) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~scenario, ncol = 2) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.border = ggplot2::element_rect(color = "black", fill = NA, linewidth = 0.5))

  if (!is.null(tech_colors)) p <- p + ggplot2::scale_color_manual(values = tech_colors)
  p
}
