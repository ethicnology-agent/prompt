import 'local_notification_platform.dart';

/// The app-facing boundary for generic local notifications. Callers cannot
/// supply session text, server paths, tool output, or credentials.
class LocalNotificationService {
  LocalNotificationService(this._platform);

  final LocalNotificationPlatform _platform;

  factory LocalNotificationService.platform() =>
      LocalNotificationService(createLocalNotificationPlatform());

  var _enabled = false;

  /// Whether the user granted permission during this run. Nothing is ever
  /// shown before an explicit opt-in, so a denied or unavailable platform
  /// simply stays silent.
  bool get isEnabled => _enabled;

  Future<LocalNotificationPermission> requestPermission() async {
    try {
      final permission = await _platform.requestPermission();
      _enabled = permission == LocalNotificationPermission.granted;
      return permission;
    } on Exception {
      _enabled = false;
      return LocalNotificationPermission.unavailable;
    }
  }

  Future<void> showSessionCompleted() =>
      _show(SessionNotificationKind.completed);

  Future<void> showSessionFailed() => _show(SessionNotificationKind.failed);

  Future<void> _show(SessionNotificationKind kind) async {
    if (!_enabled) {
      return;
    }
    await _platform.showSessionNotification(kind);
  }
}
