# Generate a Posit Connect Cloud manifest for CATHA.
# Run from the CATHA project root, e.g.:
#   setwd("/home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v9")
#   source("generate_connect_manifest_official.R")

options(repos = c(CRAN = "https://cloud.r-project.org"))

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect")
}

# Make sure the R-only runtime dependencies are installed locally before
# generating the manifest. Python/Basic Pitch is deliberately NOT captured.
r_packages <- c(
  "shiny", "bslib", "DT", "jsonlite", "dplyr", "ggplot2",
  "tuneR", "seewave"
)
missing <- r_packages[!vapply(r_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  install.packages(missing)
}

# Optional sanity check: show the direct dependencies detected from the app.
cat("\nDirect R packages requested for Connect Cloud manifest:\n")
print(r_packages)
cat("\nWriting manifest.json with rsconnect::writeManifest()...\n")

rsconnect::writeManifest(
  appDir = ".",
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  quarto = FALSE,
  envManagementR = TRUE,
  envManagementPy = FALSE,
  packageRepositoryResolutionR = "lax",
  verbose = TRUE
)

cat("\nDone. Commit the generated manifest.json to GitHub and redeploy.\n")
