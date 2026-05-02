# Optional external notation engines for CATHA.

# system2() builds a shell command on Unix-like systems. Arguments that contain
# parentheses, spaces, semicolons, or inline Python code must therefore be
# shell-quoted explicitly. Without this, Linux can emit errors such as:
#   sh: 1: Syntax error: "(" unexpected
# This wrapper is used for Basic Pitch, ffmpeg-style paths, and music21 calls.
if (!exists("quote_system_arg", mode = "function")) {
  quote_system_arg <- function(x) {
    x <- as.character(x)
    if (.Platform$OS.type == "windows") {
      shQuote(x, type = "cmd")
    } else {
      shQuote(x, type = "sh")
    }
  }
}

if (!exists("system2_capture", mode = "function")) {
  system2_capture <- function(command, args = character(), stdout = TRUE, stderr = TRUE, ...) {
    args <- as.character(args %||% character())
    quoted_args <- vapply(args, quote_system_arg, character(1), USE.NAMES = FALSE)
    suppressWarnings(system2(command, args = quoted_args, stdout = stdout, stderr = stderr, ...))
  }
}

#
# The default CATHA score remains the transparent therapist-guided acoustic trace.
# This helper adds an optional Basic Pitch pathway that can generate MIDI and
# note-event CSV files from the same uploaded/recorded audio segments.

candidate_paths_for_executable <- function(label = "executable") {
  project_dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)

  if (identical(label, "Basic Pitch")) {
    return(c(
      file.path(project_dir, ".venv-basic-pitch", "bin", "basic-pitch"),
      file.path(project_dir, ".venv-basic-pitch", "Scripts", "basic-pitch.exe"),
      file.path(project_dir, ".venv", "bin", "basic-pitch"),
      file.path(project_dir, ".venv", "Scripts", "basic-pitch.exe")
    ))
  }

  if (identical(label, "Python")) {
    return(c(
      file.path(project_dir, ".venv-basic-pitch", "bin", "python"),
      file.path(project_dir, ".venv-basic-pitch", "Scripts", "python.exe"),
      file.path(project_dir, ".venv", "bin", "python"),
      file.path(project_dir, ".venv", "Scripts", "python.exe")
    ))
  }

  character(0)
}

find_executable <- function(command, label = "executable") {
  command <- as.character(command %||% "")
  command <- trimws(command)
  if (!nzchar(command)) {
    stop(sprintf("No %s command was provided.", label), call. = FALSE)
  }

  # Allow a direct path, for example C:/Users/name/AppData/.../basic-pitch.exe
  # or /Users/name/.local/bin/basic-pitch.
  if (file.exists(command)) {
    return(normalizePath(command, winslash = "/", mustWork = TRUE))
  }

  # If the user typed a path, fail with a path-specific message rather than a
  # generic PATH message. This prevents confusion between the Basic Pitch field
  # and the Python/music21 field.
  looks_like_path <- grepl("/", command, fixed = TRUE) || grepl("\\", command, fixed = TRUE) || grepl("^[A-Za-z]:", command)
  if (looks_like_path) {
    stop(
      sprintf(
        "%s path does not exist: %s. Check that this value is in the correct field and that the file exists.",
        label,
        command
      ),
      call. = FALSE
    )
  }

  resolved <- Sys.which(command)
  if (nzchar(resolved)) {
    return(normalizePath(resolved, winslash = "/", mustWork = TRUE))
  }

  # Project-local virtual environments are common on Linux/macOS because modern
  # Python distributions block global pip installs. Auto-detect these before
  # showing the generic PATH error.
  candidates <- candidate_paths_for_executable(label)
  candidates <- candidates[file.exists(candidates)]
  if (length(candidates) > 0) {
    return(normalizePath(candidates[1], winslash = "/", mustWork = TRUE))
  }

  stop(
    sprintf(
      "%s was not found on PATH and no project-local .venv-basic-pitch executable was found. Install it first or paste the full path in the correct app setting.",
      label
    ),
    call. = FALSE
  )
}

default_executable_command <- function(command, label = "executable") {
  command <- as.character(command %||% "")
  command <- trimws(command)
  if (!nzchar(command)) return(command)

  if (nzchar(Sys.which(command))) return(command)

  candidates <- candidate_paths_for_executable(label)
  candidates <- candidates[file.exists(candidates)]
  if (length(candidates) > 0) {
    return(normalizePath(candidates[1], winslash = "/", mustWork = TRUE))
  }

  command
}

basic_pitch_available <- function(command = "basic-pitch") {
  tryCatch({
    find_executable(command, label = "Basic Pitch")
    TRUE
  }, error = function(e) FALSE)
}

midi_to_note_label <- function(midi_note) {
  midi_note <- suppressWarnings(as.integer(midi_note))
  if (!is.finite(midi_note)) return(NA_character_)
  pitch <- midi_to_musicxml(midi_note)
  accidental <- if (!is.na(pitch$alter) && pitch$alter == 1) "#" else if (!is.na(pitch$alter) && pitch$alter == -1) "b" else ""
  paste0(pitch$step, accidental, pitch$octave)
}


midi_note_to_abc <- function(midi_note) {
  midi_note <- suppressWarnings(as.integer(midi_note))
  if (!is.finite(midi_note)) return("z")
  pitch <- midi_to_musicxml(midi_note)
  step <- pitch$step
  alter <- pitch$alter
  octave <- pitch$octave
  if (is.na(step) || is.na(octave)) return("z")

  acc <- if (!is.na(alter) && alter == 1) "^" else if (!is.na(alter) && alter == -1) "_" else ""
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
}

abc_length_suffix <- function(units) {
  units <- suppressWarnings(as.integer(round(as.numeric(units))))
  if (!is.finite(units) || units <= 1) return("")
  as.character(units)
}

external_notes_to_abc <- function(notes_df,
                                  title = NULL,
                                  base_unit_seconds = 0.125,
                                  beats_per_bar = 4,
                                  beat_unit = 4,
                                  default_clef = NULL) {
  if (is.null(notes_df) || nrow(notes_df) == 0) return("")

  notes_df <- notes_df[order(notes_df$note_start_segment_s, notes_df$pitch_midi), , drop = FALSE]
  title <- title %||% paste0("External MIDI - ", notes_df$label[1])

  if (is.null(default_clef) || !nzchar(default_clef)) {
    median_midi <- stats::median(notes_df$pitch_midi, na.rm = TRUE)
    default_clef <- if (is.finite(median_midi) && median_midi < 60) "bass" else "treble"
  }

  base_unit_seconds <- suppressWarnings(as.numeric(base_unit_seconds))
  if (!is.finite(base_unit_seconds) || base_unit_seconds <= 0) base_unit_seconds <- 0.125

  measure_units <- beats_per_bar * (16 / beat_unit) # with L:1/16
  if (!is.finite(measure_units) || measure_units <= 0) measure_units <- 16

  tokens <- character()
  current_pos <- 0
  units_in_bar <- 0

  for (i in seq_len(nrow(notes_df))) {
    row <- notes_df[i, , drop = FALSE]
    start_units <- max(0L, as.integer(round(as.numeric(row$note_start_segment_s) / base_unit_seconds)))
    end_units <- max(start_units + 1L, as.integer(round(as.numeric(row$note_end_segment_s) / base_unit_seconds)))
    gap_units <- max(0L, start_units - current_pos)
    note_units <- max(1L, end_units - start_units)

    if (gap_units > 0) {
      while (gap_units > 0) {
        space_left <- measure_units - units_in_bar
        piece <- min(gap_units, space_left)
        tokens <- c(tokens, paste0("z", abc_length_suffix(piece)))
        units_in_bar <- units_in_bar + piece
        gap_units <- gap_units - piece
        if (units_in_bar >= measure_units) {
          tokens <- c(tokens, "|")
          units_in_bar <- 0
        }
      }
    }

    abc_pitch <- midi_note_to_abc(row$pitch_midi)
    remaining <- note_units
    while (remaining > 0) {
      space_left <- measure_units - units_in_bar
      piece <- min(remaining, space_left)
      tokens <- c(tokens, paste0(abc_pitch, abc_length_suffix(piece)))
      units_in_bar <- units_in_bar + piece
      remaining <- remaining - piece
      if (units_in_bar >= measure_units) {
        tokens <- c(tokens, "|")
        units_in_bar <- 0
      }
    }

    current_pos <- max(current_pos, end_units)
  }

  if (length(tokens) == 0) tokens <- c("z4", "|")
  if (tail(tokens, 1) != "|") tokens <- c(tokens, "|")

  # Chunk tokens into shorter lines for cleaner abcjs rendering.
  chunk_size <- 24
  chunks <- split(tokens, ceiling(seq_along(tokens) / chunk_size))
  body <- vapply(chunks, function(x) paste(x, collapse = " "), character(1))

  header <- paste0(
    "X:1
",
    "T:", title, "
",
    "M:", beats_per_bar, "/", beat_unit, "
",
    "L:1/16
",
    "K:C clef=", default_clef, "
"
  )

  paste0(header, paste(body, collapse = "
"))
}

write_segment_wavs <- function(wave, segments, output_dir) {
  req_cols <- c("segment_id", "label", "start", "end")
  missing_cols <- setdiff(req_cols, names(segments))
  if (length(missing_cols) > 0) {
    stop("Segments table is missing required columns: ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  if (nrow(segments) == 0) {
    stop("Add at least one segment before running external notation.", call. = FALSE)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  out <- vector("list", nrow(segments))
  for (i in seq_len(nrow(segments))) {
    seg <- segments[i, , drop = FALSE]
    safe_label <- sanitize_stem(seg$label %||% paste0("segment_", seg$segment_id))
    wav_path <- file.path(output_dir, sprintf("segment_%03d_%s.wav", as.integer(seg$segment_id), safe_label))
    segment_wave <- extract_segment_wave(wave, start = seg$start, end = seg$end)
    tuneR::writeWave(segment_wave, wav_path, extensible = FALSE)
    out[[i]] <- list(
      segment_id = as.integer(seg$segment_id),
      label = as.character(seg$label),
      start = as.numeric(seg$start),
      end = as.numeric(seg$end),
      duration = as.numeric(seg$end - seg$start),
      wav_path = normalizePath(wav_path, winslash = "/", mustWork = TRUE)
    )
  }
  out
}

read_basic_pitch_note_events <- function(csv_path, segment_info) {
  if (is.null(csv_path) || is.na(csv_path) || !file.exists(csv_path)) {
    return(data.frame())
  }

  # Basic Pitch 0.4.0 writes a note-event CSV whose header is usually:
  #   start_time_s,end_time_s,pitch_midi,velocity,pitch_bend
  # The pitch_bend value is often a sequence of comma-separated integers.
  # That means rows can have many more fields than the 5-column header, e.g.
  # 44, 50, 100+ fields. Strict readers such as read.csv()/pandas may reject
  # the file or silently mangle it. For CATHA we only need the first four
  # stable columns; the remaining fields are preserved as pitch_bend_values.
  lines <- tryCatch(readLines(csv_path, warn = FALSE), error = function(e) character())
  if (length(lines) < 2) return(data.frame())

  parse_line <- function(line) {
    # Basic Pitch paths/fields here are numeric and unquoted in current output;
    # scan() is more tolerant of ragged rows than read.csv().
    vals <- tryCatch(
      scan(text = line, what = character(), sep = ",", quiet = TRUE, quote = "\"", blank.lines.skip = FALSE),
      error = function(e) character()
    )
    vals
  }

  rows <- lapply(lines[-1], parse_line)
  rows <- rows[vapply(rows, length, integer(1)) >= 4]
  if (length(rows) == 0) return(data.frame())

  start_time <- suppressWarnings(as.numeric(vapply(rows, function(x) x[[1]], character(1))))
  end_time <- suppressWarnings(as.numeric(vapply(rows, function(x) x[[2]], character(1))))
  pitch_midi <- suppressWarnings(as.integer(round(as.numeric(vapply(rows, function(x) x[[3]], character(1))))))
  velocity <- suppressWarnings(as.integer(round(as.numeric(vapply(rows, function(x) x[[4]], character(1))))))
  pitch_bend_values <- vapply(rows, function(x) {
    if (length(x) <= 4) return("")
    vals <- x[-seq_len(4)]
    vals <- vals[!is.na(vals) & nzchar(vals)]
    paste(vals, collapse = " ")
  }, character(1))

  keep <- is.finite(start_time) & is.finite(end_time) & is.finite(pitch_midi) & end_time > start_time
  if (!any(keep)) return(data.frame())

  start_time <- start_time[keep]
  end_time <- end_time[keep]
  pitch_midi <- pitch_midi[keep]
  velocity <- velocity[keep]
  pitch_bend_values <- pitch_bend_values[keep]

  out <- data.frame(
    segment_id = segment_info$segment_id,
    label = segment_info$label,
    segment_start = segment_info$start,
    segment_end = segment_info$end,
    note_start_segment_s = start_time,
    note_end_segment_s = end_time,
    note_start_audio_s = segment_info$start + start_time,
    note_end_audio_s = segment_info$start + end_time,
    duration_s = end_time - start_time,
    pitch_midi = pitch_midi,
    note = vapply(pitch_midi, midi_to_note_label, character(1)),
    velocity = velocity,
    pitch_bend_values = pitch_bend_values,
    source_csv = normalizePath(csv_path, winslash = "/", mustWork = TRUE),
    stringsAsFactors = FALSE
  )

  out[order(out$note_start_audio_s, out$pitch_midi), , drop = FALSE]
}

convert_midi_to_musicxml <- function(midi_path, musicxml_path, python_command = "python") {
  if (is.null(midi_path) || is.na(midi_path) || !file.exists(midi_path)) return(FALSE)
  python <- tryCatch(find_executable(python_command, label = "Python"), error = function(e) NA_character_)
  if (is.na(python) || !nzchar(python)) return(FALSE)

  script <- paste(
    "import sys",
    "from music21 import converter",
    "midi_path = sys.argv[1]",
    "xml_path = sys.argv[2]",
    "score = converter.parse(midi_path)",
    "score.write('musicxml', fp=xml_path)",
    sep = "; "
  )
  out <- system2_capture(
    python,
    args = c("-c", script, normalizePath(midi_path, winslash = "/", mustWork = TRUE), normalizePath(musicxml_path, winslash = "/", mustWork = FALSE)),
    stdout = TRUE,
    stderr = TRUE
  )
  file.exists(musicxml_path)
}


find_python_for_external_notation <- function(python_command = "python", basic_pitch_path = NULL) {
  # 1) Prefer the value explicitly provided in the app.
  explicit <- tryCatch(find_executable(python_command, label = "Python"), error = function(e) NA_character_)
  if (!is.na(explicit) && nzchar(explicit) && file.exists(explicit)) return(explicit)

  # 2) If Basic Pitch lives in a virtual environment, the matching Python is
  # normally in the same bin/Scripts folder. This is the safest choice because
  # it has pretty_midi/music21 installed alongside Basic Pitch.
  if (!is.null(basic_pitch_path) && !is.na(basic_pitch_path) && nzchar(basic_pitch_path)) {
    sibling <- if (.Platform$OS.type == "windows") {
      file.path(dirname(basic_pitch_path), "python.exe")
    } else {
      file.path(dirname(basic_pitch_path), "python")
    }
    if (file.exists(sibling)) return(normalizePath(sibling, winslash = "/", mustWork = TRUE))
  }

  # 3) Fall back to project-local virtual environments.
  candidates <- candidate_paths_for_executable("Python")
  candidates <- candidates[file.exists(candidates)]
  if (length(candidates) > 0) return(normalizePath(candidates[1], winslash = "/", mustWork = TRUE))

  NA_character_
}

extract_midi_note_events_to_csv <- function(midi_path, csv_path, python_command = "python", basic_pitch_path = NULL) {
  if (is.null(midi_path) || is.na(midi_path) || !file.exists(midi_path)) return(FALSE)
  python <- find_python_for_external_notation(python_command, basic_pitch_path = basic_pitch_path)
  if (is.na(python) || !nzchar(python) || !file.exists(python)) return(FALSE)

  script <- paste(
    "import sys, csv",
    "import pretty_midi",
    "midi_path = sys.argv[1]",
    "csv_path = sys.argv[2]",
    "pm = pretty_midi.PrettyMIDI(midi_path)",
    "with open(csv_path, 'w', newline='') as f:",
    "    w = csv.writer(f)",
    "    w.writerow(['start_time_s', 'end_time_s', 'pitch_midi', 'velocity', 'instrument_name', 'program', 'is_drum'])",
    "    for inst in pm.instruments:",
    "        for note in inst.notes:",
    "            w.writerow([note.start, note.end, note.pitch, note.velocity, inst.name, inst.program, inst.is_drum])",
    sep = "\n"
  )

  log <- system2_capture(
    python,
    args = c("-c", script, normalizePath(midi_path, winslash = "/", mustWork = TRUE), normalizePath(csv_path, winslash = "/", mustWork = FALSE)),
    stdout = TRUE,
    stderr = TRUE
  )
  file.exists(csv_path)
}

run_basic_pitch_on_segments <- function(wave,
                                        segments,
                                        output_dir,
                                        basic_pitch_command = "basic-pitch",
                                        python_command = "python",
                                        convert_musicxml = TRUE,
                                        onset_threshold = NULL,
                                        frame_threshold = NULL,
                                        minimum_note_length = NULL,
                                        minimum_frequency = NULL,
                                        maximum_frequency = NULL,
                                        multiple_pitch_bends = FALSE,
                                        no_melodia = FALSE) {
  basic_pitch <- find_executable(basic_pitch_command, label = "Basic Pitch")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  segment_dir <- file.path(output_dir, "segment_wavs")
  engine_dir <- file.path(output_dir, "basic_pitch_outputs")
  dir.create(engine_dir, recursive = TRUE, showWarnings = FALSE)

  segment_files <- write_segment_wavs(wave, segments, segment_dir)
  runs <- vector("list", length(segment_files))
  note_tables <- list()

  for (i in seq_along(segment_files)) {
    seg <- segment_files[[i]]
    seg_output_dir <- file.path(engine_dir, sprintf("segment_%03d", seg$segment_id))
    dir.create(seg_output_dir, recursive = TRUE, showWarnings = FALSE)

    args <- c(
      "--save-midi",
      "--save-note-events"
    )
    if (!is.null(onset_threshold) && is.finite(as.numeric(onset_threshold))) {
      args <- c(args, "--onset-threshold", as.character(as.numeric(onset_threshold)))
    }
    if (!is.null(frame_threshold) && is.finite(as.numeric(frame_threshold))) {
      args <- c(args, "--frame-threshold", as.character(as.numeric(frame_threshold)))
    }
    if (!is.null(minimum_note_length) && is.finite(as.numeric(minimum_note_length))) {
      args <- c(args, "--minimum-note-length", as.character(as.numeric(minimum_note_length)))
    }
    if (!is.null(minimum_frequency) && is.finite(as.numeric(minimum_frequency))) {
      args <- c(args, "--minimum-frequency", as.character(as.numeric(minimum_frequency)))
    }
    if (!is.null(maximum_frequency) && is.finite(as.numeric(maximum_frequency))) {
      args <- c(args, "--maximum-frequency", as.character(as.numeric(maximum_frequency)))
    }
    if (isTRUE(multiple_pitch_bends)) {
      args <- c(args, "--multiple-pitch-bends")
    }
    if (isTRUE(no_melodia)) {
      args <- c(args, "--no-melodia")
    }
    args <- c(
      args,
      normalizePath(seg_output_dir, winslash = "/", mustWork = TRUE),
      normalizePath(seg$wav_path, winslash = "/", mustWork = TRUE)
    )

    log <- system2_capture(basic_pitch, args = args, stdout = TRUE, stderr = TRUE)
    midi_files <- list.files(seg_output_dir, pattern = "\\.mid$", full.names = TRUE)
    csv_files <- list.files(seg_output_dir, pattern = "\\.csv$", full.names = TRUE)
    midi_path <- if (length(midi_files) > 0) normalizePath(midi_files[1], winslash = "/", mustWork = TRUE) else NA_character_
    csv_path <- if (length(csv_files) > 0) normalizePath(csv_files[1], winslash = "/", mustWork = TRUE) else NA_character_

    musicxml_path <- NA_character_
    musicxml_created <- FALSE
    if (isTRUE(convert_musicxml) && !is.na(midi_path)) {
      musicxml_path <- file.path(seg_output_dir, paste0(tools::file_path_sans_ext(basename(midi_path)), ".musicxml"))
      musicxml_created <- convert_midi_to_musicxml(midi_path, musicxml_path, python_command = python_command)
      if (!isTRUE(musicxml_created)) musicxml_path <- NA_character_
    }

    notes <- read_basic_pitch_note_events(csv_path, seg)
    midi_fallback_csv <- NA_character_
    midi_fallback_used <- FALSE
    if (nrow(notes) == 0 && !is.na(midi_path) && file.exists(midi_path)) {
      midi_fallback_csv <- file.path(seg_output_dir, paste0(tools::file_path_sans_ext(basename(midi_path)), "_midi_notes_fallback.csv"))
      midi_fallback_used <- extract_midi_note_events_to_csv(
        midi_path = midi_path,
        csv_path = midi_fallback_csv,
        python_command = python_command,
        basic_pitch_path = basic_pitch
      )
      if (isTRUE(midi_fallback_used)) {
        fallback_notes <- read_basic_pitch_note_events(midi_fallback_csv, seg)
        if (nrow(fallback_notes) > 0) notes <- fallback_notes
      }
    }
    if (nrow(notes) > 0) note_tables[[length(note_tables) + 1L]] <- notes

    runs[[i]] <- list(
      segment_id = seg$segment_id,
      label = seg$label,
      segment_start = seg$start,
      segment_end = seg$end,
      segment_wav = seg$wav_path,
      midi = midi_path,
      note_events_csv = csv_path,
      note_events_csv_size_bytes = if (!is.na(csv_path) && file.exists(csv_path)) file.info(csv_path)$size else NA_real_,
      note_events_csv_line_count = if (!is.na(csv_path) && file.exists(csv_path)) length(readLines(csv_path, warn = FALSE)) else NA_integer_,
      midi_fallback_note_events_csv = if (!is.na(midi_fallback_csv) && file.exists(midi_fallback_csv)) normalizePath(midi_fallback_csv, winslash = "/", mustWork = TRUE) else NA_character_,
      midi_fallback_used = isTRUE(midi_fallback_used),
      musicxml = if (!is.na(musicxml_path) && file.exists(musicxml_path)) normalizePath(musicxml_path, winslash = "/", mustWork = TRUE) else NA_character_,
      musicxml_created = isTRUE(musicxml_created),
      cli_args = paste(args, collapse = " "),
      note_count = nrow(notes),
      log = paste(log, collapse = "\n")
    )
  }

  combined_notes <- if (length(note_tables) > 0) do.call(rbind, note_tables) else data.frame()
  summary_path <- file.path(output_dir, "basic_pitch_note_events_all_segments.csv")
  utils::write.csv(combined_notes, summary_path, row.names = FALSE, na = "")

  list(
    engine = "Basic Pitch",
    run_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    output_dir = normalizePath(output_dir, winslash = "/", mustWork = TRUE),
    basic_pitch_command = basic_pitch,
    python_command = python_command,
    musicxml_conversion_requested = isTRUE(convert_musicxml),
    basic_pitch_settings = list(
      onset_threshold = onset_threshold,
      frame_threshold = frame_threshold,
      minimum_note_length = minimum_note_length,
      minimum_frequency = minimum_frequency,
      maximum_frequency = maximum_frequency,
      multiple_pitch_bends = isTRUE(multiple_pitch_bends),
      no_melodia = isTRUE(no_melodia)
    ),
    note_events_all_csv = normalizePath(summary_path, winslash = "/", mustWork = TRUE),
    runs = runs,
    note_events = combined_notes
  )
}

basic_pitch_notes_as_table <- function(external_notation) {
  if (is.null(external_notation) || is.null(external_notation$note_events)) return(data.frame())
  external_notation$note_events
}

external_notation_files <- function(external_notation, type = c("midi", "note_events_csv", "musicxml", "all")) {
  type <- match.arg(type)
  if (is.null(external_notation) || is.null(external_notation$runs)) return(character())
  fields <- switch(
    type,
    midi = "midi",
    note_events_csv = "note_events_csv",
    musicxml = "musicxml",
    all = c("segment_wav", "midi", "note_events_csv", "midi_fallback_note_events_csv", "musicxml")
  )
  if (type == "note_events_csv") fields <- c(fields, "midi_fallback_note_events_csv")
  files <- character()
  for (run in external_notation$runs) {
    for (field in fields) {
      path <- run[[field]]
      if (!is.null(path) && length(path) == 1 && !is.na(path) && nzchar(path) && file.exists(path)) {
        files <- c(files, normalizePath(path, winslash = "/", mustWork = TRUE))
      }
    }
  }
  if (type %in% c("note_events_csv", "all")) {
    summary_path <- external_notation$note_events_all_csv
    if (!is.null(summary_path) && !is.na(summary_path) && file.exists(summary_path)) {
      files <- c(files, normalizePath(summary_path, winslash = "/", mustWork = TRUE))
    }
  }
  unique(files)
}

copy_or_zip_external_files <- function(files, target_file) {
  files <- files[file.exists(files)]
  if (length(files) == 0) {
    stop("No external notation files were available to download.", call. = FALSE)
  }
  if (length(files) == 1) {
    ok <- file.copy(files[1], target_file, overwrite = TRUE)
    if (!isTRUE(ok)) stop("Could not copy external notation file for download.", call. = FALSE)
    return(invisible(target_file))
  }

  zip_dir <- file.path(tempdir(), paste0("catha_external_download_", as.integer(stats::runif(1, 1, 1e8))))
  dir.create(zip_dir, recursive = TRUE, showWarnings = FALSE)
  used_names <- character()
  for (i in seq_along(files)) {
    base <- basename(files[i])
    if (base %in% used_names) {
      base <- paste0(sprintf("%03d_", i), base)
    }
    used_names <- c(used_names, base)
    file.copy(files[i], file.path(zip_dir, base), overwrite = TRUE)
  }
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(zip_dir)
  utils::zip(zipfile = normalizePath(target_file, winslash = "/", mustWork = FALSE), files = list.files(zip_dir), flags = "-r9X")
  invisible(target_file)
}
