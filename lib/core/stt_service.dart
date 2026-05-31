import 'dart:io';
import 'app_config.dart';
import 'paths.dart';

/// Speech-to-Text via whisper.cpp (whisper-cli subprocess).
class SttService {
  final AppConfig config;
  SttService(this.config);

  Future<String> transcribe(String wavPath) async {
    final result = await Process.run(
      AppPaths.whisperBin,
      [
        '--model',    AppPaths.whisperModel,
        '--language', config.sttLanguage,
        '--no-timestamps',
        '--file',     wavPath,
      ],
      environment: {
        ...Platform.environment,
        'LD_LIBRARY_PATH': AppPaths.whisperDir,
      },
    );

    if (result.exitCode != 0) {
      throw Exception(
          'whisper-cli failed (${result.exitCode}): ${result.stderr}');
    }

    return (result.stdout as String).trim();
  }
}
