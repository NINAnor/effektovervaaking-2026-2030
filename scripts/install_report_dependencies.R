# anybadger is not available on conda-forge and is required by each report's
# ecRxiv helper functions. Use a pinned public archive to avoid GitHub API auth.
if (!requireNamespace("anybadger", quietly = TRUE) || utils::packageVersion("anybadger") < "0.1.1") {
  remotes::install_url(
    "https://github.com/lmeninato/anybadger/archive/aa3abe54538ab5664add5b8ea87c5957d1293787.tar.gz",
    upgrade = "never"
  )
}
