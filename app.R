
suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(jsonlite)
  library(dplyr)
  library(ggplot2)
  library(tuneR)
  library(soundgen)
  library(seewave)
})

# And add it to your required_packages check on line 12:
required_packages <- c("shiny", "bslib", "DT", "jsonlite", "dplyr", "ggplot2", "tuneR", "soundgen")

source(file.path("R", "helpers_audio.R"))
source(file.path("R", "helpers_exports.R"))

required_packages <- c("shiny", "bslib", "DT", "jsonlite", "dplyr", "ggplot2", "tuneR")
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
    # class = "catha-brand",
    # tags$span("CATHA") # Restores the text on the left
    class = "catha-brand"
  ),
  id = "main_nav",
  theme = app_theme,
  header = tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
      tags$script(src = "recorder.js"),
      # ABCJS for sheet music rendering
      tags$script(src = "https://cdn.jsdelivr.net/npm/abcjs@6.2.2/dist/abcjs-basic-min.js"),
      tags$script(HTML("
        $(document).on('shiny:sessioninitialized', function() {
          Shiny.addCustomMessageHandler('render_abc', function(abc) {
            if(document.getElementById('paper')) {
              ABCJS.renderAbc('paper', abc, { responsive: 'resize' });
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
          actionButton("reset_audio", "Clear current audio", class = "btn-outline-secondary"),
          hr(),
          h6("Audio preparation"),
          checkboxInput("downmix_to_mono", "Downmix uploads to mono for analysis", value = TRUE),
          numericInput("analysis_sample_rate", "Target sample rate (Hz)", value = 44100, min = 8000, max = 96000, step = 1000),
          p(class = "small muted-text", "Uploaded files are normalized to analysis-ready WAV. Browser recordings are captured as WAV and loaded directly.")
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
          actionButton("apply_brush_range", "Use current brush", class = "btn-outline-primary"),
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
          p(class = "muted-text", "Computes analysis-friendly traces: duration, intensity, pauses, pitch contour, and voiced fraction."),
          numericInput("frame_ms", "Frame size (ms)", value = 40, min = 10, max = 250, step = 5),
          numericInput("pitch_floor", "Pitch floor (Hz)", value = 75, min = 30, max = 400, step = 5),
          numericInput("pitch_ceiling", "Pitch ceiling (Hz)", value = 500, min = 100, max = 1000, step = 10),
          sliderInput("silence_quantile", "Pause threshold quantile", min = 0.01, max = 0.5, value = 0.15, step = 0.01),
          actionButton("run_features", "Run feature extraction", class = "btn-primary"),
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
            tabPanel("Musical Notation", 
                     tags$div(id = "paper", style = "background: white; padding: 15px; border-radius: 8px; margin-top: 15px; border: 1px solid var(--catha-border); overflow-x: auto;"),
                     DTOutput("notation_table"))
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
            downloadButton("download_musicxml", "MusicXML"),
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
        
        tags$hr(),
        tags$h4("What It Does"),
        tags$p("CATHA is designed as a research-support environment that helps preserve selected formal aspects of voiced expression—such as pitch contour, pacing, silence, and dynamic intensity—in a revisitable and interoperable form. It translates the temporal and relational features of clinically salient speech into acoustic traces and hybrid analytic scores (including standard sheet music notation)."),
        tags$p("Crucially, CATHA operates within strict ethical boundaries. It is explicitly not an autonomous application or a diagnostic classifier. It does not attempt to decode inner truth or label emotions; rather, it relies entirely on a therapist-guided workflow to document \"speech seeking orientation under finitude\"."),
        
        tags$hr(),
        tags$h4("Step-by-Step Instructions"),
        tags$ol(
          tags$li(tags$strong("Audio Intake: "), "Upload a standard audio file (.wav, .mp3) or record a live session directly through your browser. The app will automatically standardize the sample rate and generate a waveform for you to inspect."),
          tags$li(tags$strong("Segmentation: "), "Click and drag (brush) over the waveform in the 'Audio Intake' tab, then switch to the 'Segmentation' tab to formally define that snippet as a clinically salient episode. Add a descriptive label and notes."),
          tags$li(tags$strong("Features & Traces: "), "Once your segments are defined, click 'Run feature extraction'. CATHA will map the pitch contour and intensity using the robust `seewave` acoustic engine. Navigate the sub-tabs to view the raw plots, the numeric feature table, and the auto-generated Musical Notation sheet."),
          tags$li(tags$strong("Annotations & Export: "), "Select your processed segments one by one to attach verbatim transcripts, flag salience markers, and document interpretive uncertainty. Once your clinical contextualization is complete, download the individual files or click 'Full CATHA bundle' to export your audio, CSVs, JSON data, and MusicXML files for downstream analysis.")
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
    audio_wav_path = NULL,
    audio_wave = NULL,
    audio_summary = NULL,
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
    traces = list()
  )
  
  empty_state <- function() {
    rv$audio_source <- NULL
    rv$audio_original_name <- NULL
    rv$audio_wav_path <- NULL
    rv$audio_wave <- NULL
    rv$audio_summary <- NULL
    rv$segments <- rv$segments[0, ]
    rv$annotations <- rv$annotations[0, ]
    rv$features <- tibble()
    rv$traces <- list()
  }
  
  load_audio <- function(input_path, display_name, source_type = "Upload") {
    req(file.exists(input_path))
    out_name <- paste0(tools::file_path_sans_ext(basename(display_name)), "_analysis.wav")
    out_path <- file.path(session_dir, out_name)
    wav_path <- ensure_wav(
      input_path = input_path,
      output_path = out_path,
      sample_rate = input$analysis_sample_rate,
      mono = isTRUE(input$downmix_to_mono)
    )
    wave <- safe_read_wave(wav_path)
    summary <- summarize_wave(wave, display_name, source_type)
    
    rv$audio_source <- source_type
    rv$audio_original_name <- display_name
    rv$audio_wav_path <- wav_path
    rv$audio_wave <- wave
    rv$audio_summary <- summary
    rv$segments <- rv$segments[0, ]
    rv$annotations <- rv$annotations[0, ]
    rv$features <- tibble()
    rv$traces <- list()
    
    updateTextInput(session, "segment_label", value = "Episode 1")
    updateNumericInput(session, "segment_start", value = 0)
    updateNumericInput(session, "segment_end", value = min(5, summary$duration_seconds))
  }
  
  observeEvent(input$audio_upload, {
    req(input$audio_upload)
    tryCatch(
      {
        load_audio(input$audio_upload$datapath, input$audio_upload$name, source_type = "File upload")
        showNotification("Audio loaded and normalized for analysis.", type = "message")
      },
      error = function(e) {
        showNotification(paste("Audio load failed:", conditionMessage(e)), type = "error", duration = 8)
      }
    )
  })
  
  observeEvent(input$recorded_audio, {
    req(input$recorded_audio$data)
    record_path <- file.path(session_dir, input$recorded_audio$name %||% "catha_recording.wav")
    tryCatch(
      {
        writeBin(jsonlite::base64_dec(input$recorded_audio$data), record_path)
        load_audio(record_path, basename(record_path), source_type = "Browser recording")
        showNotification("Browser recording captured and loaded.", type = "message")
      },
      error = function(e) {
        showNotification(paste("Recording import failed:", conditionMessage(e)), type = "error", duration = 8)
      }
    )
  })
  
  observeEvent(input$start_recording, {
    session$sendCustomMessage("catha-start-recording", list())
  })
  
  observeEvent(input$stop_recording, {
    session$sendCustomMessage("catha-stop-recording", list())
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
  
  observeEvent(input$apply_brush_range, {
    brush <- input$wave_brush
    req(brush)
    updateNumericInput(session, "segment_start", value = round(max(0, brush$xmin), 3))
    updateNumericInput(session, "segment_end", value = round(max(brush$xmax, brush$xmin), 3))
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
    showNotification("Segment added.", type = "message")
  })
  
  observeEvent(input$delete_segment, {
    selected <- input$segments_table_rows_selected
    if (length(selected) == 0 || nrow(rv$segments) == 0) return()
    seg_id <- rv$segments$segment_id[selected[1]]
    rv$segments <- rv$segments[-selected[1], , drop = FALSE]
    rv$annotations <- rv$annotations %>% filter(segment_id != seg_id)
    rv$features <- rv$features %>% filter(segment_id != seg_id)
    rv$traces[[as.character(seg_id)]] <- NULL
    showNotification("Selected segment removed.", type = "message")
  })
  
  observeEvent(input$clear_segments, {
    rv$segments <- rv$segments[0, ]
    rv$annotations <- rv$annotations[0, ]
    rv$features <- tibble()
    rv$traces <- list()
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
        audio_summary = rv$audio_summary
      )
    }
  )
}

shinyApp(ui, server)
