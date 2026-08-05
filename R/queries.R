#' Default transportation sector GCAM queries
#'
#' Returns the set of `gcamwrapper` query strings used to pull transport
#' service (physical output), technology non-energy cost, and region lists
#' for the endogenous learning routines. Override any element if your GCAM
#' XML uses different sector/subsector naming.
#'
#' @return A named list of query strings: `service`, `input_cost`,
#'   `adjusted_cost`, `region`.
#' @export
trn_queries <- function() {
  list(
    service = paste0(
      "world/region{region@name}/sector[+NamedFilter,StringRegexMatches,^trn_]/",
      "subsector{subsector@name}/technology{tech@name}/period{vintage@year}/",
      "output{output@name}/physical-output{year@year}"
    ),
    input_cost = paste0(
      "world/region{region@name}/sector[+NamedFilter,StringRegexMatches,^trn_]/",
      "subsector{subsector@name}/technology{tech@name}/period{vintage@year}/",
      "input{input@name}/input-cost"
    ),
    adjusted_cost = paste0(
      "world/region{region@name}/sector[+NamedFilter,StringRegexMatches,^trn_]/",
      "subsector{subsector@name}/technology{tech@name}/period{vintage@year}/",
      "input{input@name}/adjusted-cost{year@year}"
    ),
    region = "world/region{region@name}"
  )
}

#' Default power sector GCAM queries (GCAM v8.2 naming)
#'
#' Returns the set of `gcamwrapper` query strings used to pull generation
#' (physical output), capacity factor, and capital/OM-fixed cost for both
#' the globally-aggregated (non-US) regions and the US-disaggregated
#' regions. Override any element if your GCAM version/XML uses different
#' sector/subsector naming.
#'
#' @return A named list of query strings.
#' @export
power_queries <- function() {
  list(
    gen_world = paste0(
      "world/region{region@name}/sector[+NamedFilter,StringRegexMatches,^elect]/",
      "subsector{subsector@name}/technology{tech@name}/period{vintage@year}/",
      "output{output@name}/physical-output{year@year}"
    ),
    gen_us = paste0(
      "world/region{region@name}/sector{sector@name}/subsector{subsector@name}/",
      "nested-subsector{subsector1@name}/technology{tech@name}/period{vintage@year}/",
      "output{output@name}/physical-output{year@year}"
    ),
    cap_factor_world = paste0(
      "world/region{region@name}/sector[+NamedFilter,StringEquals,electricity]/",
      "subsector{subsector@name}/technology{tech@name}/period{vintage@year}/capacity-factor"
    ),
    cap_factor_us = paste0(
      "world/region{region@name}/sector{sector@name}/subsector{subsector@name}/",
      "nested-subsector{subsector1@name}/technology{tech@name}/period{vintage@year}/capacity-factor"
    ),
    capital_cost_world = paste0(
      "world/region{region@name}/sector[+NamedFilter,StringRegexMatches,^elect]/",
      "subsector{subsector@name}/technology{tech@name}/period{vintage@year}/",
      "input[+NamedFilter,StringRegexMatches,capital]/adjusted-cost{year@year}"
    ),
    capital_cost_us = paste0(
      "world/region{region@name}/sector{sector@name}/subsector{subsector@name}/",
      "nested-subsector{subsector1@name}/technology{tech@name}/period{vintage@year}/",
      "input[+NamedFilter,StringRegexMatches,capital]/adjusted-cost{year@year}"
    )
  )
}
