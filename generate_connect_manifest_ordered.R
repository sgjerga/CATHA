# Generate a Connect Cloud manifest for CATHA with:
# - R package management enabled
# - Python package management disabled
# - package DESCRIPTION metadata restored
# - package entries ordered so dependencies are listed before dependents
#
# Run from the CATHA project root:
#   source("generate_connect_manifest_ordered.R")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

message("Generating ordered Posit Connect Cloud manifest for CATHA...")

options(repos = c(CRAN = "https://cloud.r-project.org"))

needed <- c(
  "rsconnect",
  "shiny", "bslib", "DT", "jsonlite", "dplyr", "ggplot2", "tuneR", "seewave"
)

missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  message("Installing missing local packages needed for manifest generation: ", paste(missing, collapse = ", "))
  install.packages(missing, dependencies = TRUE)
}

if (file.exists("requirements.txt")) {
  message("NOTE: requirements.txt exists. Connect Cloud R-only deployment should not commit it unless you want Python managed by Connect.")
}

# Create a normal rsconnect manifest first. This is the official format Connect Cloud expects.
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

manifest <- jsonlite::read_json("manifest.json", simplifyVector = FALSE)

# Ensure Python management is disabled even if an older manifest had Python metadata.
manifest$environment$environment_management$python <- FALSE
manifest$python <- NULL

pkg_names <- names(manifest$packages)

# Restore full DESCRIPTION fields from the installed package library. Handwritten manifests
# often omit Imports/Depends, which can make Connect install packages in a bad order.
for (pkg in pkg_names) {
  desc <- tryCatch(utils::packageDescription(pkg), error = function(e) NULL)
  if (is.null(desc)) next
  desc_list <- as.list(desc)
  desc_list <- desc_list[vapply(desc_list, function(x) length(x) == 1 && !is.na(x), logical(1))]
  desc_list <- lapply(desc_list, as.character)

  manifest$packages[[pkg]]$Source <- manifest$packages[[pkg]]$Source %||% "CRAN"
  manifest$packages[[pkg]]$Repository <- manifest$packages[[pkg]]$Repository %||% "https://cloud.r-project.org"
  manifest$packages[[pkg]]$description <- desc_list
  manifest$packages[[pkg]]$description$Repository <- manifest$packages[[pkg]]$description$Repository %||% "CRAN"
  manifest$packages[[pkg]]$description$RemoteType <- manifest$packages[[pkg]]$description$RemoteType %||% "standard"
  manifest$packages[[pkg]]$description$RemotePkgRef <- manifest$packages[[pkg]]$description$RemotePkgRef %||% pkg
  manifest$packages[[pkg]]$description$RemoteRef <- manifest$packages[[pkg]]$description$RemoteRef %||% pkg
  manifest$packages[[pkg]]$description$RemoteRepos <- manifest$packages[[pkg]]$description$RemoteRepos %||% "https://cloud.r-project.org/"
}

parse_dep_names <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) return(character())
  x <- gsub("\\n", " ", x)
  parts <- unlist(strsplit(x, ",", fixed = TRUE), use.names = FALSE)
  parts <- trimws(gsub("\\s*\\(.*?\\)", "", parts))
  parts <- parts[nzchar(parts) & parts != "R"]
  unique(parts)
}

pkg_deps <- setNames(vector("list", length(pkg_names)), pkg_names)
for (pkg in pkg_names) {
  desc <- manifest$packages[[pkg]]$description
  deps <- unique(c(
    parse_dep_names(desc$Depends),
    parse_dep_names(desc$Imports),
    parse_dep_names(desc$LinkingTo)
  ))
  pkg_deps[[pkg]] <- intersect(deps, pkg_names)
}

# Topological sort: dependencies before packages that need them.
ordered <- character()
visiting <- new.env(parent = emptyenv())
visited <- new.env(parent = emptyenv())

visit <- function(pkg) {
  if (isTRUE(visited[[pkg]])) return()
  if (isTRUE(visiting[[pkg]])) return()
  visiting[[pkg]] <- TRUE
  for (dep in pkg_deps[[pkg]]) visit(dep)
  visited[[pkg]] <- TRUE
  ordered <<- c(ordered, pkg)
}

for (pkg in pkg_names) visit(pkg)
ordered <- unique(ordered)

manifest$packages <- manifest$packages[ordered]

jsonlite::write_json(
  manifest,
  path = "manifest.json",
  pretty = TRUE,
  auto_unbox = TRUE,
  null = "null"
)

message("Wrote ordered manifest.json with ", length(ordered), " R packages.")
message("First packages in install order: ", paste(head(ordered, 12), collapse = ", "))
message("Check examples:")
message("  fontawesome Imports: ", manifest$packages$fontawesome$description$Imports %||% "<not included>")
message("  seewave Depends/Imports: ", paste(c(manifest$packages$seewave$description$Depends, manifest$packages$seewave$description$Imports), collapse = " | "))

