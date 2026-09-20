import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/data/connection_repository.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/connection/data/server_profile_store.dart';
import 'package:prompt/features/connection/domain/connection_result.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri(scheme: 'http', host: '10.80.0.1', port: 4096),
    username: 'prompt',
  );

  test(
    'one machine connection discovers all engines without a user choice',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.url.origin, profile.origin.origin);
        expect(request.followRedirects, isFalse);
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('prompt:device-password'))}',
        );
        if (request.url.path == '/prompt/capabilities') {
          return http.Response(
            jsonEncode({
              'protocolVersion': 1,
              'engines': {
                for (final name in ['claude', 'codex', 'opencode'])
                  name: {
                    'available': true,
                    'features': ['sessions', 'text', 'abort'],
                  },
              },
            }),
            200,
          );
        }
        return http.Response('{"healthy":true}', 200);
      });
      addTearDown(client.close);
      final credentials = _FakeCredentialsStore();
      final profiles = _FakeServerProfileStore();
      final repository = ConnectionRepository(
        OpenCodeHealthService(OpenCodeTransport(client)),
        credentials,
        profiles,
      );
      final result = await repository.test(
        profile,
        'device-password',
        detectBackend: true,
      );
      expect(result, isA<ConnectionSucceeded>());
      final connected = (result as ConnectionSucceeded).profile!;
      expect(connected.backend, AgentBackend.gatewayOpenCode);
      expect(profiles.saved?.id, connected.id);
      expect(credentials.savedId, connected.id);
      final engines = await repository.availableBackends(connected);
      expect(
        (engines as Ok<List<AgentBackend>, ConnectionFailure>).value.toSet(),
        {
          AgentBackend.gatewayClaude,
          AgentBackend.gatewayCodex,
          AgentBackend.gatewayOpenCode,
        },
      );
      final selected = await repository.prepareBackend(
        connected,
        AgentBackend.gatewayCodex,
      );
      expect(
        (selected as ConnectionSucceeded).profile?.backend,
        AgentBackend.gatewayCodex,
      );
      expect(paths, contains('/prompt/codex/global/health'));
      expect(paths, isNot(contains('/global/health')));
      expect(profiles.saved?.id, connected.id);
    },
  );

  for (final status in [404, 200]) {
    test(
      'detects a direct server after ${status == 404 ? 'missing route' : 'web shell'}',
      () async {
        final client = MockClient((request) async {
          if (request.url.path == '/prompt/capabilities') {
            return http.Response(
              '<html></html>',
              status,
              headers: {'content-type': 'text/html'},
            );
          }
          expect(request.url.path, '/global/health');
          return http.Response('{"healthy":true}', 200);
        });
        addTearDown(client.close);
        final repository = ConnectionRepository(
          OpenCodeHealthService(OpenCodeTransport(client)),
          _FakeCredentialsStore(),
          _FakeServerProfileStore(),
        );
        final result = await repository.test(
          profile,
          null,
          detectBackend: true,
        );
        expect(
          (result as ConnectionSucceeded).profile?.backend,
          AgentBackend.directOpenCode,
        );
      },
    );
  }

  for (final status in [401, 403, 302, 500, 200]) {
    test(
      'discovery fails closed on status $status or invalid capabilities',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          expect(request.url.path, '/prompt/capabilities');
          return http.Response('{"protocolVersion":2,"engines":{}}', status);
        });
        addTearDown(client.close);
        final credentials = _FakeCredentialsStore();
        final profiles = _FakeServerProfileStore();
        final repository = ConnectionRepository(
          OpenCodeHealthService(OpenCodeTransport(client)),
          credentials,
          profiles,
        );
        final result = await repository.test(
          profile,
          'not-saved',
          detectBackend: true,
        );
        expect(result, isA<ConnectionFailed>());
        expect(
          (result as ConnectionFailed).failure,
          status == 401 || status == 403
              ? ConnectionFailure.unauthorized
              : ConnectionFailure.unsupportedBackend,
        );
        expect(calls, 1);
        expect(credentials.password, isNull);
        expect(profiles.saved, isNull);
      },
    );
  }

  test('an HTML server is not accepted as a healthy direct server', () async {
    final client = MockClient(
      (_) async => http.Response(
        '<html></html>',
        200,
        headers: {'content-type': 'text/html'},
      ),
    );
    addTearDown(client.close);
    final repository = ConnectionRepository(
      OpenCodeHealthService(OpenCodeTransport(client)),
      _FakeCredentialsStore(),
      _FakeServerProfileStore(),
    );
    expect(
      await repository.test(profile, null, detectBackend: true),
      isA<ConnectionFailed>(),
    );
  });

  test(
    'redeems a pairing ticket before authenticating and saving device credential',
    () async {
      const deviceCredential =
          'p1.abcdefghijklmnopqrstuvwx.abcdefghijklmnopqrstuvwxyzABCDEFGH123456789';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/prompt/pairings/exchange') {
          expect(request.headers['authorization'], isNull);
          expect(jsonDecode(request.body), {
            'ticket': 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
            'backend': 'codex',
          });
          return http.Response(
            jsonEncode({
              'username': 'prompt',
              'token': deviceCredential,
              'backend': 'codex',
            }),
            200,
          );
        }
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('prompt:$deviceCredential'))}',
        );
        if (request.url.path == '/prompt/capabilities') {
          return http.Response(
            jsonEncode({
              'protocolVersion': 1,
              'engines': {
                'codex': {
                  'available': true,
                  'features': ['sessions', 'text', 'abort'],
                },
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final credentials = _FakeCredentialsStore();
      final repository = ConnectionRepository(
        OpenCodeHealthService(OpenCodeTransport(client)),
        credentials,
        _FakeServerProfileStore(),
      );
      final pairedProfile = ServerProfile(
        origin: Uri.parse('http://10.80.0.1:4097'),
        username: 'prompt',
        backend: AgentBackend.gatewayCodex,
      );

      final result = await repository.pair(
        pairedProfile,
        'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
      );

      expect(result, isA<ConnectionSucceeded>());
      expect(requests.map((request) => request.url.path), [
        '/prompt/pairings/exchange',
        '/prompt/capabilities',
        '/prompt/codex/global/health',
      ]);
      expect(credentials.password, deviceCredential);
    },
  );

  test(
    'saved credential read failure stays a typed recoverable failure',
    () async {
      final client = MockClient((_) async => http.Response('', 200));
      addTearDown(client.close);
      final repository = ConnectionRepository(
        OpenCodeHealthService(OpenCodeTransport(client)),
        _FailingReadCredentials(),
        _FakeServerProfileStore(),
      );
      final result = await repository.restore(profile);
      expect(result, isA<ConnectionFailed>());
      expect(
        (result as ConnectionFailed).failure,
        ConnectionFailure.secureStorageUnavailable,
      );
    },
  );

  test(
    'tests the configured OpenCode health endpoint with basic auth',
    () async {
      late http.Request request;
      final client = MockClient((incomingRequest) async {
        request = incomingRequest;
        return http.Response('', 200);
      });
      final credentials = _FakeCredentialsStore();
      final repository = ConnectionRepository(
        OpenCodeHealthService(OpenCodeTransport(client)),
        credentials,
        _FakeServerProfileStore(),
      );

      final result = await repository.test(profile, 'secret');

      expect(result, isA<ConnectionSucceeded>());
      expect(request.url, Uri.parse('http://10.80.0.1:4096/global/health'));
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('prompt:secret'))}',
      );
      expect(credentials.password, 'secret');
    },
  );

  test('maps rejected credentials to a recoverable failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = ConnectionRepository(
      OpenCodeHealthService(OpenCodeTransport(client)),
      _FakeCredentialsStore(),
      _FakeServerProfileStore(),
    );

    final result = await repository.test(profile, 'wrong-secret');

    expect(result, isA<ConnectionFailed>());
    expect(
      (result as ConnectionFailed).failure,
      ConnectionFailure.unauthorized,
    );
  });

  test(
    'rejects unsupported connection schemes before making a request',
    () async {
      final client = MockClient((_) async => http.Response('', 200));
      final repository = ConnectionRepository(
        OpenCodeHealthService(OpenCodeTransport(client)),
        _FakeCredentialsStore(),
        _FakeServerProfileStore(),
      );
      final unsupportedProfile = ServerProfile(
        origin: Uri(scheme: 'ftp', host: '10.80.0.1', port: 4096),
      );

      final result = await repository.test(unsupportedProfile, null);

      expect(result, isA<ConnectionFailed>());
      expect(
        (result as ConnectionFailed).failure,
        ConnectionFailure.invalidAddress,
      );
    },
  );

  test('rejects public HTTP origins before making a request', () async {
    final client = MockClient((_) async => http.Response('', 200));
    final repository = ConnectionRepository(
      OpenCodeHealthService(OpenCodeTransport(client)),
      _FakeCredentialsStore(),
      _FakeServerProfileStore(),
    );
    final publicProfile = ServerProfile(
      origin: Uri.parse('http://198.51.100.1:4096'),
    );

    final result = await repository.test(publicProfile, null);

    expect(result, isA<ConnectionFailed>());
    expect(
      (result as ConnectionFailed).failure,
      ConnectionFailure.invalidAddress,
    );
  });
}

class _FakeCredentialsStore implements CredentialsStore {
  String? password;
  String? savedId;

  @override
  Future<void> clearPassword(String profileId) async {
    password = null;
  }

  @override
  Future<String?> readPassword(String profileId) async => password;

  @override
  Future<void> savePassword(String profileId, String? value) async {
    password = value;
    savedId = profileId;
  }
}

class _FailingReadCredentials extends _FakeCredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async =>
      throw Exception('synthetic storage failure');
}

class _FakeServerProfileStore implements ServerProfileStore {
  ServerProfile? saved;
  @override
  Future<ServerProfile?> load(String id) async => null;

  @override
  Future<ServerProfile?> loadLast() async => null;

  @override
  Future<void> save(ServerProfile profile) async {
    saved = profile;
  }
}
