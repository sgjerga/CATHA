
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

trace_to_note_rows <- function(contour, bin_seconds = 0.125) {
  if (is.null(contour) || nrow(contour) == 0) return(data.frame())
  contour <- contour[order(contour$time), , drop = FALSE]
  total_time <- max(contour$time, na.rm = TRUE)
  if (!is.finite(total_time) || total_time <= 0) total_time <- bin_seconds
  bins <- seq(0, total_time + bin_seconds, by = bin_seconds)
  if (length(bins) < 2) bins <- c(0, bin_seconds)

  rows <- vector("list", length(bins) - 1)
  for (i in seq_len(length(bins) - 1)) {
    slice <- contour$hz[contour$time >= bins[i] & contour$time < bins[i + 1]]
    slice <- slice[is.finite(slice) & !is.na(slice)]
    if (length(slice) == 0) {
      rows[[i]] <- data.frame(type = "rest", step = NA_character_, alter = NA_integer_, octave = NA_integer_, duration = 1L)
    } else {
      hz <- stats::median(slice)
      midi <- round(69 + 12 * log2(hz / 440))
      pitch <- midi_to_musicxml(midi)
      rows[[i]] <- data.frame(type = "note", step = pitch$step, alter = pitch$alter, octave = pitch$octave, duration = 1L)
    }
  }
  do.call(rbind, rows)
}

write_musicxml <- function(segments, traces, file, title = "CATHA Trace Export") {
  measures <- character()
  measure_number <- 1L

  if (nrow(segments) == 0) {
    measures <- c(
      '<measure number="1">',
      '  <attributes>',
      '    <divisions>1</divisions>',
      '    <time><beats>4</beats><beat-type>4</beat-type></time>',
      '    <clef><sign>G</sign><line>2</line></clef>',
      '  </attributes>',
      '  <note><rest/><duration>4</duration><type>whole</type></note>',
      '</measure>'
    )
  } else {
    for (i in seq_len(nrow(segments))) {
      seg <- segments[i, ]
      trace <- traces[[as.character(seg$segment_id)]]
      notes <- trace_to_note_rows(trace$contour)
      if (nrow(notes) == 0) {
        notes <- data.frame(type = "rest", step = NA_character_, alter = NA_integer_, octave = NA_integer_, duration = 4L)
      }
      measure_lines <- c(sprintf('<measure number="%s">', measure_number))
      if (measure_number == 1L) {
        measure_lines <- c(
          measure_lines,
          '  <attributes>',
          '    <divisions>1</divisions>',
          '    <time><beats>4</beats><beat-type>4</beat-type></time>',
          '    <clef><sign>G</sign><line>2</line></clef>',
          '  </attributes>'
        )
      }
      measure_lines <- c(measure_lines, sprintf('  <direction placement="above"><direction-type><words>%s</words></direction-type></direction>', gsub('&', 'and', seg$label)))
      for (j in seq_len(nrow(notes))) {
        row <- notes[j, ]
        if (row$type == "rest") {
          measure_lines <- c(measure_lines, '  <note><rest/><duration>1</duration><type>quarter</type></note>')
        } else {
          note_xml <- c(
            '  <note>',
            '    <pitch>',
            sprintf('      <step>%s</step>', row$step),
            if (!is.na(row$alter) && row$alter != 0) sprintf('      <alter>%s</alter>', row$alter) else NULL,
            sprintf('      <octave>%s</octave>', row$octave),
            '    </pitch>',
            sprintf('    <duration>%s</duration>', row$duration),
            '    <type>quarter</type>',
            '  </note>'
          )
          measure_lines <- c(measure_lines, note_xml)
        }
      }
      measure_lines <- c(measure_lines, '</measure>')
      measures <- c(measures, measure_lines)
      measure_number <- measure_number + 1L
    }
  }

  xml <- c(
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
    '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
    '<score-partwise version="4.0">',
    '  <work>',
    sprintf('    <work-title>%s</work-title>', gsub('&', 'and', title)),
    '  </work>',
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

write_bundle <- function(bundle_file, audio_path, segments, features, annotations, traces, audio_summary = NULL) {
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
  write_musicxml(segments, traces, file.path(build_dir, "trace.musicxml"))

  manifest <- c(
    "CATHA export bundle",
    sprintf("Exported at: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    sprintf("Segments: %s", nrow(segments)),
    sprintf("Annotated segments: %s", nrow(annotations)),
    sprintf("Feature rows: %s", nrow(features)),
    "",
    "Files:",
    "- segments.csv: episode boundaries and labels",
    "- features.csv: formal features per segment",
    "- annotations.csv: therapist-guided annotations and uncertainty",
    "- trace.json: hierarchical trace export for downstream pipelines",
    "- segments.TextGrid: Praat-compatible segmentation",
    "- trace.musicxml: score-oriented trace export"
  )
  writeLines(manifest, con = file.path(build_dir, "README.txt"))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(build_dir)
  utils::zip(zipfile = normalizePath(bundle_file, winslash = "/", mustWork = FALSE), files = list.files(build_dir), flags = "-r9X")
}
