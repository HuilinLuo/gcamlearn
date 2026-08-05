# gcamLearn

This package enables dndogenous technology learning-by-doing for GCAM and GCAM-USA, built on top of
[`gcamwrapper`](https://github.com/JGCRI/gcamwrapper). Tracks cumulative
technology deployment and updates technology costs period-by-period
according to a two-factor (learning share + fixed share) learning curve,
for both the **transportation** and **power** sectors.

The origianl code for GCAM v6.0 see: https://github.com/trwaite/endogenous_tech_change. The code shall be used after installing gcamwrapper (for installation of gcamwrapper see: https://github.com/JGCRI/gcamwrapper), and be used in the gcamwrapper R project. More versions for v6.0 are also available.



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

## 1. Configure the environment 

`gcamwrapper` must be built/loaded from source and if its
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

Necessary parts:
To run the model some preperations:

1. In the GCAM configuration file (i.e., configuration.xml), turn off the function to write the database: ../output/database_basexdb
2. For GCAMv8.2, for some reason the "//" logic in ymls will result in fatal error and immediate shutdown of R. Solution: I have updated query forms in the R code (works for power- and transport- related queries), but for other queries in "inst/extdata/queries.yml" file, users need to pay attention to all queries with "//". An updated CO2 emission file to use: co2_query <- "world/region{region@name}/sector{sector@name}/subsector{subsector@name}/technology{tech@name}/period/ghg[NamedFilter,StringEquals,CO2]/emissions{year@year}".
3. All the debugging are accredited to amazing Pralit and Matthew at JGCRI. For other gcamwrapper-related questions, if JGCRI people are too busy, feel free to contact Huilin (hxl5625@psu.edu).

## 2. Transportation sector learning

We start by defining the initial time and deployment, as well as learning rate for transportation sector technologies. All learning rate subject to change.
An example using GCAM-USA:

```r
g <- create_gcam_session(
  config_file = "configuration.xml", # change to your own configuration file
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

We start by defining the initial time and deployment, as well as learning rate for power sector technologies. All learning rate subject to change.
An example using GCAM-USA:

```r
g <- create_gcam_session(
  config_file = "configuration_ira_USA.xml",
  config_path = "/path/to/gcam-core/exe",
  warmup_period = 5 # here it is 2015
)

run_power_endo_learning(
  g = g,
  end_period = 11, # it is 2050
  map_world_path = "input_endo/mappings/learning_components_learning_map_simplified.csv",
  map_us_path    = "input_endo/mappings/learning_components_learning_map_US.csv",
  t0_world_path  = "input_endo/t0_cost_deployment.csv",
  t0_us_path     = "input_endo/t0_cost_deployment_USA.csv",
  region_scope   = "global"
)
```

## 4. Compare scenarios

An example of plotting

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

