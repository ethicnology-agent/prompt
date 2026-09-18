import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/opencode_chat_api.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/presentation/widgets/approval_dock.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

// OpenCode 1.18.31 PermissionRequest, not the legacy Permission shape.
const request = <String, dynamic>{
  'id': 'per_modern',
  'sessionID': 'ses_modern',
  'permission': 'bash',
  'patterns': ['git status --short'],
  'always': ['git *'],
  'metadata': {'command': 'git status --short', 'cwd': '/workspace/project'},
};

void main() {
  test(
    'actual native gateway REST record retains legacy detail despite permission field',
    () {
      // Shape emitted by Sessions.permission in gateway/src/sessions.js.
      final detail =
          mapPendingPermission({
                'id': 'native-request',
                'sessionID': 'native-session',
                'type': 'Shell command',
                'permission': 'item/commandExecution/requestApproval',
                'title':
                    'Command: git status\nWorking directory: /workspace/project',
                'pattern': <String>[],
                'metadata': {
                  'command': 'git status',
                  'cwd': '/workspace/project',
                },
                'time': {'created': 1700000000000},
              }, sessionId: 'native-session')
              as PendingPermissionApproval;
      expect(detail.permissionId, 'native-request');
      expect(detail.toolType, 'Shell command');
      expect(
        detail.title,
        'Command: git status\nWorking directory: /workspace/project',
      );
      expect(detail.hasKnownAlwaysScope, isFalse);
    },
  );
  test(
    'legacy native permission remains actionable and other sessions ignored',
    () {
      const legacy = {
        'id': 'native',
        'sessionID': 'ses_modern',
        'type': 'bash',
        'title': 'Exact native command',
      };
      final event = mapConversationEvent(
        const OpenCodeEventEnvelope(
          directory: null,
          payload: {'type': 'permission.updated', 'properties': legacy},
        ),
        sessionId: 'ses_modern',
      );
      expect(
        ((event as SessionBlockedEvent).detail as PendingPermissionApproval)
            .title,
        'Exact native command',
      );
      expect(mapPendingPermission(request, sessionId: 'another'), isNull);
    },
  );
  test('pinned modern permission.asked blocks with actionable detail', () {
    final event = mapConversationEvent(
      const OpenCodeEventEnvelope(
        directory: '/workspace/project',
        payload: {'type': 'permission.asked', 'properties': request},
      ),
      sessionId: 'ses_modern',
    );
    expect(event, isA<SessionBlockedEvent>());
    final detail = (event as SessionBlockedEvent).detail;
    expect(detail, isA<PendingPermissionApproval>());
    expect(
      (detail as PendingPermissionApproval).title,
      contains('git status --short'),
    );
    expect(detail.patterns, ['git status --short']);
    expect(detail.alwaysPatterns, ['git *']);
    expect(detail.ruleScope, PermissionRuleScope.directoryInstance);
    expect(detail.workingDirectory, '/workspace/project');
  });

  test(
    'modern REST approvals are not silently discarded as an empty list',
    () async {
      final api = OpenCodeChatApi(
        OpenCodeTransport(
          MockClient(
            (r) async => http.Response(
              jsonEncode(r.url.path == '/permission' ? [request] : []),
              200,
            ),
          ),
        ),
      );
      final result = await api.listPendingApprovals(
        ServerProfile(
          origin: Uri.parse('http://10.0.0.1:4096'),
          username: 'opencode',
        ),
        null,
        OpenCodeSession(
          id: 'ses_modern',
          projectId: 'p',
          directory: '/workspace/project',
          title: 'Test',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );
      expect(result, hasLength(1));
      expect(
        (result.single as PendingPermissionApproval).permissionId,
        'per_modern',
      );
    },
  );

  testWidgets('unknown legacy always scope is hidden even when supported', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalDock(
            approval: const PendingPermissionApproval(
              sessionId: 's',
              permissionId: 'p',
              toolType: 'bash',
              title: 'Run a command',
            ),
            onRespondToPermission: (_, _) async => true,
            onReplyToQuestion: (_, _) async => true,
            onRejectQuestion: (_) async => true,
          ),
        ),
      ),
    );
    expect(find.text('Always allow'), findsNothing);
    expect(find.text('Deny'), findsOneWidget);
  });

  test(
    'malformed active REST approval fails closed rather than empty',
    () async {
      final api = OpenCodeChatApi(
        OpenCodeTransport(
          MockClient(
            (r) async => http.Response(
              jsonEncode(
                r.url.path == '/permission'
                    ? [
                        {...request, 'patterns': 123},
                      ]
                    : [],
              ),
              200,
            ),
          ),
        ),
      );
      await expectLater(
        api.listPendingApprovals(
          ServerProfile(
            origin: Uri.parse('http://10.0.0.1:4096'),
            username: 'opencode',
          ),
          null,
          OpenCodeSession(
            id: 'ses_modern',
            projectId: 'p',
            directory: '/workspace/project',
            title: 'Test',
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'pinned compatibility reply retains the session route and response body',
    () async {
      http.Request? sent;
      final api = OpenCodeChatApi(
        OpenCodeTransport(
          MockClient((r) async {
            sent = r;
            return http.Response('true', 200);
          }),
        ),
      );
      await api.respondToPermission(
        ServerProfile(
          origin: Uri.parse('http://10.0.0.1:4096'),
          username: 'opencode',
        ),
        null,
        OpenCodeSession(
          id: 'ses_modern',
          projectId: 'p',
          directory: '/workspace/project',
          title: 'Test',
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
        'per_modern',
        PermissionResponse.once,
      );
      expect(sent!.url.path, '/session/ses_modern/permissions/per_modern');
      expect(sent!.url.queryParameters['directory'], '/workspace/project');
      expect(jsonDecode(sent!.body), {'response': 'once'});
    },
  );

  testWidgets(
    'modern always requires explicit scope confirmation; cancel sends nothing',
    (tester) async {
      final responses = <PermissionResponse>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalDock(
              directory: '/workspace/project',
              approval: mapPendingPermission(request, sessionId: 'ses_modern')!,
              onRespondToPermission: (_, response) async {
                responses.add(response);
                return true;
              },
              onReplyToQuestion: (_, _) async => true,
              onRejectQuestion: (_) async => true,
            ),
          ),
        ),
      );
      expect(
        find.text('Working directory: /workspace/project'),
        findsOneWidget,
      );
      await tester.tap(find.text('Always allow'));
      await tester.pumpAndSettle();
      expect(responses, isEmpty);
      expect(find.text('git *'), findsOneWidget);
      expect(find.text('Directory: /workspace/project'), findsOneWidget);
      expect(
        find.textContaining('not limited to this session'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(responses, isEmpty);
      await tester.tap(find.text('Always allow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm always allow'));
      await tester.pumpAndSettle();
      expect(responses, [PermissionResponse.always]);
    },
  );

  testWidgets('stale confirmation cannot answer a replaced approval', (
    tester,
  ) async {
    var approval = mapPendingPermission(request, sessionId: 'ses_modern')!;
    late StateSetter update;
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ApprovalDock(
                directory: '/workspace/project',
                approval: approval,
                onRespondToPermission: (_, _) async {
                  replies++;
                  return true;
                },
                onReplyToQuestion: (_, _) async => true,
                onRejectQuestion: (_) async => true,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Always allow'));
    await tester.pumpAndSettle();
    update(
      () => approval = mapPendingPermission({
        ...request,
        'id': 'new',
      }, sessionId: 'ses_modern')!,
    );
    await tester.pump();
    await tester.tap(find.text('Confirm always allow'));
    await tester.pumpAndSettle();
    expect(replies, 0);
  });

  for (final omit in ['capability', 'patterns', 'directory']) {
    testWidgets('modern always hidden without $omit', (tester) async {
      final approval = mapPendingPermission({
        ...request,
        if (omit == 'patterns') 'always': <String>[],
      }, sessionId: 'ses_modern')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalDock(
              directory: omit == 'directory' ? null : '/workspace/project',
              allowAlways: omit != 'capability',
              approval: approval,
              onRespondToPermission: (_, _) async => true,
              onReplyToQuestion: (_, _) async => true,
              onRejectQuestion: (_) async => true,
            ),
          ),
        ),
      );
      expect(find.text('Always allow'), findsNothing);
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
    });
  }
}
