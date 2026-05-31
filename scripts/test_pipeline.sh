#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Home AI — Pipeline smoke test
#  Tests each component independently: STT, LLM, TTS
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

WHISPER_BIN="/home/yuki/whisper.cpp/build/bin/whisper-cli"
WHISPER_MODEL="/home/yuki/whisper.cpp/models/ggml-base.en.bin"
PIPER_BIN="/home/yuki/piper-tts/piper/piper"
PIPER_MODEL="/home/yuki/en_US-lessac-medium.onnx"
OLLAMA_URL="http://localhost:11434"
OLLAMA_MODEL="llama3.2:3b"
TMP_DIR="/tmp/home_ai_test"

mkdir -p "$TMP_DIR"

green()  { echo -e "\e[32m✓ $*\e[0m"; }
red()    { echo -e "\e[31m✗ $*\e[0m"; exit 1; }
yellow() { echo -e "\e[33m» $*\e[0m"; }

echo ""
echo "═══════════════════════════════════════"
echo "  Home AI — Pipeline Smoke Test"
echo "═══════════════════════════════════════"
echo ""

# ── 1. Record 3 s of audio ──────────────────────────────────────────────────
yellow "Recording 3 seconds of audio (say something!)…"
WAV="$TMP_DIR/test_rec.wav"
# Use sox `rec` — routes through PipeWire's PulseAudio bridge (more reliable
# than raw arecord when launched outside a full login-shell environment).
UID_VAL=$(id -u)
export PULSE_SERVER="unix:/run/user/${UID_VAL}/pulse/native"
rec --no-show-progress -r 16000 -c 1 -e signed -b 16 "$WAV" trim 0 3 \
  && green "Recorded → $WAV" || red "rec (sox) failed"

# ── 2. Whisper STT ──────────────────────────────────────────────────────────
yellow "Running whisper-cli STT…"
TRANSCRIPT=$("$WHISPER_BIN" \
  --model "$WHISPER_MODEL" \
  --language en \
  --no-timestamps \
  --file "$WAV" 2>/dev/null | tr -s ' ' | xargs)
echo "  Transcript: \"$TRANSCRIPT\""
green "STT complete"

# ── 3. Ollama LLM ───────────────────────────────────────────────────────────
yellow "Calling Ollama ($OLLAMA_MODEL)…"
PROMPT="${TRANSCRIPT:-Hello, are you working?}"
REPLY=$(curl -sf "$OLLAMA_URL/api/chat" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$OLLAMA_MODEL\",\"stream\":false,\"messages\":[
    {\"role\":\"system\",\"content\":\"You are Aria, a concise home assistant. Reply in one sentence.\"},
    {\"role\":\"user\",\"content\":\"$PROMPT\"}
  ]}" | python3 -c "import sys,json; print(json.load(sys.stdin)['message']['content'])")
echo "  Reply: \"$REPLY\""
green "LLM complete"

# ── 4. Piper TTS ────────────────────────────────────────────────────────────
yellow "Synthesising speech with Piper…"
TTS_WAV="$TMP_DIR/test_tts.wav"
export LD_LIBRARY_PATH="/home/yuki/piper-tts/piper:${LD_LIBRARY_PATH:-}"
echo "$REPLY" | "$PIPER_BIN" \
  --model "$PIPER_MODEL" \
  --output_file "$TTS_WAV" 2>/dev/null
green "TTS complete → $TTS_WAV"

# ── 5. Playback ─────────────────────────────────────────────────────────────
yellow "Playing TTS output…"
aplay -q "$TTS_WAV" && green "Playback complete"

echo ""
echo "═══════════════════════════════════════"
echo "  All checks passed! 🎉"
echo "═══════════════════════════════════════"
echo ""
rm -rf "$TMP_DIR"
