# Generate a proper recursive R-only manifest for Posit Connect Cloud.
# Run this from the CATHA project root after installing local R dependencies.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", repos = "https://cloud.r-project.org")
}

# Python/Basic Pitch is intentionally ignored for Connect Cloud.
# Basic Pitch remains a local-only optional feature unless deployed to a Docker host.
rsconnect::writeManifest(
  appDir = getwd(),
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  envManagementR = TRUE,
  envManagementPy = FALSE,
  packageRepositoryResolutionR = "lax",
  forceGeneratePythonEnvironment = FALSE
)

message("Wrote manifest.json. Commit the generated file to GitHub and redeploy in Connect Cloud.")
