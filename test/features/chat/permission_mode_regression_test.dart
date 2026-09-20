import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

void main() {
  final session = OpenCodeSession(
    id: 'session-1',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  ServerProfile profileFor(AgentBackend backend) => ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4101'),
    username: 'prompt',
    backend: backend,
  );

  test('every native engine carries a permission mode it advertises', () async {
    for (final (backend, mode) in [
      (AgentBackend.gatewayClaude, 'plan'),
      (AgentBackend.gatewayCodex, 'read'),
    ]) {
      http.Request? captured;
      final service = OpenCodeChatService(
        OpenCodeTransport(
          MockClient((request) async {
            captured = request;
            return http.Response('', 204);
          }),
        ),
      );

      await service.sendPromptAsync(
        profileFor(backend),
        'secret',
        session,
        'Do the thing',
        executionOptions: PromptExecutionOptions(permissionModeId: mode),
      );

      expect(
        jsonDecode(captured!.body)['permissionMode'],
        mode,
        reason: 'the $backend gateway must forward its own permission mode',
      );
    }
  });

  test('a proxied OpenCode server never receives a permission mode', () async {
    final service = OpenCodeChatService(
      OpenCodeTransport(MockClient((request) async => http.Response('', 204))),
    );

    for (final backend in [
      AgentBackend.gatewayOpenCode,
      AgentBackend.directOpenCode,
    ]) {
      await expectLater(
        service.sendPromptAsync(
          profileFor(backend),
          'secret',
          session,
          'Do the thing',
          executionOptions: const PromptExecutionOptions(
            permissionModeId: 'plan',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
