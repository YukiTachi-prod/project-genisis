import 'dart:convert';
import 'dart:io';
import 'app_config.dart';
import 'paths.dart';

/// Speech-to-Text via whisper.cpp (whisper-cli subprocess).
class SttService {
  final AppConfig config;
  final List<Process> _activeProcesses = [];

  SttService(this.config);

  Future<String> transcribe(String wavPath) async {
    final process = await Process.start(
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
    _activeProcesses.add(process);

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();

    process.stdout.transform(utf8.decoder).listen((data) => stdoutBuf.write(data));
    process.stderr.transform(utf8.decoder).listen((data) => stderrBuf.write(data));

    try {
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw Exception(
            'whisper-cli failed ($exitCode): $stderrBuf');
      }
      return stdoutBuf.toString().trim();
    } finally {
      _activeProcesses.remove(process);
    }
  }

  void dispose() {
    for (final proc in _activeProcesses) {
      try {
        proc.kill();
      } catch (_) {}
    }
    _activeProcesses.clear();
  }
}
