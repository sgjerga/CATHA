CATHA Basic Pitch ragged CSV reader fix (2026-05-02)

Replace these files in the CATHA project:
- app.R
- R/helpers_audio.R
- R/helpers_external_notation.R

This patch fixes the Basic Pitch note-event importer. Basic Pitch 0.4.0 writes note-event CSV rows with many pitch-bend values after the first four stable columns. Those rows are ragged: the header has 5 columns, but rows can have many more comma-separated fields. CATHA now parses the first stable columns manually and preserves remaining pitch-bend values as a string.
