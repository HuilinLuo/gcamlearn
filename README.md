# gcamLearn

Endogenous technology learning-by-doing for GCAM, built on top of
[`gcamwrapper`](https://github.com/JGCRI/gcamwrapper). Tracks cumulative
technology deployment and updates technology costs period-by-period
according to a two-factor (learning share + fixed share) learning curve,
for both the **transportation** and **power** sectors.

This package was refactored from a set of standalone analysis scripts into
reusable, parameterized functions -- no personal file paths or hardcoded
scenario assumptions are baked in; everything is passed as an argument.

## Installation

```r
# install.packages("devtools")
devtools::install("path/to/gcamLearn")
# or, once documentation is (re)generated:
devtools::document("path/to/gcamLearn")
devtools::install("path/to/gcamLearn")
```

`gcamwrapper` itself is not on CRAN -- install it separately from
https://github.com/JGCRI/gcamwrapper before using any function here that
touches a running GCAM session.

## 1. Configure the environment (optional)

Only needed if `gcamwrapper` must be built/loaded from source and its
dependency paths aren't already set via `.Renviron`:

```r
library(gcamLearn)

setup_gcam_env(
  gcam_include = "C:/gcam-core/cvs/objects",
  gcam_lib     = "C:/gcam-core/cvs/objects/build/linux",
  boost_include = "C:/gcam-core/libs/boost-lib",
  boost_lib     = "C:/gcam-core/libs/boost-lib/stage/lib",
  tbb_include   = "C:/rtools44/mingw64/include/oneapi",
  tbb_lib       = "C:/rtools44/mingw64/bin",
  eigen_include = "C:/gcam-core/libs/eigen",
  java_include        = "C:/jdk-18/include",
  java_include_win32  = "C:/jdk-18/include/win32",
  java_lib            = "C:/jdk-18/bin/server",
  jars_lib      = "C:/gcam-core/libs/jars/*",
  python_include = "C:/Python310/include",
  osname_lowercase = "win32"
)
```

## 2. Transportation sector learning

```r
g <- create_gcam_session(
  config_file = "cfg_2050nl_202502.xml",
  config_path = "/path/to/gcam-core/exe",
  warmup_period = 2
)

learning_config <- build_trn_learning_config(list(
  list(subsector = "Car", technology = "BEV",
       TD_init = 12800, C0 = 0.2668, fixed_ratio = 0.7, learning_rate = 0.19),
  list(subsector = "Car", technology = "FCEV",
       TD_init = 265, C0 = 0.355, fixed_ratio = 0.6, learning_rate = 0.21),
  list(subsector = "Light truck", technology = "BEV",
       TD_init = 20857 * 0.27 / 1e6, C0 = 0.2025, fixed_ratio = 0.7, learning_rate = 0.18),
  list(subsector = "Light truck", technology = "FCEV",
       TD_init = 20857 * 0.27 / 1e6, C0 = 0.2554, fixed_ratio = 0.55, learning_rate = 0.08),
  list(subsector = "Medium truck", technology = "BEV",
       TD_init = 20857 * 2.07 / 1e6, C0 = 0.4549, fixed_ratio = 0.6, learning_rate = 0.19),
  list(subsector = "Medium truck", technology = "FCEV",
       TD_init = 20857 * 2.07 / 1e6, C0 = 0.3879, fixed_ratio = 0.55, learning_rate = 0.08),
  list(subsector = "Heavy truck", technology = "BEV",
       TD_init = 20857 * 4.16 / 1e6, C0 = 1.2336, fixed_ratio = 0.5, learning_rate = 0.19),
  list(subsector = "Heavy truck", technology = "FCEV",
       TD_init = 20857 * 4.16 / 1e6, C0 = 0.5737, fixed_ratio = 0.5, learning_rate = 0.08)
))

result <- run_trn_endo_learning(
  g = g,
  learning_config = learning_config,
  end_year = 2050,
  mode = "local"   # or "global"
)

write.csv(result$tracking, "trn_tracking.csv", row.names = FALSE)
```

Or, if you keep a reusable mapping CSV (columns matching
`build_trn_learning_config()`'s output, plus optionally `b_high`/`b_low`
instead of `b` for a high/low learning-rate scenario):

```r
learning_config <- read_trn_learning_config("input_endo/mappings/trn_mapping.csv")
result <- run_trn_endo_learning(g, learning_config, end_year = 2035,
                                 mode = "global", b_col = "b_high")
```

## 3. Power sector learning

```r
g <- create_gcam_session(
  config_file = "configuration_ira_USA.xml",
  config_path = "/path/to/gcam-core/exe",
  warmup_period = 5
)

run_power_endo_learning(
  g = g,
  end_period = 11,
  map_world_path = "input_endo/mappings/learning_components_learning_map_simplified.csv",
  map_us_path    = "input_endo/mappings/learning_components_learning_map_US.csv",
  t0_world_path  = "input_endo/t0_cost_deployment.csv",
  t0_us_path     = "input_endo/t0_cost_deployment_USA.csv",
  region_scope   = "global"
)
```

## 4. Compare scenarios

```r
plot_trn_service_by_tech(
  csv_files = c("trn_output_nl.csv", "trn_output_lt.csv"),
  scenario_names = c("No learning", "Endogenous learning"),
  subsectors = "Car"
)

plot_power_generation_by_tech(
  csv_files = c("gen_vin_US_nl.csv", "gen_vin_US_lp.csv"),
  scenario_names = c("No learning", "Endogenous learning")
)

plot_trn_costs(
  csv_files = c("trn_cost_nl.csv", "trn_cost_lt.csv"),
  scenario_names = c("No learning", "Endogenous learning"),
  region = "TX"
)

plot_power_costs(
  csv_files = c("cap_power_nl_US.csv", "cap_power_lp_US.csv"),
  scenario_names = c("No learning", "Endogenous learning"),
  target_techs = c("PV_int", "wind_int", "CSP_int"),
  region = "TX"
)
```

## Notes on the refactor

- All hardcoded personal file paths (`/Users/Huilin/...`, `C:/Users/Huilin/...`)
  have been removed; every path is now a function argument.
- The two versions of the transport `update_costs_for_tech()` logic that
  existed in the original script (an early version and a later, more
  general "v2" version) have been consolidated into a single function,
  [`update_trn_tech_cost()`], based on the later version.
- The power-sector script's duplicated `cap_all_cost_d_US_use` /
  `cap_all_cost_d_world_use` blocks (an old and new attempt at the same
  merge, left in the script back to back) have been consolidated into one
  clean implementation in [`apply_power_cost_coefficients()`].
- GCAM query strings are now returned by [`trn_queries()`] /
  [`power_queries()`] instead of being scattered globals, so they're easy
  to override for a different GCAM version's sector/subsector naming.
