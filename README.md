
# CATHA

This project contains an R Shiny prototype of **CATHA (Clinical Audio Translation for Therapeutic Attunement)**. It is designed as a therapist-guided research support application aligned with the doctoral proposal's computational scope: selective audio handling, episode segmentation, formal feature tracing, uncertainty marking, and non-diagnostic export.

## What the App does

- accepts **uploaded audio** (`.mp3`, `.wav`, `.ogg`, `.m4a`, `.webm`)
- accepts **browser-based microphone recordings from the computer**
- normalizes audio into analysis-ready WAV
- supports therapist-guided **episode segmentation**
- extracts formal features including:
  - duration
  - RMS / intensity estimate
  - pause ratio and pause count
  - voiced fraction
  - estimated pitch contour and summary statistics
- supports therapist-guided annotation:
  - transcript excerpt
  - salience flags
  - recurrence note
  - therapist response note
  - clinical memo
  - uncertainty score
- exports to:
  - `segments.csv`
  - `features.csv`
  - `annotations.csv`
  - `trace.json`
  - `segments.TextGrid` (Praat-compatible)
  - `trace.musicxml`
  - optional Basic Pitch MIDI / note-event CSV / MusicXML outputs
  - zipped bundle with all outputs

## Files in this project

- `app.R` — main Shiny app
- `R/helpers_audio.R` — audio preparation and feature extraction helpers
- `R/helpers_exports.R` — export helpers for JSON, TextGrid, MusicXML, and zip bundle
- `R/helpers_external_notation.R` — optional external Basic Pitch audio-to-MIDI helper
- `www/recorder.js` — browser microphone capture and WAV handoff to Shiny
- `www/styles.css` — UI styling
- `install_packages.R` — package installer
- `run_app.R` — convenience launcher

## Before you run it

### 1) Install R
Install a recent version of R (4.3+ recommended).

### 2) Install required system dependency for MP3 conversion
For `.mp3` and other non-WAV uploads, the app uses **ffmpeg** to convert audio into WAV.

- Windows: install ffmpeg and make sure it is available on PATH
- macOS: `brew install ffmpeg`
- Ubuntu/Debian: `sudo apt-get install ffmpeg`

### 3) Install R packages
Open R or RStudio in this project folder and run:

```r
source("install_packages.R")
```

### 4) Optional: install Basic Pitch for external MIDI transcription
The core CATHA app does not require this. Install it only if you want the optional **Basic Pitch external audio-to-MIDI** engine inside the **Features & Traces** view.

```bash
python -m pip install basic-pitch music21
```

- `basic-pitch` creates MIDI and note-event CSV files from selected segment WAVs.
- `music21` is optional but recommended if you want CATHA to attempt MIDI-to-MusicXML conversion.
- If Shiny cannot find `basic-pitch` or `python`, paste the full executable path into the app's Basic Pitch settings.

## How to open the application

### Option A — easiest
In R or RStudio, set the working directory to this project folder and run:

```r
source("run_app.R")
```

### Option B — directly

```r
shiny::runApp(".", launch.browser = TRUE)
```

## Suggested workflow inside the app

1. Go to **Audio Intake**.
2. Upload an `.mp3` / `.wav` file or record using **Start recording** / **Stop recording**.
3. Inspect the waveform.
4. In **Audio Intake**, brush over the waveform; the selected time range is copied automatically into the segment start/end fields. Then go to **Segmentation** and add clinically salient segments.
5. Go to **Features & Traces** and run feature extraction.
6. Use **CATHA hybrid score** for the built-in transparent pitch-contour trace.
7. Optional: choose **Basic Pitch external audio-to-MIDI** and click **Run Basic Pitch notation** to generate MIDI and note-event CSV files for the selected segments.
8. Go to **Annotations & Export** and add transcript excerpts, salience markers, recurrence notes, therapist response notes, and uncertainty.
9. Export the complete bundle for downstream work.

## Notes and limitations

- Pitch estimation is intentionally lightweight and transparent; it is meant as a therapist-guided support trace rather than a definitive readout.
- The built-in MusicXML export is a score-oriented trace approximation for downstream experimentation, not a final musicological representation.
- Basic Pitch is optional and may generate more music-like MIDI/note events, but speech, breath, consonants, glides, background sound, and overlapping voices can still produce false or unstable note events.
- The app avoids automatic emotion labelling or diagnosis by design.

## License and copyright

Copyright © Sllobodan Gjerga, 2026 (sgjerga@gmail.com).

CATHA is licensed under the **PolyForm Noncommercial License 1.0.0**. The software may be used free of charge for noncommercial academic and research purposes. Commercial use is not permitted under this license without prior written permission. For commercial licensing, contact sgjerga@gmail.com.

Full license text: https://polyformproject.org/licenses/noncommercial/1.0.0

## Practical next improvements

- editable transcript import/export templates
- richer multi-track therapist/patient response tracing
- optional spectrogram view
- compare CATHA trace vs Basic Pitch outputs in joint displays
- better note quantization and score rendering
- secure authentication and encrypted storage for deployment in a hospital environment


## Patch note
- Fixed feature extraction crash caused by a missing `stats::hanning.window()` function by replacing it with an internal Hann window implementation.
- Added safer error handling around feature extraction so the UI shows a notification instead of stalling on backend errors.
- Removed the redundant **Use current brush** button; waveform brushing already populates segment start/end automatically.
- Added copyright and PolyForm Noncommercial licensing information to the About & Documentation view and README.
