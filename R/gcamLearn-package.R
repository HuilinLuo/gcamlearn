#' gcamLearn: Endogenous Technology Learning-by-Doing for GCAM
#'
#' @description
#' `gcamLearn` drives a running [gcamwrapper] GCAM model, tracks cumulative
#' technology deployment (transportation vehicle-technologies and power
#' generation technologies), and updates technology costs period-by-period
#' according to a two-factor learning curve (a "learning" cost share that
#' falls with cumulative deployment, plus a "fixed" cost share that is flat
#' or slowly declining). Includes convenience wrappers to configure the
#' GCAM build environment and to plot scenario comparisons from GCAM
#' query output.
#'
#' @section Typical workflow:
#' \enumerate{
#'   \item [setup_gcam_env()] (only if `gcamwrapper` needs to be built/loaded
#'     from source paths).
#'   \item [create_gcam_session()] to initialize and warm up a GCAM model
#'     object.
#'   \item [build_trn_learning_config()] / [run_trn_endo_learning()] for
#'     transportation sector learning, or
#'     [run_power_endo_learning()] for the power sector.
#'   \item [plot_trn_service_by_tech()], [plot_power_generation_by_tech()],
#'     [plot_trn_costs()], [plot_power_costs()] to compare scenarios.
#' }
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
