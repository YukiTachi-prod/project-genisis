import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/audio_service.dart';
import '../core/stt_service.dart';
import '../core/llm_service.dart';
import '../core/tts_service.dart';
import '../core/paths.dart';
import '../models/chat_message.dart';

class VoiceOption {
  final String name;
  final String id;
  final String relativePath;

  const VoiceOption({
    required this.name,
    required this.id,
    required this.relativePath,
  });
}

const List<VoiceOption> availableVoices = [
  VoiceOption(
    name: 'Lessac (US Female - Default)',
    id: 'en_US-lessac-medium',
    relativePath: 'en/en_US/lessac/medium',
  ),
  VoiceOption(
    name: 'Ryan (US Male)',
    id: 'en_US-ryan-medium',
    relativePath: 'en/en_US/ryan/medium',
  ),
  VoiceOption(
    name: 'Joe (US Male)',
    id: 'en_US-joe-medium',
    relativePath: 'en/en_US/joe/medium',
  ),
  VoiceOption(
    name: 'Danny (US Male - Low Quality)',
    id: 'en_US-danny-low',
    relativePath: 'en/en_US/danny/low',
  ),
  VoiceOption(
    name: 'Alan (GB Male - Low Quality)',
    id: 'en_GB-alan-low',
    relativePath: 'en/en_GB/alan/low',
  ),
  VoiceOption(
    name: 'Northern English Male (GB Male)',
    id: 'en_GB-northern_english_male-medium',
    relativePath: 'en/en_GB/northern_english_male/medium',
  ),
];

class ModelOption {
  final String name;
  final String id;
  final String description;

  const ModelOption({
    required this.name,
    required this.id,
    required this.description,
  });
}

const List<ModelOption> availableModels = [
  ModelOption(
    name: 'Llama 3.2 (3B - Default)',
    id: 'llama3.2:3b',
    description: 'Lightweight, fast general-purpose local assistant model.',
  ),
  ModelOption(
    name: 'Qwen 2.5 Coder (7B)',
    id: 'qwen2.5-coder:7b',
    description: 'Powerful, state-of-the-art open-source coding model.',
  ),
  ModelOption(
    name: 'DeepSeek Coder (6.7B)',
    id: 'deepseek-coder:6.7b',
    description: 'Highly capable model tailored for coding and technical tasks.',
  ),
  ModelOption(
    name: 'Llama 3.1 (8B)',
    id: 'llama3.1:8b',
    description: 'Robust general assistant model with excellent reasoning.',
  ),
];

enum AiState {
  idle,
  priming,
  recording,
  transcribing,
  thinking,
  speaking,
}

class ChatProvider extends ChangeNotifier {
  final AppConfig config;
  late final AudioService _audio;
  late final SttService   _stt;
  late final LlmService   _llm;
  late final TtsService   _tts;

  static const _windowChannel = MethodChannel('com.example.home_ai/window');

  final List<ChatEntry> _messages = [];
  AiState _state = AiState.idle;
  String _statusText = 'Ready';
  bool _ttsEnabled = true;
  bool _welcomeAnnounced = false;
  bool _primingWarmUpDone = false;

  bool get isPrimingWarmUpDone => _primingWarmUpDone;

  bool _isTerminalOpen = false;
  bool get isTerminalOpen => _isTerminalOpen;

  Process? _terminalProcess;
  final List<String> _terminalLines = [];
  List<String> get terminalLines => List.unmodifiable(_terminalLines);
  bool _passwordPromptAnnounced = false;
  List<String> _localOllamaModels = [];
  List<String> get localOllamaModels => List.unmodifiable(_localOllamaModels);

  bool _aiInitiatedCommand = false;
  String _currentExecutingCommand = '';
  final StringBuffer _stdoutBuffer = StringBuffer();
  final List<String> _downloadLogs = [];
  List<String> get downloadLogs => List.unmodifiable(_downloadLogs);

  void clearDownloadLogs() {
    _downloadLogs.clear();
    notifyListeners();
  }

  void addDownloadLog(String message) {
    _downloadLogs.add(message);
    notifyListeners();
  }

  ChatProvider(this.config) {
    _audio = AudioService(config);
    _stt   = SttService(config);
    _llm   = LlmService(config);
    _tts   = TtsService(config);
  }

  /// Called by GlowScreen to warm up the LLM without touching AiState.
  Future<void> warmUpForIntro() async {
    try {
      await _llm.warmUp();
    } catch (_) {}
  }

  List<ChatEntry> get messages   => List.unmodifiable(_messages);
  AiState         get state      => _state;
  String          get statusText => _statusText;
  bool            get ttsEnabled => _ttsEnabled;
  bool            get isIdle     => _state == AiState.idle;

  void toggleTts() {
    _ttsEnabled = !_ttsEnabled;
    notifyListeners();
  }

  void clearHistory() {
    _messages.clear();
    _llm.clearHistory();
    addGreeting();
    notifyListeners();
  }

  String get systemPrompt => config.llmSystemPrompt;

  Future<void> updatePersonality(String prompt) async {
    _llm.updateSystemPrompt(prompt);
    _messages.clear();
    addGreeting();
    await AppConfig.saveSystemPrompt(prompt);
    notifyListeners();
    await _primePersonality();
  }

  Future<void> _primePersonality() async {
    _primingWarmUpDone = false;
    _setState(AiState.priming, 'Loading personality…');
    try {
      await _llm.warmUp();
    } catch (_) {
      // Warm-up failure is non-fatal; Ollama may not be running yet.
    }
    _primingWarmUpDone = true;
    notifyListeners();
  }

  void completePriming() {
    _primingWarmUpDone = false;
    _setState(AiState.idle, 'Ready');
  }

  // ── Voice pipeline ────────────────────────────────────────────────────────

  /// Full voice turn: record → STT → LLM → TTS → play.
  Future<void> startVoiceTurn() async {
    if (!isIdle) return;

    String? wavPath;
    String? ttsPath;

    try {
      // 1. Record
      _setState(AiState.recording, 'Listening…');
      wavPath = await _audio.record();

      // 2. Transcribe
      _setState(AiState.transcribing, 'Transcribing…');
      final transcript = await _stt.transcribe(wavPath);
      if (transcript.isEmpty) {
        _setState(AiState.idle, 'No speech detected');
        return;
      }
      _addMessage(MessageRole.user, transcript);

      // 3. LLM
      _setState(AiState.thinking, 'Thinking…');
      final reply = await _llm.chat(transcript);
      final parsedReply = _parseAndExecuteTerminalCommand(reply);
      _addMessage(MessageRole.assistant, parsedReply);

      // 4. TTS + Playback
      if (_ttsEnabled && parsedReply.trim().isNotEmpty) {
        _setState(AiState.speaking, 'Speaking…');
        ttsPath = await _tts.synthesize(parsedReply);
        await _audio.playWav(ttsPath);
      }
    } catch (e) {
      _addMessage(MessageRole.assistant, '⚠️ Error: $e', isError: true);
    } finally {
      _setState(AiState.idle, 'Ready');
      _cleanup(wavPath);
      _cleanup(ttsPath);
    }
  }

  /// Stop recording early (push-to-talk release before timeout).
  void stopRecording() {
    if (_state == AiState.recording) _audio.stopRecording();
  }

  // ── Text pipeline (type a message instead of speaking) ────────────────────

  Future<void> sendText(String userText) async {
    final text = userText.trim();
    if (!isIdle || text.isEmpty) return;

    if (text.startsWith('/')) {
      await handleSlashCommand(text);
      return;
    }

    String? ttsPath;
    try {
      _addMessage(MessageRole.user, text);

      _setState(AiState.thinking, 'Thinking…');
      final reply = await _llm.chat(text);
      final parsedReply = _parseAndExecuteTerminalCommand(reply);
      _addMessage(MessageRole.assistant, parsedReply);

      if (_ttsEnabled && parsedReply.trim().isNotEmpty) {
        _setState(AiState.speaking, 'Speaking…');
        ttsPath = await _tts.synthesize(parsedReply);
        await _audio.playWav(ttsPath);
      }
    } catch (e) {
      _addMessage(MessageRole.assistant, '⚠️ Error: $e', isError: true);
    } finally {
      _setState(AiState.idle, 'Ready');
      _cleanup(ttsPath);
    }
  }

  Future<void> handleSlashCommand(String text) async {
    final parts = text.split(' ');
    final cmd = parts[0].toLowerCase();
    final args = parts.sublist(1).join(' ').trim();

    _addMessage(MessageRole.user, text);

    switch (cmd) {
      case '/help':
        _addMessage(MessageRole.system, 
          'Available commands:\n'
          '  /help                  - Show this help message\n'
          '  /clear                 - Clear screen & conversation history\n'
          '  /tts [on|off]          - Toggle or set voice output (TTS)\n'
          '  /disable --voice       - Disable AI voice output\n'
          '  /enable --voice        - Enable AI voice output\n'
          '  /personality [prompt]  - View or update system prompt (/personality -edit to open editor)\n'
          '  /voice                 - Open voice selection dialog\n'
          '  /model                 - Open LLM model selection dialog\n'
          '  /fullscreen            - Switch to fullscreen mode\n'
          '  /windowed              - Switch to windowed mode\n'
          '  /terminal (or /term)   - Toggle the embedded live terminal panel\n'
          '  /mic (or /record)      - Trigger voice recording (runs for ${config.recordSeconds}s)\n'
          '  /status                - Show connection and model status\n'
          '  /exit                  - Shutdown the application'
        );
        break;
      case '/clear':
        clearHistory();
        break;
      case '/tts':
        if (args.isEmpty) {
          toggleTts();
          _addMessage(MessageRole.system, 'TTS voice output is now ${_ttsEnabled ? "enabled" : "disabled"}.');
        } else if (args.toLowerCase() == 'on') {
          _ttsEnabled = true;
          notifyListeners();
          _addMessage(MessageRole.system, 'TTS voice output enabled.');
        } else if (args.toLowerCase() == 'off') {
          _ttsEnabled = false;
          notifyListeners();
          _addMessage(MessageRole.system, 'TTS voice output disabled.');
        } else {
          _addMessage(MessageRole.system, 'Usage: /tts [on|off]', isError: true);
        }
        break;
      case '/disable':
        if (args == '--voice') {
          _ttsEnabled = false;
          notifyListeners();
          _addMessage(MessageRole.system, 'AI voice output disabled.');
        } else {
          _addMessage(MessageRole.system, 'Usage: /disable --voice', isError: true);
        }
        break;
      case '/enable':
        if (args == '--voice') {
          _ttsEnabled = true;
          notifyListeners();
          _addMessage(MessageRole.system, 'AI voice output enabled.');
        } else {
          _addMessage(MessageRole.system, 'Usage: /enable --voice', isError: true);
        }
        break;
      case '/personality':
      case '/system':
        if (args.isEmpty) {
          _addMessage(MessageRole.system, 'Current personality prompt:\n${config.llmSystemPrompt}');
        } else if (args == '-edit') {
          _addMessage(MessageRole.system, 'Opening editor window...');
        } else {
          _addMessage(MessageRole.system, 'Updating personality...');
          await updatePersonality(args);
          _addMessage(MessageRole.system, 'Personality successfully updated.');
        }
        break;
      case '/mic':
      case '/record':
        if (!isIdle) {
          _addMessage(MessageRole.system, 'System is busy.', isError: true);
        } else {
          startVoiceTurn();
        }
        break;
      case '/status':
        _addMessage(MessageRole.system, 
          'System Status:\n'
          '  STT Engine: whisper-cli\n'
          '  LLM Engine: Ollama (${config.llmBaseUrl})\n'
          '  LLM Model:  ${config.llmModel}\n'
          '  TTS Engine: Piper\n'
          '  Audio Device: ${config.audioInputDevice.isEmpty ? "default" : config.audioInputDevice}'
        );
        break;
      case '/voice':
        _addMessage(MessageRole.system, 'Opening voice selection dialog...');
        break;
      case '/model':
        _addMessage(MessageRole.system, 'Opening model selection dialog...');
        break;
      case '/fullscreen':
        await setFullscreen();
        _addMessage(MessageRole.system, 'Window set to fullscreen.');
        break;
      case '/windowed':
        await setWindowed();
        _addMessage(MessageRole.system, 'Window set to windowed.');
        break;
      case '/terminal':
      case '/term':
        toggleTerminal();
        _addMessage(MessageRole.system, _isTerminalOpen ? 'Opened live terminal panel.' : 'Closed live terminal panel.');
        break;
      case '/exit':
        _addMessage(MessageRole.system, 'Shutting down Home AI...');
        await Future.delayed(const Duration(milliseconds: 300));
        exit(0);
      default:
        _addMessage(MessageRole.system, 'Unknown command: $cmd. Type /help for assistance.', isError: true);
        break;
    }
  }

  void addGreeting() {
    _messages.add(ChatEntry(
      role: MessageRole.system,
      text: ' Welcome, user\n'
            ' Welcome to Home AI Terminal\n'
            ' ────────────────────────────────────────\n'
            ' Type /help to see all available commands.\n'
            ' Voice output (TTS) is ${_ttsEnabled ? "enabled" : "disabled"}.',
      timestamp: DateTime.now(),
    ));
  }

  void addLocalCommandEcho(String commandText) {
    _addMessage(MessageRole.user, commandText);
  }

  Future<void> announceWelcome() async {
    if (_welcomeAnnounced) return;
    _welcomeAnnounced = true;

    _messages.clear();
    addGreeting();
    notifyListeners();

    await checkSpecsAndRecommend();

    if (_ttsEnabled) {
      String? ttsPath;
      try {
        _setState(AiState.speaking, 'Speaking…');
        ttsPath = await _tts.synthesize('Welcome, user');
        await _audio.playWav(ttsPath);
      } catch (_) {
      } finally {
        _setState(AiState.idle, 'Ready');
        _cleanup(ttsPath);
      }
    }
  }

  Future<void> checkSpecsAndRecommend() async {
    final ramGB = await _getSystemRamGB();
    String recommendation;
    if (ramGB < 8.0) {
      recommendation = 'Llama 3.2 (3B - Default)';
    } else if (ramGB < 16.0) {
      recommendation = 'Qwen 2.5 Coder (7B) or DeepSeek Coder (6.7B)';
    } else {
      recommendation = 'Llama 3.1 (8B) or Qwen 2.5 Coder (7B)';
    }

    final formattedRam = ramGB.toStringAsFixed(1);
    final specMsg = 
        ' 🖥️ System Spec Scan:\n'
        '  Detected System RAM: $formattedRam GB\n'
        '  Recommended LLM:     $recommendation\n'
        '  Current LLM Model:   ${config.llmModel}\n'
        '  To switch models, type: /model';

    _addMessage(MessageRole.system, specMsg);
  }

  Future<double> _getSystemRamGB() async {
    try {
      if (Platform.isLinux) {
        final file = File('/proc/meminfo');
        if (await file.exists()) {
          final lines = await file.readAsLines();
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              final match = RegExp(r'\d+').firstMatch(line);
              if (match != null) {
                final kB = int.parse(match.group(0)!);
                return kB / (1024 * 1024); // KB to GB
              }
            }
          }
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('sysctl', ['-n', 'hw.memsize']);
        if (result.exitCode == 0) {
          final bytes = int.tryParse(result.stdout.toString().trim());
          if (bytes != null) {
            return bytes / (1024 * 1024 * 1024); // Bytes to GB
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['ComputerSystem', 'get', 'TotalPhysicalMemory']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty && trimmed != 'TotalPhysicalMemory') {
              final bytes = int.tryParse(trimmed);
              if (bytes != null) {
                return bytes / (1024 * 1024 * 1024);
              }
            }
          }
        }
      }
    } catch (_) {
      // Fallback
    }
    return 8.0; // Fallback to 8GB
  }

  Future<void> downloadAndSetVoice(VoiceOption voice) async {
    _primingWarmUpDone = false;
    _setState(AiState.priming, 'Downloading voice…');
    clearDownloadLogs();
    try {
      addDownloadLog('[INF] Initializing voice model setup...');
      final onnxFile = File('${AppPaths.piperVoiceDir}/${voice.id}.onnx');
      final jsonFile = File('${AppPaths.piperVoiceDir}/${voice.id}.onnx.json');

      if (!onnxFile.existsSync() || !jsonFile.existsSync()) {
        await Directory(AppPaths.piperVoiceDir).create(recursive: true);
        
        final client = http.Client();
        const baseHuggingFaceUrl = 'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0';

        try {
          if (!onnxFile.existsSync()) {
            final onnxUrl = '$baseHuggingFaceUrl/${voice.relativePath}/${voice.id}.onnx';
            addDownloadLog('[INF] Fetching: ${voice.id}.onnx');
            final response = await client.get(Uri.parse(onnxUrl));
            if (response.statusCode != 200) {
              throw Exception('Failed to download ONNX file (HTTP ${response.statusCode})');
            }
            await onnxFile.writeAsBytes(response.bodyBytes);
            addDownloadLog('[ OK ] Saved: ${voice.id}.onnx');
          } else {
            addDownloadLog('[ OK ] Already exists: ${voice.id}.onnx');
          }

          if (!jsonFile.existsSync()) {
            final jsonUrl = '$baseHuggingFaceUrl/${voice.relativePath}/${voice.id}.onnx.json';
            addDownloadLog('[INF] Fetching: ${voice.id}.onnx.json');
            final response = await client.get(Uri.parse(jsonUrl));
            if (response.statusCode != 200) {
              throw Exception('Failed to download JSON file (HTTP ${response.statusCode})');
            }
            await jsonFile.writeAsBytes(response.bodyBytes);
            addDownloadLog('[ OK ] Saved: ${voice.id}.onnx.json');
          } else {
            addDownloadLog('[ OK ] Already exists: ${voice.id}.onnx.json');
          }
        } finally {
          client.close();
        }
      }

      await AppConfig.saveTtsVoice(voice.id);
      addDownloadLog('[ OK ] Voice setup completed successfully.');
      _addMessage(MessageRole.system, 'Voice changed to ${voice.name}.');
    } catch (e) {
      addDownloadLog('[ ERR ] Failed to download voice: $e');
      _addMessage(MessageRole.system, '⚠️ Failed to change voice: $e', isError: true);
    } finally {
      _primingWarmUpDone = true;
      notifyListeners();
    }
  }

  Future<void> fetchLocalOllamaModels() async {
    try {
      final response = await http.get(Uri.parse('${config.llmBaseUrl}/api/tags'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['models'] as List<dynamic>? ?? [];
        _localOllamaModels = list.map((m) => m['name'] as String).toList();
        notifyListeners();
      }
    } catch (_) {
      // Offline/unreachable is handled gracefully
    }
  }

  Future<void> setLlmModel(ModelOption model) async {
    _primingWarmUpDone = false;
    _setState(AiState.priming, 'Downloading ${model.name}…');
    clearDownloadLogs();
    try {
      addDownloadLog('[INF] Initializing model setup for ${model.name}...');
      
      // 1. Fetch available models
      await fetchLocalOllamaModels();
      final exists = _localOllamaModels.any((m) => 
        m == model.id || m == '${model.id}:latest' || m.startsWith('${model.id}:')
      );

      // 2. If it does not exist, pull it via Ollama
      if (!exists) {
        addDownloadLog('[INF] Model not found locally. Connecting to Ollama...');
        final client = http.Client();
        final request = http.Request('POST', Uri.parse('${config.llmBaseUrl}/api/pull'))
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({'name': model.id, 'stream': true});
          
        addDownloadLog('[INF] Pulling model from Ollama library...');
        final response = await client.send(request).timeout(const Duration(minutes: 15));
        if (response.statusCode != 200) {
          throw Exception('Ollama failed to pull model (HTTP ${response.statusCode})');
        }
        
        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (line.trim().isEmpty) continue;
          final parsedJson = jsonDecode(line) as Map<String, dynamic>;
          final status = parsedJson['status'] as String? ?? '';
          final total = parsedJson['total'] as int? ?? 0;
          final completed = parsedJson['completed'] as int? ?? 0;
          
          if (total > 0) {
            final pct = (completed / total * 100).toStringAsFixed(1);
            final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
            final completedMB = (completed / (1024 * 1024)).toStringAsFixed(1);
            addDownloadLog('[INF] Progress: $pct% ($completedMB MB / $totalMB MB) - $status');
          } else {
            addDownloadLog('[INF] Status: $status');
          }
        }
        client.close();
        addDownloadLog('[ OK ] Model downloaded successfully!');
      } else {
        addDownloadLog('[ OK ] Model already exists locally.');
      }

      // 3. Save to config & update
      addDownloadLog('[INF] Saving model selection...');
      await AppConfig.saveLlmModel(model.id);

      // 4. Warm up the new model
      addDownloadLog('[INF] Loading model into Ollama memory...');
      _setState(AiState.priming, 'Warming up ${model.name}…');
      await _llm.warmUp();
      addDownloadLog('[ OK ] Model loaded and warmed up!');

      _addMessage(MessageRole.system, 'LLM model changed to ${model.name}.');
    } catch (e) {
      addDownloadLog('[ ERR ] Failed to change model: $e');
      _addMessage(MessageRole.system, '⚠️ Failed to change model: $e', isError: true);
    } finally {
      _primingWarmUpDone = true;
      notifyListeners();
    }
  }

  Future<void> setFullscreen() async {
    try {
      await _windowChannel.invokeMethod('fullscreen');
    } catch (e) {
      _addMessage(MessageRole.system, '⚠️ Failed to enter fullscreen: $e', isError: true);
    }
  }

  Future<void> setWindowed() async {
    try {
      await _windowChannel.invokeMethod('windowed');
    } catch (e) {
      _addMessage(MessageRole.system, '⚠️ Failed to exit fullscreen: $e', isError: true);
    }
  }

  void toggleTerminal() {
    _isTerminalOpen = !_isTerminalOpen;
    notifyListeners();
    if (_isTerminalOpen && _terminalProcess == null) {
      _startTerminalProcess();
    }
  }

  Future<void> _startTerminalProcess() async {
    try {
      final shell = Platform.isWindows ? 'cmd.exe' : '/bin/bash';
      _terminalProcess = await Process.start(shell, []);

      // Listen to stdout
      _terminalProcess!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        _appendTerminalOutput(data);
      });

      // Listen to stderr
      _terminalProcess!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        _appendTerminalOutput(data);
      });
      
      _terminalProcess!.exitCode.then((code) {
        _appendTerminalOutput('\n[Process exited with code $code]\n');
        _terminalProcess = null;
        _announceCommandFinished(code);
      });
    } catch (e) {
      _appendTerminalOutput('⚠️ Failed to start shell process: $e\n');
    }
  }

  void sendTerminalCommand(String command) {
    _llm.addHistoryMessage('system', 'Terminal command started: $command');
    if (_terminalProcess == null) {
      _startTerminalProcess().then((_) {
        _sendTerminalRaw(command);
      });
    } else {
      _sendTerminalRaw(command);
    }
  }

  void _sendTerminalRaw(String command) {
    _currentExecutingCommand = command;
    _stdoutBuffer.clear();

    _terminalProcess!.stdin.writeln(command);
    final checkExitCodeCmd = Platform.isWindows
        ? 'echo ___COMMAND_FINISHED_WITH_EXIT_CODE___:%errorlevel%'
        : 'echo ___COMMAND_FINISHED_WITH_EXIT_CODE___:\$?';
    _terminalProcess!.stdin.writeln(checkExitCodeCmd);
    _terminalProcess!.stdin.flush();
  }

  void _appendTerminalOutput(String data) {
    _stdoutBuffer.write(data);
    final bufferStr = _stdoutBuffer.toString();

    // Check if the completion marker is in the buffer
    if (bufferStr.contains('___COMMAND_FINISHED_WITH_EXIT_CODE___')) {
      final match = RegExp(r'___COMMAND_FINISHED_WITH_EXIT_CODE___:(\d+)').firstMatch(bufferStr);
      if (match != null) {
        final exitCode = int.tryParse(match.group(1) ?? '0') ?? 0;
        
        // Extract output up to the marker
        final markerIdx = bufferStr.indexOf('___COMMAND_FINISHED_WITH_EXIT_CODE___');
        String cleanOutput = '';
        if (markerIdx != -1) {
          cleanOutput = bufferStr.substring(0, markerIdx).trim();
        } else {
          cleanOutput = bufferStr.trim();
        }

        // Clean up last line prompt
        final lastLineIndex = cleanOutput.lastIndexOf('\n');
        if (lastLineIndex != -1) {
          final lastLine = cleanOutput.substring(lastLineIndex + 1);
          if (lastLine.contains('\$') || lastLine.contains('#') || lastLine.contains('>')) {
            cleanOutput = cleanOutput.substring(0, lastLineIndex).trim();
          }
        }

        _handleCommandCompleted(_currentExecutingCommand, cleanOutput, exitCode);
        _stdoutBuffer.clear();
      }
    }

    // Filter out the command marker line from the user-visible terminal lines
    final filteredData = data.replaceAll(RegExp(r'.*___COMMAND_FINISHED_WITH_EXIT_CODE___.*'), '');
    if (filteredData.isNotEmpty) {
      _terminalLines.add(filteredData);
      if (_terminalLines.length > 500) {
        _terminalLines.removeAt(0);
      }
      notifyListeners();

      // Check if a password prompt just appeared in the output
      final normalized = filteredData.trimRight().toLowerCase();
      if (normalized.endsWith('password:') ||
          normalized.endsWith('password :') ||
          normalized.endsWith('passcode:') ||
          normalized.endsWith('password: ') ||
          (normalized.contains('password') && normalized.endsWith(':'))) {
        if (!_passwordPromptAnnounced) {
          _passwordPromptAnnounced = true;
          _announcePasswordRequired();
        }
      } else if (filteredData.trim().isNotEmpty) {
        _passwordPromptAnnounced = false;
      }
    }
  }

  Future<void> _handleCommandCompleted(String command, String output, int exitCode) async {
    _llm.addHistoryMessage('system', 'Terminal command "$command" finished with exit code $exitCode. Output:\n$output');

    if (!_aiInitiatedCommand) {
      final success = exitCode == 0;
      _addMessage(MessageRole.system, success 
          ? 'Command finished successfully.' 
          : 'Command exited with error code $exitCode.');
      return;
    }

    _aiInitiatedCommand = false;

    try {
      _setState(AiState.thinking, 'Thinking…');
      final reply = await _llm.chat('[System: Summarize the result of the command "$command" and state the important parts of its output. Focus on key status info or errors.]');
      final parsedReply = _parseAndExecuteTerminalCommand(reply);
      _addMessage(MessageRole.assistant, parsedReply);

      if (_ttsEnabled && parsedReply.trim().isNotEmpty) {
        _setState(AiState.speaking, 'Speaking…');
        final ttsPath = await _tts.synthesize(parsedReply);
        await _audio.playWav(ttsPath);
        _cleanup(ttsPath);
      }
    } catch (e) {
      _addMessage(MessageRole.assistant, '⚠️ Error analyzing command output: $e', isError: true);
    } finally {
      _setState(AiState.idle, 'Ready');
    }
  }

  void _announcePasswordRequired() async {
    _llm.addHistoryMessage('system', 'The terminal is prompting for a password. Command execution is paused.');
    _addMessage(MessageRole.assistant, 'The terminal is prompting for a password. Please enter it in the live shell.');
    if (_ttsEnabled) {
      String? ttsPath;
      try {
        _setState(AiState.speaking, 'Speaking…');
        ttsPath = await _tts.synthesize('The terminal is prompting for a password.');
        await _audio.playWav(ttsPath);
      } catch (_) {
      } finally {
        _setState(AiState.idle, 'Ready');
        _cleanup(ttsPath);
      }
    }
  }

  void _announceCommandFinished(int exitCode) async {
    _llm.addHistoryMessage('system', 'The terminal process exited with code $exitCode.');
    final success = exitCode == 0;
    final msg = success 
        ? 'The terminal process has finished successfully.' 
        : 'The terminal process exited with an error (code $exitCode).';
    _addMessage(MessageRole.assistant, msg);
    if (_ttsEnabled) {
      String? ttsPath;
      try {
        _setState(AiState.speaking, 'Speaking…');
        ttsPath = await _tts.synthesize(success ? 'Command finished successfully.' : 'Command exited with an error.');
        await _audio.playWav(ttsPath);
      } catch (_) {
      } finally {
        _setState(AiState.idle, 'Ready');
        _cleanup(ttsPath);
      }
    }
  }

  @override
  void dispose() {
    _terminalProcess?.kill();
    super.dispose();
  }

  String _parseAndExecuteTerminalCommand(String reply) {
    String parsedReply = reply;
    bool actionTriggered = false;
    String actionMsg = '';

    if (reply.contains('[RUN_COMMAND:')) {
      final start = reply.indexOf('[RUN_COMMAND:') + '[RUN_COMMAND:'.length;
      final end = reply.indexOf(']', start);
      if (end != -1) {
        final cmd = reply.substring(start, end).trim();
        parsedReply = reply.replaceRange(reply.indexOf('[RUN_COMMAND:'), end + 1, '').trim();
        if (!_isTerminalOpen) {
          toggleTerminal();
        }
        _aiInitiatedCommand = true;
        sendTerminalCommand(cmd);
        actionTriggered = true;
        actionMsg = 'Executing command: $cmd';
      }
    } else if (reply.contains('[OPEN_TERMINAL]')) {
      parsedReply = reply.replaceAll('[OPEN_TERMINAL]', '').trim();
      if (!_isTerminalOpen) {
        toggleTerminal();
      }
      actionTriggered = true;
      actionMsg = 'Certainly, opening the terminal.';
    } else if (reply.contains('[CLOSE_TERMINAL]')) {
      parsedReply = reply.replaceAll('[CLOSE_TERMINAL]', '').trim();
      if (_isTerminalOpen) {
        toggleTerminal();
      }
      actionTriggered = true;
      actionMsg = 'Certainly, closing the terminal.';
    }

    if (actionTriggered && parsedReply.isEmpty) {
      parsedReply = actionMsg;
    }

    return parsedReply;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setState(AiState s, String label) {
    _state = s;
    _statusText = label;
    notifyListeners();
  }

  void _addMessage(MessageRole role, String text, {bool isError = false}) {
    _messages.add(ChatEntry(
      role:      role,
      text:      text,
      timestamp: DateTime.now(),
      isError:   isError,
    ));
    notifyListeners();
  }

  void _cleanup(String? path) {
    if (path == null) return;
    try { File(path).deleteSync(); } catch (_) {}
  }
}
