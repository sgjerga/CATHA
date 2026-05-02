# Generate an R-only manifest.json for Posit Connect Cloud.
# This intentionally does not include Python/Basic Pitch dependencies.
# Run this from the CATHA project root before publishing:
#   setwd("/path/to/CATHA_Shiny_Prototype_v9")
#   source("generate_connect_manifest_R_only.R")

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", repos = "https://cloud.r-project.org")
}

# Keep Python artifacts out of the bundle. The Basic Pitch feature remains
# available only for users who run CATHA locally and configure Python paths.
ignore_lines <- c(
  "# Local/dev-only files that Connect Cloud should not deploy",
  ".venv-basic-pitch",
  ".venv",
  "Rproj.user",
  ".Rproj.user",
  ".git",
  "basic_pitch_test",
  "basic_pitch_test_v9",
  "requirements.txt",
  "*.mid",
  "*.musicxml",
  "*_basic_pitch.csv",
  "*_basic_pitch.mid",
  "*.zip",
  "*.tar.gz",
  "__pycache__"
)
writeLines(ignore_lines, ".rscignore")

rsconnect::writeManifest(
  appDir = getwd(),
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  python = NULL,
  forceGeneratePythonEnvironment = FALSE
)

message("R-only manifest.json regenerated. Commit manifest.json and .rscignore to GitHub.")
