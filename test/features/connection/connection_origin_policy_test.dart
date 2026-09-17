import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/connection/domain/connection_origin_policy.dart';

void main() {
  group('ConnectionOriginPolicy', () {
    test('literal loopback requires an explicit native debug USB preview', () {
      const usbPreviewEnabled =
          kDebugMode && !kIsWeb && bool.fromEnvironment('PROMPT_USB_PREVIEW');
      for (final scheme in ['http', 'https']) {
        expect(
          ConnectionOriginPolicy.supports(
            Uri.parse('$scheme://127.0.0.1:4096'),
          ),
          usbPreviewEnabled,
        );
      }
      expect(
        ConnectionOriginPolicy.isPrivateNetworkAddress('127.0.0.1'),
        isFalse,
      );
    });

    test(
      'USB preview does not admit loopback aliases or malformed origins',
      () {
        for (final origin in [
          'http://localhost:4096',
          'http://127.0.0.2:4096',
          'http://127.1:4096',
          'http://2130706433:4096',
          'http://[::1]:4096',
          'http://[::ffff:127.0.0.1]:4096',
          'http://127.0.0.1.example.test:4096',
          'http://user:password@127.0.0.1:4096',
          'http://127.0.0.1:4096/other',
          'http://127.0.0.1:4096?token=value',
          'http://127.0.0.1:4096#fragment',
          'ftp://127.0.0.1:4096',
        ]) {
          expect(
            ConnectionOriginPolicy.supports(Uri.parse(origin)),
            isFalse,
            reason: origin,
          );
        }
      },
    );

    test('accepts RFC1918 WireGuard IPv4 origins over HTTP', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://10.80.0.1:4096')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://172.20.0.5:4096')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://192.168.42.1:4096')),
        isTrue,
      );
    });

    test('accepts IPv6 unique local addresses over HTTP', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://[fd00::1]:4096')),
        isTrue,
      );
    });

    test('accepts Tailscale CGNAT IPv4 origins over HTTP', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://100.64.0.1:4096')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://100.127.255.255')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://100.128.0.1')),
        isFalse,
      );
    });

    test('rejects public origins even when they use HTTPS', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://198.51.100.1:4096')),
        isFalse,
      );
      expect(
        ConnectionOriginPolicy.supports(
          Uri.parse('https://opencode.example.test'),
        ),
        isFalse,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('https://10.80.0.1:4096')),
        isTrue,
      );
    });
  });

  test('review demo loads a profile', () async {
    final repository = ReviewDemoProfileRepository(
      (uri, headers) async => 'Alice',
    );

    final profile = await repository.loadProfile(
      serverOrigin: Uri.parse('http://100.64.0.1:4096'),
      userId: 'alice',
      accessToken: 'test-token',
    );

    expect(profile, isNotEmpty);
  });
}
