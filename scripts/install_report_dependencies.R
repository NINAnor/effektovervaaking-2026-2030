# anybadger is not available on conda-forge and is required by each report's
# ecRxiv helper functions.
if (!requireNamespace("anybadger", quietly = TRUE) || utils::packageVersion("anybadger") < "0.1.1") {
  remotes::install_github("lmeninato/anybadger", upgrade = "never")
}
