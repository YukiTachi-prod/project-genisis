import 'dart:io';
import 'app_config.dart';
import 'paths.dart';

/// Text-to-Speech via Piper subprocess.
/// Piper reads text from stdin and writes a WAV to --output_file.
class TtsService {
  final AppConfig config;
  TtsService(this.config);

  Future<String> synthesize(String text) async {
    await Directory(AppPaths.tmp).create(recursive: true);
    final outPath = '${AppPaths.tmp}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';

    final voiceName = config.ttsVoice;
    final modelPath = '${AppPaths.piperVoiceDir}/$voiceName.onnx';

    final process = await Process.start(
      AppPaths.piperBin,
      [
        '--model',       modelPath,
        '--output_file', outPath,
      ],
      // Piper needs its bundled shared libraries in LD_LIBRARY_PATH (Linux)
      // or DYLD_LIBRARY_PATH (macOS).
      environment: {
        ...Platform.environment,
        if (Platform.isLinux)
          'LD_LIBRARY_PATH':
              '${AppPaths.piperDir}:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
        if (Platform.isMacOS)
          'DYLD_LIBRARY_PATH':
              '${AppPaths.piperDir}:${Platform.environment['DYLD_LIBRARY_PATH'] ?? ''}',
      },
    );

    process.stdin.write(_sanitize(text));
    await process.stdin.close();

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      final err =
          await process.stderr.transform(const SystemEncoding().decoder).join();
      throw Exception('piper failed ($exitCode): $err');
    }

    return outPath;
  }

  /// Strips symbols so Piper only speaks words and numbers.
  /// Keeps: letters, digits, spaces, apostrophes (contractions),
  /// hyphens between word characters, and sentence-pause punctuation
  /// (, . ! ?) converted to commas/periods so Piper still pauses naturally.
  static String _sanitize(String text) {
    // Collapse markdown/code fences and bullet markers
    var s = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');

    // Replace sentence-ending punctuation with a period (pause)
    s = s.replaceAll(RegExp(r'[!?]+'), '.');

    // Replace clause-separating punctuation with a comma (short pause)
    s = s.replaceAll(RegExp(r'[;:]+'), ',');

    // Drop all remaining symbols except letters, digits, space,
    // apostrophe, hyphen between word chars, comma, period.
    s = s.replaceAllMapped(RegExp(r"[^\w\s'.,-]"), (_) => '');

    // Hyphens only make sense between word characters; strip bare ones
    s = s.replaceAll(RegExp(r'(?<!\w)-|-(?!\w)'), ' ');

    // Collapse runs of punctuation/spaces
    s = s.replaceAll(RegExp(r'[,\.]{2,}'), '.');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }
}
