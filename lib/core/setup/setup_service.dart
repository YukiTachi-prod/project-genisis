import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../paths.dart';
import 'setup_event.dart';

// ── Download URLs ────────────────────────────────────────────────────────────

const _whisperModelUrl =
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true';

const _piperBaseUrl =
    'https://github.com/rhasspy/piper/releases/download/2023.11.14-2';

const _piperVoiceBase =
    'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium';

// ─────────────────────────────────────────────────────────────────────────────

class SetupService {
  static final List<Process> _activeProcesses = [];

  static void terminateActiveProcesses() {
    for (final proc in _activeProcesses) {
      try {
        final pid = proc.pid;
        proc.kill();
        if (Platform.isLinux || Platform.isMacOS) {
          Process.runSync('pkill', ['-P', '$pid']);
        } else if (Platform.isWindows) {
          Process.runSync('taskkill', ['/F', '/T', '/PID', '$pid']);
        }
      } catch (_) {}
    }
    _activeProcesses.clear();
  }

  /// Returns true when every required file already exists under ~/.home_ai/
  static bool isComplete() {
    return File(AppPaths.whisperBin).existsSync() &&
        File(AppPaths.whisperModel).existsSync() &&
        File(AppPaths.piperBin).existsSync() &&
        File(AppPaths.piperVoiceOnnx).existsSync() &&
        File(AppPaths.piperVoiceJson).existsSync();
  }

  /// Run full setup; yields [SetupEvent]s as work progresses.
  /// Consume with: `await for (final e in svc.run()) { ... }`
  Stream<SetupEvent> run() async* {
    try {
      await _mkdirs();
      yield* _setupWhisperCli();
      yield* _setupWhisperModel();
      yield* _setupPiper();
      yield* _setupPiperVoice();
      yield* _checkOllama();
      yield SetupEvent.allDone();
    } catch (e, st) {
      yield SetupEvent.stepError('fatal', '$e\n$st');
    }
  }

  // ── Directory init ──────────────────────────────────────────────────────────

  Future<void> _mkdirs() async {
    for (final d in [
      AppPaths.whisperModelDir,
      AppPaths.piperVoiceDir,
      AppPaths.tmp,
    ]) {
      await Directory(d).create(recursive: true);
    }
  }

  // ── whisper-cli ─────────────────────────────────────────────────────────────

  Stream<SetupEvent> _setupWhisperCli() async* {
    const id = 'whisper-cli';
    if (File(AppPaths.whisperBin).existsSync()) {
      yield SetupEvent.stepDone(id);
      return;
    }

    yield SetupEvent.stepStart(id, 'Setting up whisper-cli…');
    yield SetupEvent.stepProgress(id, null);

    // 1. Check PATH
    final whichResult = await Process.run('which', ['whisper-cli']);
    if (whichResult.exitCode == 0) {
      final found = (whichResult.stdout as String).trim();
      yield SetupEvent.log(id, 'Found whisper-cli at $found — linking…');
      await _symlink(found, AppPaths.whisperBin);
      yield SetupEvent.stepDone(id);
      return;
    }

    // 2. Check common known paths
    const knownPaths = [
      '/usr/local/bin/whisper-cli',
      '/usr/bin/whisper-cli',
      '/opt/homebrew/bin/whisper-cli',
    ];
    for (final p in knownPaths) {
      if (File(p).existsSync()) {
        yield SetupEvent.log(id, 'Found whisper-cli at $p — linking…');
        await _symlink(p, AppPaths.whisperBin);
        yield SetupEvent.stepDone(id);
        return;
      }
    }

    // 3. Build from source
    yield SetupEvent.log(id, 'No pre-built binary found — building from source…');
    yield* _buildWhisperCli(id);
    yield SetupEvent.stepDone(id);
  }

  Stream<SetupEvent> _buildWhisperCli(String id) async* {
    final srcDir = AppPaths.whisperSrcDir;

    if (!Directory('$srcDir/.git').existsSync()) {
      yield SetupEvent.log(id, 'Cloning whisper.cpp (shallow)…');
      yield* _run(id, 'git', [
        'clone', '--depth', '1',
        'https://github.com/ggerganov/whisper.cpp.git',
        srcDir,
      ]);
    } else {
      yield SetupEvent.log(id, 'Source already cloned.');
    }

    yield SetupEvent.log(id, 'cmake configure…');
    yield* _run(id, 'cmake', [
      '-B', '$srcDir/build',
      '-S', srcDir,
      '-DCMAKE_BUILD_TYPE=Release',
    ]);

    final cores = Platform.numberOfProcessors;
    yield SetupEvent.log(id, 'Building with $cores cores (this takes a few minutes)…');
    yield* _run(id, 'cmake', [
      '--build', '$srcDir/build',
      '--target', 'whisper-cli',
      '-j', '$cores',
    ]);

    final built = '$srcDir/build/bin/whisper-cli';
    if (!File(built).existsSync()) {
      throw Exception('Build finished but whisper-cli not found at $built');
    }

    await Directory(AppPaths.whisperDir).create(recursive: true);
    await File(built).copy(AppPaths.whisperBin);
    await _chmod(AppPaths.whisperBin);
    yield SetupEvent.log(id, 'Installed → ${AppPaths.whisperBin}');

    // Copy shared libraries so whisper-cli can find them via LD_LIBRARY_PATH.
    yield SetupEvent.log(id, 'Copying shared libraries…');
    await _copySharedLibs('$srcDir/build', AppPaths.whisperDir);

    yield SetupEvent.log(id, 'Cleaning up build sources…');
    await Directory(srcDir).delete(recursive: true);
  }

  /// Copies all .so files from [buildDir]/src and [buildDir]/ggml/src
  /// into [destDir] so the whisper-cli binary can load them at runtime.
  Future<void> _copySharedLibs(String buildDir, String destDir) async {
    final searchDirs = [
      '$buildDir/src',
      '$buildDir/ggml/src',
    ];
    for (final dir in searchDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      await for (final entry in d.list()) {
        if (entry is File && entry.path.contains('.so')) {
          final name = entry.uri.pathSegments.last;
          await entry.copy('$destDir/$name');
        }
      }
    }
  }

  // ── Whisper model ───────────────────────────────────────────────────────────

  Stream<SetupEvent> _setupWhisperModel() async* {
    const id = 'whisper-model';
    if (File(AppPaths.whisperModel).existsSync()) {
      yield SetupEvent.stepDone(id);
      return;
    }

    yield SetupEvent.stepStart(id, 'Getting Whisper model…');
    yield SetupEvent.stepProgress(id, null);

    // Check well-known existing paths before downloading
    const knownModels = [
      '/home/yuki/whisper.cpp/models/ggml-base.en.bin',
      '/opt/homebrew/share/whisper.cpp/models/ggml-base.en.bin',
    ];
    for (final p in knownModels) {
      if (File(p).existsSync()) {
        yield SetupEvent.log(id, 'Found model at $p — copying…');
        await File(p).copy(AppPaths.whisperModel);
        yield SetupEvent.stepDone(id);
        return;
      }
    }

    yield SetupEvent.log(id, 'Downloading ggml-base.en.bin (148 MB)…');
    yield* _downloadFile(id, _whisperModelUrl, AppPaths.whisperModel);
    yield SetupEvent.stepDone(id);
  }

  // ── Piper binary ─────────────────────────────────────────────────────────────

  Stream<SetupEvent> _setupPiper() async* {
    const id = 'piper';
    if (File(AppPaths.piperBin).existsSync()) {
      yield SetupEvent.stepDone(id);
      return;
    }

    yield SetupEvent.stepStart(id, 'Getting Piper TTS…');
    yield SetupEvent.stepProgress(id, null);

    // Check existing install
    const knownPiperPaths = ['/home/yuki/piper-tts/piper/piper'];
    for (final p in knownPiperPaths) {
      if (File(p).existsSync()) {
        yield SetupEvent.log(id, 'Found piper at $p — copying…');
        await _copyDir(File(p).parent.path, AppPaths.piperDir);
        await _chmod(AppPaths.piperBin);
        yield SetupEvent.stepDone(id);
        return;
      }
    }

    final archiveName = _piperArchiveName();
    final url = '$_piperBaseUrl/$archiveName';
    final archivePath = '${AppPaths.tmp}/$archiveName';

    yield SetupEvent.log(id, 'Downloading $archiveName…');
    yield* _downloadFile(id, url, archivePath);

    yield SetupEvent.log(id, 'Extracting…');
    yield* _run(id, 'tar', ['-xzf', archivePath, '-C', AppPaths.base]);

    await _chmod(AppPaths.piperBin);
    await File(archivePath).delete();
    yield SetupEvent.stepDone(id);
  }

  // ── Piper voice ───────────────────────────────────────────────────────────────

  Stream<SetupEvent> _setupPiperVoice() async* {
    const id = 'piper-voice';
    final onnxDone = File(AppPaths.piperVoiceOnnx).existsSync();
    final jsonDone = File(AppPaths.piperVoiceJson).existsSync();
    if (onnxDone && jsonDone) {
      yield SetupEvent.stepDone(id);
      return;
    }

    yield SetupEvent.stepStart(id, 'Getting voice model…');
    yield SetupEvent.stepProgress(id, null);

    // Check existing voice files
    const knownOnnx = '/home/yuki/en_US-lessac-medium.onnx';
    const knownJson = '/home/yuki/en_US-lessac-medium.onnx.json';
    if (File(knownOnnx).existsSync() && File(knownJson).existsSync()) {
      yield SetupEvent.log(id, 'Found voice model at ~/  — copying…');
      await File(knownOnnx).copy(AppPaths.piperVoiceOnnx);
      await File(knownJson).copy(AppPaths.piperVoiceJson);
      yield SetupEvent.stepDone(id);
      return;
    }

    if (!onnxDone) {
      yield SetupEvent.log(id, 'Downloading en_US-lessac-medium.onnx (~63 MB)…');
      yield* _downloadFile(
          id, '$_piperVoiceBase/en_US-lessac-medium.onnx', AppPaths.piperVoiceOnnx);
    }
    if (!jsonDone) {
      yield SetupEvent.log(id, 'Downloading en_US-lessac-medium.onnx.json…');
      yield* _downloadFile(
          id, '$_piperVoiceBase/en_US-lessac-medium.onnx.json', AppPaths.piperVoiceJson);
    }
    yield SetupEvent.stepDone(id);
  }

  // ── Ollama check ──────────────────────────────────────────────────────────────

  Stream<SetupEvent> _checkOllama() async* {
    const id = 'ollama';
    yield SetupEvent.stepStart(id, 'Checking Ollama…');
    yield SetupEvent.stepProgress(id, null);

    final whichOllama = await Process.run('which', ['ollama']);
    if (whichOllama.exitCode != 0) {
      yield SetupEvent.log(
          id, '⚠ Ollama not found — install from https://ollama.com', error: true);
      yield SetupEvent.stepDone(id);
      return;
    }

    try {
      final resp = await http
          .get(Uri.parse('http://localhost:11434/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final models = (body['models'] as List<dynamic>? ?? [])
          .map((m) => (m as Map<String, dynamic>)['name'] as String)
          .toList();

      const target = 'llama3.2:3b';
      if (models.any((m) => m.startsWith(target))) {
        yield SetupEvent.log(id, '✓ $target is ready.');
        yield SetupEvent.stepDone(id);
        return;
      }

      yield SetupEvent.log(id, '$target not found — pulling (may take a while)…');
      yield* _run(id, 'ollama', ['pull', target]);
      yield SetupEvent.stepDone(id);
    } catch (e) {
      yield SetupEvent.log(
          id, '⚠ Ollama not reachable — run: ollama serve', error: true);
      yield SetupEvent.stepDone(id);
    }
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  String _piperArchiveName() {
    if (Platform.isMacOS) {
      final arch = Process.runSync('uname', ['-m']).stdout.toString().trim();
      return arch == 'arm64'
          ? 'piper_macos_aarch64.tar.gz'
          : 'piper_macos_x64.tar.gz';
    }
    return 'piper_linux_x86_64.tar.gz';
  }

  /// Spawn a process, stream stdout/stderr as log events, and emit an
  /// indeterminate [SetupEvent.stepProgress] so the UI shows a running bar.
  Stream<SetupEvent> _run(String stepId, String exe, List<String> args) async* {
    yield SetupEvent.stepProgress(stepId, null); // indeterminate while running

    final proc = await Process.start(exe, args);
    _activeProcesses.add(proc);

    try {
      final combined = StreamController<SetupEvent>();
      var pending = 2;
      void done() {
        if (--pending == 0) combined.close();
      }

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) => combined.add(SetupEvent.log(stepId, l)), onDone: done);
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) => combined.add(SetupEvent.log(stepId, l)), onDone: done);

      yield* combined.stream;

      final code = await proc.exitCode;
      if (code != 0) throw Exception('$exe exited with code $code');
    } finally {
      _activeProcesses.remove(proc);
    }
  }

  /// Download a file, yielding determinate [SetupEvent.stepProgress] events
  /// (0.0–1.0) as bytes arrive, plus log lines every 10 %.
  Stream<SetupEvent> _downloadFile(
      String stepId, String url, String dest) async* {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode} downloading $url');
      }

      final total = resp.contentLength ?? 0;
      var received = 0;
      var lastLogPct = -1;

      await File(dest).parent.create(recursive: true);
      final sink = File(dest).openWrite();
      final ctrl = StreamController<SetupEvent>();

      resp.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) {
          final ratio = received / total;
          final pct   = (ratio * 100).truncate();

          // Emit a progress event on every percent change
          ctrl.add(SetupEvent.stepProgress(stepId, ratio,
              label: '${_mb(received)} / ${_mb(total)} MB'));

          // Log a text line every 10 %
          if (pct != lastLogPct && pct % 10 == 0) {
            ctrl.add(SetupEvent.log(
                stepId, '  $pct%  (${_mb(received)} / ${_mb(total)} MB)'));
            lastLogPct = pct;
          }
        }
        return chunk;
      }).pipe(sink).then((_) => ctrl.close()).catchError(ctrl.addError);

      yield* ctrl.stream;
    } finally {
      client.close();
    }
  }

  String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  Future<void> _symlink(String target, String link) async {
    await Directory(File(link).parent.path).create(recursive: true);
    if (FileSystemEntity.isLinkSync(link)) await Link(link).delete();
    await Link(link).create(target);
  }

  Future<void> _chmod(String path) async =>
      Process.run('chmod', ['+x', path]);

  Future<void> _copyDir(String src, String dst) async {
    await Directory(dst).create(recursive: true);
    await Process.run('cp', ['-r', '$src/.', dst]);
  }
}
