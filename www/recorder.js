(function () {
  "use strict";

  let audioContext = null;
  let mediaStream = null;
  let sourceNode = null;
  let processorNode = null;
  let silentGainNode = null;
  let recordedChunks = [];
  let isStarting = false;
  let isRecording = false;
  let previewObjectUrl = null;
  let directButtonHandlersRegistered = false;
  let shinyHandlersRegistered = false;
  let fallbackTimer = null;
  let serverConfirmedRecordingId = null;

  function logRecorder(message, payload) {
    if (payload !== undefined) {
      console.log("[CATHA recorder] " + message, payload);
    } else {
      console.log("[CATHA recorder] " + message);
    }
  }

  function updateBadge(text, cls) {
    const badge = document.getElementById("recording_badge");
    if (!badge) return;
    badge.textContent = text;
    badge.className = "status-badge " + (cls || "idle");
  }

  function setButtonState(recordingOrStarting) {
    const startButton = document.getElementById("start_recording");
    const stopButton = document.getElementById("stop_recording");
    if (startButton) startButton.disabled = !!recordingOrStarting;
    if (stopButton) stopButton.disabled = !isRecording;
  }

  function shinyInputReady() {
    return !!(
      window.Shiny &&
      (typeof window.Shiny.setInputValue === "function" || typeof window.Shiny.onInputChange === "function")
    );
  }

  function sendShinyInput(name, value) {
    if (!shinyInputReady()) return false;
    if (typeof window.Shiny.setInputValue === "function") {
      window.Shiny.setInputValue(name, value, { priority: "event" });
    } else {
      window.Shiny.onInputChange(name, value);
    }
    return true;
  }

  function reportState(state, message, extra) {
    sendShinyInput("recording_state", Object.assign({
      state: state,
      message: message || "",
      t: Date.now(),
      nonce: Math.random().toString(36).slice(2)
    }, extra || {}));
  }

  function mergeBuffers(buffers, totalLength) {
    const result = new Float32Array(totalLength);
    let offset = 0;
    for (let i = 0; i < buffers.length; i += 1) {
      result.set(buffers[i], offset);
      offset += buffers[i].length;
    }
    return result;
  }

  function writeString(view, offset, string) {
    for (let i = 0; i < string.length; i += 1) {
      view.setUint8(offset + i, string.charCodeAt(i));
    }
  }

  function encodeWav(samples, sampleRate) {
    const buffer = new ArrayBuffer(44 + samples.length * 2);
    const view = new DataView(buffer);

    writeString(view, 0, "RIFF");
    view.setUint32(4, 36 + samples.length * 2, true);
    writeString(view, 8, "WAVE");
    writeString(view, 12, "fmt ");
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, 1, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * 2, true);
    view.setUint16(32, 2, true);
    view.setUint16(34, 16, true);
    writeString(view, 36, "data");
    view.setUint32(40, samples.length * 2, true);

    let index = 44;
    for (let i = 0; i < samples.length; i += 1) {
      const sample = Math.max(-1, Math.min(1, samples[i]));
      view.setInt16(index, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
      index += 2;
    }

    return new Blob([view], { type: "audio/wav" });
  }

  function cleanupAudioGraph() {
    if (processorNode) {
      try { processorNode.disconnect(); } catch (e) { /* no-op */ }
      processorNode.onaudioprocess = null;
      processorNode = null;
    }
    if (sourceNode) {
      try { sourceNode.disconnect(); } catch (e) { /* no-op */ }
      sourceNode = null;
    }
    if (silentGainNode) {
      try { silentGainNode.disconnect(); } catch (e) { /* no-op */ }
      silentGainNode = null;
    }
    if (mediaStream) {
      mediaStream.getTracks().forEach(function (track) {
        try { track.stop(); } catch (e) { /* no-op */ }
      });
      mediaStream = null;
    }
  }

  function browserSupportsMicrophoneCapture() {
    return !!(
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === "function" &&
      (window.AudioContext || window.webkitAudioContext)
    );
  }

  function microphoneErrorMessage(err) {
    const name = err && err.name ? err.name : "";
    const detail = err && err.message ? err.message : "";

    if (name === "NotAllowedError" || name === "PermissionDeniedError") {
      return "Microphone permission is blocked for this page. Click the browser lock/settings icon near the address bar, allow microphone access for 127.0.0.1/localhost, then reload the app.";
    }
    if (name === "NotFoundError" || name === "DevicesNotFoundError") {
      return "No microphone was found. Please connect/select a microphone and try again.";
    }
    if (name === "NotReadableError" || name === "TrackStartError") {
      return "The microphone is already in use by another app or browser tab. Close the other app/tab and try again.";
    }
    if (name === "OverconstrainedError" || name === "ConstraintNotSatisfiedError") {
      return "The browser could not open the microphone with the requested audio settings.";
    }
    if (name === "SecurityError") {
      return "Microphone recording requires localhost, 127.0.0.1, or HTTPS.";
    }
    return detail || "The browser could not start microphone recording.";
  }

  function showBrowserPreview(blob) {
    const shell = document.getElementById("recording_preview_shell");
    const audio = document.getElementById("recording_preview_audio");
    if (!shell || !audio) return;

    if (previewObjectUrl) {
      URL.revokeObjectURL(previewObjectUrl);
      previewObjectUrl = null;
    }

    previewObjectUrl = URL.createObjectURL(blob);
    audio.src = previewObjectUrl;
    shell.style.display = "block";
  }

  function hideBrowserPreview() {
    const shell = document.getElementById("recording_preview_shell");
    const audio = document.getElementById("recording_preview_audio");
    if (audio) {
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
    }
    if (previewObjectUrl) {
      URL.revokeObjectURL(previewObjectUrl);
      previewObjectUrl = null;
    }
    if (shell) shell.style.display = "none";
  }

  function readBlobAsBase64(blob) {
    return new Promise(function (resolve, reject) {
      const reader = new FileReader();
      reader.onerror = function () {
        reject(new Error("The browser could not prepare the recording for transfer to Shiny."));
      };
      reader.onloadend = function () {
        const result = String(reader.result || "");
        resolve(result.indexOf(",") >= 0 ? result.split(",")[1] : result);
      };
      reader.readAsDataURL(blob);
    });
  }

  function sendFallbackChunks(payload) {
    if (serverConfirmedRecordingId === payload.id) return;
    const chunkSize = 24000; // base64 characters; deliberately small for Shiny inputs
    const total = Math.ceil(payload.data.length / chunkSize);
    updateBadge("Direct transfer not confirmed. Sending fallback chunks…", "idle");
    logRecorder("sending fallback chunks", { id: payload.id, total: total });

    for (let i = 0; i < total; i += 1) {
      window.setTimeout(function () {
        if (serverConfirmedRecordingId === payload.id) return;
        const chunkPayload = {
          id: payload.id,
          index: i + 1,
          total: total,
          data: payload.data.slice(i * chunkSize, (i + 1) * chunkSize),
          metadata: {
            id: payload.id,
            name: payload.name,
            mime: payload.mime,
            sampleRate: payload.sampleRate,
            size: payload.size,
            created: payload.created
          },
          nonce: Date.now() + "_" + Math.random().toString(36).slice(2)
        };
        sendShinyInput("recorded_audio_chunk", chunkPayload);
        if ((i + 1) === total) {
          updateBadge("Recording sent by fallback bridge. Loading waveform…", "idle");
        }
      }, i * 80);
    }
  }

  function sendRecordingToShiny(base64, metadata) {
    const payload = Object.assign({}, metadata, {
      id: metadata.id || (Date.now() + "_" + Math.random().toString(36).slice(2)),
      data: base64,
      transport: "recorded_audio",
      nonce: Date.now() + "_" + Math.random().toString(36).slice(2)
    });

    serverConfirmedRecordingId = null;
    logRecorder("sending recording to Shiny input$recorded_audio", {
      id: payload.id,
      bytes: payload.size,
      payloadChars: base64.length
    });

    if (!sendShinyInput("recorded_audio", payload)) {
      throw new Error("Recording was captured, but Shiny is not connected. Please reload the app and try again.");
    }

    updateBadge("Recording sent. Loading waveform…", "idle");
    reportState("sent", "Recording sent to Shiny input$recorded_audio.", { id: payload.id, bytes: payload.size });

    if (fallbackTimer) window.clearTimeout(fallbackTimer);
    fallbackTimer = window.setTimeout(function () {
      if (serverConfirmedRecordingId !== payload.id) {
        sendFallbackChunks(payload);
      }
    }, 8000);
  }

  async function startRecording() {
    if (isStarting || isRecording) return;

    if (!window.isSecureContext && window.location.hostname !== "localhost" && window.location.hostname !== "127.0.0.1") {
      const message = "Microphone recording requires localhost, 127.0.0.1, or HTTPS.";
      updateBadge(message, "error");
      reportState("error", message);
      return;
    }

    if (!browserSupportsMicrophoneCapture()) {
      const message = "Microphone recording is not supported in this browser.";
      updateBadge(message, "error");
      reportState("error", message);
      return;
    }

    isStarting = true;
    setButtonState(true);
    hideBrowserPreview();
    updateBadge("Requesting microphone permission…", "idle");
    reportState("starting", "Requesting microphone permission.");

    try {
      let stream;
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: false,
            noiseSuppression: false,
            autoGainControl: false
          }
        });
      } catch (firstErr) {
        if (firstErr && (firstErr.name === "OverconstrainedError" || firstErr.name === "ConstraintNotSatisfiedError")) {
          stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        } else {
          throw firstErr;
        }
      }

      mediaStream = stream;
      const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
      audioContext = new AudioContextCtor();
      await audioContext.resume();

      sourceNode = audioContext.createMediaStreamSource(mediaStream);
      processorNode = audioContext.createScriptProcessor(4096, 1, 1);
      silentGainNode = audioContext.createGain();
      silentGainNode.gain.value = 0;
      recordedChunks = [];

      processorNode.onaudioprocess = function (event) {
        if (!isRecording) return;
        const input = event.inputBuffer.getChannelData(0);
        recordedChunks.push(new Float32Array(input));
      };

      sourceNode.connect(processorNode);
      processorNode.connect(silentGainNode);
      silentGainNode.connect(audioContext.destination);

      isRecording = true;
      isStarting = false;
      setButtonState(false);
      updateBadge("Recording from browser microphone…", "recording");
      reportState("recording", "Recording in browser.");
    } catch (err) {
      console.error(err);
      cleanupAudioGraph();
      if (audioContext) {
        try { await audioContext.close(); } catch (e) { /* no-op */ }
        audioContext = null;
      }
      isStarting = false;
      isRecording = false;
      setButtonState(false);
      const message = microphoneErrorMessage(err);
      updateBadge(message, "error");
      reportState("error", message);
    }
  }

  async function stopRecording() {
    if (isStarting && !isRecording) {
      updateBadge("Microphone is still starting. Please wait a moment, then press Stop recording.", "idle");
      return;
    }
    if (!isRecording) return;

    isRecording = false;
    setButtonState(false);
    updateBadge("Preparing recording…", "idle");
    reportState("encoding", "Encoding recording in browser.");

    const sampleRate = audioContext ? audioContext.sampleRate : 44100;
    cleanupAudioGraph();

    if (audioContext) {
      try { await audioContext.close(); } catch (e) { /* no-op */ }
      audioContext = null;
    }

    const totalLength = recordedChunks.reduce(function (sum, chunk) {
      return sum + chunk.length;
    }, 0);

    if (totalLength === 0) {
      const message = "No audio samples were captured. Please try recording again.";
      recordedChunks = [];
      updateBadge(message, "error");
      reportState("error", message);
      return;
    }

    const merged = mergeBuffers(recordedChunks, totalLength);
    recordedChunks = [];
    const wavBlob = encodeWav(merged, sampleRate);
    showBrowserPreview(wavBlob);
    updateBadge("Recording captured. Sending to CATHA…", "idle");

    try {
      const timestamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 17);
      const id = "rec_" + timestamp + "_" + Math.random().toString(36).slice(2);
      const metadata = {
        id: id,
        name: "catha_recording_" + timestamp + ".wav",
        mime: "audio/wav",
        sampleRate: sampleRate,
        size: wavBlob.size,
        created: Date.now()
      };
      const base64 = await readBlobAsBase64(wavBlob);
      sendRecordingToShiny(base64, metadata);
    } catch (err) {
      console.error(err);
      const message = err && err.message ? err.message : "Recording could not be sent to CATHA.";
      updateBadge(message, "error");
      reportState("error", message);
    }
  }

  function registerShinyHandlers() {
    if (shinyHandlersRegistered) return true;
    if (!(window.Shiny && typeof window.Shiny.addCustomMessageHandler === "function")) return false;

    window.Shiny.addCustomMessageHandler("catha-recording-loaded", function (payload) {
      logRecorder("recording loaded by server", payload);
      if (payload && payload.id) serverConfirmedRecordingId = payload.id;
      if (fallbackTimer) {
        window.clearTimeout(fallbackTimer);
        fallbackTimer = null;
      }
      const message = payload && payload.message ? payload.message : "Recording loaded and ready for segmentation/features.";
      updateBadge(message, "ready");
      reportState("ready", message, { id: payload && payload.id ? payload.id : null });
    });

    window.Shiny.addCustomMessageHandler("catha-recording-error", function (payload) {
      logRecorder("recording error from server", payload);
      if (fallbackTimer) {
        window.clearTimeout(fallbackTimer);
        fallbackTimer = null;
      }
      const message = payload && payload.message ? payload.message : "Recording could not be loaded by CATHA.";
      updateBadge(message, "error");
      reportState("error", message);
    });

    window.Shiny.addCustomMessageHandler("catha-hide-recording-preview", function () {
      hideBrowserPreview();
      updateBadge("Recorder idle", "idle");
    });

    shinyHandlersRegistered = true;
    logRecorder("Shiny custom message handlers registered");
    sendShinyInput("catha_recorder_client_ready", {
      ready: true,
      t: Date.now(),
      nonce: Math.random().toString(36).slice(2)
    });
    return true;
  }

  function attachDirectButtonHandlers() {
    if (directButtonHandlersRegistered) return;
    document.addEventListener("click", function (event) {
      const startButton = event.target.closest ? event.target.closest("#start_recording") : null;
      const stopButton = event.target.closest ? event.target.closest("#stop_recording") : null;
      if (startButton) startRecording();
      if (stopButton) stopRecording();
    });
    directButtonHandlersRegistered = true;
  }

  function initializeRecorder() {
    attachDirectButtonHandlers();
    registerShinyHandlers();
    document.addEventListener("shiny:connected", registerShinyHandlers);
    document.addEventListener("shiny:sessioninitialized", registerShinyHandlers);
    document.addEventListener("shiny:bound", registerShinyHandlers);
    if (window.jQuery) {
      window.jQuery(document).on("shiny:connected", registerShinyHandlers);
      window.jQuery(document).on("shiny:sessioninitialized", registerShinyHandlers);
      window.jQuery(document).on("shiny:bound", registerShinyHandlers);
    }
    window.setTimeout(registerShinyHandlers, 250);
    window.setTimeout(registerShinyHandlers, 1000);
    isStarting = false;
    isRecording = false;
    setButtonState(false);
    updateBadge("Recorder idle", "idle");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initializeRecorder);
  } else {
    initializeRecorder();
  }
})();
