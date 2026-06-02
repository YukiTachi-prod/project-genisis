import 'dart:math';
import 'package:flutter/material.dart';

/// A reusable loading screen overlay matching the Home AI monospace dark-mode aesthetic.
/// It renders the 4 orbiting glowing orbs that transition into a central rectangle,
/// then expands out to the corners when complete.
class LoadingOverlay extends StatefulWidget {
  final bool isDone;
  final String statusText;
  final String? subtitleText; // Custom subtitle text override
  final List<String>? logs;
  final VoidCallback onComplete;

  const LoadingOverlay({
    super.key,
    required this.isDone,
    required this.statusText,
    this.subtitleText,
    this.logs,
    required this.onComplete,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay> with TickerProviderStateMixin {
  late final AnimationController _orbitCtrl;
  final _logScrollCtrl = ScrollController();
  late final AnimationController _squareCtrl;
  late final AnimationController _lineCtrl;
  late final AnimationController _expandCtrl;

  List<Offset> _p3From = [];
  List<Offset> _squarePts = [];
  List<Offset> _cornerPts = [];

  late final DateTime _startTime;
  bool _transitionStarted = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();

    _orbitCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _squareCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _lineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _expandCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));

    _orbitCtrl.repeat();

    if (widget.isDone) {
      _transitionStarted = true;
      _runExitTransition();
    }
  }

  @override
  void didUpdateWidget(covariant LoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDone && !_transitionStarted) {
      _transitionStarted = true;
      _runExitTransition();
    }
    if (widget.logs != oldWidget.logs) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runExitTransition() async {
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
    const minOrbit = 1500; // minimum orbit time
    if (elapsed < minOrbit) {
      await Future.delayed(Duration(milliseconds: minOrbit - elapsed));
    }

    if (!mounted) return;

    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);
    const orbitR = 90.0;
    final angle = _orbitCtrl.value * 2 * pi;

    _p3From = List.generate(4, (i) {
      final a = angle + i * (2 * pi / 4);
      return center + Offset(cos(a) * orbitR, sin(a) * orbitR);
    });
    _orbitCtrl.stop();

    final hw = size.width * 0.13;
    final hh = size.height * 0.13;
    _squarePts = [
      center + Offset(-hw, -hh),
      center + Offset(hw, -hh),
      center + Offset(hw, hh),
      center + Offset(-hw, hh),
    ];
    _cornerPts = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];

    await _squareCtrl.forward();
    await _lineCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _expandCtrl.forward();

    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    _squareCtrl.dispose();
    _lineCtrl.dispose();
    _expandCtrl.dispose();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  List<Offset> _orbPositions(Offset center) {
    if (_p3From.isNotEmpty) {
      final sq = CurvedAnimation(parent: _squareCtrl, curve: Curves.easeInOut).value;
      final ex = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeIn).value;
      return List.generate(4, (i) {
        final mid = Offset.lerp(_p3From[i], _squarePts[i], sq)!;
        return Offset.lerp(mid, _cornerPts[i], ex)!;
      });
    }

    final angle = _orbitCtrl.value * 2 * pi;
    const orbitR = 90.0;
    return List.generate(4, (i) {
      final a = angle + i * (2 * pi / 4);
      return center + Offset(cos(a) * orbitR, sin(a) * orbitR);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);
    const orbSz = 12.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_orbitCtrl, _squareCtrl, _lineCtrl, _expandCtrl]),
      builder: (context, _) {
        final orbs = _orbPositions(center);
        final showLines = _squareCtrl.value >= 1.0;
        final lineProgress = _lineCtrl.value;

        final orbWidgets = <Widget>[];
        for (final pos in orbs) {
          orbWidgets.add(
            Positioned(
              left: pos.dx - orbSz / 2,
              top: pos.dy - orbSz / 2,
              child: Container(
                width: orbSz,
                height: orbSz,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF5B6EF5),
                  boxShadow: [
                    BoxShadow(color: Color(0xAA5B6EF5), blurRadius: 10, spreadRadius: 2),
                    BoxShadow(color: Color(0x385B6EF5), blurRadius: 24, spreadRadius: 7),
                  ],
                ),
              ),
            ),
          );
        }

        final isDownloading = widget.statusText.toUpperCase().contains('DOWNLOADING');

        Widget contentWidget;
        if (isDownloading) {
          contentWidget = Stack(
            children: [
              Align(
                alignment: const Alignment(-0.35, 0.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Downloading...',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC8D0FF),
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF5B6EF5).withValues(alpha: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 40,
                top: 80,
                bottom: 80,
                child: _TerminalBox(
                  title: 'download.progress',
                  logs: widget.logs ?? [],
                  scrollCtrl: _logScrollCtrl,
                ),
              ),
            ],
          );
        } else {
          final String subtitle;
          if (widget.subtitleText != null) {
            subtitle = widget.subtitleText!;
          } else {
            subtitle = _expandCtrl.value > 0.0
                ? 'WORKSPACE ACTIVE'
                : _squareCtrl.value >= 1.0
                    ? 'LOCKING CONFIG...'
                    : 'PRIMING KV CACHE...';
          }

          contentWidget = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.statusText.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC8D0FF),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: Color(0xFFAEB2D1),
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          );
        }

        return Material(
          color: const Color(0xEC06061A),
          child: Stack(
            children: [
              contentWidget,
              if (!isDownloading && showLines && orbs.length == 4)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ForegroundPainter(
                        p3Orbs: orbs,
                        showLines: showLines,
                        lineProgress: lineProgress,
                      ),
                    ),
                  ),
                ),
              if (!isDownloading) ...orbWidgets,
            ],
          ),
        );
      },
    );
  }
}

class _TerminalBox extends StatelessWidget {
  final String title;
  final List<String> logs;
  final ScrollController scrollCtrl;

  const _TerminalBox({
    required this.title,
    required this.logs,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 460,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xEC0A0A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF5B6EF5).withValues(alpha: 0.26),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B6EF5).withValues(alpha: 0.07),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _dot(const Color(0xFFFF5F57)),
              const SizedBox(width: 6),
              _dot(const Color(0xFFFFBD2E)),
              const SizedBox(width: 6),
              _dot(const Color(0xFF28C840)),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFAEB2D1),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: logs.map((l) => _LogLine(l)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

class _LogLine extends StatelessWidget {
  final String text;
  const _LogLine(this.text);

  @override
  Widget build(BuildContext context) {
    Color color = const Color(0xFFD0D0E5);
    if (text.contains('[ OK')) color = const Color(0xFF28C840);
    if (text.contains('[ WRN')) color = const Color(0xFFFFBD2E);
    if (text.contains('[ ERR')) color = const Color(0xFFFF5F57);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: color,
        ),
      ),
    );
  }
}

class _ForegroundPainter extends CustomPainter {
  final List<Offset> p3Orbs;
  final bool         showLines;
  final double       lineProgress;
  const _ForegroundPainter({
    required this.p3Orbs,
    required this.showLines,
    required this.lineProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showLines) return;

    final cx = p3Orbs.fold(0.0, (s, o) => s + o.dx) / 4;
    final cy = p3Orbs.fold(0.0, (s, o) => s + o.dy) / 4;
    final sorted = [...p3Orbs]..sort((a, b) =>
        atan2(a.dy - cy, a.dx - cx).compareTo(atan2(b.dy - cy, b.dx - cx)));

    final path = Path()
      ..moveTo(sorted[0].dx, sorted[0].dy)
      ..lineTo(sorted[1].dx, sorted[1].dy)
      ..lineTo(sorted[2].dx, sorted[2].dy)
      ..lineTo(sorted[3].dx, sorted[3].dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF06061A).withValues(alpha: lineProgress));

    final glowPaint = Paint()
      ..color       = const Color(0xFF5B6EF5).withValues(alpha: 0.14)
      ..strokeWidth = 5.0;

    final linePaint = Paint()
      ..color       = const Color(0xFF5B6EF5).withValues(alpha: 0.65)
      ..strokeWidth = 1.0;

    for (int i = 0; i < 4; i++) {
      final a = sorted[i];
      final b = sorted[(i + 1) % 4];

      final mid = Offset.lerp(a, b, 0.5)!;
      final endA = Offset.lerp(a, mid, lineProgress)!;
      final endB = Offset.lerp(b, mid, lineProgress)!;

      canvas.drawLine(a, endA, glowPaint);
      canvas.drawLine(b, endB, glowPaint);

      canvas.drawLine(a, endA, linePaint);
      canvas.drawLine(b, endB, linePaint);
    }
  }

  @override
  bool shouldRepaint(_ForegroundPainter o) => o.lineProgress != lineProgress || o.showLines != showLines;
}
