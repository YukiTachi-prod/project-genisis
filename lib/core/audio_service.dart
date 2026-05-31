import 'dart:io';
import 'app_config.dart';
import 'paths.dart';

/// Records audio using sox `rec` and plays WAV files.
///
/// Platform differences:
///   Linux  — playback via `aplay`; recording through PipeWire PulseAudio bridge.
///   macOS  — playback via `afplay` (built-in); `rec` routes through CoreAudio.
class AudioService {
  final AppConfig config;
  Process? _recordProcess;

  AudioService(this.config);

  // On Linux, PipeWire exposes a fixed PulseAudio socket.
  // Passing PULSE_SERVER explicitly ensures subprocesses launched from
  // Flutter (which may not inherit the full session env) can reach it.
  Map<String, String> get _env {
    if (Platform.isLinux) {
      final uid = Process.runSync('id', ['-u']).stdout.toString().trim();
      return {
        ...Platform.environment,
        'PULSE_SERVER': 'unix:/run/user/$uid/pulse/native',
      };
    }
    return Platform.environment; // macOS: no special setup needed
  }

  /// Records for up to [config.recordSeconds] seconds.
  /// Returns the path to the recorded WAV file (caller must delete it).
  Future<String> record() async {
    await Directory(AppPaths.tmp).create(recursive: true);
    final outPath =
        '${AppPaths.tmp}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    _recordProcess = await Process.start(
      'rec',
      [
        '--no-show-progress',
        '-r', '${config.sampleRate}',
        '-c', '${config.channels}',
        '-e', 'signed',
        '-b', '16',
        outPath,
        'trim', '0', '${config.recordSeconds}',
      ],
      environment: _env,
    );

    final exitCode = await _recordProcess!.exitCode;
    _recordProcess = null;

    // 0 = timed out naturally, 130 = SIGINT (stopRecording called), both OK.
    if (exitCode != 0 && exitCode != 130) {
      throw Exception('rec (sox) failed with exit code $exitCode');
    }
    return outPath;
  }

  /// Interrupt an in-progress recording early (push-to-talk release).
  void stopRecording() => _recordProcess?.kill(ProcessSignal.sigint);

  /// Plays a WAV file and waits for completion.
  Future<void> playWav(String wavPath) async {
    late ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('afplay', [wavPath]);
    } else {
      result = await Process.run(
        'aplay',
        [
          '-q',
          if (config.audioOutputDevice.isNotEmpty) ...[
            '-D', config.audioOutputDevice
          ],
          wavPath,
        ],
        environment: _env,
      );
    }
    if (result.exitCode != 0) {
      throw Exception('Playback failed: ${result.stderr}');
    }
  }
}
