import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';

void main() {
  final origin = Uri.parse('http://10.0.0.1:4096');
  ServerProfile profile(AgentBackend backend) =>
      ServerProfile(origin: origin, username: 'prompt', backend: backend);

  test(
    'legacy IDs unchanged and each backend isolates queue and credentials',
    () {
      expect(
        profile(AgentBackend.directOpenCode).id,
        sha256.convert(utf8.encode('$origin\u0000prompt')).toString(),
      );
      expect(
        AgentBackend.values.map((backend) => profile(backend).id).toSet(),
        hasLength(4),
      );
      expect(
        profile(
          AgentBackend.gatewayClaude,
        ).capabilities.supports(BackendFeature.text),
        isFalse,
      );
    },
  );

  test('routes gateway requests and SSE within engine namespace', () async {
    final paths = <String>[];
    final transport = OpenCodeTransport(
      MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );
    await transport.get(
      profile(AgentBackend.gatewayClaude),
      'token',
      '/session',
    );
    await transport.send(
      profile(AgentBackend.gatewayCodex),
      'token',
      '/global/event',
    );
    await transport.get(
      profile(AgentBackend.gatewayOpenCode),
      'token',
      '/prompt/capabilities',
    );
    await transport.get(
      profile(AgentBackend.directOpenCode),
      'token',
      '/session',
    );
    expect(paths, [
      '/prompt/claude/session',
      '/prompt/codex/global/event',
      '/prompt/capabilities',
      '/session',
    ]);
  });

  test(
    'refuses absolute or authority paths before transmitting credentials',
    () {
      final transport = OpenCodeTransport(
        MockClient((_) async {
          fail('Must not transmit');
        }),
      );
      for (final path in [
        'https://example.com/session',
        '//example.com/session',
        'session',
        '/%2e%2e/session',
        '/session/%252e%252e/global/health',
        '/session/%2e%2e%2fglobal/health',
        '/session/%5cglobal',
        '/session/%0aAuthorization',
        '/session/\u0000',
      ]) {
        expect(
          () =>
              transport.get(profile(AgentBackend.gatewayCodex), 'token', path),
          throwsA(isA<InvalidOpenCodeOrigin>()),
        );
      }
    },
  );

  test(
    'REST and SSE never follow redirect responses carrying credentials',
    () async {
      final methods = <String>[];
      final transport = OpenCodeTransport(
        MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], isNotEmpty);
          expect(request.url.host, '10.0.0.1');
          methods.add(request.method);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.com'},
          );
        }),
      );
      final selected = profile(AgentBackend.gatewayCodex);
      expect(
        (await transport.get(selected, 'token', '/session')).statusCode,
        302,
      );
      expect(
        (await transport.post(
          selected,
          'token',
          '/session',
          body: '{}',
        )).statusCode,
        302,
      );
      expect(
        (await transport.patch(
          selected,
          'token',
          '/session/x',
          body: '{}',
        )).statusCode,
        302,
      );
      expect(
        (await transport.delete(selected, 'token', '/session/x')).statusCode,
        302,
      );
      expect(
        (await transport.send(selected, 'token', '/global/event')).statusCode,
        302,
      );
      expect(methods, ['GET', 'POST', 'PATCH', 'DELETE', 'GET']);
    },
  );

  test('only recognized advertised capabilities are enabled', () async {
    final health = OpenCodeHealthService(
      OpenCodeTransport(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'protocolVersion': 1,
              'engines': {
                'claude': {
                  'available': true,
                  'features': [
                    'sessions',
                    'text',
                    'abort',
                    'permissions',
                    'futureFeature',
                  ],
                },
              },
            }),
            200,
          ),
        ),
      ),
    );
    final capabilities = await health.checkCapabilities(
      profile(AgentBackend.gatewayClaude),
      'token',
    );
    expect(capabilities?.supports(BackendFeature.text), isTrue);
    expect(capabilities?.supports(BackendFeature.attachments), isFalse);
    expect(capabilities?.supports(BackendFeature.terminal), isFalse);
  });

  test(
    'missing engine, unknown protocol, unavailable and incomplete fail closed',
    () async {
      for (final body in [
        {},
        {'protocolVersion': 2, 'engines': {}},
        {
          'protocolVersion': 1,
          'engines': {
            'claude': {
              'available': false,
              'features': ['sessions', 'text', 'abort'],
            },
          },
        },
        {
          'protocolVersion': 1,
          'engines': {
            'claude': {
              'available': true,
              'features': ['text'],
            },
          },
        },
      ]) {
        final health = OpenCodeHealthService(
          OpenCodeTransport(
            MockClient((_) async => http.Response(jsonEncode(body), 200)),
          ),
        );
        expect(
          await health.checkCapabilities(
            profile(AgentBackend.gatewayClaude),
            'token',
          ),
          isNull,
        );
      }
    },
  );
}
