import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/capabilities/data/capabilities_repository.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/capabilities/domain/capabilities_load_result.dart';
import 'package:prompt/features/capabilities/domain/open_code_agent.dart';
import 'package:prompt/features/capabilities/presentation/capabilities_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  CapabilitiesRepository repositoryFor(http.Client client) {
    return CapabilitiesRepository(
      OpenCodeCapabilitiesService(OpenCodeTransport(client)),
      const _PasswordStore(),
    );
  }

  test(
    'loads typed models, agents, and commands from official endpoints',
    () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        switch (request.url.path) {
          case '/provider':
            return http.Response(
              jsonEncode({
                'all': [
                  {
                    'id': 'anthropic',
                    'models': {
                      'claude-sonnet': {'name': 'Claude Sonnet'},
                    },
                  },
                ],
                'default': {},
                'connected': ['anthropic'],
              }),
              200,
            );
          case '/agent':
            return http.Response(
              jsonEncode([
                {
                  'name': 'build',
                  'description': 'Implement changes',
                  'mode': 'primary',
                  'builtIn': true,
                },
              ]),
              200,
            );
          case '/command':
            return http.Response(
              jsonEncode([
                {
                  'name': 'review',
                  'description': 'Review a change',
                  'template': r'Review $ARGUMENTS',
                  'agent': 'build',
                  'model': 'anthropic/claude-sonnet',
                },
              ]),
              200,
            );
        }
        return http.Response('', 404);
      });

      final result = await repositoryFor(client).load(profile);

      expect(requestedPaths, containsAll(['/provider', '/agent', '/command']));
      final loaded = result as CapabilitiesLoaded;
      expect(loaded.capabilities.models.single.providerId, 'anthropic');
      expect(loaded.capabilities.models.single.id, 'claude-sonnet');
      expect(loaded.capabilities.models.single.isProviderConnected, isTrue);
      expect(loaded.capabilities.agents.single.mode, OpenCodeAgentMode.primary);
      expect(
        loaded.capabilities.commands.single.model?.modelId,
        'claude-sonnet',
      );
    },
  );

  test('maps malformed capability payloads to a user-safe failure', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/provider') {
        return http.Response('{}', 200);
      }
      return http.Response('[]', 200);
    });

    final result = await repositoryFor(client).load(profile);

    expect(result, isA<CapabilitiesLoadFailed>());
    expect(
      (result as CapabilitiesLoadFailed).failure,
      CapabilitiesFailure.unexpectedResponse,
    );
  });

  test('accepts bounded native permission modes only from a gateway', () async {
    final client = MockClient(
      (request) async => http.Response(
        request.url.path.endsWith('/provider')
            ? jsonEncode({
                'all': [
                  {
                    'id': 'codex',
                    'models': {
                      'default': {'name': 'CLI default'},
                    },
                    'executionOptions': {
                      'version': 1,
                      'permissionModes': [
                        {
                          'id': 'ask',
                          'label': 'Ask',
                          'description': 'Request approval',
                        },
                        {'id': 'auto', 'label': 'Auto'},
                      ],
                      'defaultPermissionModeId': 'ask',
                    },
                  },
                  {
                    'id': 'other',
                    'models': <String, Object>{},
                    'executionOptions': {
                      'version': 1,
                      'permissionModes': [
                        {'id': 'unsafe', 'label': 'Unsafe'},
                      ],
                      'defaultPermissionModeId': 'unsafe',
                    },
                  },
                  {
                    'id': 'claude',
                    'models': <String, Object>{},
                    'executionOptions': {
                      'version': 1,
                      'permissionModes': [
                        {
                          'id': 'ask',
                          'label': 'Auto',
                          'description': 'Request approval when needed',
                        },
                        {
                          'id': 'plan',
                          'label': 'Plan',
                          'description': 'Do not execute tools',
                        },
                      ],
                      'defaultPermissionModeId': 'ask',
                    },
                  },
                ],
                'connected': ['codex', 'claude', 'other'],
              })
            : '[]',
        200,
      ),
    );
    addTearDown(client.close);
    final native = await repositoryFor(client).load(
      ServerProfile(
        origin: profile.origin,
        username: profile.username,
        backend: AgentBackend.gatewayCodex,
      ),
    );
    final nativeCapabilities = (native as CapabilitiesLoaded).capabilities;
    expect(nativeCapabilities.permissionModes.map((mode) => mode.id), [
      'ask',
      'auto',
    ]);
    expect(
      nativeCapabilities.permissionModes.first.description,
      'Request approval',
    );
    expect(nativeCapabilities.defaultPermissionModeId, 'ask');

    final claude = await repositoryFor(client).load(
      ServerProfile(
        origin: profile.origin,
        username: profile.username,
        backend: AgentBackend.gatewayClaude,
      ),
    );
    final claudeCapabilities = (claude as CapabilitiesLoaded).capabilities;
    expect(claudeCapabilities.permissionModes.map((mode) => mode.id), [
      'ask',
      'plan',
    ]);
    expect(claudeCapabilities.defaultPermissionModeId, 'ask');

    final direct = await repositoryFor(client).load(profile);
    expect(
      (direct as CapabilitiesLoaded).capabilities.permissionModes,
      isEmpty,
    );
    expect(direct.capabilities.defaultPermissionModeId, isNull);
  });

  test('accepts agents without the legacy builtIn field', () async {
    final client = MockClient((request) async {
      return switch (request.url.path) {
        '/provider' => http.Response(
          jsonEncode({'all': [], 'default': {}, 'connected': []}),
          200,
        ),
        '/agent' => http.Response(
          jsonEncode([
            {
              'name': 'build',
              'description': 'Implement changes',
              'mode': 'primary',
            },
          ]),
          200,
        ),
        '/command' => http.Response('[]', 200),
        _ => http.Response('', 404),
      };
    });

    final result = await repositoryFor(client).load(profile);

    final loaded = result as CapabilitiesLoaded;
    expect(loaded.capabilities.agents.single.name, 'build');
    expect(loaded.capabilities.agents.single.isBuiltIn, isFalse);
  });

  test(
    'retains model pricing and limits while treating invalid prices as unknown',
    () async {
      final client = MockClient(
        (request) async => switch (request.url.path) {
          '/provider' => http.Response(
            jsonEncode({
              'all': [
                {
                  'id': 'catalog',
                  'models': {
                    'known': {
                      'name': 'Known',
                      'cost': {
                        'input': 1.25,
                        'output': 2,
                        'cache': {'read': 0.1, 'write': 0.2},
                        'experimentalOver200K': true,
                      },
                      'limit': {'context': 100, 'input': 80},
                      'releaseDate': '2026-01-01',
                      'status': 'active',
                      'capabilities': ['reasoning'],
                    },
                    'unknown': {
                      'name': 'Unknown',
                      'cost': {'input': 0, 'output': 'bad', 'cache': null},
                      'limit': {'input': 'bad'},
                    },
                  },
                },
              ],
              'connected': ['catalog'],
            }),
            200,
          ),
          '/agent' => http.Response('[]', 200),
          '/command' => http.Response('[]', 200),
          _ => http.Response('', 404),
        },
      );
      final record = await OpenCodeCapabilitiesService(
        OpenCodeTransport(client),
      ).fetch(profile, null);
      final known = record.providers.single.models.first;
      final unknown = record.providers.single.models.last;
      expect(known.pricing, isA<OpenCodeModelPricingRecord>());
      expect(known.pricing!.input, 1.25);
      expect(known.limits!.context, 100);
      expect(known.capabilities, ['reasoning']);
      expect(unknown.pricing!.input, isNull);
      expect(unknown.pricing!.output, isNull);
      expect(record.providers.single.isConnected, isTrue);
    },
  );

  test(
    'ignores unsupported commands without hiding models and agents',
    () async {
      final client = MockClient((request) async {
        return switch (request.url.path) {
          '/provider' => http.Response(
            jsonEncode({
              'all': [
                {
                  'id': 'anthropic',
                  'models': {
                    'claude-sonnet': {'name': 'Claude Sonnet'},
                  },
                },
              ],
              'default': {},
              'connected': ['anthropic'],
            }),
            200,
          ),
          '/agent' => http.Response(
            jsonEncode([
              {'name': 'build', 'mode': 'primary'},
            ]),
            200,
          ),
          '/command' => http.Response(
            jsonEncode([
              {'name': 'future-command', 'template': 42},
            ]),
            200,
          ),
          _ => http.Response('', 404),
        };
      });

      final result = await repositoryFor(client).load(profile);

      final loaded = result as CapabilitiesLoaded;
      expect(loaded.capabilities.models.single.name, 'Claude Sonnet');
      expect(loaded.capabilities.agents.single.name, 'build');
      expect(loaded.capabilities.commands, isEmpty);
    },
  );

  test('view model exposes empty, ready, and retryable states', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final empty = calls <= 3;
      switch (request.url.path) {
        case '/provider':
          return http.Response(
            jsonEncode({
              'all': empty
                  ? []
                  : [
                      {
                        'id': 'openai',
                        'models': {
                          'gpt-5': {'name': 'GPT-5'},
                        },
                      },
                    ],
              'default': {},
              'connected': [],
            }),
            200,
          );
        case '/agent':
        case '/command':
          return http.Response('[]', 200);
      }
      return http.Response('', 404);
    });
    final viewModel = CapabilitiesViewModel(repositoryFor(client));

    await viewModel.load(profile);
    expect(viewModel.value, isA<CapabilitiesEmpty>());

    await viewModel.retry();
    expect(viewModel.value, isA<CapabilitiesReady>());
    viewModel.dispose();
  });
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
