import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import 'paths.dart';

/// Loads user-tunable settings from config.yaml.
/// Binary / model paths are NOT here — those come from [AppPaths].
///
/// Load order (first wins):
///   1. ~/.home_ai/config.yaml   (user-edited copy)
///   2. Bundled config/config.yaml (app defaults)
class AppConfig {
  // STT
  late final String sttLanguage;
  late final int    recordSeconds;

  // LLM
  late final String llmBaseUrl;
  late       String llmModel;
  late       String llmSystemPrompt;
  late final int    llmMaxTokens;
  late final double llmTemperature;

  // Audio
  late final String audioInputDevice;
  late final String audioOutputDevice;
  late final int    sampleRate;
  late final int    channels;
  late       String ttsVoice;

  static AppConfig? _instance;
  AppConfig._();

  static Future<AppConfig> load() async {
    if (_instance != null) return _instance!;
    final cfg = AppConfig._();

    String raw;
    final userFile = File(AppPaths.userConfig);
    if (userFile.existsSync()) {
      raw = await userFile.readAsString();
    } else {
      raw = await rootBundle.loadString('config/config.yaml');
    }

    final doc = loadYaml(raw) as YamlMap;

    final stt = doc['stt'] as YamlMap? ?? YamlMap();
    cfg.sttLanguage    = stt['language']       as String? ?? 'en';
    cfg.recordSeconds  = stt['record_seconds'] as int?    ?? 5;

    final llm = doc['llm'] as YamlMap? ?? YamlMap();
    cfg.llmBaseUrl      = llm['base_url']      as String? ?? 'http://localhost:11434';
    cfg.llmModel        = llm['model']         as String? ?? 'llama3.2:3b';
    cfg.llmSystemPrompt = llm['system_prompt'] as String? ??
        'You are Aria, a friendly home assistant. Reply in short spoken sentences.';
    cfg.llmMaxTokens    = llm['max_tokens']    as int?    ?? 256;
    cfg.llmTemperature  = (llm['temperature']  as num?)?.toDouble() ?? 0.7;

    final audio = doc['audio'] as YamlMap? ?? YamlMap();
    cfg.audioInputDevice  = audio['input_device']  as String? ?? '';
    cfg.audioOutputDevice = audio['output_device'] as String? ?? '';
    cfg.sampleRate        = audio['sample_rate']   as int?    ?? 16000;
    cfg.channels          = audio['channels']      as int?    ?? 1;
    cfg.ttsVoice          = audio['tts_voice']     as String? ?? 'en_US-lessac-medium';

    _instance = cfg;
    return cfg;
  }

  /// Update the system prompt in memory and persist it to ~/.home_ai/config.yaml.
  static Future<void> saveSystemPrompt(String prompt) async {
    assert(_instance != null, 'AppConfig not loaded');
    _instance!.llmSystemPrompt = prompt;
    final yaml = _buildYaml(_instance!);
    await File(AppPaths.userConfig).writeAsString(yaml);
  }

  /// Update the active TTS voice in memory and persist it to ~/.home_ai/config.yaml.
  static Future<void> saveTtsVoice(String voiceName) async {
    assert(_instance != null, 'AppConfig not loaded');
    _instance!.ttsVoice = voiceName;
    final yaml = _buildYaml(_instance!);
    await File(AppPaths.userConfig).writeAsString(yaml);
  }

  /// Update the active LLM model in memory and persist it to ~/.home_ai/config.yaml.
  static Future<void> saveLlmModel(String modelName) async {
    assert(_instance != null, 'AppConfig not loaded');
    _instance!.llmModel = modelName;
    final yaml = _buildYaml(_instance!);
    await File(AppPaths.userConfig).writeAsString(yaml);
  }

  static String _buildYaml(AppConfig c) {
    final indented = c.llmSystemPrompt
        .trim()
        .split('\n')
        .map((l) => '    $l')
        .join('\n');
    return '''
stt:
  language: ${c.sttLanguage}
  record_seconds: ${c.recordSeconds}

llm:
  base_url: ${c.llmBaseUrl}
  model: ${c.llmModel}
  system_prompt: |
$indented
  max_tokens: ${c.llmMaxTokens}
  temperature: ${c.llmTemperature}

audio:
  input_device: "${c.audioInputDevice}"
  output_device: "${c.audioOutputDevice}"
  sample_rate: ${c.sampleRate}
  channels: ${c.channels}
  tts_voice: ${c.ttsVoice}
''';
  }
}
