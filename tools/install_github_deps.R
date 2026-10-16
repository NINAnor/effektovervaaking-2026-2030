# R packages that are not on conda-forge are installed from GitHub into the pixi environment.
# Run automatically by the pixi render tasks (pixi run render-all).

# anybadger >= 0.1.1 is needed by _common.R (ecRxiv) for the version badge; the CRAN version 0.1.0 is broken
if (!requireNamespace("anybadger", quietly = TRUE) || utils::packageVersion("anybadger") < "0.1.1") {
  remotes::install_github("lmeninato/anybadger", upgrade = "never")
}
