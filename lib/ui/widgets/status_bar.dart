import 'package:flutter/material.dart';
import '../../providers/chat_provider.dart';

class StatusBar extends StatelessWidget {
  final AiState state;
  final String text;
  const StatusBar({super.key, required this.state, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    Color dotColor = switch (state) {
      AiState.idle        => Colors.green.shade400,
      AiState.priming     => cs.tertiary,
      AiState.recording   => Colors.red.shade400,
      AiState.transcribing => Colors.orange.shade400,
      AiState.thinking    => cs.primary,
      AiState.speaking    => Colors.purple.shade300,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          // Pulsing dot
          _PulseDot(color: dotColor, animate: state != AiState.idle),
          const SizedBox(width: 8),
          Text(text,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool animate;
  const _PulseDot({required this.color, required this.animate});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.animate
        ? FadeTransition(
            opacity: _anim,
            child: _dot(),
          )
        : _dot();
  }

  Widget _dot() => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
}
