import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../models/chat_message.dart';
import '../../core/paths.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/embedded_terminal.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().announceWelcome();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  ThemeData _buildDarkTheme(BuildContext context) {
    final accentColor = const Color(0xFF5B6EF5);
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF0B0B2E),
      surfaceContainerLowest: const Color(0xFF040416),
      surfaceContainerLow: const Color(0xFF080824),
      surfaceContainer: const Color(0xFF0C0C34),
      surfaceContainerHigh: const Color(0xFF10103E),
      surfaceContainerHighest: const Color(0xFF141448),
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFF9E9EAF),
      primary: accentColor,
      primaryContainer: const Color(0xFF1B1B54),
      onPrimaryContainer: const Color(0xFFD6DBFF),
      outlineVariant: const Color(0xFF2E2E5D),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF06061A),
    );
  }

  void _sendText(ChatProvider chat, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 2 && parts[0].toLowerCase() == '/personality' && parts[1].toLowerCase() == '-edit') {
      chat.addLocalCommandEcho(trimmed);
      _showPersonalityDialog(context, chat);
    } else if (trimmed.toLowerCase() == '/voice') {
      chat.addLocalCommandEcho(trimmed);
      _showVoiceDialog(context, chat);
    } else if (trimmed.toLowerCase() == '/model') {
      chat.addLocalCommandEcho(trimmed);
      _showModelDialog(context, chat);
    } else {
      chat.sendText(trimmed);
    }
  }

  void _showPersonalityDialog(BuildContext ctx, ChatProvider chat) {
    final controller = TextEditingController(text: chat.systemPrompt);
    showDialog<void>(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B0B2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF5B6EF5), width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.psychology_outlined, color: Color(0xFF5B6EF5), size: 22),
            SizedBox(width: 10),
            Text(
              'EDIT SYSTEM PROMPT',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Modifying the system prompt will reset the conversational history.',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF6E6E8A),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 12,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter AI personality instructions...',
                  hintStyle: const TextStyle(color: Color(0xFF3E3E5C)),
                  filled: true,
                  fillColor: const Color(0xFF06061A),
                  contentPadding: const EdgeInsets.all(12),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF5B6EF5), width: 1.0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF2E2E5D), width: 1.0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF6E6E8A),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final prompt = controller.text.trim();
              if (prompt.isNotEmpty) {
                chat.updatePersonality(prompt);
              }
              Navigator.of(dctx).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF5B6EF5),
            ),
            child: const Text(
              'SAVE & RESET',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF28C840),
              ),
            ),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showVoiceDialog(BuildContext ctx, ChatProvider chat) {
    showDialog<void>(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dctx) {
        final currentVoiceId = chat.config.ttsVoice;
        
        return AlertDialog(
          backgroundColor: const Color(0xFF0B0B2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF5B6EF5), width: 1),
          ),
          title: const Row(
            children: [
              Icon(Icons.record_voice_over_outlined, color: Color(0xFF5B6EF5), size: 22),
              SizedBox(width: 10),
              Text(
                'SELECT TTS VOICE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Select a text-to-speech voice. Selecting a new voice will download the necessary model files dynamically.',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF6E6E8A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...availableVoices.map((voice) {
                    final isActive = voice.id == currentVoiceId;
                    final onnxFile = File('${AppPaths.piperVoiceDir}/${voice.id}.onnx');
                    final isDownloaded = onnxFile.existsSync();

                    String statusText;
                    Color statusColor;
                    if (isActive) {
                      statusText = '[ACTIVE]';
                      statusColor = const Color(0xFF28C840);
                    } else if (isDownloaded) {
                      statusText = '[DOWNLOADED]';
                      statusColor = const Color(0xFF5B6EF5);
                    } else {
                      statusText = '[DOWNLOAD REQUIRED]';
                      statusColor = const Color(0xFFFFBD2E);
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? const Color(0xFF141448) 
                            : const Color(0xFF06061A),
                        border: Border.all(
                          color: isActive ? const Color(0xFF5B6EF5) : const Color(0xFF1E1E3F),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(dctx).pop();
                          if (!isActive) {
                            chat.downloadAndSetVoice(voice);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  voice.name,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: isActive ? Colors.white : const Color(0xFFD6DBFF),
                                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text(
                'CLOSE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Color(0xFF6E6E8A),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showModelDialog(BuildContext ctx, ChatProvider chat) {
    // Proactively fetch local models
    chat.fetchLocalOllamaModels();

    showDialog<void>(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dctx) {
        return Consumer<ChatProvider>(
          builder: (context, chatProvider, child) {
            final currentModelId = chatProvider.config.llmModel;

            return AlertDialog(
              backgroundColor: const Color(0xFF0B0B2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF5B6EF5), width: 1),
              ),
              title: const Row(
                children: [
                  Icon(Icons.psychology_outlined, color: Color(0xFF5B6EF5), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'SELECT LLM MODEL',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Select a local LLM model to run on your Ollama server. Selecting a new model will pull it dynamically if not already downloaded.',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF6E6E8A),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...availableModels.map((model) {
                        final isActive = model.id == currentModelId;
                        
                        // Check if model is in the local models list fetched from Ollama API
                        final isDownloaded = chatProvider.localOllamaModels.any((m) =>
                          m == model.id || m == '${model.id}:latest' || m.startsWith('${model.id}:')
                        );

                        String statusText;
                        Color statusColor;
                        if (isActive) {
                          statusText = '[ACTIVE]';
                          statusColor = const Color(0xFF28C840);
                        } else if (isDownloaded) {
                          statusText = '[DOWNLOADED]';
                          statusColor = const Color(0xFF5B6EF5);
                        } else {
                          statusText = '[DOWNLOAD REQUIRED]';
                          statusColor = const Color(0xFFFFBD2E);
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive 
                                ? const Color(0xFF141448) 
                                : const Color(0xFF06061A),
                            border: Border.all(
                              color: isActive ? const Color(0xFF5B6EF5) : const Color(0xFF1E1E3F),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(dctx).pop();
                              if (!isActive) {
                                chatProvider.setLlmModel(model);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          model.name,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            color: isActive ? Colors.white : const Color(0xFFD6DBFF),
                                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          model.description,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 9,
                                            color: Color(0xFF8E8EA8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(),
                  child: const Text(
                    'CLOSE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xFF6E6E8A),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _buildDarkTheme(context),
      child: Consumer<ChatProvider>(
        builder: (ctx, chat, _) {
          _scrollToBottom();
          final isReady = chat.isIdle;
          final targetColor = isReady ? const Color(0xFF28C840) : const Color(0xFF5B6EF5);

          return Stack(
            children: [
              Scaffold(
                body: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            // ── Terminal Output Stream ───────────────────────
                            Expanded(
                              child: SelectionArea(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  itemCount: chat.messages.length,
                                  itemBuilder: (_, i) =>
                                      TerminalLine(entry: chat.messages[i]),
                                ),
                              ),
                            ),

                            // ── Terminal Status Bar ──────────────────────────
                            _TerminalStatus(state: chat.state, text: chat.statusText),

                            // ── Prompt Input Row ─────────────────────────────
                            _buildInputRow(ctx, chat),
                          ],
                        ),
                      ),
                      if (chat.isTerminalOpen)
                        Container(
                          width: MediaQuery.of(context).size.width * 0.45,
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Color(0xFF1E1E3F), width: 1.0),
                            ),
                          ),
                          child: EmbeddedTerminalWidget(chat: chat),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Screen edge glow (from loading Phase 3) ───────────────
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(begin: const Color(0xFF5B6EF5), end: targetColor),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    builder: (context, color, child) {
                      return CustomPaint(
                        painter: _EdgePainter(color: color ?? const Color(0xFF5B6EF5)),
                      );
                    },
                  ),
                ),
              ),



              // ── Terminal Priming Overlay ─────────────────────────────
              if (chat.state == AiState.priming)
                LoadingOverlay(
                  isDone: chat.isPrimingWarmUpDone,
                  statusText: chat.statusText,
                  logs: chat.downloadLogs,
                  onComplete: () => chat.completePriming(),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputRow(BuildContext ctx, ChatProvider chat) {
    final isReady = chat.isIdle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF06061A),
        border: Border(top: BorderSide(color: Color(0xFF1E1E3F), width: 0.5)),
      ),
      child: Row(
        children: [
          // Prompt symbol
          const Text(
            'user@home-ai:~\$ ',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5B6EF5),
            ),
          ),
          const SizedBox(width: 4),
          // Input field
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: isReady,
              onSubmitted: (v) => _sendText(chat, v),
              autofocus: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Colors.white,
              ),
              decoration: const InputDecoration(
                hintText: 'Type message or command (/help)...',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFF3E3E5C),
                ),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Terminal Line Widget ───────────────────────────────────────────────────────
class TerminalLine extends StatelessWidget {
  final ChatEntry entry;
  const TerminalLine({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    Color color;
    String prefix;

    if (entry.isUser) {
      color = Colors.white;
      prefix = 'user@home-ai:~\$ ';
    } else if (entry.isAssistant) {
      color = const Color(0xFFD6DBFF);
      prefix = 'agent> ';
    } else {
      if (entry.isError) {
        color = const Color(0xFFFF5F57);
        prefix = '[error] ';
      } else {
        color = const Color(0xFF6E6E8A);
        prefix = '[system] ';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prefix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: entry.isUser
                  ? const Color(0xFF5B6EF5)
                  : entry.isAssistant
                      ? const Color(0xFF8897EC)
                      : color,
            ),
          ),
          Expanded(
            child: Text(
              entry.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Terminal Status Bar Widget ─────────────────────────────────────────────────
class _TerminalStatus extends StatelessWidget {
  final AiState state;
  final String text;
  const _TerminalStatus({required this.state, required this.text});

  @override
  Widget build(BuildContext context) {
    if (state == AiState.idle) {
      return const SizedBox.shrink();
    }

    Color color = switch (state) {
      AiState.idle         => const Color(0xFF28C840),
      AiState.priming      => const Color(0xFF5B6EF5),
      AiState.recording    => const Color(0xFFFF5F57),
      AiState.transcribing => const Color(0xFFFFBD2E),
      AiState.thinking     => const Color(0xFF8897EC),
      AiState.speaking     => const Color(0xFFB57EDC),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A26),
        border: Border(
          top: BorderSide(color: Color(0xFF1E1E3F), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (state != AiState.idle)
            const _TerminalSpinner()
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 10),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          const Text(
            'HOME-AI v1.0.0',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Color(0xFF4C566A),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unicode Terminal Spinner ───────────────────────────────────────────────────
class _TerminalSpinner extends StatefulWidget {
  const _TerminalSpinner();

  @override
  State<_TerminalSpinner> createState() => _TerminalSpinnerState();
}

class _TerminalSpinnerState extends State<_TerminalSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _charIndex = 0;
  static const _chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..addListener(() {
        final idx = (_ctrl.value * _chars.length).floor();
        if (idx != _charIndex) {
          setState(() {
            _charIndex = idx;
          });
        }
      })
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _chars[_charIndex % _chars.length],
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Color(0xFF5B6EF5),
      ),
    );
  }
}

// ── Screen Edges Painter (Phase 3 lines reproduction) ──────────────────────────
class _EdgePainter extends CustomPainter {
  final Color color;
  const _EdgePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];

    for (int i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      
      // Thick outer glowing line
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color.withValues(alpha: 0.14)
          ..strokeWidth = 5.0,
      );
      
      // Thin sharp inner line
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color.withValues(alpha: 0.65)
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) => oldDelegate.color != color;
}



// ── Foreground Painter for Priming (Matches GlowScreen) ──────────────────────────
