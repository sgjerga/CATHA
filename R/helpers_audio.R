
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

sanitize_stem <- function(x) {
  gsub("[^A-Za-z0-9_-]+", "_", tools::file_path_sans_ext(basename(x)))
}

ensure_wav <- function(input_path, output_path, sample_rate = 44100, mono = TRUE) {
  stopifnot(file.exists(input_path))
  ext <- tolower(tools::file_ext(input_path))
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

  ffmpeg <- Sys.which("ffmpeg")
  if (nzchar(ffmpeg)) {
    args <- c(
      "-y",
      "-i", normalizePath(input_path, winslash = "/", mustWork = TRUE),
      if (isTRUE(mono)) c("-ac", "1") else c(),
      "-ar", as.character(sample_rate),
      normalizePath(output_path, winslash = "/", mustWork = FALSE)
    )
    out <- suppressWarnings(system2(ffmpeg, args = args, stdout = TRUE, stderr = TRUE))
    if (!file.exists(output_path)) {
      stop("ffmpeg could not convert the audio file. Details: ", paste(out, collapse = " "))
    }
    return(output_path)
  }

  if (ext == "wav") {
    ok <- file.copy(input_path, output_path, overwrite = TRUE)
    if (!ok) stop("Could not copy WAV file into the analysis workspace.")
    return(output_path)
  }

  stop("ffmpeg is required to convert non-WAV uploads (such as .mp3) into analysis-ready WAV.")
}

safe_read_wave <- function(path) {
  w <- tuneR::readWave(path)
  if (isTRUE(w@stereo)) {
    w <- tuneR::mono(w, which = "left")
  }
  w
}

wave_samples <- function(wave) {
  samples <- wave@left
  as.numeric(samples) / (2^(wave@bit - 1))
}

summarize_wave <- function(wave, display_name, source_type) {
  samples <- wave_samples(wave)
  duration <- length(samples) / wave@samp.rate
  list(
    display_name = display_name,
    source_type = source_type,
    duration_seconds = round(duration, 3),
    sample_rate = wave@samp.rate,
    channels = if (isTRUE(wave@stereo)) 2L else 1L,
    bit_depth = wave@bit,
    sample_count = length(samples)
  )
}

downsample_wave_df <- function(wave, max_points = 15000) {
  samples <- wave_samples(wave)
  n <- length(samples)
  if (n <= max_points) {
    idx <- seq_len(n)
  } else {
    idx <- unique(round(seq(1, n, length.out = max_points)))
  }
  data.frame(
    time = (idx - 1) / wave@samp.rate,
    amplitude = samples[idx]
  )
}

extract_segment_wave <- function(wave, start, end) {
  tuneR::extractWave(wave, from = start, to = end, xunit = "time")
}

frame_indices <- function(signal_length, frame_size, hop_size) {
  starts <- seq.int(1, max(1, signal_length - frame_size + 1), by = hop_size)
  ends <- pmin(signal_length, starts + frame_size - 1)
  cbind(starts, ends)
}

frame_rms_trace <- function(samples, sr, frame_size, hop_size) {
  idx <- frame_indices(length(samples), frame_size, hop_size)
  rms <- numeric(nrow(idx))
  times <- numeric(nrow(idx))
  for (i in seq_len(nrow(idx))) {
    segment <- samples[idx[i, 1]:idx[i, 2]]
    rms[i] <- sqrt(mean(segment^2))
    times[i] <- ((idx[i, 1] + idx[i, 2]) / 2) / sr
  }
  data.frame(time = times, rms = rms)
}

hann_window <- function(n) {
  n <- as.integer(n)
  if (is.na(n) || n <= 1L) return(rep(1, max(1L, n)))
  0.5 - 0.5 * cos(2 * pi * (0:(n - 1)) / (n - 1))
}

estimate_pitch_trace <- function(samples, sr, frame_size, hop_size, pitch_floor = 75, pitch_ceiling = 500) {
  idx <- frame_indices(length(samples), frame_size, hop_size)
  min_lag <- max(1L, floor(sr / pitch_ceiling))
  max_lag <- max(min_lag + 1L, ceiling(sr / pitch_floor))
  out_time <- numeric(nrow(idx))
  out_hz <- rep(NA_real_, nrow(idx))
  window <- hann_window(frame_size)

  for (i in seq_len(nrow(idx))) {
    frame <- samples[idx[i, 1]:idx[i, 2]]
    if (length(frame) < frame_size) {
      frame <- c(frame, rep(0, frame_size - length(frame)))
    }
    rms <- sqrt(mean(frame^2))
    out_time[i] <- ((idx[i, 1] + idx[i, 2]) / 2) / sr
    if (rms < 0.0001) next

    frame <- frame - mean(frame)
    frame <- frame * window
    ac <- stats::acf(frame, plot = FALSE, lag.max = max_lag, demean = FALSE)$acf
    ac <- as.numeric(ac)
    if (length(ac) <= max_lag + 1) next

    search <- ac[(min_lag + 1):(max_lag + 1)]
    best_idx <- which.max(search)
    best_corr <- search[best_idx]
    if (!is.finite(best_corr) || best_corr < 0.1) next

    lag <- min_lag + best_idx - 1L
    out_hz[i] <- sr / lag
  }

  data.frame(time = out_time - min(out_time), hz = out_hz)
}

count_pause_runs <- function(flags) {
  flags <- as.logical(flags)
  if (length(flags) == 0) return(0L)
  sum(c(flags[1], diff(as.integer(flags)) == 1L))
}

extract_segment_bundle <- function(wave, start, end, pitch_floor = 75, pitch_ceiling = 500, frame_ms = 40, silence_quantile = 0.15) {
  segment_wave <- extract_segment_wave(wave, start, end)
  samples <- wave_samples(segment_wave)
  sr <- segment_wave@samp.rate
  duration <- length(samples) / sr
  frame_size <- max(128L, as.integer(round(sr * frame_ms / 1000)))
  hop_size <- max(64L, as.integer(round(frame_size / 2)))

  rms_trace <- frame_rms_trace(samples, sr, frame_size, hop_size)
if (nrow(rms_trace) == 0 || all(is.na(rms_trace$rms))) {
  pause_threshold <- NA_real_
  rms_trace$pause_flag <- logical(0)
} else {
  pause_threshold <- stats::quantile(rms_trace$rms, probs = silence_quantile, na.rm = TRUE, names = FALSE)
  rms_trace$pause_flag <- rms_trace$rms <= pause_threshold
}

  # NEW STRATEGY: Use seewave for rock-solid, package-based pitch tracking
  # seewave requires the analysis window length to be an exact even number
  window_len <- as.integer(frame_size + (frame_size %% 2)) 
  
  f0_matrix <- suppressWarnings(seewave::fund(
    segment_wave,
    fmax = pitch_ceiling,
    fmin = pitch_floor,
    wl = window_len,
    ovlp = 50,
    threshold = 1, # 1% amplitude threshold to aggressively catch quiet speech
    plot = FALSE
  ))
  
  # seewave returns a simple, strict numeric matrix (col 1 = time, col 2 = hz).
  # This guarantees Shiny will never choke on complex object data.
  contour <- data.frame(
    time = as.numeric(f0_matrix[, 1]),
    hz = as.numeric(f0_matrix[, 2]) * 1000
  )
  voiced <- contour$hz[is.finite(contour$hz) & !is.na(contour$hz)]

  features <- data.frame(
    rms = round(sqrt(mean(samples^2)), 6),
    peak_amplitude = round(max(abs(samples)), 6),
    intensity_db = round(20 * log10(sqrt(mean(samples^2)) + 1e-8), 3),
    pause_ratio = round(mean(rms_trace$pause_flag), 3),
    pause_count = count_pause_runs(rms_trace$pause_flag),
    voiced_fraction = round(mean(is.finite(contour$hz) & !is.na(contour$hz)), 3),
    pitch_mean_hz = if (length(voiced) > 0) round(mean(voiced), 3) else NA_real_,
    pitch_median_hz = if (length(voiced) > 0) round(stats::median(voiced), 3) else NA_real_,
    pitch_sd_hz = if (length(voiced) > 1) round(stats::sd(voiced), 3) else NA_real_,
    pitch_range_hz = if (length(voiced) > 0) round(max(voiced) - min(voiced), 3) else NA_real_,
    segment_duration_s = round(duration, 3)
  )

  list(
    features = features,
    traces = list(
      contour = contour,
      intensity = rms_trace
    )
  )
}
