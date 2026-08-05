#' Create and warm up a GCAM model session
#'
#' Thin wrapper around [gcamwrapper::create_and_initialize()] that also
#' advances ("warms up") the model through its initial calibration periods,
#' since endogenous-learning cost updates should only begin once the model
#' has reached a chosen starting period/year.
#'
#' @param config_file Name of the GCAM configuration XML file (must live in
#'   `config_path`).
#' @param config_path Path to the directory containing GCAM's `exe`/config
#'   files (GCAM's working directory for this run).
#' @param warmup_period Integer GCAM model period to advance to before
#'   returning (e.g. `2` to reach the first two periods, `5` for period 5).
#'   Use `NULL` to skip warmup entirely and return the freshly-initialized
#'   session.
#'
#' @return The initialized (and optionally warmed-up) `gcamwrapper` session
#'   object `g`.
#' @export
create_gcam_session <- function(config_file, config_path, warmup_period = NULL) {
  if (!requireNamespace("gcamwrapper", quietly = TRUE)) {
    stop("gcamwrapper is required but not installed. See setup_gcam_env().",
         call. = FALSE)
  }

  g <- gcamwrapper::create_and_initialize(config_file, config_path)

  if (!is.null(warmup_period)) {
    while (gcamwrapper::get_current_period(g) < warmup_period) {
      gcamwrapper::run_period(g)
    }
  }

  g
}
