#' US state + national GCAM region names
#'
#' The 50 US state regions plus `"USA"` (the national aggregate region),
#' using GCAM's USA-disaggregated region naming convention. Used throughout
#' `gcamLearn` as the default set of regions for "local" (US-only) learning
#' and for filtering results to the United States.
#'
#' @format A character vector of 51 GCAM region names.
#' @export
US_regions <- c(
  "USA", "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DC", "DE", "FL",
  "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
  "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
  "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
  "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
)
