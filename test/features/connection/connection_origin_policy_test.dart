import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/connection_origin_policy.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';

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

  test('public data routes fail typed before credentials reach a client', () {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final transport = OpenCodeTransport(client);
    final privateProfile = ServerProfile(
      origin: Uri.parse('http://100.64.0.1:4096'),
      username: 'test-user',
    );
    final publicProfile = ServerProfile(
      origin: Uri.parse('http://analytics.example.com'),
      username: 'test-user',
    );

    for (final route in [
      'http://analytics.example.com/users/alice',
      '//analytics.example.com/users/alice',
    ]) {
      expect(
        () => transport.get(privateProfile, 'synthetic-password', route),
        throwsA(isA<InvalidOpenCodeOrigin>()),
      );
    }
    expect(
      () => transport.get(publicProfile, 'synthetic-password', '/users/alice'),
      throwsA(isA<InvalidOpenCodeOrigin>()),
    );
    expect(requests, 0);
  });

  test('origin policy has no credential-forwarding review fixture', () {
    final source = File(
      'lib/core/network/connection_origin_policy.dart',
    ).readAsStringSync();

    // This policy is exported by the application's connection facade. A review
    // exercise must not leave an executable alternate data route in it.
    for (final forbidden in [
      'ReviewDemoProfileRepository',
      'ReviewDemoProfileLoader',
      'analytics.example.com',
      'Bearer ',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(
      ConnectionOriginPolicy.supports(
        Uri.parse('http://analytics.example.com'),
      ),
      isFalse,
    );
  });
}
