# Basic Pitch zero-note troubleshooting patch

This patch updates the optional Basic Pitch pathway in CATHA.

## What changed

- Adds `--save-midi` to the Basic Pitch command so MIDI files are always created when Basic Pitch runs.
- Adds advanced Basic Pitch sensitivity controls in the Shiny UI:
  - onset threshold
  - frame/sustain threshold
  - minimum note length
  - minimum frequency
  - maximum frequency
  - multiple pitch bends
  - no-melodia toggle
- Uses speech-friendlier defaults: onset 0.30, frame 0.20, minimum note length 50 ms, frequency range 65–900 Hz.
- Makes the note-event CSV reader more tolerant of column-name variations.
- Adds clearer hints in the UI when Basic Pitch completes but the note-event table is empty.

## Files to replace

Replace these two files in your CATHA project:

- `app.R`
- `R/helpers_external_notation.R`

Keep your existing `.venv-basic-pitch` folder.

## Suggested first settings for spoken voice

Use short, clearly voiced segments first.

- Onset threshold: 0.30
- Frame/sustain threshold: 0.20
- Minimum note length: 50 ms
- Minimum frequency: 65 Hz
- Maximum frequency: 900 Hz
- Allow multiple pitch bends: checked
- Skip melodia post-processing: unchecked

If the table is still empty, try:

- Onset threshold: 0.20
- Frame/sustain threshold: 0.15
- Minimum note length: 30 ms

More sensitive settings can produce false positives, so outputs should be reviewed manually.
