# Generate a Posit Connect Cloud manifest using older package versions that are
# more likely to be available in Connect Cloud's package cache.
#
# This script does NOT use renv and does NOT manage Python dependencies.
# It installs the packages into a local throwaway library named
# .connect_manifest_lib, then runs rsconnect::writeManifest() from that library.
#
# Run from the CATHA project root:
#   source("generate_connect_manifest_cached_versions.R")

options(repos = c(CRAN = "https://cloud.r-project.org"))

local_lib <- file.path(getwd(), ".connect_manifest_lib")
dir.create(local_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(normalizePath(local_lib, winslash = "/", mustWork = TRUE), .libPaths()))

message("Using manifest-generation library: ", .libPaths()[1])

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, lib = .libPaths()[1], dependencies = TRUE)
  }
}

install_if_missing("remotes")
install_if_missing("rsconnect")

# Versions chosen to avoid Connect Cloud building the newest Shiny/bslib/sass/htmltools
# dependency chain from source. These are conservative versions that are known to work
# with a Bootstrap-5/bslib Shiny app and are commonly cached on Connect Cloud.
pins <- c(
  htmltools = "0.5.8.1",
  lifecycle = "1.0.4",
  vctrs = "0.6.5",
  pillar = "1.9.0",
  tibble = "3.2.1",
  tidyselect = "1.2.1",
  jquerylib = "0.1.4",
  memoise = "2.0.1",
  cachem = "1.1.0",
  sass = "0.4.9",
  fontawesome = "0.5.3",
  bslib = "0.9.0",
  later = "1.4.1",
  promises = "1.3.2",
  httpuv = "1.6.15",
  shiny = "1.9.1",
  htmlwidgets = "1.6.4",
  crosstalk = "1.2.1",
  DT = "0.33",
  gtable = "0.3.5",
  scales = "1.3.0",
  isoband = "0.2.7",
  ggplot2 = "3.5.1",
  dplyr = "1.1.4",
  signal = "1.8-1",
  tuneR = "1.4.7",
  seewave = "2.2.4",
  jsonlite = "1.8.9"
)

for (pkg in names(pins)) {
  have <- requireNamespace(pkg, quietly = TRUE)
  version_ok <- FALSE
  if (have) {
    version_ok <- as.character(utils::packageVersion(pkg)) == pins[[pkg]]
  }
  if (!version_ok) {
    message("Installing ", pkg, "@", pins[[pkg]])
    remotes::install_version(
      package = pkg,
      version = pins[[pkg]],
      repos = "https://cloud.r-project.org",
      lib = .libPaths()[1],
      upgrade = "never",
      dependencies = TRUE,
      quiet = FALSE
    )
  }
}

# Sanity check: the important packages must be found from .connect_manifest_lib.
required <- c("shiny", "bslib", "DT", "jsonlite", "dplyr", "ggplot2", "tuneR", "seewave")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop("Still missing packages: ", paste(missing, collapse = ", "), call. = FALSE)
}

# Remove Python dependency management for Connect Cloud.
if (file.exists("requirements.txt")) {
  message("NOTE: requirements.txt exists. Do not commit it for the Connect Cloud R-only deployment.")
}

rsconnect::writeManifest(
  appDir = getwd(),
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  python = NULL,
  forceGeneratePythonEnvironment = FALSE,
  envManagementR = TRUE,
  envManagementPy = FALSE,
  packageRepositoryResolutionR = "lax",
  quiet = FALSE
)

message("\nWrote manifest.json.")
message("Package versions captured:")
for (pkg in required) {
  message("  ", pkg, " ", as.character(utils::packageVersion(pkg)))
}
message("\nCommit manifest.json, .rscignore, and this script. Do not commit .connect_manifest_lib, renv/, .venv-basic-pitch, or requirements.txt.")
