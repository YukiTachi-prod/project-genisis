import 'dart:io';

/// All canonical paths for Home AI live under ~/.home_ai/
/// Works identically on Linux and macOS.
class AppPaths {
  AppPaths._();

  static final String home = Platform.environment['HOME'] ?? '/tmp';
  static final String base = '$home/.home_ai';

  // ── Whisper ──────────────────────────────────────────────────────────────
  static String get whisperDir      => '$base/whisper';
  static String get whisperBin      => '$whisperDir/whisper-cli';
  static String get whisperModelDir => '$whisperDir/models';
  static String get whisperModel    => '$whisperModelDir/ggml-base.en.bin';
  /// Temporary clone dir used during the build; deleted after install.
  static String get whisperSrcDir   => '$base/whisper-src';

  // ── Piper ─────────────────────────────────────────────────────────────────
  static String get piperDir       => '$base/piper';
  static String get piperBin       => '$piperDir/piper';
  static String get piperVoiceDir  => '$piperDir/voices';
  static String get piperVoiceOnnx => '$piperVoiceDir/en_US-lessac-medium.onnx';
  static String get piperVoiceJson => '$piperVoiceDir/en_US-lessac-medium.onnx.json';

  // ── Runtime temp ──────────────────────────────────────────────────────────
  static String get tmp => '$base/tmp';

  // ── User-editable config (overrides bundled defaults) ─────────────────────
  static String get userConfig => '$base/config.yaml';
}
