# 🏠 Home AI

A fully **local** voice assistant built with Flutter (Linux desktop).

| Layer | Tool | Model |
|-------|------|-------|
| 🎤 Speech-to-Text | whisper.cpp (`whisper-cli`) | `ggml-base.en` |
| 🧠 Language Model | Ollama | `llama3.2:3b` |
| 🔊 Text-to-Speech | Piper | `en_US-lessac-medium` |

No cloud. No API keys. Everything runs on your machine.

---

## Project layout

```
home_ai/
├── config/
│   └── config.yaml           ← all paths & settings (edit this)
├── lib/
│   ├── main.dart
│   ├── app.dart               ← theme + MaterialApp
│   ├── core/
│   │   ├── app_config.dart    ← YAML config loader
│   │   ├── audio_service.dart ← arecord / aplay wrappers
│   │   ├── stt_service.dart   ← whisper-cli subprocess
│   │   ├── llm_service.dart   ← Ollama REST client
│   │   └── tts_service.dart   ← Piper subprocess
│   ├── models/
│   │   └── chat_message.dart
│   ├── providers/
│   │   └── chat_provider.dart ← ChangeNotifier orchestrator
│   └── ui/
│       ├── screens/home_screen.dart
│       └── widgets/
│           ├── message_bubble.dart
│           └── status_bar.dart
└── scripts/
    └── test_pipeline.sh       ← standalone pipeline smoke test
```

---

## Quick start

### 1. Smoke-test the pipeline (no Flutter needed)

```bash
bash scripts/test_pipeline.sh
```

Say something after "Recording…" — you should hear Aria reply.

### 2. Run the Flutter app

```bash
flutter pub get
flutter run -d linux
```

### 3. Using the app

| Action | How |
|--------|-----|
| **Voice input** | Hold the 🎤 button, speak, release early or wait for timeout |
| **Text input** | Type in the text field and press Enter or ➤ |
| **Mute TTS** | Click 🔊 in the toolbar |
| **Clear history** | Click 🗑️ in the toolbar |

---

## Configuration (`config/config.yaml`)

All binary paths, model paths, Ollama settings, and audio device overrides live
in `config/config.yaml`. Change `record_seconds`, swap models, or point to a
different Ollama model without touching any Dart code.

### Choosing a whisper model

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| `ggml-tiny.en.bin`  | ~39 MB | fastest | lower |
| `ggml-base.en.bin`  | ~74 MB | fast | good ← **default** |
| `ggml-small.en.bin` | ~244 MB | moderate | better |
| `ggml-medium.en.bin`| ~769 MB | slow | best offline |

Download extras:
```bash
cd ~/whisper.cpp && bash models/download-ggml-model.sh small.en
```

### Swapping the LLM

```bash
ollama pull mistral        # or phi3, gemma2, etc.
# then update config/config.yaml → llm.model: mistral
```

---

## Requirements

- Flutter 3.41+ with Linux desktop enabled (`flutter config --enable-linux-desktop`)
- whisper.cpp built at `~/whisper.cpp/build/bin/whisper-cli`
- Piper binary + onnx voice model
- Ollama running (`ollama serve`)
- `arecord` / `aplay` (ALSA utils — standard on Fedora)
