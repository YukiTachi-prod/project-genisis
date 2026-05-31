import 'package:flutter/material.dart';
import '../../core/setup/setup_event.dart';
import '../../core/setup/setup_service.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _steps = <String, SetupStep>{
    'whisper-cli':   SetupStep(id: 'whisper-cli',   title: 'Whisper CLI'),
    'whisper-model': SetupStep(id: 'whisper-model', title: 'Whisper model (148 MB)'),
    'piper':         SetupStep(id: 'piper',         title: 'Piper TTS'),
    'piper-voice':   SetupStep(id: 'piper-voice',   title: 'Piper voice model'),
    'ollama':        SetupStep(id: 'ollama',        title: 'Ollama LLM'),
  };

  final _logs = <_LogLine>[];
  bool _allDone = false;
  bool _hasError = false;
  final _scrollCtrl = ScrollController();

  /// Progress for the currently-active step.
  /// null  → no step running (hidden bar)
  /// -1.0  → indeterminate (animated shimmer)
  /// 0–1.0 → determinate percentage
  double? _stepProgress;
  String  _stepProgressLabel = '';
  String  _stepProgressTitle = '';

  @override
  void initState() {
    super.initState();
    _runSetup();
  }

  Future<void> _runSetup() async {
    final svc = SetupService();
    // run() is an async* generator — subscribe before awaiting so no events
    // are missed, then drive it to completion.
    await for (final event in svc.run()) {
      if (!mounted) break;
      _handleEvent(event);
    }
  }

  void _handleEvent(SetupEvent e) {
    setState(() {
      switch (e.type) {
        case SetupEventType.stepStart:
          _steps[e.stepId]?.isRunning = true;
          _stepProgressTitle = _steps[e.stepId]?.title ?? e.stepId;
          _stepProgress      = -1.0; // indeterminate until first progress event
          _stepProgressLabel = '';

        case SetupEventType.log:
          _addLog(_LogLine(e.message, isError: e.isError, stepId: e.stepId));

        case SetupEventType.stepProgress:
          // progress == null → indeterminate; else 0.0–1.0
          _stepProgress      = e.progress ?? -1.0;
          _stepProgressLabel = e.message;

        case SetupEventType.stepDone:
          final s = _steps[e.stepId];
          if (s != null) {
            s.isRunning = false;
            s.isDone    = true;
          }
          _stepProgress = null; // hide step bar between steps

        case SetupEventType.stepError:
          final s = _steps[e.stepId];
          if (s != null) {
            s.isRunning = false;
            s.isError   = true;
          }
          _hasError     = true;
          _stepProgress = null;
          _addLog(_LogLine(e.message, isError: true, stepId: e.stepId));

        case SetupEventType.allDone:
          _allDone      = true;
          _stepProgress = null;
      }
    });
  }

  void _addLog(_LogLine line) {
    _logs.add(line);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final doneCount = _steps.values.where((s) => s.isDone).length;
    final progress = doneCount / _steps.length;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Icon(Icons.auto_awesome, size: 32, color: cs.primary),
              const SizedBox(width: 12),
              Text('Setting up Home AI',
                  style: tt.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(
              'Downloading and configuring all required components. '
              'This only happens once.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),

            const SizedBox(height: 32),

            // Step checklist
            ...(_steps.values.map((s) => _StepTile(step: s))),

            const SizedBox(height: 24),

            // ── Overall progress bar ──────────────────────────────────────
            Row(children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: _allDone ? 1.0 : progress,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: _hasError ? cs.error : cs.primary,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _allDone ? '✓' : '$doneCount / ${_steps.length}',
                style: tt.labelSmall?.copyWith(
                  color: _allDone ? Colors.green.shade400 : cs.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              _allDone
                  ? 'Setup complete'
                  : 'Overall — step ${doneCount + 1} of ${_steps.length}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),

            const SizedBox(height: 12),

            // ── Current-step progress bar (hidden when idle) ──────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _stepProgress == null
                  ? const SizedBox.shrink()
                  : _StepProgressBar(
                      title:    _stepProgressTitle,
                      label:    _stepProgressLabel,
                      progress: _stepProgress,
                      hasError: _hasError,
                    ),
            ),

            const SizedBox(height: 12),

            // Scrollable log
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (_, i) {
                    final l = _logs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        l.message,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: l.isError
                              ? cs.error
                              : cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Continue button (shown when done)
            if (_allDone)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onComplete,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Launch Home AI'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

            if (_hasError && !_allDone)
              Text(
                '⚠ Some steps failed. You can still continue — '
                'check the log for details.',
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final SetupStep step;
  const _StepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget icon;
    if (step.isDone) {
      icon = Icon(Icons.check_circle, color: Colors.green.shade400, size: 20);
    } else if (step.isError) {
      icon = Icon(Icons.error_outline, color: cs.error, size: 20);
    } else if (step.isRunning) {
      icon = SizedBox(
        width: 18, height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
      );
    } else {
      icon = Icon(Icons.radio_button_unchecked,
          color: cs.outlineVariant, size: 20);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 24, child: icon),
          const SizedBox(width: 12),
          Text(
            step.title,
            style: TextStyle(
              color: step.isDone
                  ? cs.onSurface
                  : step.isRunning
                      ? cs.primary
                      : cs.onSurfaceVariant,
              fontWeight:
                  step.isRunning ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step-level progress bar ────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final String  title;
  final String  label;
  /// -1.0 = indeterminate, 0.0–1.0 = determinate
  final double? progress;
  final bool    hasError;

  const _StepProgressBar({
    required this.title,
    required this.label,
    required this.progress,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isIndeterminate = progress == null || progress! < 0;
    final value           = isIndeterminate ? null : progress!.clamp(0.0, 1.0);
    final pct             = value != null ? '${(value * 100).round()}%' : '';
    final color           = hasError ? cs.error : cs.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pct.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(pct,
                  style: tt.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  )),
            ],
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value,
          backgroundColor: cs.surfaceContainerHighest,
          color: color,
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

class _LogLine {
  final String message;
  final bool isError;
  final String stepId;
  _LogLine(this.message, {this.isError = false, this.stepId = ''});
}
