
packages <- c(
  "shiny",
  "bslib",
  "DT",
  "jsonlite",
  "dplyr",
  "ggplot2",
  "tuneR",
  "soundgen",
  "seewave"
)

missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All required packages are already installed.")
}
