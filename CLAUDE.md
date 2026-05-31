# Home AI — Claude Code guide

## What this project is

A Flutter desktop app (Linux-primary) that implements a voice-first home assistant:
**mic → Whisper STT → Ollama LLM → Piper TTS → speaker**
Text input is also supported. All inference is local (no cloud calls).

## Architecture

```
lib/
  core/
    app_config.dart       # Loads config.yaml (user file or bundled); singleton
    paths.dart            # All ~/.home_ai/* paths in one place
    audio_service.dart    # arecord/aplay subprocess wrappers
    stt_service.dart      # Calls whisper-cli subprocess; sets LD_LIBRARY_PATH
    llm_service.dart      # Ollama /api/chat (non-streaming); warmUp() primes KV cache
    tts_service.dart      # Piper TTS subprocess; _sanitize() strips non-speech symbols
    setup/
      setup_service.dart  # Installer: downloads/builds whisper, piper, ollama model
      setup_event.dart    # Stream events emitted during setup
  models/
    chat_message.dart
  providers/
    chat_provider.dart    # ChangeNotifier; owns the voice/text pipeline & AiState
  ui/
    screens/
      glow_screen.dart    # Animated intro screen (GlowScreen → HomeScreen on complete)
      home_screen.dart    # Main chat UI + personality dialog
    widgets/
      status_bar.dart     # Dot indicator for AiState
config/
  config.yaml             # Bundled defaults (never edited at runtime)
```

## Startup flow

`main.dart` → `HomeAiApp` always shows `GlowScreen` first, then fades to `HomeScreen`
after `onComplete` fires. There is no separate setup screen — setup runs inside
GlowScreen's left terminal panel.

### GlowScreen phases

1. **Idle**: dark background with warping grid, centred "G" circle.
2. **Ripple**: pressing G fires a ripple animation (750 ms).
3. **Phase 1** (3 s): 4 glowing orbs orbit the centre; both terminals slide in from
   screen edges. Right terminal runs LLM warm-up (`warmUpForIntro`). Left terminal
   streams `SetupService().run()` events.
4. **Phase 2**: orbiting continues until both tasks complete.
5. **Phase 3**: orbs animate to a centred square, edges appear, then expand to screen
   corners. `_ForegroundPainter` draws the fill + edges only after orbs settle
   (`showLines = true`); positions are sorted by angle from centroid so the polygon
   is always convex.
6. Fade to `HomeScreen`.

## Runtime data location

Everything lives under `~/.home_ai/`:
- `whisper/whisper-cli` — STT binary
- `whisper/*.so*` — whisper + ggml shared libraries (must be co-located with binary)
- `whisper/models/ggml-base.en.bin` — Whisper model
- `piper/piper` — TTS binary
- `piper/voices/` — Piper voice files
- `config.yaml` — user-edited config (overrides bundled defaults)
- `tmp/` — transient wav/tts files (auto-deleted)

## Key constraints

### whisper-cli shared libraries
The binary is dynamically linked against `libwhisper.so.1`, `libggml.so.0`,
`libggml-cpu.so.0`, and `libggml-base.so.0`. These `.so` files must be in
`~/.home_ai/whisper/`. `SttService` sets `LD_LIBRARY_PATH` to that directory
before spawning the subprocess. If you rebuild whisper.cpp you must also copy
the new `.so` files there (setup_service._copySharedLibs handles this on
fresh installs).

### AppConfig singleton
`AppConfig.load()` caches the instance. `AppConfig.saveSystemPrompt()` mutates
it in-place and writes `~/.home_ai/config.yaml`. If you add new config fields,
update `_buildYaml()` so saves don't lose them.

### LLM conversation history
`LlmService._history` holds the full conversation including the system message
at index 0. `updateSystemPrompt()` replaces it and clears history.
`clearHistory()` removes everything except the system message.

### LLM warm-up
`LlmService.warmUp()` sends the system prompt + a single "." with `num_predict: 1`
to prime Ollama's KV cache. Called by `ChatProvider.warmUpForIntro()` (silent,
no AiState change) during GlowScreen loading, and by `_primePersonality()` after
a personality update.

### TTS symbol sanitisation
`TtsService._sanitize()` is called before every Piper invocation. It strips markdown
fences, converts `!?` → `.` and `;:` → `,`, drops all non-word/non-number symbols,
and collapses whitespace — so only words and numbers are spoken aloud.

### AiState
`AiState` enum: `idle | priming | recording | transcribing | thinking | speaking`.
`priming` is set during `_primePersonality()` (post personality-update) and shows
a blocking overlay in HomeScreen. It is NOT set during the GlowScreen warm-up.

## Building & running

```bash
flutter run -d linux          # dev run
flutter build linux           # release build
```

On first run `SetupService` downloads/builds all dependencies; progress is streamed
to GlowScreen's left terminal. Subsequent runs detect completion and finish quickly.

## Config file format

`~/.home_ai/config.yaml` (or bundled `config/config.yaml` as fallback):

```yaml
stt:
  language: en
  record_seconds: 5
llm:
  base_url: http://localhost:11434
  model: llama3.2:3b
  system_prompt: |
    You are Aria, a friendly home assistant.
  max_tokens: 256
  temperature: 0.7
audio:
  input_device: ""
  output_device: ""
  sample_rate: 16000
  channels: 1
```

The AI personality (system_prompt) can be changed at runtime via the
psychology icon in the app bar.
