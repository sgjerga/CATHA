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
  message("All required R packages are already installed.")
}

message("\nOptional external notation engine:")
message("To enable Basic Pitch MIDI / note-event transcription, install Python packages outside R:")
message("  python -m pip install basic-pitch music21")
message("Basic Pitch is optional; the core CATHA Shiny app still runs without it.")
