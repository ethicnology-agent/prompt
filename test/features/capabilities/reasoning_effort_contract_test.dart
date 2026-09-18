import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/capabilities/capabilities.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.0.0.5:4097'),
    username: 'operator',
    backend: AgentBackend.gatewayCodex,
  );
  final session = OpenCodeSession(
    id: 'session',
    projectId: 'project',
    directory: '/workspace',
    title: 'Fixture',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  const metadata = {
    'version': 1,
    'reasoningEfforts': [
      {
        'id': 'dynamic-effort',
        'label': 'Dynamic effort',
        'description': 'Reported by engine',
      },
    ],
    'defaultReasoningEffortId': 'dynamic-effort',
  };

  Future<OpenCodeModel> modelFor(AgentBackend backend, Object? options) async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/provider')
              ? {
                  'all': [
                    {
                      'id': 'codex',
                      'models': {
                        'actual-model': {
                          'name': 'Actual',
                          'executionOptions': options,
                        },
                      },
                    },
                  ],
                  'connected': ['codex'],
                }
              : [],
        ),
        200,
      ),
    );
    addTearDown(client.close);
    final repository = CapabilitiesRepository(
      OpenCodeCapabilitiesService(OpenCodeTransport(client)),
      _Credentials(),
    );
    final result = await repository.load(
      ServerProfile(
        origin: profile.origin,
        username: profile.username,
        backend: backend,
      ),
    );
    return (result as CapabilitiesLoaded).capabilities.models.single;
  }

  test(
    'native per-model metadata exposes dynamic typed effort choices',
    () async {
      final model = await modelFor(AgentBackend.gatewayCodex, metadata);
      expect(
        model.executionOptions!.reasoningEfforts.single.id,
        'dynamic-effort',
      );
      expect(
        model.executionOptions!.reasoningEfforts.single.label,
        'Dynamic effort',
      );
      expect(
        model.executionOptions!.defaultReasoningEffortId,
        'dynamic-effort',
      );
      expect(model.executionOptions!.supports('invented'), isFalse);
    },
  );

  test(
    'unknown metadata and OpenCode variants never advertise native efforts',
    () async {
      for (final backend in [
        AgentBackend.directOpenCode,
        AgentBackend.gatewayOpenCode,
      ]) {
        expect((await modelFor(backend, metadata)).executionOptions, isNull);
      }
      expect(
        (await modelFor(AgentBackend.gatewayCodex, {
          ...metadata,
          'version': 2,
        })).executionOptions,
        isNull,
      );
      expect(
        (await modelFor(AgentBackend.gatewayCodex, {
          ...metadata,
          'reasoningEfforts': [
            {'id': 'bad\nvalue', 'label': 'Bad'},
          ],
        })).executionOptions,
        isNull,
      );
    },
  );

  test(
    'native prompt preserves exact queued effort without permissions or variant fields',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/prompt/codex/session/session/prompt_async');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reasoningEffort'], 'dynamic-effort');
        expect(body['model'], {
          'providerID': 'codex',
          'modelID': 'actual-model',
        });
        expect(body['messageID'], 'queued-operation');
        expect(
          body.keys,
          unorderedEquals(['messageID', 'parts', 'model', 'reasoningEffort']),
        );
        return http.Response('', 204);
      });
      addTearDown(client.close);
      await OpenCodeChatService(OpenCodeTransport(client)).sendPromptAsync(
        profile,
        'synthetic',
        session,
        'Fixture',
        operationId: 'queued-operation',
        executionOptions: const PromptExecutionOptions(
          modelProviderId: 'codex',
          modelId: 'actual-model',
          reasoningEffort: 'dynamic-effort',
        ),
      );
    },
  );

  test(
    'unsupported backend, default or mismatched model rejects before sending',
    () async {
      final client = MockClient((_) async => throw StateError('Must not send'));
      addTearDown(client.close);
      final service = OpenCodeChatService(OpenCodeTransport(client));
      for (final backend in [
        AgentBackend.directOpenCode,
        AgentBackend.gatewayOpenCode,
        AgentBackend.gatewayClaude,
      ]) {
        await expectLater(
          service.sendPromptAsync(
            ServerProfile(
              origin: profile.origin,
              username: profile.username,
              backend: backend,
            ),
            'synthetic',
            session,
            'Fixture',
            executionOptions: const PromptExecutionOptions(
              modelProviderId: 'codex',
              modelId: 'actual-model',
              reasoningEffort: 'high',
            ),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        service.sendPromptAsync(
          profile,
          'synthetic',
          session,
          'Fixture',
          executionOptions: const PromptExecutionOptions(
            modelProviderId: 'codex',
            modelId: 'default',
            reasoningEffort: 'high',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}

class _Credentials implements CredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async => 'synthetic';
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
