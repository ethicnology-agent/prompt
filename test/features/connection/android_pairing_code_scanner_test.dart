import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/connection/data/pairing_code_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('me.ethicnology.prompt/pairing');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the decoded value from one explicit scan', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          expect(call.method, 'scan');
          return 'prompt://connect?fixture';
        });

    final result = await const AndroidPairingCodeScanner().scan();

    expect(calls, 1);
    expect(result, isA<PairingScanCompleted>());
    expect((result as PairingScanCompleted).value, 'prompt://connect?fixture');
  });

  test('maps cancellation without manufacturing an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(
      await const AndroidPairingCodeScanner().scan(),
      isA<PairingScanCancelled>(),
    );
  });

  test(
    'maps platform failures and oversized values without exposing them',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
              code: 'scanner_unavailable',
              message: 'synthetic-sensitive-provider-message',
            ),
          );

      expect(
        await const AndroidPairingCodeScanner().scan(),
        isA<PairingScanUnavailable>(),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => List.filled(2049, 'x').join(),
          );
      expect(
        await const AndroidPairingCodeScanner().scan(),
        isA<PairingScanUnavailable>(),
      );
    },
  );

  test(
    'maps an explicit camera denial without exposing platform details',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
              code: 'camera_permission_denied',
              message: 'synthetic-sensitive-provider-message',
            ),
          );

      expect(
        await const AndroidPairingCodeScanner().scan(),
        isA<PairingScanPermissionDenied>(),
      );
    },
  );
}
