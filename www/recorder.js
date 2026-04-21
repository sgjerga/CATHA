
(function () {
  let audioContext = null;
  let mediaStream = null;
  let sourceNode = null;
  let processorNode = null;
  let recordedChunks = [];
  let isRecording = false;

  function updateBadge(text, cls) {
    const badge = document.getElementById("recording_badge");
    if (!badge) return;
    badge.textContent = text;
    badge.className = "status-badge " + cls;
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
      view.setInt16(index, sample < 0 ? sample * 0x8000 : sample * 0x7FFF, true);
      index += 2;
    }

    return new Blob([view], { type: "audio/wav" });
  }

  async function startRecording() {
    if (isRecording) return;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      updateBadge("Microphone recording not supported in this browser", "error");
      return;
    }

    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
      sourceNode = audioContext.createMediaStreamSource(mediaStream);
      processorNode = audioContext.createScriptProcessor(4096, 1, 1);
      recordedChunks = [];

      processorNode.onaudioprocess = function (event) {
        if (!isRecording) return;
        const input = event.inputBuffer.getChannelData(0);
        recordedChunks.push(new Float32Array(input));
      };

      sourceNode.connect(processorNode);
      processorNode.connect(audioContext.destination);
      isRecording = true;
      updateBadge("Recording from browser microphone…", "recording");
      if (window.Shiny) {
        window.Shiny.setInputValue("recording_state", { state: "recording", t: Date.now() }, { priority: "event" });
      }
    } catch (err) {
      console.error(err);
      updateBadge("Microphone permission denied or unavailable", "error");
    }
  }

  async function stopRecording() {
    if (!isRecording) return;
    isRecording = false;

    if (processorNode) {
      processorNode.disconnect();
      processorNode.onaudioprocess = null;
    }
    if (sourceNode) sourceNode.disconnect();
    if (mediaStream) {
      mediaStream.getTracks().forEach(function (track) { track.stop(); });
    }

    const totalLength = recordedChunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const merged = mergeBuffers(recordedChunks, totalLength);
    const wavBlob = encodeWav(merged, audioContext.sampleRate);

    if (audioContext) {
      await audioContext.close();
    }

    const reader = new FileReader();
    reader.onloadend = function () {
      const base64 = reader.result.split(",")[1];
      if (window.Shiny) {
        window.Shiny.setInputValue(
          "recorded_audio",
          {
            name: "catha_recording.wav",
            mime: "audio/wav",
            data: base64,
            created: Date.now()
          },
          { priority: "event" }
        );
      }
      updateBadge("Recording captured and sent to CATHA", "ready");
    };
    reader.readAsDataURL(wavBlob);
  }

  if (window.Shiny) {
    window.Shiny.addCustomMessageHandler("catha-start-recording", function () {
      startRecording();
    });
    window.Shiny.addCustomMessageHandler("catha-stop-recording", function () {
      stopRecording();
    });
  }
})();
