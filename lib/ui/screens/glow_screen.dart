import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/setup/setup_event.dart';
import '../../core/setup/setup_service.dart';
import '../../providers/chat_provider.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _bg      = Color(0xFF06061A);
const _accent  = Color(0xFF5B6EF5);
const _gRadius = 44.0;
const _orbitR  = 90.0;
const _orbSz   = 12.0;
const _nOrbs   = 4;

enum _Phase { idle, rippling, phase1, phase2, phase3 }

// ── GlowScreen ─────────────────────────────────────────────────────────────────

class GlowScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const GlowScreen({super.key, required this.onComplete});

  @override
  State<GlowScreen> createState() => _GlowScreenState();
}

class _GlowScreenState extends State<GlowScreen> with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;

  late final AnimationController _rippleCtrl;
  late final AnimationController _orbitCtrl;
  late final AnimationController _termCtrl;
  late final AnimationController _squareCtrl;
  late final AnimationController _lineCtrl;
  late final AnimationController _expandCtrl;

  List<Offset> _p3From    = [];
  List<Offset> _squarePts = [];
  List<Offset> _cornerPts = [];

  // Right terminal — LLM personality warm-up
  final List<String> _logs      = [];
  final _logScroll               = ScrollController();
  final _primingDone             = Completer<void>();

  // Left terminal — dependency / setup check
  final List<String> _sysLogs   = [];
  final _sysLogScroll            = ScrollController();
  final _depsDone                = Completer<void>();

  bool  _primingStarted          = false;
  bool  _gHovered                = false;

  // Tracks mouse position for grid warp; Offset far off-screen = no warp.
  final _mousePos = ValueNotifier<Offset>(const Offset(-9999, -9999));

  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _orbitCtrl  = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _termCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _squareCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _lineCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _expandCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _orbitCtrl.dispose();
    _termCtrl.dispose();
    _squareCtrl.dispose();
    _lineCtrl.dispose();
    _expandCtrl.dispose();
    _logScroll.dispose();
    _sysLogScroll.dispose();
    _mousePos.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<Offset> _allOrbPositions(Offset center) {
    final angle = _orbitCtrl.value * 2 * pi;
    return List.generate(_nOrbs, (i) {
      final a = angle + i * (2 * pi / _nOrbs);
      return center + Offset(cos(a) * _orbitR, sin(a) * _orbitR);
    });
  }

  List<Offset> _phase3OrbPositions() {
    if (_p3From.isEmpty || _squarePts.isEmpty) return [];
    final sq = CurvedAnimation(parent: _squareCtrl, curve: Curves.easeInOut).value;
    final ex = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeIn).value;
    return List.generate(4, (i) {
      final mid = Offset.lerp(_p3From[i], _squarePts[i], sq)!;
      return Offset.lerp(mid, _cornerPts[i], ex)!;
    });
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() => _logs.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addSysLog(String msg) {
    if (!mounted) return;
    setState(() => _sysLogs.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sysLogScroll.hasClients) {
        _sysLogScroll.animateTo(
          _sysLogScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runSystemCheck() async {
    _addSysLog('[ SYS ] Checking dependencies...');
    await Future.delayed(const Duration(milliseconds: 350));
    try {
      await for (final e in SetupService().run()) {
        final line = _eventToLog(e);
        if (line != null) _addSysLog(line);
      }
    } catch (e) {
      _addSysLog('[ ERR ] Setup error: $e');
    }
    if (!_depsDone.isCompleted) _depsDone.complete();
  }

  static String? _eventToLog(SetupEvent e) => switch (e.type) {
    SetupEventType.stepStart    => '[ SYS ] ${e.message}',
    SetupEventType.log          => e.isError
        ? '[ WRN ] ${e.message}'
        : '       ${e.message}',
    SetupEventType.stepProgress => e.message.isNotEmpty
        ? '       ${e.message}'
        : null,
    SetupEventType.stepDone     => '[ OK  ] ${e.stepId}',
    SetupEventType.stepError    => '[ ERR ] ${e.message}',
    SetupEventType.allDone      => '[ OK  ] All systems ready',
  };

  // ── Sequence ───────────────────────────────────────────────────────────────

  Future<void> _onTap() async {
    if (_phase != _Phase.idle) return;
    final size   = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);

    if (!_primingStarted) {
      _primingStarted = true;
      _runLoading();
      _runSystemCheck();
    }

    // Terminal starts sliding in immediately on tap.
    _termCtrl.forward();

    // ── Ripple ──────────────────────────────────────────────────────────────
    setState(() => _phase = _Phase.rippling);
    await _rippleCtrl.forward();

    // ── Phase 1: 4 orbs orbit for 3 s ───────────────────────────────────────
    setState(() => _phase = _Phase.phase1);
    _orbitCtrl.repeat();
    await Future.delayed(const Duration(seconds: 3));

    // ── Phase 2: wait for LLM ────────────────────────────────────────────────
    setState(() => _phase = _Phase.phase2);

    // Wait for both LLM warm-up and dependency check to finish.
    await Future.wait([_primingDone.future, _depsDone.future]);
    await Future.delayed(const Duration(milliseconds: 700));

    // ── Phase 3: snapshot orb positions → square → expand ───────────────────
    _p3From = _allOrbPositions(center); // all 4 orbs go to rectangle corners
    _orbitCtrl.stop();

    final hw = size.width  * 0.13;
    final hh = size.height * 0.13;
    _squarePts = [
      center + Offset(-hw, -hh),
      center + Offset( hw, -hh),
      center + Offset( hw,  hh),
      center + Offset(-hw,  hh),
    ];
    _cornerPts = [
      Offset.zero,
      Offset(size.width,  0),
      Offset(size.width,  size.height),
      Offset(0,           size.height),
    ];

    setState(() => _phase = _Phase.phase3);
    await _squareCtrl.forward();
    await _lineCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    await _expandCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 120));

    widget.onComplete();
  }

  Future<void> _runLoading() async {
    final chat = context.read<ChatProvider>();
    _addLog('[ SYS ] Initializing personality engine...');
    await Future.delayed(const Duration(milliseconds: 480));
    _addLog('[ LLM ] Loading model: ${chat.config.llmModel}');

    final llmFuture = chat.warmUpForIntro();

    await Future.delayed(const Duration(milliseconds: 900));
    _addLog('[ INF ] Processing system prompt...');
    await Future.delayed(const Duration(milliseconds: 720));
    _addLog('[ INF ] Warming KV cache...');

    try {
      await llmFuture;
      _addLog('[ OK  ] Personality ready');
    } catch (_) {
      _addLog('[ WRN ] Ollama unavailable — continuing offline');
    }

    if (!_primingDone.isCompleted) _primingDone.complete();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);

    return MouseRegion(
      onHover: (e) => _mousePos.value = e.localPosition,
      onExit:  (_) => _mousePos.value = const Offset(-9999, -9999),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _rippleCtrl, _orbitCtrl, _termCtrl,
          _squareCtrl, _lineCtrl, _expandCtrl, _mousePos,
        ]),
        builder: (ctx, _) => _buildContent(ctx, size, center),
      ),
    );
  }

  Widget _buildContent(BuildContext ctx, Size size, Offset center) {
    final allOrbs = (_phase == _Phase.phase1 || _phase == _Phase.phase2)
        ? _allOrbPositions(center)
        : <Offset>[];
    final p3Orbs  = _phase == _Phase.phase3 ? _phase3OrbPositions() : <Offset>[];
    final termT   = CurvedAnimation(parent: _termCtrl, curve: Curves.easeOut).value;

    final children = <Widget>[
      // ── Grid background (always visible, warps with mouse) ────────────────
      Positioned.fill(
        child: CustomPaint(
          painter: _GridPainter(
            phase:    _phase,
            center:   center,
            mousePos: _mousePos.value,
            rippleT:  _rippleCtrl.value,
          ),
        ),
      ),

      // ── Central G button (idle + rippling only) ───────────────────────────
      if (_phase == _Phase.idle || _phase == _Phase.rippling)
        Positioned(
          left: center.dx - _gRadius,
          top:  center.dy - _gRadius,
          child: MouseRegion(
            onEnter: (_) => setState(() => _gHovered = true),
            onExit:  (_) => setState(() => _gHovered = false),
            cursor:  SystemMouseCursors.click,
            child: AnimatedScale(
              scale:    _gHovered ? 1.14 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve:    Curves.easeOut,
              child: GestureDetector(onTap: _onTap, child: const _GCircle()),
            ),
          ),
        ),
    ];

    // ── Orbiting orbs (phases 1 & 2) ────────────────────────────────────────
    for (int i = 0; i < allOrbs.length; i++) {
      children.add(_OrbWidget(position: allOrbs[i], index: i));
    }

    // ── Terminals: slide in simultaneously from opposite edges on tap ─────────
    if (_phase != _Phase.idle && termT > 0) {
      final t = termT.clamp(0.0, 1.0);

      // Left terminal — system.check (slides in from the left edge)
      children.add(
        Positioned(
          left: 20,
          top:  90,
          child: Transform.translate(
            offset: Offset(-(1 - t) * 500, 0),
            child: Opacity(
              opacity: t,
              child: _TerminalBox(
                title:      'system.check',
                logs:       _sysLogs,
                scrollCtrl: _sysLogScroll,
              ),
            ),
          ),
        ),
      );

      // Right terminal — personality.init (slides in from the right edge)
      children.add(
        Positioned(
          right: 20,
          top:   90,
          child: Transform.translate(
            offset: Offset((1 - t) * 500, 0),
            child: Opacity(
              opacity: t,
              child: _TerminalBox(
                title:      'personality.init',
                logs:       _logs,
                scrollCtrl: _logScroll,
              ),
            ),
          ),
        ),
      );
    }

    // ── Phase 3 layers ────────────────────────────────────────────────────────
    if (_phase == _Phase.phase3 && p3Orbs.length == 4) {
      // Edges only appear once the square animation has fully completed.
      final showLines = _squareCtrl.value >= 1.0;

      // Fill (always) + lines (only after orbs reach their positions).
      children.add(
        Positioned.fill(
          child: CustomPaint(
            painter: _ForegroundPainter(
              p3Orbs: p3Orbs,
              showLines: showLines,
              lineProgress: _lineCtrl.value,
            ),
          ),
        ),
      );

      // Animated orbs (0-3) rendered above the fill
      for (int i = 0; i < p3Orbs.length; i++) {
        children.add(_OrbWidget(position: p3Orbs[i], index: i));
      }
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: children),
    );
  }
}

// ── Grid Painter ───────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final _Phase  phase;
  final Offset  center;
  final Offset  mousePos;
  final double  rippleT;

  // Grid appearance
  static const _gs    = 55.0;   // cell spacing
  static const _maxD  = 16.0;   // max mouse warp displacement
  static const _fallR = 130.0;  // warp falloff radius
  static const _fadeZ = 150.0;  // edge fade zone width
  static const _baseA = 0.18;   // peak grid opacity (at screen centre)

  const _GridPainter({
    required this.phase,
    required this.center,
    required this.mousePos,
    required this.rippleT,
  });

  // Push a grid point away from the mouse cursor.
  Offset _warp(Offset pt) {
    final d    = pt - mousePos;
    final dist = d.distance;
    if (dist <= 0 || dist >= _fallR) return pt;
    return pt + (d / dist) * (_maxD * (1 - dist / _fallR));
  }

  // Opacity: full in the centre, fades to 0 near each edge.
  double _edgeAlpha(Offset pt, Size size) {
    final nearest = min(
      min(pt.dx, size.width  - pt.dx),
      min(pt.dy, size.height - pt.dy),
    );
    return (nearest / _fadeZ).clamp(0.0, 1.0) * _baseA;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (phase == _Phase.rippling) _paintRipple(canvas);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final cols = (size.width  / _gs).ceil() + 1;
    final rows = (size.height / _gs).ceil() + 1;
    final ox   = (size.width  % _gs) / 2;
    final oy   = (size.height % _gs) / 2;

    // Precompute displaced positions and edge opacities for every grid vertex.
    final pts = List.generate(rows + 1, (j) =>
        List.generate(cols + 1, (i) =>
            _warp(Offset(ox + i * _gs, oy + j * _gs))));
    final ops = List.generate(rows + 1, (j) =>
        List.generate(cols + 1, (i) =>
            _edgeAlpha(Offset(ox + i * _gs, oy + j * _gs), size)));

    final paint = Paint()..strokeWidth = 0.5;

    // Horizontal segments
    for (int j = 0; j <= rows; j++) {
      for (int i = 0; i < cols; i++) {
        final a = (ops[j][i] + ops[j][i + 1]) / 2;
        if (a < 0.004) continue;
        paint.color = _accent.withValues(alpha: a);
        canvas.drawLine(pts[j][i], pts[j][i + 1], paint);
      }
    }

    // Vertical segments
    for (int i = 0; i <= cols; i++) {
      for (int j = 0; j < rows; j++) {
        final a = (ops[j][i] + ops[j + 1][i]) / 2;
        if (a < 0.004) continue;
        paint.color = _accent.withValues(alpha: a);
        canvas.drawLine(pts[j][i], pts[j + 1][i], paint);
      }
    }
  }

  void _paintRipple(Canvas canvas) {
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.18;
      final t     = ((rippleT - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      canvas.drawCircle(
        center,
        _gRadius + t * 210,
        Paint()
          ..color       = _accent.withValues(alpha: (1 - t) * 0.70)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.mousePos != mousePos || o.rippleT != rippleT || o.phase != phase;
}

// ── Foreground Painter (phase 3: fill rectangle + glowing edges) ───────────────

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
    // Skip during squareCtrl animation — orbs aren't settled yet, so connecting
    // them in index order creates a self-intersecting (bow-tie) polygon.
    if (!showLines) return;

    // Sort clockwise by angle from centroid so the polygon is always convex
    // regardless of which orbit position maps to which corner index.
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
    canvas.drawPath(path, Paint()..color = _bg.withValues(alpha: lineProgress));

    final glowPaint = Paint()
      ..color       = _accent.withValues(alpha: 0.14)
      ..strokeWidth = 5.0;

    final linePaint = Paint()
      ..color       = _accent.withValues(alpha: 0.65)
      ..strokeWidth = 1.0;

    for (int i = 0; i < 4; i++) {
      final a = sorted[i];
      final b = sorted[(i + 1) % 4];
      
      final mid = Offset.lerp(a, b, 0.5)!;
      final endA = Offset.lerp(a, mid, lineProgress)!;
      final endB = Offset.lerp(b, mid, lineProgress)!;

      // Draw thick glow segments
      canvas.drawLine(a, endA, glowPaint);
      canvas.drawLine(b, endB, glowPaint);

      // Draw thin sharp segments
      canvas.drawLine(a, endA, linePaint);
      canvas.drawLine(b, endB, linePaint);
    }
  }

  @override
  bool shouldRepaint(_ForegroundPainter o) => o.lineProgress != lineProgress || o.showLines != showLines;
}

// ── G Circle ───────────────────────────────────────────────────────────────────

class _GCircle extends StatelessWidget {
  const _GCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  _gRadius * 2,
      height: _gRadius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF11113A),
        border: Border.all(color: const Color(0xFF5B6EF5), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x735B6EF5), blurRadius: 24, spreadRadius: 4),
          BoxShadow(color: Color(0x265B6EF5), blurRadius: 52, spreadRadius: 14),
        ],
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            color:         Colors.white,
            fontSize:      30,
            fontWeight:    FontWeight.w300,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}

// ── Orb Widget ─────────────────────────────────────────────────────────────────

class _OrbWidget extends StatelessWidget {
  final Offset position;
  final int    index;
  const _OrbWidget({required this.position, required this.index});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - _orbSz / 2,
      top:  position.dy - _orbSz / 2,
      child: Container(
        width:  _orbSz,
        height: _orbSz,
        decoration: const BoxDecoration(
          shape:     BoxShape.circle,
          color:     _accent,
          boxShadow: [
            BoxShadow(color: Color(0xAA5B6EF5), blurRadius: 10, spreadRadius: 2),
            BoxShadow(color: Color(0x385B6EF5), blurRadius: 24, spreadRadius: 7),
          ],
        ),
      ),
    );
  }
}

// ── Terminal Box ───────────────────────────────────────────────────────────────

class _TerminalBox extends StatelessWidget {
  final String           title;
  final List<String>     logs;
  final ScrollController scrollCtrl;
  const _TerminalBox({
    required this.title,
    required this.logs,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 480,
      constraints: const BoxConstraints(maxHeight: 360),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        const Color(0xDA0A0A1E),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
          color: const Color(0xFF5B6EF5).withValues(alpha: 0.26),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color:        const Color(0xFF5B6EF5).withValues(alpha: 0.07),
            blurRadius:   28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:       MainAxisSize.min,
        children: [
          // macOS-style traffic lights + window title
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
                  color:      Color(0xFFAEB2D1),
                  fontSize:   11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
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
        width:  8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

// ── Log Line ───────────────────────────────────────────────────────────────────

class _LogLine extends StatelessWidget {
  final String text;
  const _LogLine(this.text);

  @override
  Widget build(BuildContext context) {
    Color color = const Color(0xFFD0D0E5);
    if (text.contains('[ OK'))  color = const Color(0xFF28C840);
    if (text.contains('[ WRN')) color = const Color(0xFFFFBD2E);
    if (text.contains('[ ERR')) color = const Color(0xFFFF5F57);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color:      color,
          fontSize:   11,
          fontFamily: 'monospace',
          height:     1.4,
        ),
      ),
    );
  }
}
