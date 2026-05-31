enum SetupEventType { stepStart, log, stepProgress, stepDone, stepError, allDone }

class SetupEvent {
  final SetupEventType type;
  final String stepId;
  final String message;
  final bool isError;

  /// For [SetupEventType.stepProgress]:
  ///   null  → indeterminate (build / extract / unknown duration)
  ///   0–1.0 → determinate percentage (file download)
  final double? progress;

  const SetupEvent._({
    required this.type,
    required this.stepId,
    required this.message,
    this.isError = false,
    this.progress,
  });

  factory SetupEvent.stepStart(String id, String msg) =>
      SetupEvent._(type: SetupEventType.stepStart, stepId: id, message: msg);

  factory SetupEvent.log(String id, String msg, {bool error = false}) =>
      SetupEvent._(type: SetupEventType.log, stepId: id, message: msg, isError: error);

  /// [progress] — 0.0–1.0 for downloads, null for indeterminate operations.
  factory SetupEvent.stepProgress(String id, double? progress, {String label = ''}) =>
      SetupEvent._(
          type: SetupEventType.stepProgress,
          stepId: id,
          message: label,
          progress: progress);

  factory SetupEvent.stepDone(String id) =>
      SetupEvent._(type: SetupEventType.stepDone, stepId: id, message: '');

  factory SetupEvent.stepError(String id, String msg) =>
      SetupEvent._(type: SetupEventType.stepError, stepId: id, message: msg, isError: true);

  factory SetupEvent.allDone() =>
      SetupEvent._(type: SetupEventType.allDone, stepId: '', message: 'Setup complete!');
}

class SetupStep {
  final String id;
  final String title;
  bool isDone = false;
  bool isRunning = false;
  bool isError = false;
  String statusLine = '';

  SetupStep({required this.id, required this.title});
}
