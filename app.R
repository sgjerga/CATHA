
options(shiny.maxRequestSize = 100 * 1024^2)

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(jsonlite)
  library(dplyr)
  library(ggplot2)
  library(tuneR)
  library(seewave)
  library(cpp11)
})

source(file.path("R", "helpers_audio.R"))
source(file.path("R", "helpers_exports.R"))
source(file.path("R", "helpers_external_notation.R"))

required_packages <- c("shiny", "bslib", "DT", "jsonlite", "dplyr", "ggplot2", "tuneR", "seewave", "cpp11")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop(
    sprintf(
      "Missing packages: %s\nRun install_packages.R first, then restart the app.",
      paste(missing_packages, collapse = ", ")
    ),
    call. = FALSE
  )
}

app_theme <- bs_theme(
  version = 5,
  bootswatch = "minty",
  base_font = font_google("Inter"),
  code_font = font_google("JetBrains Mono")
)

salience_options <- c(
  "Orientation-seeking speech present",
  "Marked silence or pause sequence",
  "Vocal shift in intensity/register/contour",
  "Recurrent phrase or melodic-speech motif",
  "Containment/disclosure transition",
  "Notable response to therapist music or song",
  "Clinically meaningful therapist-patient shift"
)

ui <- page_navbar(
  title = div(
    class = "catha-brand catha-brand-compact",
    tags$div(
      class = "catha-brand-copy",
      tags$span(class = "catha-brand-title", "CATHA"),
      tags$small("Clinical Audio Translation for Therapeutic Attunement")
    )
  ),
  id = "main_nav",
  window_title = "CATHA",
  theme = app_theme,
  header = tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
      tags$script(src = "recorder.js?v=20260502-recording-final-noise-filter"),
      # ABCJS for sheet music rendering
      tags$script(src = "https://cdn.jsdelivr.net/npm/abcjs@6.2.2/dist/abcjs-basic-min.js"),
      tags$script(HTML("
        $(document).on('shiny:sessioninitialized', function() {
          Shiny.addCustomMessageHandler('render_abc', function(abc) {
            if(document.getElementById('paper')) {
              ABCJS.renderAbc('paper', abc, { responsive: 'resize' });
            }
          });
          Shiny.addCustomMessageHandler('render_external_abc', function(abc) {
            if(document.getElementById('external_paper')) {
              if(!abc || !String(abc).trim()) {
                document.getElementById('external_paper').innerHTML = '<p class=\"small muted-text mb-0\">No external note score available yet.</p>';
              } else {
                ABCJS.renderAbc('external_paper', abc, { responsive: 'resize' });
              }
            }
          });
        });
      "))
    )
  ),
  
  nav_panel(
    "Audio Intake",
    p(class = "lead mb-3", style = "color: #557086;", "Load and standardize clinical audio files or capture fresh recordings to prepare them for acoustic analysis."),
    page_fillable(
      fillable = FALSE,
      layout_columns(
        col_widths = c(4, 8),
        card(
          class = "catha-card",
          card_header("1. Load or record audio"),
          p(class = "muted-text", "Use a pre-recorded .mp3/.wav file or capture a fresh browser-based computer microphone recording."),
          fileInput(
            "audio_upload",
            label = "Upload audio",
            accept = c(".mp3", ".wav", ".ogg", ".m4a", ".webm")
          ),
          div(
            class = "record-grid",
            actionButton("start_recording", "Start recording", class = "btn-success"),
            actionButton("stop_recording", "Stop recording", class = "btn-outline-danger")
          ),
          div(id = "recording_badge", class = "status-badge idle", "Recorder idle"),
          div(
            id = "recording_preview_shell",
            class = "audio-shell",
            style = "display: none; margin-top: 0.75rem;",
            tags$strong("Immediate browser preview"),
            tags$p(
              class = "small muted-text mb-2",
              "This preview appears as soon as the browser has encoded the recording. The analysis player and waveform appear after Shiny has imported the WAV."
            ),
            tags$audio(id = "recording_preview_audio", controls = NA, style = "width: 100%;")
          ),
          actionButton("reset_audio", "Clear current audio", class = "btn-outline-secondary"),
          hr(),
          h6("Audio preparation"),
          checkboxInput("downmix_to_mono", "Downmix audio to mono for analysis", value = TRUE),
          numericInput("analysis_sample_rate", "Target sample rate (Hz)", value = 44100, min = 8000, max = 96000, step = 1000),
          checkboxInput("reduce_background_noise", "Reduce ambient/background noise before analysis", value = FALSE),
          conditionalPanel(
            condition = "input.reduce_background_noise === true",
            selectInput(
              "noise_reduction_strength",
              "Noise reduction strength",
              choices = c("Light", "Medium", "Strong"),
              selected = "Medium"
            ),
            checkboxInput("speech_bandpass", "Also apply gentle speech band-pass filter (80–8000 Hz)", value = TRUE)
          ),
          actionButton("reprocess_audio", "Apply preparation settings to current audio", class = "btn-outline-primary"),
          uiOutput("preprocessing_status_ui"),
          p(class = "small muted-text", "The selected preparation is applied before waveform display, segmentation, feature extraction, and musical translation. Noise reduction uses ffmpeg's transparent spectral denoise filter; it is optional because very strong filtering can remove clinically relevant breath/noise cues.")
        ),
        card(
          class = "catha-card",
          full_screen = TRUE,
          card_header("2. Inspect waveform"),
          uiOutput("audio_player_ui"),
          plotOutput("waveform_plot", height = 340, brush = brushOpts(id = "wave_brush", direction = "x", resetOnNew = TRUE)),
          div(class = "brush-hint", "Tip: brush over the waveform to populate segment start/end automatically."),
          layout_columns(
            col_widths = c(3, 3, 3, 3),
            value_box(title = "Duration", value = textOutput("duration_box", inline = TRUE), showcase = NULL, theme = value_box_theme(bg = "#edf7f3")),
            value_box(title = "Sample rate", value = textOutput("sample_rate_box", inline = TRUE), showcase = NULL, theme = value_box_theme(bg = "#eef4ff")),
            value_box(title = "Channels", value = textOutput("channels_box", inline = TRUE), showcase = NULL, theme = value_box_theme(bg = "#fff4ea")),
            value_box(title = "Bit depth", value = textOutput("bit_box", inline = TRUE), showcase = NULL, theme = value_box_theme(bg = "#f6efff"))
          )
        )
      )
    )
  ),
  
  nav_panel(
    "Segmentation",
    p(class = "lead mb-3", style = "color: #557086;", "Isolate specific episodes of clinically salient speech by brushing the waveform, ensuring extraction focuses only on meaningful moments."),
    page_fillable(
      fillable = FALSE,
      layout_columns(
        col_widths = c(4, 8),
        card(
          class = "catha-card",
          card_header("3. Define clinically salient segments"),
          textInput("segment_label", "Segment label", value = "Episode 1"),
          numericInput("segment_start", "Start (seconds)", value = 0, min = 0, step = 0.1),
          numericInput("segment_end", "End (seconds)", value = 5, min = 0, step = 0.1),
          textAreaInput("segment_note", "Quick segment note", rows = 3, placeholder = "Why is this episode clinically salient?"),
          actionButton("add_segment", "Add segment", class = "btn-primary"),
          br(), br(),
          actionButton("delete_segment", "Delete selected segment", class = "btn-outline-danger"),
          actionButton("clear_segments", "Clear all segments", class = "btn-outline-secondary")
        ),
        card(
          class = "catha-card",
          full_screen = TRUE,
          card_header("Segment table"),
          DTOutput("segments_table")
        )
      )
    )
  ),
  
  nav_panel(
    "Features & Traces",
    p(class = "lead mb-3", style = "color: #557086;", "Extract formal acoustic features—such as pitch contour and intensity—from your defined segments to visualize the patient's voiced expression."),
    page_fillable(
      fillable = FALSE,
      layout_columns(
        col_widths = c(4, 8),
        card(
          class = "catha-card",
          card_header("4. Extract formal features"),
          p(class = "muted-text", "Computes analysis-friendly traces from the current prepared audio: duration, intensity, pauses, pitch contour, and voiced fraction."),
          numericInput("frame_ms", "Frame size (ms)", value = 40, min = 10, max = 250, step = 5),
          numericInput("pitch_floor", "Pitch floor (Hz)", value = 75, min = 30, max = 400, step = 5),
          numericInput("pitch_ceiling", "Pitch ceiling (Hz)", value = 500, min = 100, max = 1000, step = 10),
          sliderInput("silence_quantile", "Pause threshold quantile", min = 0.01, max = 0.5, value = 0.15, step = 0.01),
          actionButton("run_features", "Run feature extraction", class = "btn-primary"),
          hr(),
          h6("Notation engines"),
          p(class = "small muted-text", "The default CATHA score remains a transparent acoustic trace. Basic Pitch is optional and creates external MIDI / note-event outputs for a more music-like transcription."),
          selectInput(
            "notation_engine",
            "Notation engine",
            choices = c(
              "CATHA hybrid trace (built in)" = "catha_trace",
              "Basic Pitch external audio-to-MIDI" = "basic_pitch"
            ),
            selected = "catha_trace"
          ),
          conditionalPanel(
            condition = "input.notation_engine === 'basic_pitch'",
            textInput("basic_pitch_command", "Basic Pitch executable or full path", value = default_executable_command("basic-pitch", "Basic Pitch")),
            tags$details(
              tags$summary("Advanced Basic Pitch sensitivity settings"),
              p(class = "small muted-text", "For spoken voice, lower thresholds may detect more note events but can also create false positives. Start with short, voiced segments and review results manually."),
              numericInput("basic_pitch_onset_threshold", "Onset threshold", value = 0.30, min = 0.01, max = 0.99, step = 0.05),
              numericInput("basic_pitch_frame_threshold", "Frame/sustain threshold", value = 0.20, min = 0.01, max = 0.99, step = 0.05),
              numericInput("basic_pitch_minimum_note_length", "Minimum note length (ms)", value = 50, min = 10, max = 1000, step = 10),
              numericInput("basic_pitch_minimum_frequency", "Minimum frequency (Hz)", value = 65, min = 30, max = 400, step = 5),
              numericInput("basic_pitch_maximum_frequency", "Maximum frequency (Hz)", value = 900, min = 100, max = 2000, step = 25),
              checkboxInput("basic_pitch_multiple_bends", "Allow multiple pitch bends", value = TRUE),
              checkboxInput("basic_pitch_no_melodia", "Skip Basic Pitch melodia post-processing", value = FALSE)
            ),
            checkboxInput("basic_pitch_to_musicxml", "Try converting Basic Pitch MIDI to MusicXML with Python music21", value = TRUE),
            conditionalPanel(
              condition = "input.basic_pitch_to_musicxml === true",
              textInput("python_command", "Python executable used for optional music21 conversion", value = default_executable_command("python", "Python"))
            ),
            actionButton("run_external_notation", "Run Basic Pitch notation", class = "btn-outline-primary"),
            uiOutput("external_notation_status_ui"),
            p(class = "small muted-text", "Install outside R with: python -m pip install basic-pitch music21. If the app cannot find the commands, paste their full paths here.")
          ),
          hr(),
          uiOutput("trace_segment_ui")
        ),
        card(
          class = "catha-card",
          full_screen = TRUE,
          card_header("Trace visualisation"),
          tabsetPanel(
            id = "trace_tabs",
            tabPanel("Pitch contour", plotOutput("pitch_plot", height = 320)),
            tabPanel("Intensity / pauses", plotOutput("intensity_plot", height = 320)),
            tabPanel("Feature table", DTOutput("features_table")),
            tabPanel("CATHA hybrid score", 
                     tags$div(id = "paper", style = "background: white; padding: 15px; border-radius: 8px; margin-top: 15px; border: 1px solid var(--catha-border); overflow-x: auto;"),
                     DTOutput("notation_table")),
            tabPanel("External MIDI notes",
                     uiOutput("external_notation_summary_ui"),
                     uiOutput("external_score_segment_ui"),
                     tags$div(id = "external_paper", style = "background: white; padding: 15px; border-radius: 8px; margin-top: 15px; border: 1px solid var(--catha-border); overflow-x: auto;"),
                     tags$p(class = "small muted-text mt-2", "Rendered from Basic Pitch note events with the same ABC score engine used for the CATHA hybrid score. Durations are quantized for display and should be reviewed manually."),
                     DTOutput("external_notation_table"))
          )
        )
      )
    )
  ),
  
  nav_panel(
    "Annotations & Export",
    p(class = "lead mb-3", style = "color: #557086;", "Integrate acoustic traces with your clinical interpretation, mark interpretive uncertainties, and export the complete data bundle for downstream analysis."),
    page_fillable(
      fillable = FALSE,
      layout_columns(
        col_widths = c(4, 8),
        card(
          class = "catha-card",
          card_header("5. Therapist-guided annotation"),
          uiOutput("annotation_segment_ui"),
          textAreaInput("transcript_text", "Transcript / excerpt", rows = 4, placeholder = "Paste or type the transcript excerpt here"),
          checkboxGroupInput("salience_flags", "Salience markers", choices = salience_options),
          sliderInput("uncertainty_score", "Interpretive uncertainty", min = 0, max = 100, value = 30, post = "%"),
          textInput("recurrence_note", "Recurrence / motif note"),
          textInput("response_note", "Therapist response note"),
          textAreaInput("clinical_note", "Clinical / analytic memo", rows = 5),
          selectInput("recommended_export", "Recommended representation", choices = c("Transcript only", "Trace", "Full score"), selected = "Trace"),
          actionButton("save_annotation", "Save annotation", class = "btn-primary")
        ),
        card(
          class = "catha-card",
          full_screen = TRUE,
          card_header("6. Integrated export-ready view"),
          DTOutput("joint_table"),
          div(
            class = "download-grid",
            downloadButton("download_segments", "Segments CSV"),
            downloadButton("download_features", "Features CSV"),
            downloadButton("download_annotations", "Annotations CSV"),
            downloadButton("download_trace_json", "Trace JSON"),
            downloadButton("download_textgrid", "Praat TextGrid"),
            downloadButton("download_musicxml", "CATHA MusicXML"),
            downloadButton("download_basic_pitch_midi", "Basic Pitch MIDI"),
            downloadButton("download_basic_pitch_notes", "Basic Pitch notes CSV"),
            downloadButton("download_basic_pitch_musicxml", "Basic Pitch MusicXML"),
            downloadButton("download_bundle", "Full CATHA bundle")
          )
        )
      )
    )
  ),
  
  nav_panel(
    "About & Documentation",
    page_fillable(
      fillable = FALSE,
      card(
        class = "catha-card",
        card_header("CATHA App Documentation"),
        
        tags$h4("What CATHA Stands For"),
        tags$p(tags$strong("Clinical Audio Translation for Therapeutic Attunement")),
        tags$p(
          "CATHA is a therapist-guided research-support application for preserving selected formal aspects of voiced expression in oncology and palliative-care music therapy. Its outputs are analytic traces and documentation aids, not diagnostic statements."
        ),

        tags$hr(),
        tags$h4("What CATHA Does"),
        tags$p(
          "CATHA accepts uploaded or browser-recorded audio, prepares it as analysis-ready WAV, supports therapist-defined episode segmentation, extracts selected acoustic features, and exports segment metadata, features, annotations, JSON, Praat TextGrid, MusicXML, MIDI, and note-event CSV files."
        ),
        tags$p(
          "The default CATHA score is a transparent hybrid pitch-contour notation derived from frame-level acoustic tracing. The optional MIDI-based notation pathway uses Basic Pitch to infer note events and produce external MIDI / note-event outputs. This is usually the more accurate and musically readable option when the aim is discrete-note transcription, while the built-in CATHA score remains better for transparent clinical tracing of speech contour and uncertainty."
        ),
        tags$p(
          class = "small muted-text",
          "Important: neither notation pathway should be interpreted as a direct readout of emotion, intention, diagnosis, prognosis, or inner truth. Speech contains breath, consonants, glides, unstable F0, pauses, and noise; all rendered scores should be reviewed manually and interpreted only within clinical context."
        ),

        tags$hr(),
        tags$h4("Core Workflow"),
        tags$ol(
          tags$li(tags$strong("Audio Intake: "), "Upload .wav, .mp3, .ogg, .m4a, or .webm audio, or record directly from the browser microphone. CATHA prepares a standardized WAV and displays the waveform."),
          tags$li(tags$strong("Segmentation: "), "Brush over the waveform to select clinically salient moments. The brushed time range is copied automatically into the segment start/end fields. Add a label and segment note, then save the segment."),
          tags$li(tags$strong("Features & Traces: "), "Run feature extraction to calculate duration, RMS/intensity, pause measures, voiced fraction, pitch contour, pitch range, and summary statistics. Review the pitch contour, intensity trace, feature table, and CATHA hybrid score."),
          tags$li(tags$strong("External MIDI Notation: "), "Choose 'Basic Pitch external audio-to-MIDI', confirm the Basic Pitch and Python paths, adjust sensitivity if needed, and click 'Run Basic Pitch notation'. Review the rendered external score and the note-event table."),
          tags$li(tags$strong("Annotations & Export: "), "Attach transcripts, salience flags, recurrence notes, therapist-response notes, clinical memos, and uncertainty ratings. Export individual files or the full CATHA bundle.")
        ),

        tags$hr(),
        tags$h4("Software Architecture"),
        tags$ul(
          tags$li(tags$strong("R Shiny frontend/backend: "), "main interface, upload/record handling, segment management, plotting, tables, and export controls."),
          tags$li(tags$strong("Browser JavaScript recorder: "), "captures microphone audio in the browser and passes WAV data to Shiny."),
          tags$li(tags$strong("R audio helpers: "), "standardize audio, optionally reduce noise / apply speech band-pass filtering, extract acoustic traces, and write segment WAVs."),
          tags$li(tags$strong("R export helpers: "), "write CSV, JSON, TextGrid, CATHA MusicXML, and ZIP bundles."),
          tags$li(tags$strong("Optional Python layer: "), "runs Basic Pitch for audio-to-MIDI transcription and music21 / pretty_midi for MIDI conversion and fallback note extraction."),
          tags$li(tags$strong("ABCJS score rendering: "), "renders the in-app CATHA hybrid score and external MIDI score in the browser.")
        ),

        tags$hr(),
        tags$h4("R Dependencies"),
        tags$p("CATHA relies on these R packages:"),
        tags$ul(
          tags$li(tags$code("shiny"), " — web application framework."),
          tags$li(tags$code("bslib"), " — Bootstrap cards, layout, theming, and navigation."),
          tags$li(tags$code("DT"), " — interactive tables for segments, features, annotations, and note events."),
          tags$li(tags$code("jsonlite"), " — JSON trace export."),
          tags$li(tags$code("dplyr"), " — table manipulation and joins."),
          tags$li(tags$code("ggplot2"), " — waveform, pitch, and intensity visualisation."),
          tags$li(tags$code("tuneR"), " — WAV reading/writing and segment extraction."),
          tags$li(tags$code("seewave"), " — acoustic feature extraction, especially pitch estimation for the default CATHA trace."),
          tags$li(tags$code("tools"), ", ", tags$code("stats"), ", and ", tags$code("utils"), " — base/recommended R packages used for file handling, statistics, and ZIP export.")
        ),
        tags$p("Install the R packages from the project root with:"),
        tags$pre("source(\"install_packages.R\")"),
        tags$p("Or install them manually in R:"),
        tags$pre("install.packages(c(\n  \"shiny\", \"bslib\", \"DT\", \"jsonlite\", \"dplyr\",\n  \"ggplot2\", \"tuneR\", \"seewave\"\n), repos = \"https://cloud.r-project.org\")"),

        tags$hr(),
        tags$h4("System Dependencies"),
        tags$ul(
          tags$li(tags$strong("R 4.3+ recommended: "), "the app is developed as an R Shiny prototype."),
          tags$li(tags$strong("ffmpeg: "), "required for reliable conversion of MP3, M4A, OGG, and WebM uploads into analysis-ready WAV."),
          tags$li(tags$strong("Modern browser: "), "Chrome/Chromium, Firefox, or similar. Browser recording requires localhost, 127.0.0.1, or HTTPS."),
          tags$li(tags$strong("Internet access for score rendering: "), "the app currently loads ABCJS from a CDN. For offline or hospital deployment, download ABCJS and serve it locally from the www folder.")
        ),
        tags$p("Ubuntu / Debian system preparation:"),
        tags$pre("sudo apt update\nsudo apt install r-base ffmpeg python3-full python3-venv curl"),
        tags$p("macOS system preparation, if using Homebrew:"),
        tags$pre("brew install ffmpeg"),
        tags$p("Windows preparation: install R/RStudio and ffmpeg, then make sure ffmpeg is available on PATH."),

        tags$hr(),
        tags$h4("Optional Python Dependencies for MIDI-Based Notation"),
        tags$p(
          "The Basic Pitch feature is optional. The core CATHA app runs without Python, but MIDI-based notation requires a separate Python environment. This is the recommended setup on Ubuntu 24.04 / recent Debian systems, where global pip installs are blocked for safety."
        ),
        tags$pre("cd /home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v8\n\n# Install uv if needed\ncurl -LsSf https://astral.sh/uv/install.sh | sh\nsource ~/.bashrc\n\n# Create a Python 3.11 environment for Basic Pitch\nuv venv .venv-basic-pitch --python 3.11 --seed\n\n# Install Basic Pitch and conversion helpers\nuv pip install --python .venv-basic-pitch pip wheel \"setuptools<81\"\nuv pip install --python .venv-basic-pitch \"basic-pitch==0.4.0\" music21"),
        tags$p("Then test the installation from the project root:"),
        tags$pre(".venv-basic-pitch/bin/basic-pitch --help\n.venv-basic-pitch/bin/python -c \"import music21, pretty_midi; print('Python notation tools OK')\""),
        tags$p("In the CATHA app, use these paths:"),
        tags$pre("Basic Pitch executable:\n/home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v8/.venv-basic-pitch/bin/basic-pitch\n\nPython executable for music21 / MIDI fallback:\n/home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v8/.venv-basic-pitch/bin/python"),
        tags$p(
          class = "small muted-text",
          "TensorFlow/CUDA warnings are usually harmless on a CPU-only laptop. Basic Pitch can run on CPU; it may simply take longer on long recordings."
        ),

        tags$hr(),
        tags$h4("Default CATHA Hybrid Score vs MIDI-Based Notation"),
        tags$h5("1. Default CATHA hybrid score"),
        tags$ul(
          tags$li("Uses the app's own transparent pitch-contour extraction and quantization."),
          tags$li("Best for therapist-guided acoustic tracing, preserving contour, pauses, intensity, uncertainty, and clinical context."),
          tags$li("Intentionally conservative: it does not claim to be exact musical transcription."),
          tags$li("Recommended when your research focus is formal tracing of speech under finitude rather than producing a polished melody transcription.")
        ),
        tags$h5("2. Basic Pitch MIDI-based notation"),
        tags$ul(
          tags$li("Uses an external audio-to-MIDI model to infer note events from the selected segment."),
          tags$li("Usually more accurate and musically readable when the target is discrete musical notes, MIDI, or a conventional score-like representation."),
          tags$li("Exports MIDI, note-event CSV, and, when music21 conversion succeeds, MusicXML."),
          tags$li("Works best on clear, voiced, relatively stable, single-source audio. It can struggle with ordinary speech, breath noise, consonants, overlapping sounds, or very short segments."),
          tags$li("Should be treated as a candidate transcription requiring manual review, not as a clinical interpretation.")
        ),
        tags$p("Recommended first Basic Pitch settings for speech/sung-speech testing:"),
        tags$pre("Onset threshold: 0.30\nFrame/sustain threshold: 0.20\nMinimum note length: 50 ms\nMinimum frequency: 65 Hz\nMaximum frequency: 900 Hz\nAllow multiple pitch bends: enabled"),
        tags$p("If too few notes appear, try a longer voiced segment or lower sensitivity settings:"),
        tags$pre("Onset threshold: 0.20\nFrame/sustain threshold: 0.15\nMinimum note length: 30 ms"),

        tags$hr(),
        tags$h4("How to Run the App"),
        tags$pre("setwd(\"/home/enio/Downloads/CATHA/CATHA_Shiny_Prototype_v8\")\nsource(\"run_app.R\")"),
        tags$p("A typical Basic Pitch test from the terminal is:"),
        tags$pre("mkdir -p basic_pitch_test
.venv-basic-pitch/bin/basic-pitch --save-midi --save-note-events basic_pitch_test file_example_MP3_700KB.mp3"),
        tags$p("If this creates a .mid file and a .csv file, the Python side is working. If CATHA does not show notes, check that your selected segment includes the voiced part of the recording and that the Basic Pitch executable path is correct."),

        tags$hr(),
        tags$h4("Copyright and License"),
        tags$p(tags$strong("Copyright: "), "© Sllobodan Gjerga, 2026 (sgjerga@gmail.com)."),
        tags$p(
          tags$strong("License: "),
          tags$a(
            "PolyForm Noncommercial License 1.0.0",
            href = "https://polyformproject.org/licenses/noncommercial/1.0.0",
            target = "_blank",
            rel = "noopener noreferrer"
          ),
          ". CATHA may be used free of charge for noncommercial academic and research purposes. Commercial use is not permitted under this license without prior written permission; for commercial licensing, contact sgjerga@gmail.com."
        ),
        tags$p(
          class = "small muted-text",
          "This licensing notice is informational and does not replace the full LICENSE file distributed with the source code."
        )
      )
    )
  ),
  
  # NEW: Push to the right and display the enlarged, locked-ratio logo
  nav_spacer(),
  nav_item(
    tags$img(src = "CATHA_Logo.png", height = "75px", alt = "CATHA Logo", style = "width: auto; object-fit: contain;")
  )
)

server <- function(input, output, session) {
  `%notin%` <- Negate(`%in%`)
  resource_id <- paste0("catha_audio_", gsub("[^A-Za-z0-9]", "", session$token))
  session_dir <- file.path(tempdir(), resource_id)
  dir.create(session_dir, recursive = TRUE, showWarnings = FALSE)
  addResourcePath(resource_id, session_dir)
  
  rv <- reactiveValues(
    audio_source = NULL,
    audio_original_name = NULL,
    audio_input_path = NULL,
    audio_input_display_name = NULL,
    audio_input_source_type = NULL,
    audio_wav_path = NULL,
    audio_wave = NULL,
    audio_summary = NULL,
    audio_preprocessing = NULL,
    segments = tibble(
      segment_id = integer(),
      label = character(),
      start = double(),
      end = double(),
      duration = double(),
      segment_note = character()
    ),
    annotations = tibble(
      segment_id = integer(),
      transcript = character(),
      salience_flags = character(),
      uncertainty = integer(),
      recurrence_note = character(),
      response_note = character(),
      clinical_note = character(),
      recommended_export = character()
    ),
    features = tibble(),
    traces = list(),
    external_notation = NULL
  )
  
  empty_state <- function() {
    rv$audio_source <- NULL
    rv$audio_original_name <- NULL
    rv$audio_input_path <- NULL
    rv$audio_input_display_name <- NULL
    rv$audio_input_source_type <- NULL
    rv$audio_wav_path <- NULL
    rv$audio_wave <- NULL
    rv$audio_summary <- NULL
    rv$audio_preprocessing <- NULL
    rv$segments <- rv$segments[0, ]
    rv$annotations <- rv$annotations[0, ]
    rv$features <- tibble()
    rv$traces <- list()
    rv$external_notation <- NULL
  }
  
  stage_source_audio <- function(input_path, display_name) {
    req(file.exists(input_path))
    ext <- tolower(tools::file_ext(display_name %||% input_path))
    if (!nzchar(ext)) ext <- tolower(tools::file_ext(input_path))
    if (!nzchar(ext)) ext <- "wav"
    stem <- sanitize_stem(display_name %||% basename(input_path))
    staged_name <- sprintf(
      "%s_%s_source.%s",
      format(Sys.time(), "%Y%m%d_%H%M%S"),
      stem,
      ext
    )
    staged_path <- file.path(session_dir, staged_name)
    ok <- file.copy(input_path, staged_path, overwrite = TRUE)
    if (!ok) stop("Could not stage the source audio for preprocessing.", call. = FALSE)
    staged_path
  }

  current_preprocessing_settings <- function() {
    reduce_noise <- isTRUE(input$reduce_background_noise)
    strength <- input$noise_reduction_strength %||% "Medium"
    bandpass <- if (is.null(input$speech_bandpass)) TRUE else isTRUE(input$speech_bandpass)
    list(
      reduce_background_noise = reduce_noise,
      noise_reduction_strength = strength,
      speech_bandpass = bandpass,
      label = if (reduce_noise) {
        paste0(
          "Ambient/background-noise reduction: ", strength,
          if (bandpass) " + speech band-pass" else ""
        )
      } else {
        "Ambient/background-noise reduction: off"
      }
    )
  }

  load_audio <- function(input_path, display_name, source_type = "Upload", stage_source = TRUE) {
    req(file.exists(input_path))

    source_path <- input_path
    if (isTRUE(stage_source)) {
      source_path <- stage_source_audio(input_path, display_name)
      rv$audio_input_path <- source_path
      rv$audio_input_display_name <- display_name
      rv$audio_input_source_type <- source_type
    }

    prep <- current_preprocessing_settings()
    prep_slug <- if (isTRUE(prep$reduce_background_noise)) {
      paste0("denoised_", tolower(prep$noise_reduction_strength))
    } else {
      "unfiltered"
    }
    out_name <- paste0(
      sanitize_stem(display_name), "_",
      format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
      prep_slug,
      "_analysis.wav"
    )
    out_path <- file.path(session_dir, out_name)

    message(
      "[CATHA audio] preparing analysis WAV: noise_reduction=", prep$reduce_background_noise,
      ", strength=", prep$noise_reduction_strength,
      ", speech_bandpass=", prep$speech_bandpass
    )

    wav_path <- ensure_wav(
      input_path = source_path,
      output_path = out_path,
      sample_rate = input$analysis_sample_rate,
      mono = isTRUE(input$downmix_to_mono),
      reduce_background_noise = prep$reduce_background_noise,
      noise_reduction_strength = prep$noise_reduction_strength,
      speech_bandpass = prep$speech_bandpass
    )
    wave <- safe_read_wave(wav_path)
    summary <- summarize_wave(wave, display_name, source_type)
    summary$preprocessing <- prep$label

    rv$audio_source <- source_type
    rv$audio_original_name <- display_name
    rv$audio_wav_path <- wav_path
    rv$audio_wave <- wave
    rv$audio_summary <- summary
    rv$audio_preprocessing <- prep$label
    rv$segments <- rv$segments[0, ]
    rv$annotations <- rv$annotations[0, ]
    rv$features <- tibble()
    rv$traces <- list()
    rv$external_notation <- NULL

    updateTextInput(session, "segment_label", value = "Episode 1")
    updateNumericInput(session, "segment_start", value = 0)
    updateNumericInput(session, "segment_end", value = min(5, summary$duration_seconds))
  }

  observeEvent(input$audio_upload, {
    req(input$audio_upload)
    tryCatch(
      {
        load_audio(input$audio_upload$datapath, input$audio_upload$name, source_type = "File upload", stage_source = TRUE)
        showNotification(sprintf("Audio loaded for analysis. %s", rv$audio_preprocessing %||% ""), type = "message")
      },
      error = function(e) {
        showNotification(paste("Audio load failed:", conditionMessage(e)), type = "error", duration = 8)
      }
    )
  })
  
  recording_chunks <- new.env(parent = emptyenv())
  processed_recording_ids <- new.env(parent = emptyenv())
  
  safe_recording_filename <- function(name) {
    name <- if (is.null(name) || !nzchar(name)) "catha_recording.wav" else basename(name)
    name <- gsub("[^A-Za-z0-9_.-]", "_", name)
    if (!grepl("\\.wav$", name, ignore.case = TRUE)) {
      name <- paste0(tools::file_path_sans_ext(name), ".wav")
    }
    paste0(format(Sys.time(), "%Y%m%d_%H%M%S_"), name)
  }
  
  import_recording_payload <- function(payload, transport = "direct") {
    if (is.character(payload) && length(payload) == 1) {
      payload <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
    }
    if (is.null(payload$data) || !nzchar(payload$data)) {
      stop("The recording payload did not contain audio data.", call. = FALSE)
    }
    recording_id <- payload$id %||% payload$recording_id %||% payload$nonce %||% paste0("recording_", as.integer(Sys.time()))
    processed_key <- paste0("id_", gsub("[^A-Za-z0-9_.-]", "_", recording_id))
    if (exists(processed_key, envir = processed_recording_ids, inherits = FALSE)) {
      message("[CATHA recorder] duplicate recording ignored: ", recording_id)
      session$sendCustomMessage(
        "catha-recording-loaded",
        list(message = "Recording already loaded and ready for segmentation/features.", id = recording_id)
      )
      return(invisible(NULL))
    }
    
    record_name <- safe_recording_filename(payload$name %||% "catha_recording.wav")
    record_path <- file.path(session_dir, record_name)
    raw_audio <- jsonlite::base64_dec(payload$data)
    writeBin(raw_audio, record_path)
    message("[CATHA recorder] saved ", length(raw_audio), " bytes via ", transport, " to ", record_path)
    
    load_audio(record_path, basename(record_path), source_type = "Browser recording", stage_source = TRUE)
    assign(processed_key, TRUE, envir = processed_recording_ids)
    showNotification("Browser recording captured and loaded.", type = "message")
    session$sendCustomMessage(
      "catha-recording-loaded",
      list(
        message = sprintf("Recording loaded: %s", basename(record_path)),
        id = recording_id,
        bytes = length(raw_audio),
        duration = rv$audio_summary$duration_seconds %||% NA_real_
      )
    )
  }
  
  observeEvent(input$recorded_audio, {
    message("[CATHA recorder] recorded_audio event received")
    tryCatch(
      import_recording_payload(input$recorded_audio, transport = "direct Shiny input"),
      error = function(e) {
        message("[CATHA recorder] direct import failed: ", conditionMessage(e))
        showNotification(paste("Recording import failed:", conditionMessage(e)), type = "error", duration = 10)
        session$sendCustomMessage("catha-recording-error", list(message = conditionMessage(e)))
      }
    )
  }, ignoreInit = TRUE)
  
  observeEvent(input$recorded_audio_chunk, {
    chunk <- input$recorded_audio_chunk
    tryCatch({
      if (is.character(chunk) && length(chunk) == 1) {
        chunk <- jsonlite::fromJSON(chunk, simplifyVector = FALSE)
      }
      id <- chunk$id %||% chunk$recording_id
      if (is.null(id) || !nzchar(id)) stop("Missing fallback recording id.", call. = FALSE)
      key <- paste0("id_", gsub("[^A-Za-z0-9_.-]", "_", id))
      total <- as.integer(chunk$total)
      index <- as.integer(chunk$index)
      if (is.na(total) || is.na(index) || total < 1 || index < 1 || index > total) {
        stop("Invalid fallback chunk index.", call. = FALSE)
      }
      if (!exists(key, envir = recording_chunks, inherits = FALSE)) {
        assign(key, list(total = total, parts = vector("list", total), metadata = chunk$metadata %||% list()), envir = recording_chunks)
      }
      entry <- get(key, envir = recording_chunks, inherits = FALSE)
      entry$parts[[index]] <- chunk$data
      assign(key, entry, envir = recording_chunks)
      received <- sum(vapply(entry$parts, function(x) !is.null(x) && nzchar(x), logical(1)))
      message(sprintf("[CATHA recorder] fallback chunk received: %s %s/%s", id, received, total))
      
      if (received == total) {
        payload <- entry$metadata
        payload$data <- paste0(unlist(entry$parts, use.names = FALSE), collapse = "")
        payload$id <- id
        if (is.null(payload$name) || !nzchar(payload$name)) payload$name <- paste0("catha_recording_", id, ".wav")
        rm(list = key, envir = recording_chunks)
        import_recording_payload(payload, transport = "fallback chunks")
      }
    }, error = function(e) {
      message("[CATHA recorder] fallback import failed: ", conditionMessage(e))
      showNotification(paste("Recording fallback import failed:", conditionMessage(e)), type = "error", duration = 10)
      session$sendCustomMessage("catha-recording-error", list(message = conditionMessage(e)))
    })
  }, ignoreInit = TRUE)
  
  observeEvent(input$catha_recorder_client_ready, {
    message("[CATHA recorder] client ready")
  }, ignoreInit = TRUE)
  
  # Microphone capture is handled directly in www/recorder.js from the user's
  # click. These observers intentionally do not send start/stop messages back
  # to the browser, because that can create duplicate getUserMedia() calls.
  observeEvent(input$start_recording, {
    message("[CATHA recorder] start button observed by Shiny; browser handles microphone start directly")
  }, ignoreInit = TRUE)
  
  observeEvent(input$stop_recording, {
    message("[CATHA recorder] stop button observed by Shiny; browser handles microphone stop directly")
  }, ignoreInit = TRUE)
  
  observeEvent(input$reprocess_audio, {
    req(rv$audio_input_path)
    if (!file.exists(rv$audio_input_path)) {
      showNotification("The original source audio is no longer available in this session. Please upload or record it again.", type = "error", duration = 8)
      return()
    }
    tryCatch(
      {
        load_audio(
          rv$audio_input_path,
          rv$audio_input_display_name %||% rv$audio_original_name %||% basename(rv$audio_input_path),
          source_type = rv$audio_input_source_type %||% rv$audio_source %||% "Audio",
          stage_source = FALSE
        )
        showNotification(sprintf("Audio reprocessed and derived segment/feature state reset. %s", rv$audio_preprocessing %||% ""), type = "message")
      },
      error = function(e) {
        showNotification(paste("Audio reprocessing failed:", conditionMessage(e)), type = "error", duration = 10)
      }
    )
  }, ignoreInit = TRUE)

  output$preprocessing_status_ui <- renderUI({
    if (is.null(rv$audio_summary)) {
      return(tags$p(class = "small muted-text mt-2", "Current analysis audio: none loaded yet."))
    }
    tags$div(
      class = "small muted-text mt-2",
      tags$strong("Current analysis audio: "),
      rv$audio_preprocessing %||% "Ambient/background-noise reduction: off",
      tags$br(),
      "Changing the options above does not alter the current waveform until you click ",
      tags$em("Apply preparation settings to current audio"),
      ". Reprocessing resets segments, features, traces, and annotations so everything remains aligned with the prepared audio."
    )
  })

  observeEvent(input$reset_audio, {
    empty_state()
    showNotification("Current audio and derived state cleared.", type = "message")
  })
  
  observeEvent(input$wave_brush, {
    brush <- input$wave_brush
    if (!is.null(brush)) {
      updateNumericInput(session, "segment_start", value = round(max(0, brush$xmin), 3))
      updateNumericInput(session, "segment_end", value = round(max(brush$xmax, brush$xmin), 3))
    }
  })
  
  output$audio_player_ui <- renderUI({
    req(rv$audio_wav_path)
    tags$div(
      class = "audio-shell",
      tags$audio(
        controls = NA,
        preload = "metadata",
        style = "width: 100%;",
        src = sprintf("%s/%s", resource_id, basename(rv$audio_wav_path))
      ),
      tags$p(
        class = "small muted-text mb-0 mt-2",
        sprintf("Prepared analysis audio — %s", rv$audio_preprocessing %||% "Ambient/background-noise reduction: off")
      )
    )
  })
  
  output$waveform_plot <- renderPlot({
    req(rv$audio_wave)
    plot_df <- downsample_wave_df(rv$audio_wave, max_points = 15000)
    ggplot(plot_df, aes(x = time, y = amplitude)) +
      geom_line(color = "#198754", linewidth = 0.25, alpha = 0.9) +
      geom_hline(yintercept = 0, color = "#B0B8C4", linewidth = 0.3) +
      labs(x = "Time (s)", y = "Amplitude") +
      theme_minimal(base_size = 12) +
      theme(
        panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA)
      )
  })
  
  output$duration_box <- renderText({
    if (is.null(rv$audio_summary)) return("—")
    sprintf("%.2f s", rv$audio_summary$duration_seconds)
  })
  output$sample_rate_box <- renderText({
    if (is.null(rv$audio_summary)) return("—")
    sprintf("%s Hz", format(rv$audio_summary$sample_rate, big.mark = ","))
  })
  output$channels_box <- renderText({
    if (is.null(rv$audio_summary)) return("—")
    rv$audio_summary$channels
  })
  output$bit_box <- renderText({
    if (is.null(rv$audio_summary)) return("—")
    sprintf("%s-bit", rv$audio_summary$bit_depth)
  })
  
  # output$notation_table <- renderDT({
  #   req(input$trace_segment)
  #   trace <- rv$traces[[as.character(input$trace_segment)]]
  #   req(trace)
  #   
  #   # Extract notes using the tightened 0.125s bins
  #   notes_df <- trace_to_note_rows(trace$contour, bin_seconds = 0.125)
  #   
  #   # Generate sheet music string and send to frontend
  #   if(nrow(notes_df) > 0) {
  #     abc_header <- "X:1\nT:Extracted Speech Contour\nM:4/4\nL:1/8\nK:C\n"
  #     
  #     # Use unname() to strip names and prevent the jsonlite warning
  #     abc_notes <- unname(sapply(1:nrow(notes_df), function(i) {
  #       row <- notes_df[i,]
  #       if (row$type == "rest") return("z")
  #       
  #       step <- row$step
  #       alter <- row$alter
  #       octave <- row$octave
  #       if (is.na(octave)) return("z")
  #       
  #       # Here we only look at one item at a time, so && is correct
  #       acc <- if (!is.na(alter) && alter == 1) "^" else if (!is.na(alter) && alter == -1) "_" else ""
  #       
  #       # Map to ABC octave syntax
  #       if (octave >= 5) {
  #         note_char <- tolower(step)
  #         oct_mod <- strrep("'", octave - 5)
  #       } else if (octave == 4) {
  #         note_char <- step
  #         oct_mod <- ""
  #       } else {
  #         note_char <- step
  #         oct_mod <- strrep(",", 4 - octave)
  #       }
  #       paste0(acc, note_char, oct_mod)
  #     }))
  #     
  #     # Combine into a single clean string
  #     abc_string <- paste0(abc_header, paste(abc_notes, collapse = " "))
  #     session$sendCustomMessage("render_abc", abc_string)
  #   }
  #   
  #   # Format table for display
  #   if (nrow(notes_df) > 0) {
  #     display_df <- notes_df %>%
  #       mutate(
  #         # THE BUG FIX: Changed && to & for vectorized column operations
  #         Note = ifelse(type == "rest", "Rest", paste0(step, ifelse(!is.na(alter) & alter == 1, "#", ""), octave)),
  #         Type = tools::toTitleCase(type)
  #       ) %>%
  #       select(Type, Note, duration) %>%
  #       rename(`Event Type` = Type, `Pitch` = Note, `Duration (Bins)` = duration)
  #   } else {
  #     display_df <- data.frame(`Event Type` = character(), Pitch = character(), `Duration (Bins)` = integer())
  #   }
  #   
  #   datatable(
  #     display_df,
  #     rownames = FALSE,
  #     options = list(pageLength = 10, scrollX = TRUE),
  #     caption = "Extracted Note Sequence (0.125s bins)"
  #   )
  # })
  
  output$notation_table <- renderDT({
    req(input$trace_segment)
    trace <- rv$traces[[as.character(input$trace_segment)]]
    req(trace)
    
    # Extract notes using the tightened 0.125s bins
    notes_df <- trace_to_note_rows(trace$contour, bin_seconds = 0.125)
    
    # Generate sheet music string and send to frontend
    if(nrow(notes_df) > 0) {
      
      # NEW: Check the median frequency to dynamically assign the correct clef
      median_hz <- median(trace$contour$hz, na.rm = TRUE)
      clef_type <- if (!is.na(median_hz) && median_hz < 180) "bass" else "treble"
      
      # Inject the dynamic clef into the ABC header
      abc_header <- paste0("X:1\nT:Extracted Speech Contour\nM:4/4\nL:1/8\nK:C clef=", clef_type, "\n")
      
      # Use unname() to strip names and prevent the jsonlite warning
      abc_notes <- unname(sapply(1:nrow(notes_df), function(i) {
        row <- notes_df[i,]
        if (row$type == "rest") return("z")
        
        step <- row$step
        alter <- row$alter
        octave <- row$octave
        if (is.na(octave)) return("z")
        
        # Vectorized safe-check for accidentals
        acc <- if (!is.na(alter) && alter == 1) "^" else if (!is.na(alter) && alter == -1) "_" else ""
        
        # Map to ABC octave syntax
        if (octave >= 5) {
          note_char <- tolower(step)
          oct_mod <- strrep("'", octave - 5)
        } else if (octave == 4) {
          note_char <- step
          oct_mod <- ""
        } else {
          note_char <- step
          oct_mod <- strrep(",", 4 - octave)
        }
        paste0(acc, note_char, oct_mod)
      }))
      
      # Combine into a single clean string
      # abc_string <- paste0(abc_header, paste(abc_notes, collapse = " "))
      # session$sendCustomMessage("render_abc", abc_string)
      
      # NEW: Chunk the notes into lines of max 25 notes for clean sheet music rendering
      chunk_size <- 25
      num_chunks <- ceiling(length(abc_notes) / chunk_size)
      
      abc_lines <- sapply(seq_len(num_chunks), function(j) {
        start_idx <- (j - 1) * chunk_size + 1
        end_idx <- min(j * chunk_size, length(abc_notes))
        paste(abc_notes[start_idx:end_idx], collapse = " ")
      })
      
      # Combine header and the chunked lines (separated by explicit newlines)
      abc_string <- paste0(abc_header, paste(abc_lines, collapse = "\n"))
      session$sendCustomMessage("render_abc", abc_string)
      
    }
    
    # Format table for display
    if (nrow(notes_df) > 0) {
      display_df <- notes_df %>%
        mutate(
          Note = ifelse(type == "rest", "Rest", paste0(step, ifelse(!is.na(alter) & alter == 1, "#", ""), octave)),
          Type = tools::toTitleCase(type)
        ) %>%
        select(Type, Note, duration) %>%
        rename(`Event Type` = Type, `Pitch` = Note, `Duration (Bins)` = duration)
    } else {
      display_df <- data.frame(`Event Type` = character(), Pitch = character(), `Duration (Bins)` = integer())
    }
    
    datatable(
      display_df,
      rownames = FALSE,
      options = list(pageLength = 10, scrollX = TRUE),
      caption = "Extracted Note Sequence (0.125s bins)"
    )
  })
  
  observeEvent(input$add_segment, {
    req(rv$audio_summary)
    start_time <- as.numeric(input$segment_start)
    end_time <- as.numeric(input$segment_end)
    if (is.na(start_time) || is.na(end_time) || end_time <= start_time) {
      showNotification("Segment end must be greater than segment start.", type = "error")
      return()
    }
    if (end_time > rv$audio_summary$duration_seconds) {
      end_time <- rv$audio_summary$duration_seconds
    }
    new_id <- if (nrow(rv$segments) == 0) 1L else max(rv$segments$segment_id, na.rm = TRUE) + 1L
    new_row <- tibble(
      segment_id = new_id,
      label = input$segment_label %||% paste("Episode", new_id),
      start = round(start_time, 3),
      end = round(end_time, 3),
      duration = round(end_time - start_time, 3),
      segment_note = input$segment_note %||% ""
    )
    rv$segments <- bind_rows(rv$segments, new_row) %>% arrange(start, end)
    updateTextInput(session, "segment_label", value = paste("Episode", new_id + 1L))
    rv$external_notation <- NULL
    showNotification("Segment added. Run Basic Pitch again if you want external notation for the updated segment set.", type = "message")
  })
  
  observeEvent(input$delete_segment, {
    selected <- input$segments_table_rows_selected
    if (length(selected) == 0 || nrow(rv$segments) == 0) return()
    seg_id <- rv$segments$segment_id[selected[1]]
    rv$segments <- rv$segments[-selected[1], , drop = FALSE]
    rv$annotations <- rv$annotations %>% filter(segment_id != seg_id)
    rv$features <- rv$features %>% filter(segment_id != seg_id)
    rv$traces[[as.character(seg_id)]] <- NULL
    rv$external_notation <- NULL
    showNotification("Selected segment removed. External notation outputs were cleared because segment boundaries changed.", type = "message")
  })
  
  observeEvent(input$clear_segments, {
    rv$segments <- rv$segments[0, ]
    rv$annotations <- rv$annotations[0, ]
    rv$features <- tibble()
    rv$traces <- list()
    rv$external_notation <- NULL
    showNotification("All segments cleared.", type = "message")
  })
  
  output$segments_table <- renderDT({
    datatable(
      rv$segments,
      rownames = FALSE,
      selection = "single",
      options = list(pageLength = 8, scrollX = TRUE)
    )
  })
  
  observeEvent(input$run_features, {
    req(rv$audio_wave)
    if (nrow(rv$segments) == 0) {
      showNotification("Add at least one segment before running feature extraction.", type = "error")
      return()
    }
    
    result <- tryCatch({
      feature_rows <- list()
      trace_list <- list()
      
      for (i in seq_len(nrow(rv$segments))) {
        seg <- rv$segments[i, ]
        bundle <- extract_segment_bundle(
          wave = rv$audio_wave,
          start = seg$start,
          end = seg$end,
          pitch_floor = input$pitch_floor,
          pitch_ceiling = input$pitch_ceiling,
          frame_ms = input$frame_ms,
          silence_quantile = input$silence_quantile
        )
        feature_rows[[i]] <- bind_cols(
          seg %>% select(segment_id, label, start, end, duration),
          bundle$features
        )
        trace_list[[as.character(seg$segment_id)]] <- bundle$traces
      }
      
      list(
        features = bind_rows(feature_rows),
        traces = trace_list
      )
    }, error = function(e) {
      showNotification(
        paste("Feature extraction failed:", conditionMessage(e)),
        type = "error",
        duration = NULL
      )
      NULL
    })
    
    if (is.null(result)) return()
    
    rv$features <- result$features
    rv$traces <- result$traces
    showNotification("Feature extraction completed.", type = "message")
  })
  
  observeEvent(input$run_external_notation, {
    req(rv$audio_wave)
    if (nrow(rv$segments) == 0) {
      showNotification("Add at least one segment before running Basic Pitch.", type = "error")
      return()
    }
    if (!identical(input$notation_engine, "basic_pitch")) {
      showNotification("Choose 'Basic Pitch external audio-to-MIDI' as the notation engine first.", type = "warning")
      return()
    }

    out_dir <- file.path(session_dir, paste0("external_notation_", format(Sys.time(), "%Y%m%d_%H%M%S")))
    result <- tryCatch(
      run_basic_pitch_on_segments(
        wave = rv$audio_wave,
        segments = rv$segments,
        output_dir = out_dir,
        basic_pitch_command = input$basic_pitch_command %||% "basic-pitch",
        python_command = input$python_command %||% "python",
        convert_musicxml = isTRUE(input$basic_pitch_to_musicxml),
        onset_threshold = input$basic_pitch_onset_threshold %||% 0.30,
        frame_threshold = input$basic_pitch_frame_threshold %||% 0.20,
        minimum_note_length = input$basic_pitch_minimum_note_length %||% 50,
        minimum_frequency = input$basic_pitch_minimum_frequency %||% 65,
        maximum_frequency = input$basic_pitch_maximum_frequency %||% 900,
        multiple_pitch_bends = isTRUE(input$basic_pitch_multiple_bends),
        no_melodia = isTRUE(input$basic_pitch_no_melodia)
      ),
      error = function(e) {
        showNotification(paste("Basic Pitch notation failed:", conditionMessage(e)), type = "error", duration = NULL)
        NULL
      }
    )
    if (is.null(result)) return()
    rv$external_notation <- result
    notes <- basic_pitch_notes_as_table(result)
    showNotification(sprintf("Basic Pitch completed. Detected %s note events across %s segment(s).", nrow(notes), nrow(rv$segments)), type = "message")
  }, ignoreInit = TRUE)

  output$external_notation_status_ui <- renderUI({
    if (!identical(input$notation_engine, "basic_pitch")) return(NULL)
    if (is.null(rv$external_notation)) {
      return(tags$p(class = "small muted-text mt-2", "No Basic Pitch output in this session yet."))
    }
    notes <- basic_pitch_notes_as_table(rv$external_notation)
    midi_count <- length(external_notation_files(rv$external_notation, "midi"))
    musicxml_count <- length(external_notation_files(rv$external_notation, "musicxml"))
    zero_note_hint <- if (nrow(notes) == 0) {
      tags$span(
        tags$br(),
        "No note events were found/read. Try a longer voiced segment, lower the onset/frame thresholds, or download the Basic Pitch output bundle to inspect the per-segment CSV/MIDI/log. The app now also tries to recover note rows directly from the MIDI when the CSV is empty or unreadable."
      )
    } else NULL
    tags$div(
      class = "small muted-text mt-2",
      tags$strong("Latest Basic Pitch run: "), rv$external_notation$run_at,
      tags$br(),
      sprintf("Detected note events: %s | MIDI files: %s | MusicXML files: %s", nrow(notes), midi_count, musicxml_count),
      zero_note_hint
    )
  })


  output$external_score_segment_ui <- renderUI({
    if (is.null(rv$external_notation)) return(NULL)
    notes <- basic_pitch_notes_as_table(rv$external_notation)
    if (nrow(notes) == 0) {
      return(tags$p(class = "small muted-text", "No external notes are available to render as a score yet."))
    }
    segs <- notes %>%
      distinct(segment_id, label, segment_start, segment_end) %>%
      arrange(segment_start, segment_id)
    choices <- setNames(
      segs$segment_id,
      paste0(segs$label, " (", segs$segment_start, "–", segs$segment_end, " s)")
    )
    selectInput(
      "external_score_segment",
      "Choose external notation segment",
      choices = choices,
      selected = segs$segment_id[1]
    )
  })

  observe({
    if (is.null(rv$external_notation)) {
      session$sendCustomMessage("render_external_abc", "")
      return()
    }
    notes <- basic_pitch_notes_as_table(rv$external_notation)
    if (nrow(notes) == 0) {
      session$sendCustomMessage("render_external_abc", "")
      return()
    }
    available_seg_ids <- unique(stats::na.omit(notes$segment_id))
    if (length(available_seg_ids) == 0) {
      session$sendCustomMessage("render_external_abc", "")
      return()
    }
    seg_id <- suppressWarnings(as.integer(input$external_score_segment))
    if (length(seg_id) != 1 || is.na(seg_id) || !is.finite(seg_id) || !(seg_id %in% available_seg_ids)) {
      seg_id <- available_seg_ids[1]
    }
    seg_notes <- notes %>% filter(segment_id == seg_id) %>% arrange(note_start_segment_s, pitch_midi)
    abc_string <- external_notes_to_abc(seg_notes)
    session$sendCustomMessage("render_external_abc", abc_string)
  })

  output$external_notation_summary_ui <- renderUI({
    if (is.null(rv$external_notation)) {
      return(tags$p(class = "small muted-text", "No external MIDI notation has been generated yet. Choose Basic Pitch in the left panel and run it after defining segments."))
    }
    notes <- basic_pitch_notes_as_table(rv$external_notation)
    tags$div(
      class = "audio-shell",
      tags$strong("External notation engine: Basic Pitch"),
      tags$p(class = "small muted-text mb-0", sprintf("Run at %s. Detected %s note events. These outputs are optional and should be manually reviewed before interpretive use.", rv$external_notation$run_at, nrow(notes))),
      if (nrow(notes) == 0) tags$p(class = "small muted-text mb-0", "If this table is empty, Basic Pitch either detected no stable note events in the selected segment, or both the CSV and MIDI contained no readable note rows. Try a longer/clearer voiced segment or lower the advanced thresholds.") else NULL
    )
  })

  output$external_notation_table <- renderDT({
    notes <- basic_pitch_notes_as_table(rv$external_notation)
    seg_id <- suppressWarnings(as.integer(input$external_score_segment))
    available_seg_ids <- if (nrow(notes) > 0) unique(stats::na.omit(notes$segment_id)) else integer()
    if (
      nrow(notes) > 0 &&
      length(seg_id) == 1 &&
      !is.na(seg_id) &&
      is.finite(seg_id) &&
      seg_id %in% available_seg_ids
    ) {
      notes <- notes %>% filter(segment_id == seg_id)
    }
    if (nrow(notes) == 0) {
      notes <- data.frame(
        segment_id = integer(), label = character(), note_start_segment_s = numeric(),
        note_end_segment_s = numeric(), duration_s = numeric(), pitch_midi = integer(),
        note = character(), velocity = integer()
      )
    }
    datatable(
      notes,
      rownames = FALSE,
      options = list(pageLength = 12, scrollX = TRUE),
      caption = "Basic Pitch note events. Review manually; speech-to-note conversion is approximate."
    )
  })

  output$trace_segment_ui <- renderUI({
    req(nrow(rv$segments) > 0)
    choices <- setNames(rv$segments$segment_id, paste0(rv$segments$label, " (", rv$segments$start, "–", rv$segments$end, " s)"))
    selectInput("trace_segment", "Choose segment", choices = choices, selected = rv$segments$segment_id[1])
  })
  
  output$pitch_plot <- renderPlot({
    req(input$trace_segment)
    trace <- rv$traces[[as.character(input$trace_segment)]]
    req(trace)
    contour <- trace$contour
    
    valid_pitches <- sum(!is.na(contour$hz))
    
    # Foolproof check: Draw a text message instead of using validate()
    if (valid_pitches == 0) {
      return(
        ggplot() + 
          annotate("text", x = 0.5, y = 0.5, label = "No voiced pitch detected in this segment.\nIt may be mostly breath/unvoiced, or too quiet.", color = "#63768a") +
          theme_void()
      )
    }
    
    ggplot(contour, aes(x = time, y = hz)) +
      geom_point(color = "#0d6efd", size = 1.5, alpha = 0.8, na.rm = TRUE) +
      geom_line(color = "#0d6efd", linewidth = 0.4, na.rm = TRUE) +
      labs(x = "Time within segment (s)", y = "Estimated F0 (Hz)") +
      theme_minimal(base_size = 12) +
      theme(panel.grid.minor = element_blank())
  })
  
  output$intensity_plot <- renderPlot({
    req(input$trace_segment)
    trace <- rv$traces[[as.character(input$trace_segment)]]
    req(trace)
    intensity <- trace$intensity
    
    # Foolproof check: Draw a text message instead of using validate()
    if (is.null(intensity) || nrow(intensity) == 0) {
      return(
        ggplot() + 
          annotate("text", x = 0.5, y = 0.5, label = "No intensity trace available for this segment yet.", color = "#63768a") +
          theme_void()
      )
    }
    
    ggplot(intensity, aes(x = time, y = rms)) +
      geom_line(color = "#fd7e14", linewidth = 0.4) +
      geom_point(data = intensity %>% filter(pause_flag), aes(x = time, y = rms), color = "#dc3545", size = 1.3) +
      labs(x = "Time within segment (s)", y = "Frame RMS") +
      theme_minimal(base_size = 12) +
      theme(panel.grid.minor = element_blank())
  })
  
  output$features_table <- renderDT({
    datatable(
      rv$features,
      rownames = FALSE,
      options = list(pageLength = 8, scrollX = TRUE)
    )
  })
  
  output$annotation_segment_ui <- renderUI({
    req(nrow(rv$segments) > 0)
    choices <- setNames(rv$segments$segment_id, paste0(rv$segments$label, " (", rv$segments$start, "–", rv$segments$end, " s)"))
    selectInput("annotation_segment", "Choose segment", choices = choices, selected = rv$segments$segment_id[1])
  })
  
  observeEvent(input$annotation_segment, {
    req(input$annotation_segment)
    existing <- rv$annotations %>% filter(segment_id == as.integer(input$annotation_segment))
    if (nrow(existing) == 0) {
      updateTextAreaInput(session, "transcript_text", value = "")
      updateCheckboxGroupInput(session, "salience_flags", selected = character())
      updateSliderInput(session, "uncertainty_score", value = 30)
      updateTextInput(session, "recurrence_note", value = "")
      updateTextInput(session, "response_note", value = "")
      updateTextAreaInput(session, "clinical_note", value = "")
      updateSelectInput(session, "recommended_export", selected = "Trace")
    } else {
      updateTextAreaInput(session, "transcript_text", value = existing$transcript[[1]])
      selected_flags <- if (nzchar(existing$salience_flags[[1]] %||% "")) strsplit(existing$salience_flags[[1]], "\\|", fixed = FALSE)[[1]] else character()
      updateCheckboxGroupInput(session, "salience_flags", selected = selected_flags)
      updateSliderInput(session, "uncertainty_score", value = existing$uncertainty[[1]])
      updateTextInput(session, "recurrence_note", value = existing$recurrence_note[[1]])
      updateTextInput(session, "response_note", value = existing$response_note[[1]])
      updateTextAreaInput(session, "clinical_note", value = existing$clinical_note[[1]])
      updateSelectInput(session, "recommended_export", selected = existing$recommended_export[[1]])
    }
  }, ignoreInit = FALSE)
  
  observeEvent(input$save_annotation, {
    req(input$annotation_segment)
    new_row <- tibble(
      segment_id = as.integer(input$annotation_segment),
      transcript = input$transcript_text %||% "",
      salience_flags = paste(input$salience_flags %||% character(), collapse = "|"),
      uncertainty = as.integer(input$uncertainty_score),
      recurrence_note = input$recurrence_note %||% "",
      response_note = input$response_note %||% "",
      clinical_note = input$clinical_note %||% "",
      recommended_export = input$recommended_export %||% "Trace"
    )
    rv$annotations <- upsert_annotation(rv$annotations, new_row, key = "segment_id")
    showNotification("Annotation saved.", type = "message")
  })
  
  output$joint_table <- renderDT({
    datatable(
      build_joint_display(rv$segments, rv$features, rv$annotations),
      rownames = FALSE,
      options = list(pageLength = 10, scrollX = TRUE)
    )
  })
  
  output$download_segments <- downloadHandler(
    filename = function() {
      paste0("catha_segments_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(rv$segments, file, row.names = FALSE, na = "")
    }
  )
  
  output$download_features <- downloadHandler(
    filename = function() {
      paste0("catha_features_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(rv$features, file, row.names = FALSE, na = "")
    }
  )
  
  output$download_annotations <- downloadHandler(
    filename = function() {
      paste0("catha_annotations_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(rv$annotations, file, row.names = FALSE, na = "")
    }
  )
  
  output$download_trace_json <- downloadHandler(
    filename = function() {
      paste0("catha_trace_", Sys.Date(), ".json")
    },
    content = function(file) {
      write_trace_json(rv$segments, rv$features, rv$annotations, rv$traces, file)
    }
  )
  
  output$download_textgrid <- downloadHandler(
    filename = function() {
      paste0("catha_segments_", Sys.Date(), ".TextGrid")
    },
    content = function(file) {
      total_duration <- if (is.null(rv$audio_summary)) 0 else rv$audio_summary$duration_seconds
      write_textgrid(rv$segments, file, xmax = total_duration)
    }
  )
  
  output$download_musicxml <- downloadHandler(
    filename = function() {
      paste0("catha_trace_", Sys.Date(), ".musicxml")
    },
    content = function(file) {
      write_musicxml(rv$segments, rv$traces, file)
    }
  )
  
  output$download_basic_pitch_notes <- downloadHandler(
    filename = function() {
      paste0("catha_basic_pitch_note_events_", Sys.Date(), ".csv")
    },
    content = function(file) {
      req(rv$external_notation)
      notes <- basic_pitch_notes_as_table(rv$external_notation)
      write.csv(notes, file, row.names = FALSE, na = "")
    }
  )

  output$download_basic_pitch_midi <- downloadHandler(
    filename = function() {
      files <- external_notation_files(rv$external_notation, "midi")
      if (length(files) == 1) paste0("catha_basic_pitch_", Sys.Date(), ".mid") else paste0("catha_basic_pitch_midi_", Sys.Date(), ".zip")
    },
    content = function(file) {
      req(rv$external_notation)
      files <- external_notation_files(rv$external_notation, "midi")
      validate(need(length(files) > 0, "No Basic Pitch MIDI files have been generated yet."))
      copy_or_zip_external_files(files, file)
    }
  )

  output$download_basic_pitch_musicxml <- downloadHandler(
    filename = function() {
      files <- external_notation_files(rv$external_notation, "musicxml")
      if (length(files) == 1) paste0("catha_basic_pitch_", Sys.Date(), ".musicxml") else paste0("catha_basic_pitch_musicxml_", Sys.Date(), ".zip")
    },
    content = function(file) {
      req(rv$external_notation)
      files <- external_notation_files(rv$external_notation, "musicxml")
      validate(need(length(files) > 0, "No Basic Pitch MusicXML files have been generated yet. Install Python music21 and rerun Basic Pitch with MusicXML conversion enabled."))
      copy_or_zip_external_files(files, file)
    }
  )

  output$download_bundle <- downloadHandler(
    filename = function() {
      paste0("catha_bundle_", Sys.Date(), ".zip")
    },
    content = function(file) {
      write_bundle(
        bundle_file = file,
        audio_path = rv$audio_wav_path,
        segments = rv$segments,
        features = rv$features,
        annotations = rv$annotations,
        traces = rv$traces,
        audio_summary = rv$audio_summary,
        external_notation = rv$external_notation
      )
    }
  )
}

shinyApp(ui, server)
