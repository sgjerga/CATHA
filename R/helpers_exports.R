upsert_annotation <- function(existing, new_row, key = "segment_id") {
  key_value <- new_row[[key]][[1]]
  if (nrow(existing) == 0) return(new_row)
  if (key_value %in% existing[[key]]) {
    existing[existing[[key]] == key_value, names(new_row)] <- new_row[rep(1, sum(existing[[key]] == key_value)), names(new_row), drop = FALSE]
    existing
  } else {
    dplyr::bind_rows(existing, new_row)
  }
}

build_joint_display <- function(segments, features, annotations) {
  out <- segments
  if (nrow(features) > 0) {
    out <- dplyr::left_join(out, features, by = c("segment_id", "label", "start", "end", "duration"))
  }
  if (nrow(annotations) > 0) {
    out <- dplyr::left_join(out, annotations, by = "segment_id")
  }
  out
}

xml_escape <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  x
}

write_trace_json <- function(segments, features, annotations, traces, file) {
  trace_payload <- lapply(names(traces), function(id) {
    trace <- traces[[id]]
    list(
      segment_id = as.integer(id),
      contour = if (!is.null(trace$contour)) trace$contour else data.frame(),
      intensity = if (!is.null(trace$intensity)) trace$intensity else data.frame()
    )
  })
  payload <- list(
    exported_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    segments = segments,
    features = features,
    annotations = annotations,
    traces = trace_payload
  )
  jsonlite::write_json(payload, path = file, auto_unbox = TRUE, pretty = TRUE, na = "null")
}

write_textgrid <- function(segments, file, xmax = NULL) {
  if (is.null(xmax)) {
    xmax <- if (nrow(segments) > 0) max(segments$end, na.rm = TRUE) else 0
  }
  lines <- c(
    'File type = "ooTextFile"',
    'Object class = "TextGrid"',
    '',
    sprintf('xmin = 0'),
    sprintf('xmax = %s', format(xmax, scientific = FALSE)),
    'tiers? <exists>',
    'size = 1',
    'item []:',
    '    item [1]:',
    '        class = "IntervalTier"',
    '        name = "segments"',
    '        xmin = 0',
    sprintf('        xmax = %s', format(xmax, scientific = FALSE)),
    sprintf('        intervals: size = %s', nrow(segments))
  )
  if (nrow(segments) > 0) {
    for (i in seq_len(nrow(segments))) {
      lines <- c(
        lines,
        sprintf('        intervals [%s]:', i),
        sprintf('            xmin = %s', format(segments$start[i], scientific = FALSE)),
        sprintf('            xmax = %s', format(segments$end[i], scientific = FALSE)),
        sprintf('            text = "%s"', gsub('"', "'", segments$label[i]))
      )
    }
  }
  writeLines(lines, con = file, useBytes = TRUE)
}

midi_to_musicxml <- function(midi_note) {
  steps <- c("C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B")
  alters <- c(0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0)
  pc <- (midi_note %% 12) + 1
  octave <- floor(midi_note / 12) - 1
  list(step = steps[pc], alter = alters[pc], octave = octave)
}

parse_meter <- function(meter = "4/4") {
  meter <- as.character(meter %||% "4/4")
  pieces <- strsplit(meter, "/", fixed = TRUE)[[1]]
  if (length(pieces) != 2) pieces <- c("4", "4")
  beats <- suppressWarnings(as.integer(pieces[1]))
  beat_type <- suppressWarnings(as.integer(pieces[2]))
  if (!is.finite(beats) || beats <= 0) beats <- 4L
  if (!is.finite(beat_type) || beat_type <= 0) beat_type <- 4L
  list(beats = beats, beat_type = beat_type, label = paste0(beats, "/", beat_type))
}

subdivision_info <- function(subdivision = "1/16") {
  subdivision <- as.character(subdivision %||% "1/16")
  denom <- switch(
    subdivision,
    "1/8" = 8L,
    "1/16" = 16L,
    "1/32" = 32L,
    16L
  )
  list(
    label = paste0("1/", denom),
    denominator = denom,
    units_per_quarter = as.integer(denom / 4),
    abc_unit = paste0("1/", denom)
  )
}

units_per_measure <- function(meter = "4/4", subdivision = "1/16") {
  m <- parse_meter(meter)
  s <- subdivision_info(subdivision)
  as.integer(m$beats * s$units_per_quarter * (4 / m$beat_type))
}

units_per_beat <- function(meter = "4/4", subdivision = "1/16") {
  m <- parse_meter(meter)
  s <- subdivision_info(subdivision)
  s$units_per_quarter * (4 / m$beat_type)
}

estimate_speech_tempo_bpm <- function(intensity,
                                      default_bpm = 96,
                                      min_bpm = 55,
                                      max_bpm = 180) {
  default_bpm <- as.numeric(default_bpm %||% 96)
  if (!is.finite(default_bpm) || default_bpm <= 0) default_bpm <- 96
  if (is.null(intensity) || nrow(intensity) < 5 || !all(c("time", "rms") %in% names(intensity))) {
    return(round(default_bpm))
  }

  df <- intensity[is.finite(intensity$time) & is.finite(intensity$rms), c("time", "rms"), drop = FALSE]
  if (nrow(df) < 5) return(round(default_bpm))
  df <- df[order(df$time), , drop = FALSE]
  if (diff(range(df$time, na.rm = TRUE)) < 0.4) return(round(default_bpm))

  rms <- as.numeric(df$rms)
  rms <- rms - stats::median(rms, na.rm = TRUE)
  rng <- diff(range(rms, na.rm = TRUE))
  if (!is.finite(rng) || rng <= 0) return(round(default_bpm))
  rms <- rms / rng

  # Light smoothing without adding package dependencies.
  k <- max(3L, min(9L, as.integer(round(nrow(df) / 30))))
  kernel <- rep(1 / k, k)
  smooth <- as.numeric(stats::filter(rms, kernel, sides = 2))
  smooth[!is.finite(smooth)] <- rms[!is.finite(smooth)]

  threshold <- stats::quantile(smooth, probs = 0.65, na.rm = TRUE, names = FALSE)
  local_peak <- rep(FALSE, length(smooth))
  if (length(smooth) >= 3) {
    local_peak[2:(length(smooth) - 1)] <-
      smooth[2:(length(smooth) - 1)] >= smooth[1:(length(smooth) - 2)] &
      smooth[2:(length(smooth) - 1)] > smooth[3:length(smooth)] &
      smooth[2:(length(smooth) - 1)] >= threshold
  }
  peak_times <- df$time[local_peak]
  if (length(peak_times) < 3) return(round(default_bpm))

  # Keep syllable-like pulses separated by at least ~180 ms.
  kept <- numeric()
  last <- -Inf
  for (t in peak_times) {
    if ((t - last) >= 0.18) {
      kept <- c(kept, t)
      last <- t
    }
  }
  if (length(kept) < 3) return(round(default_bpm))

  ioi <- diff(kept)
  ioi <- ioi[is.finite(ioi) & ioi >= 0.18 & ioi <= 1.5]
  if (length(ioi) < 2) return(round(default_bpm))

  bpm <- 60 / stats::median(ioi, na.rm = TRUE)
  while (is.finite(bpm) && bpm < min_bpm) bpm <- bpm * 2
  while (is.finite(bpm) && bpm > max_bpm) bpm <- bpm / 2
  if (!is.finite(bpm) || bpm < min_bpm || bpm > max_bpm) return(round(default_bpm))
  round(bpm)
}

pitch_for_slice <- function(hz_values) {
  hz_values <- hz_values[is.finite(hz_values) & !is.na(hz_values) & hz_values > 0]
  if (length(hz_values) == 0) return(NULL)
  hz <- stats::median(hz_values)
  midi <- round(69 + 12 * log2(hz / 440))
  pitch <- midi_to_musicxml(midi)
  pitch$midi <- midi
  pitch$hz <- hz
  pitch
}

is_pause_bin <- function(intensity, bin_start, bin_end) {
  if (is.null(intensity) || nrow(intensity) == 0 || !("pause_flag" %in% names(intensity))) return(FALSE)
  idx <- intensity$time >= bin_start & intensity$time < bin_end
  flags <- intensity$pause_flag[idx]
  flags <- flags[!is.na(flags)]
  if (length(flags) == 0) return(FALSE)
  mean(as.logical(flags)) >= 0.6
}

base_contour_events <- function(contour,
                                intensity = NULL,
                                bin_seconds = 0.05,
                                merge_repeats = TRUE) {
  if (is.null(contour) || nrow(contour) == 0 || !("time" %in% names(contour)) || !("hz" %in% names(contour))) {
    return(data.frame())
  }
  contour <- contour[is.finite(contour$time), , drop = FALSE]
  if (nrow(contour) == 0) return(data.frame())
  contour <- contour[order(contour$time), , drop = FALSE]

  total_time <- max(contour$time, na.rm = TRUE)
  if (!is.finite(total_time) || total_time <= 0) total_time <- bin_seconds
  bins <- seq(0, total_time + bin_seconds, by = bin_seconds)
  if (length(bins) < 2) bins <- c(0, bin_seconds)

  rows <- vector("list", length(bins) - 1)
  for (i in seq_len(length(bins) - 1)) {
    bin_start <- bins[i]
    bin_end <- bins[i + 1]
    pause_bin <- is_pause_bin(intensity, bin_start, bin_end)
    hz_slice <- contour$hz[contour$time >= bin_start & contour$time < bin_end]
    pitch <- if (pause_bin) NULL else pitch_for_slice(hz_slice)
    if (is.null(pitch)) {
      rows[[i]] <- data.frame(
        type = "rest", midi = NA_integer_, step = NA_character_, alter = NA_integer_, octave = NA_integer_,
        hz = NA_real_, start = bin_start, end = bin_end, duration_seconds = bin_end - bin_start
      )
    } else {
      rows[[i]] <- data.frame(
        type = "note", midi = pitch$midi, step = pitch$step, alter = pitch$alter, octave = pitch$octave,
        hz = pitch$hz, start = bin_start, end = bin_end, duration_seconds = bin_end - bin_start
      )
    }
  }
  events <- do.call(rbind, rows)
  if (!isTRUE(merge_repeats) || nrow(events) <= 1) return(events)

  groups <- integer(nrow(events))
  current_group <- 1L
  groups[1] <- current_group
  for (i in 2:nrow(events)) {
    same_type <- identical(events$type[i], events$type[i - 1])
    same_pitch <- isTRUE(events$type[i] == "rest" && events$type[i - 1] == "rest") ||
      (isTRUE(events$type[i] == "note" && events$type[i - 1] == "note") && identical(events$midi[i], events$midi[i - 1]))
    if (!(same_type && same_pitch)) current_group <- current_group + 1L
    groups[i] <- current_group
  }

  collapsed <- lapply(split(events, groups), function(x) {
    first <- x[1, , drop = FALSE]
    first$start <- min(x$start, na.rm = TRUE)
    first$end <- max(x$end, na.rm = TRUE)
    first$duration_seconds <- sum(x$duration_seconds, na.rm = TRUE)
    if (first$type == "note") {
      first$hz <- stats::median(x$hz, na.rm = TRUE)
    }
    first
  })
  do.call(rbind, collapsed)
}

split_note_rows_by_measure <- function(rows, meter = "4/4", subdivision = "1/16") {
  if (is.null(rows) || nrow(rows) == 0) return(data.frame())
  upm <- units_per_measure(meter, subdivision)
  upb <- units_per_beat(meter, subdivision)
  if (!is.finite(upm) || upm <= 0) upm <- 16L
  if (!is.finite(upb) || upb <= 0) upb <- 4L

  out <- list()
  cumulative_units <- 0L
  k <- 1L
  for (i in seq_len(nrow(rows))) {
    remaining <- as.integer(max(1L, rows$duration_units[i]))
    while (remaining > 0) {
      measure_pos <- cumulative_units %% upm
      space <- upm - measure_pos
      take <- min(remaining, space)
      row <- rows[i, , drop = FALSE]
      row$duration_units <- as.integer(take)
      row$measure <- as.integer(floor(cumulative_units / upm) + 1L)
      row$beat <- round((measure_pos / upb) + 1, 3)
      row$bar_complete_after <- (measure_pos + take) >= upm
      out[[k]] <- row
      k <- k + 1L
      cumulative_units <- cumulative_units + take
      remaining <- remaining - take
    }
  }
  do.call(rbind, out)
}

trace_to_rhythm_note_rows <- function(contour,
                                      intensity = NULL,
                                      tempo_bpm = 96,
                                      meter = "4/4",
                                      subdivision = "1/16",
                                      bin_seconds = 0.05,
                                      merge_repeats = TRUE,
                                      quantize = TRUE) {
  events <- base_contour_events(contour, intensity = intensity, bin_seconds = bin_seconds, merge_repeats = merge_repeats)
  if (nrow(events) == 0) return(data.frame())

  tempo_bpm <- as.numeric(tempo_bpm %||% 96)
  if (!is.finite(tempo_bpm) || tempo_bpm <= 0) tempo_bpm <- 96
  subdiv <- subdivision_info(subdivision)
  unit_seconds <- (60 / tempo_bpm) / subdiv$units_per_quarter

  rows <- events
  if (isTRUE(quantize)) {
    rows$duration_units <- pmax(1L, as.integer(round(rows$duration_seconds / unit_seconds)))
  } else {
    rows$duration_units <- pmax(1L, as.integer(round(rows$duration_seconds / bin_seconds)))
  }
  rows$duration_beats <- round(rows$duration_units / units_per_beat(meter, subdivision), 3)
  rows$tempo_bpm <- tempo_bpm
  rows$meter <- parse_meter(meter)$label
  rows$subdivision <- subdiv$label

  split_note_rows_by_measure(rows, meter = meter, subdivision = subdivision)
}

# Backwards-compatible simple trace conversion used by older calls.
trace_to_note_rows <- function(contour, bin_seconds = 0.125) {
  rows <- trace_to_rhythm_note_rows(
    contour = contour,
    intensity = NULL,
    tempo_bpm = 120,
    meter = "4/4",
    subdivision = "1/16",
    bin_seconds = bin_seconds,
    merge_repeats = FALSE,
    quantize = TRUE
  )
  if (nrow(rows) == 0) return(data.frame())
  data.frame(
    type = rows$type,
    step = rows$step,
    alter = rows$alter,
    octave = rows$octave,
    duration = rows$duration_units
  )
}

abc_note_token <- function(row) {
  duration_units <- as.integer(row$duration_units %||% 1L)
  dur <- if (duration_units == 1L) "" else as.character(duration_units)
  if (row$type == "rest" || is.na(row$octave)) return(paste0("z", dur))
  acc <- if (!is.na(row$alter) && row$alter == 1) "^" else if (!is.na(row$alter) && row$alter == -1) "_" else ""
  step <- as.character(row$step)
  octave <- as.integer(row$octave)
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
  paste0(acc, note_char, oct_mod, dur)
}

note_rows_to_abc <- function(note_rows,
                             title = "CATHA Pulse-Quantized Speech Trace",
                             tempo_bpm = 96,
                             meter = "4/4",
                             subdivision = "1/16",
                             measures_per_line = 4) {
  m <- parse_meter(meter)
  s <- subdivision_info(subdivision)
  if (is.null(note_rows) || nrow(note_rows) == 0) {
    return(paste0(
      "X:1\n",
      "T:", title, "\n",
      "M:", m$label, "\n",
      "L:", s$abc_unit, "\n",
      "Q:1/4=", round(tempo_bpm), "\n",
      "K:C\n",
      "z", units_per_measure(meter, subdivision), " |\n"
    ))
  }

  median_octave <- suppressWarnings(stats::median(note_rows$octave[note_rows$type == "note"], na.rm = TRUE))
  clef_type <- if (is.finite(median_octave) && median_octave <= 3.5) "bass" else "treble"
  header <- paste0(
    "X:1\n",
    "T:", gsub("[\r\n]+", " ", title), "\n",
    "M:", m$label, "\n",
    "L:", s$abc_unit, "\n",
    "Q:1/4=", round(tempo_bpm), "\n",
    "K:C clef=", clef_type, "\n"
  )

  current_measure <- if ("measure" %in% names(note_rows)) note_rows$measure[1] else 1L
  measure_count_on_line <- 0L
  parts <- character()
  for (i in seq_len(nrow(note_rows))) {
    row <- note_rows[i, , drop = FALSE]
    if ("measure" %in% names(note_rows) && row$measure != current_measure) {
      parts <- c(parts, "|")
      measure_count_on_line <- measure_count_on_line + 1L
      if (measure_count_on_line %% measures_per_line == 0L) parts <- c(parts, "\n")
      current_measure <- row$measure
    }
    parts <- c(parts, abc_note_token(row))
    if (isTRUE(row$bar_complete_after)) {
      parts <- c(parts, "|")
      measure_count_on_line <- measure_count_on_line + 1L
      if (measure_count_on_line %% measures_per_line == 0L) parts <- c(parts, "\n")
    }
  }
  if (length(parts) == 0 || tail(parts, 1) != "|") parts <- c(parts, "|")
  paste0(header, paste(parts, collapse = " "), "\n")
}

musicxml_type_for_units <- function(units, subdivision = "1/16") {
  s <- subdivision_info(subdivision)
  ratio_to_quarter <- units / s$units_per_quarter
  if (abs(ratio_to_quarter - 4) < 1e-9) return("whole")
  if (abs(ratio_to_quarter - 2) < 1e-9) return("half")
  if (abs(ratio_to_quarter - 1) < 1e-9) return("quarter")
  if (abs(ratio_to_quarter - 0.5) < 1e-9) return("eighth")
  if (abs(ratio_to_quarter - 0.25) < 1e-9) return("16th")
  if (abs(ratio_to_quarter - 0.125) < 1e-9) return("32nd")
  "eighth"
}

decompose_duration_units <- function(units) {
  units <- as.integer(max(1L, units))
  pieces <- integer()
  candidates <- c(64L, 32L, 16L, 8L, 4L, 2L, 1L)
  remaining <- units
  for (candidate in candidates) {
    while (remaining >= candidate) {
      pieces <- c(pieces, candidate)
      remaining <- remaining - candidate
    }
  }
  pieces
}

note_to_musicxml_lines <- function(row, duration_units, subdivision = "1/16") {
  duration_units <- as.integer(duration_units)
  note_type <- musicxml_type_for_units(duration_units, subdivision)
  if (row$type == "rest" || is.na(row$octave)) {
    return(c(
      '  <note>',
      '    <rest/>',
      sprintf('    <duration>%s</duration>', duration_units),
      sprintf('    <type>%s</type>', note_type),
      '  </note>'
    ))
  }
  c(
    '  <note>',
    '    <pitch>',
    sprintf('      <step>%s</step>', row$step),
    if (!is.na(row$alter) && row$alter != 0) sprintf('      <alter>%s</alter>', row$alter) else NULL,
    sprintf('      <octave>%s</octave>', row$octave),
    '    </pitch>',
    sprintf('    <duration>%s</duration>', duration_units),
    sprintf('    <type>%s</type>', note_type),
    '  </note>'
  )
}

write_musicxml <- function(segments,
                           traces,
                           file,
                           title = "CATHA Pulse-Quantized Trace Export",
                           rhythm_settings = list()) {
  meter <- rhythm_settings$meter %||% "4/4"
  subdivision <- rhythm_settings$subdivision %||% "1/16"
  manual_bpm <- as.numeric(rhythm_settings$tempo_bpm %||% 96)
  if (!is.finite(manual_bpm) || manual_bpm <= 0) manual_bpm <- 96
  tempo_mode <- rhythm_settings$tempo_mode %||% "manual"
  bin_seconds <- as.numeric(rhythm_settings$bin_seconds %||% 0.05)
  merge_repeats <- if (is.null(rhythm_settings$merge_repeats)) TRUE else isTRUE(rhythm_settings$merge_repeats)

  m <- parse_meter(meter)
  s <- subdivision_info(subdivision)
  measures <- character()
  measure_number <- 1L

  add_measure_attributes <- function(lines, tempo_bpm) {
    c(
      lines,
      '  <attributes>',
      sprintf('    <divisions>%s</divisions>', s$units_per_quarter),
      sprintf('    <time><beats>%s</beats><beat-type>%s</beat-type></time>', m$beats, m$beat_type),
      '    <clef><sign>G</sign><line>2</line></clef>',
      '  </attributes>',
      sprintf('  <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>%s</per-minute></metronome></direction-type><sound tempo="%s"/></direction>', round(tempo_bpm), round(tempo_bpm))
    )
  }

  if (nrow(segments) == 0) {
    measure_lines <- c('<measure number="1">')
    measure_lines <- add_measure_attributes(measure_lines, manual_bpm)
    measure_lines <- c(
      measure_lines,
      sprintf('  <note><rest/><duration>%s</duration><type>whole</type></note>', units_per_measure(meter, subdivision)),
      '</measure>'
    )
    measures <- c(measures, measure_lines)
  } else {
    for (i in seq_len(nrow(segments))) {
      seg <- segments[i, ]
      trace <- traces[[as.character(seg$segment_id)]]
      if (is.null(trace)) trace <- list(contour = data.frame(), intensity = NULL)
      intensity <- if (!is.null(trace$intensity)) trace$intensity else NULL
      tempo_bpm <- if (identical(tempo_mode, "auto")) {
        estimate_speech_tempo_bpm(intensity, default_bpm = manual_bpm)
      } else {
        manual_bpm
      }
      notes <- if (!is.null(trace$contour)) {
        trace_to_rhythm_note_rows(
          contour = trace$contour,
          intensity = intensity,
          tempo_bpm = tempo_bpm,
          meter = meter,
          subdivision = subdivision,
          bin_seconds = bin_seconds,
          merge_repeats = merge_repeats,
          quantize = TRUE
        )
      } else {
        data.frame()
      }
      if (nrow(notes) == 0) {
        notes <- data.frame(
          type = "rest", midi = NA_integer_, step = NA_character_, alter = NA_integer_, octave = NA_integer_,
          hz = NA_real_, start = 0, end = 0, duration_seconds = 0,
          duration_units = units_per_measure(meter, subdivision), duration_beats = m$beats,
          tempo_bpm = tempo_bpm, meter = m$label, subdivision = s$label,
          measure = 1L, beat = 1, bar_complete_after = TRUE
        )
      }

      note_measures <- split(notes, notes$measure)
      for (measure_key in names(note_measures)) {
        measure_rows <- note_measures[[measure_key]]
        measure_lines <- c(sprintf('<measure number="%s">', measure_number))
        if (measure_number == 1L) {
          measure_lines <- add_measure_attributes(measure_lines, tempo_bpm)
        }
        if (as.integer(measure_key) == min(notes$measure, na.rm = TRUE)) {
          measure_lines <- c(
            measure_lines,
            sprintf('  <direction placement="above"><direction-type><words>%s</words></direction-type></direction>', xml_escape(seg$label))
          )
        }
        for (j in seq_len(nrow(measure_rows))) {
          row <- measure_rows[j, , drop = FALSE]
          for (piece in decompose_duration_units(row$duration_units)) {
            measure_lines <- c(measure_lines, note_to_musicxml_lines(row, piece, subdivision = subdivision))
          }
        }

        current_units <- sum(measure_rows$duration_units, na.rm = TRUE)
        pad_units <- units_per_measure(meter, subdivision) - current_units
        if (is.finite(pad_units) && pad_units > 0) {
          pad_row <- measure_rows[1, , drop = FALSE]
          pad_row$type <- "rest"
          pad_row$step <- NA_character_
          pad_row$alter <- NA_integer_
          pad_row$octave <- NA_integer_
          for (piece in decompose_duration_units(pad_units)) {
            measure_lines <- c(measure_lines, note_to_musicxml_lines(pad_row, piece, subdivision = subdivision))
          }
        }
        measure_lines <- c(measure_lines, '</measure>')
        measures <- c(measures, measure_lines)
        measure_number <- measure_number + 1L
      }
    }
  }

  xml <- c(
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
    '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
    '<score-partwise version="4.0">',
    '  <work>',
    sprintf('    <work-title>%s</work-title>', xml_escape(title)),
    '  </work>',
    '  <identification>',
    '    <encoding><software>CATHA Shiny Prototype</software></encoding>',
    '  </identification>',
    '  <part-list>',
    '    <score-part id="P1">',
    '      <part-name>CATHA Trace</part-name>',
    '    </score-part>',
    '  </part-list>',
    '  <part id="P1">',
    measures,
    '  </part>',
    '</score-partwise>'
  )
  writeLines(xml, con = file, useBytes = TRUE)
}

write_bundle <- function(bundle_file,
                         audio_path,
                         segments,
                         features,
                         annotations,
                         traces,
                         audio_summary = NULL,
                         rhythm_settings = list(),
                         external_notation = NULL) {
  build_dir <- file.path(tempdir(), paste0("catha_export_", as.integer(stats::runif(1, 1, 1e8))))
  dir.create(build_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(audio_path) && file.exists(audio_path)) {
    file.copy(audio_path, file.path(build_dir, basename(audio_path)), overwrite = TRUE)
  }

  write.csv(segments, file.path(build_dir, "segments.csv"), row.names = FALSE, na = "")
  write.csv(features, file.path(build_dir, "features.csv"), row.names = FALSE, na = "")
  write.csv(annotations, file.path(build_dir, "annotations.csv"), row.names = FALSE, na = "")
  write_trace_json(segments, features, annotations, traces, file.path(build_dir, "trace.json"))
  xmax <- if (!is.null(audio_summary)) audio_summary$duration_seconds else if (nrow(segments) > 0) max(segments$end, na.rm = TRUE) else 0
  write_textgrid(segments, file.path(build_dir, "segments.TextGrid"), xmax = xmax)
  write_musicxml(segments, traces, file.path(build_dir, "trace.musicxml"), rhythm_settings = rhythm_settings)

  external_file_count <- 0L
  external_note_count <- 0L
  if (!is.null(external_notation)) {
    ext_dir <- file.path(build_dir, "external_notation_basic_pitch")
    dir.create(ext_dir, recursive = TRUE, showWarnings = FALSE)

    if (exists("basic_pitch_notes_as_table", mode = "function")) {
      ext_notes <- basic_pitch_notes_as_table(external_notation)
    } else if (!is.null(external_notation$note_events)) {
      ext_notes <- external_notation$note_events
    } else {
      ext_notes <- data.frame()
    }
    external_note_count <- nrow(ext_notes)
    write.csv(ext_notes, file.path(ext_dir, "basic_pitch_note_events_all_segments.csv"), row.names = FALSE, na = "")

    if (exists("external_notation_files", mode = "function")) {
      ext_files <- external_notation_files(external_notation, "all")
    } else {
      ext_files <- character()
    }
    if (length(ext_files) > 0) {
      for (src in ext_files) {
        if (file.exists(src)) {
          dst <- file.path(ext_dir, basename(src))
          if (file.exists(dst)) {
            dst <- file.path(ext_dir, paste0(tools::file_path_sans_ext(basename(src)), "_", external_file_count + 1L, ".", tools::file_ext(src)))
          }
          ok <- file.copy(src, dst, overwrite = TRUE)
          if (isTRUE(ok)) external_file_count <- external_file_count + 1L
        }
      }
    }

    ext_manifest <- c(
      "CATHA external notation output",
      sprintf("Engine: %s", external_notation$engine %||% "Basic Pitch"),
      sprintf("Run at: %s", external_notation$run_at %||% "unknown"),
      sprintf("Detected note events: %s", external_note_count),
      "",
      "These outputs are optional MIDI / note-event transcriptions. They are not diagnostic and should be manually reviewed before interpretive use."
    )
    writeLines(ext_manifest, con = file.path(ext_dir, "README_external_notation.txt"))
  }

  manifest <- c(
    "CATHA export bundle",
    sprintf("Exported at: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    sprintf("Segments: %s", nrow(segments)),
    sprintf("Annotated segments: %s", nrow(annotations)),
    sprintf("Feature rows: %s", nrow(features)),
    sprintf("External Basic Pitch note events: %s", external_note_count),
    sprintf("External Basic Pitch files copied: %s", external_file_count),
    "",
    "Musical translation settings:",
    sprintf("- Tempo mode: %s", rhythm_settings$tempo_mode %||% "manual"),
    sprintf("- Tempo/default BPM: %s", rhythm_settings$tempo_bpm %||% 96),
    sprintf("- Meter: %s", rhythm_settings$meter %||% "4/4"),
    sprintf("- Rhythmic grid: %s", rhythm_settings$subdivision %||% "1/16"),
    "",
    "Files:",
    "- segments.csv: episode boundaries and labels",
    "- features.csv: formal features per segment",
    "- annotations.csv: therapist-guided annotations and uncertainty",
    "- trace.json: hierarchical trace export for downstream pipelines",
    "- segments.TextGrid: Praat-compatible segmentation",
    "- trace.musicxml: pulse-quantized score-oriented trace export",
    "- external_notation_basic_pitch/: optional Basic Pitch MIDI, note-event CSV, MusicXML, and segment WAV outputs when generated"
  )
  writeLines(manifest, con = file.path(build_dir, "README.txt"))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(build_dir)
  utils::zip(zipfile = normalizePath(bundle_file, winslash = "/", mustWork = FALSE), files = list.files(build_dir), flags = "-r9X")
}
