# Non-standard-evaluation column names referenced unquoted inside dplyr /
# ggplot2 pipelines (mostly columns coming straight from gcamwrapper::get_data()
# or read.csv(), whose names contain hyphens/dots and so can't always be
# written as `.data$name`). Declared here purely to keep R CMD check quiet;
# has no effect on behavior.
utils::globalVariables(c(
  "input-cost", "input-cost.x", "input-cost.y",
  "physical-output", "capacity-factor", "adjusted-cost",
  "learnin_rate_high", "learnin_rate_low", "proportion",
  "t0_deployment", "physical.output", "nested.subsector"
))
