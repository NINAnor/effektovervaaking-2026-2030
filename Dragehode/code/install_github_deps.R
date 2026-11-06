# R packages that are not on conda-forge are installed from GitHub or CRAN into the pixi environment.
# Run automatically by the pixi render task (pixi run render, from the subproject folder).

# anybadger >= 0.1.1 is needed by _common.R (ecRxiv); use a pinned public archive
# because the CRAN version 0.1.0 is broken and GitHub API auth is not required.
if (!requireNamespace("anybadger", quietly = TRUE) || utils::packageVersion("anybadger") < "0.1.1") {
  remotes::install_url(
    "https://github.com/lmeninato/anybadger/archive/aa3abe54538ab5664add5b8ea87c5957d1293787.tar.gz",
    upgrade = "never"
  )
}

# ARTool and goeveg are loaded by code/4_analyses_dragehode.qmd but are not on conda-forge; install from CRAN
for (p in c("ARTool", "goeveg")) {
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
}
