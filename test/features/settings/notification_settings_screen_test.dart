import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/platform/local_notification_service.dart';
import 'package:prompt/core/platform/local_notification_types.dart';
import 'package:prompt/features/settings/presentation/notification_settings_screen.dart';

void main() {
  testWidgets('reopening reflects existing opt-in without requesting again', (
    tester,
  ) async {
    final platform = _RecordingNotificationPlatform();
    final service = LocalNotificationService(platform);
    await service.requestPermission();
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(service: service)),
    );
    expect(find.text('Notifications are enabled.'), findsOneWidget);
    expect(platform.permissionRequests, 1);
  });

  testWidgets('requests notification permission only from enable action', (
    tester,
  ) async {
    final platform = _RecordingNotificationPlatform();
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(
          service: LocalNotificationService(platform),
        ),
      ),
    );

    expect(platform.permissionRequests, 0);
    expect(
      find.byKey(const ValueKey('notification-permission-status')),
      findsOneWidget,
    );

    await tester.tap(find.text('Enable notifications'));
    await tester.pumpAndSettle();

    expect(platform.permissionRequests, 1);
    expect(find.text('Notifications are enabled.'), findsOneWidget);
  });
}

class _RecordingNotificationPlatform implements LocalNotificationPlatform {
  var permissionRequests = 0;

  @override
  Future<LocalNotificationPermission> requestPermission() async {
    permissionRequests++;
    return LocalNotificationPermission.granted;
  }

  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {}
}
