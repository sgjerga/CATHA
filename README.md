
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
  - zipped bundle with all outputs

## Files in this project

- `app.R` — main Shiny app
- `R/helpers_audio.R` — audio preparation and feature extraction helpers
- `R/helpers_exports.R` — export helpers for JSON, TextGrid, MusicXML, and zip bundle
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
4. Go to **Segmentation** and brush over the waveform, then add clinically salient segments.
5. Go to **Features & Traces** and run feature extraction.
6. Go to **Annotations & Export** and add transcript excerpts, salience markers, recurrence notes, therapist response notes, and uncertainty.
7. Export the complete bundle for downstream work.

## Notes and limitations

- Pitch estimation is intentionally lightweight and transparent; it is meant as a therapist-guided support trace rather than a definitive readout.
- MusicXML export is a score-oriented trace approximation for downstream experimentation, not a final musicological representation.
- The app avoids automatic emotion labelling or diagnosis by design.

## Practical next improvements

- editable transcript import/export templates
- richer multi-track therapist/patient response tracing
- optional spectrogram view
- better note quantization and score rendering
- secure authentication and encrypted storage for deployment in a hospital environment


## Patch note
- Fixed feature extraction crash caused by a missing `stats::hanning.window()` function by replacing it with an internal Hann window implementation.
- Added safer error handling around feature extraction so the UI shows a notification instead of stalling on backend errors.
