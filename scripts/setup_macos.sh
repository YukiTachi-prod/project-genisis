#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Home AI — macOS pre-flight check
#  Run this once on a new Mac before `flutter run -d macos`
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

green()  { echo -e "\e[32m✓ $*\e[0m"; }
yellow() { echo -e "\e[33m» $*\e[0m"; }
red()    { echo -e "\e[31m✗ $*\e[0m"; }

echo ""
echo "═══════════════════════════════════════"
echo "  Home AI — macOS pre-flight check"
echo "═══════════════════════════════════════"
echo ""

# ── Xcode Command Line Tools ─────────────────────────────────────────────────
yellow "Checking Xcode Command Line Tools…"
if xcode-select -p &>/dev/null; then
  green "Xcode CLT found at $(xcode-select -p)"
else
  red "Xcode Command Line Tools not installed."
  echo "  Run: xcode-select --install"
  exit 1
fi

# ── Homebrew ──────────────────────────────────────────────────────────────────
yellow "Checking Homebrew…"
if ! command -v brew &>/dev/null; then
  red "Homebrew not found."
  echo "  Install from: https://brew.sh"
  exit 1
fi
green "Homebrew $(brew --version | head -1)"

# ── sox (for microphone recording via `rec`) ──────────────────────────────────
yellow "Checking sox…"
if command -v rec &>/dev/null; then
  green "sox already installed"
else
  yellow "Installing sox via Homebrew…"
  brew install sox && green "sox installed"
fi

# ── Ollama ────────────────────────────────────────────────────────────────────
yellow "Checking Ollama…"
if command -v ollama &>/dev/null; then
  green "Ollama found — $(ollama --version 2>/dev/null || echo 'version unknown')"
  yellow "Make sure it's running: ollama serve &"
else
  red "Ollama not installed."
  echo "  Install from: https://ollama.com"
  echo "  Then run:     ollama pull llama3.2:3b"
fi

# ── Flutter ───────────────────────────────────────────────────────────────────
yellow "Checking Flutter…"
if command -v flutter &>/dev/null; then
  flutter --version | head -1
  green "Flutter OK"
  flutter config --enable-macos-desktop &>/dev/null
  green "macOS desktop target enabled"
else
  red "Flutter not found."
  echo "  Install from: https://docs.flutter.dev/get-started/install/macos"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════"
echo "  Pre-flight complete!  Next steps:"
echo ""
echo "  cd home_ai"
echo "  flutter pub get"
echo "  flutter run -d macos        # dev run"
echo "  flutter build macos         # release .app"
echo ""
echo "  The app will auto-download whisper-cli,"
echo "  piper, models, and pull llama3.2:3b on"
echo "  first launch via the setup screen."
echo "═══════════════════════════════════════"
echo ""
