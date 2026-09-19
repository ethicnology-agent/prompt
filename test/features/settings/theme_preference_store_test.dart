import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/settings/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  test(
    'a false persistence result is reported instead of treated as saved',
    () async {
      SharedPreferences.resetStatic();
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'getAll' => <String, Object>{},
          'setString' => false,
          _ => throw StateError('Unexpected fixture method'),
        },
      );
      await expectLater(
        SharedPreferencesThemePreferenceStore().save(ThemeMode.dark),
        throwsA(isA<Exception>()),
      );
    },
  );
}
