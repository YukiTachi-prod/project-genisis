import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class ChatMessage {
  final String role;   // 'system' | 'user' | 'assistant'
  final String content;
  const ChatMessage({required this.role, required this.content});
  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Sends conversation history to Ollama's /api/chat endpoint and returns
/// the assistant's reply.  Streaming is NOT used here to keep the code
/// simple; switch to the streaming endpoint if you want live word output.
class LlmService {
  final AppConfig config;
  final List<ChatMessage> _history = [];

  LlmService(this.config) {
    // Seed with system prompt
    _history.add(ChatMessage(role: 'system', content: _buildSystemPrompt(config.llmSystemPrompt)));
  }

  List<ChatMessage> get history => List.unmodifiable(_history);

  /// Clears conversation context (keeps system prompt).
  void clearHistory() {
    _history.removeWhere((m) => m.role != 'system');
  }

  /// Replace the system prompt and clear conversation history.
  void updateSystemPrompt(String prompt) {
    _history.clear();
    _history.add(ChatMessage(role: 'system', content: _buildSystemPrompt(prompt)));
  }

  /// Adds a message to the history (e.g. for background execution results).
  void addHistoryMessage(String role, String content) {
    _history.add(ChatMessage(role: role, content: content));
  }

  String _buildSystemPrompt(String basePrompt) {
    return '$basePrompt\n\n'
        'Terminal Control Instructions:\n'
        '- To open the terminal panel in the UI, append "[OPEN_TERMINAL]" to your message.\n'
        '- To close the terminal panel, append "[CLOSE_TERMINAL]" to your message.\n'
        '- To run a shell command inside the user\'s terminal (embedded in the UI), append "[RUN_COMMAND: command]" to your message (e.g. "[RUN_COMMAND: ls -la]"). This will automatically open the terminal and execute the command.\n\n'
        'Browser Control Instructions:\n'
        '- To open the browser panel in the UI, append "[OPEN_BROWSER]" to your message.\n'
        '- To close the browser panel, append "[CLOSE_BROWSER]" to your message.\n'
        '- To load a URL or search a query in the browser panel, append "[BROWSER: url_or_query]" to your message (e.g. "[BROWSER: wikipedia.org]" or "[BROWSER: latest technology news]"). This will automatically open the browser panel and load the page/search.\n\n'
        'Rules:\n'
        '1. Use these tags ONLY when the user explicitly requests you to open/close the terminal/browser, run a command, search for something, or visit a website, or when a command/search is required to fulfill the request. Never use them for greetings, general chit-chat, or questions.\n'
        '2. You MUST always write conversational text explaining what you are doing alongside the tag (e.g., "Sure, opening the browser. [OPEN_BROWSER]" or "Searching for latest news: [BROWSER: latest news]"). Never output the tag alone without text.\n'
        '3. When executing a command or search via [RUN_COMMAND: command] or [BROWSER: url_or_query], you MUST NOT assume, state, or imply that the command or search has finished, succeeded, or failed in that reply. Instead, only state that you are starting or running it. The system executes them in the background asynchronously.\n'
        '4. You will receive updates in the conversation history as system messages when commands or processes exit. Use these events in subsequent turns to know the true status.';
  }

  /// Warms up the model by sending a minimal request so Ollama loads the model
  /// and caches the system-prompt KV before the first real user turn.
  Future<void> warmUp() async {
    final body = jsonEncode({
      'model': config.llmModel,
      'messages': [
        {'role': 'system', 'content': _buildSystemPrompt(config.llmSystemPrompt)},
        {'role': 'user', 'content': '.'},
      ],
      'stream': false,
      'options': {
        'num_predict': 1,
        'temperature': 0.0,
      },
    });

    await http
        .post(
          Uri.parse('${config.llmBaseUrl}/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 120));
  }

  /// Sends [userText] to the LLM and returns the assistant reply.
  Future<String> chat(String userText) async {
    _history.add(ChatMessage(role: 'user', content: userText));

    final body = jsonEncode({
      'model': config.llmModel,
      'messages': _history.map((m) => m.toJson()).toList(),
      'stream': false,
      'options': {
        'num_predict': config.llmMaxTokens,
        'temperature': config.llmTemperature,
      },
    });

    final response = await http
        .post(
          Uri.parse('${config.llmBaseUrl}/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Ollama API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final reply = (decoded['message'] as Map<String, dynamic>)['content'] as String;

    _history.add(ChatMessage(role: 'assistant', content: reply));
    return reply;
  }

  /// Unloads the model from Ollama's memory immediately.
  Future<void> unloadModel({String? modelName}) async {
    try {
      final targetModel = modelName ?? config.llmModel;
      final body = jsonEncode({
        'model': targetModel,
        'keep_alive': 0,
      });
      await http
          .post(
            Uri.parse('${config.llmBaseUrl}/api/generate'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
