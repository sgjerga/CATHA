CATHA Basic Pitch shell-quoting + MIDI fallback fix (2026-05-02)

Replace these files in your CATHA project:
- app.R
- R/helpers_audio.R
- R/helpers_external_notation.R

What changed:
- Safely shell-quotes system2() arguments on Linux/macOS/Windows so paths, filenames, and inline Python code containing spaces/parentheses do not cause: sh: 1: Syntax error: "(" unexpected
- Fixes optional music21 conversion by safely quoting the Python -c script.
- Adds a fallback that reads note events directly from the generated MIDI using pretty_midi when the Basic Pitch CSV is empty or unreadable.
- Adds window_title = "CATHA" to silence the Shiny/bslib window-title warning.

No changes to your .venv-basic-pitch environment are required.
