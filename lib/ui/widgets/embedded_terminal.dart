import 'package:flutter/material.dart';
import '../../providers/chat_provider.dart';

class EmbeddedTerminalWidget extends StatefulWidget {
  final ChatProvider chat;
  const EmbeddedTerminalWidget({super.key, required this.chat});

  @override
  State<EmbeddedTerminalWidget> createState() => _EmbeddedTerminalWidgetState();
}

class _EmbeddedTerminalWidgetState extends State<EmbeddedTerminalWidget> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-scroll to bottom once loaded
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant EmbeddedTerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submitCommand() {
    final cmd = _inputController.text;
    _inputController.clear();
    widget.chat.sendTerminalCommand(cmd);
    _focusNode.requestFocus();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminalOutput = widget.chat.terminalLines.join('');
    final normalized = terminalOutput.trimRight().toLowerCase();

    // Check if the terminal is currently prompting for a password
    final isPasswordPrompt = normalized.endsWith('password:') ||
        normalized.endsWith('password :') ||
        normalized.endsWith('passcode:') ||
        normalized.endsWith('password: ') ||
        (normalized.contains('password') && normalized.endsWith(':'));

    return Container(
      color: const Color(0xFF040416),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Terminal Header Bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF0C0C34),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF28C840),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'LIVE SHELL: BASH',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Color(0xFF6E6E8A),
                  ),
                  onPressed: () => widget.chat.toggleTerminal(),
                ),
              ],
            ),
          ),

          // ── Terminal Output Area ─────────────────────────────────────────
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              child: SelectionArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      terminalOutput,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFD6DBFF),
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Terminal Input Row ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF080824),
              border: Border(
                top: BorderSide(color: Color(0xFF1E1E3F), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Text(
                  isPasswordPrompt ? '🔑 ' : '\$ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isPasswordPrompt ? const Color(0xFFFFBD2E) : const Color(0xFF28C840),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    obscureText: isPasswordPrompt,
                    onSubmitted: (_) => _submitCommand(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      hintText: isPasswordPrompt ? 'Enter password...' : null,
                      hintStyle: isPasswordPrompt ? const TextStyle(color: Color(0xFF6E6E8A)) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
