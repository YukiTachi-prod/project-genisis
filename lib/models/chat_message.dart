enum MessageRole { user, assistant, system }

class ChatEntry {
  final MessageRole role;
  final String text;
  final DateTime timestamp;
  final bool isError;

  const ChatEntry({
    required this.role,
    required this.text,
    required this.timestamp,
    this.isError = false,
  });

  bool get isUser      => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
}
