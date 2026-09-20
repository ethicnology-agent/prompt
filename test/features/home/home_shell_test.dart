import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/chat/presentation/conversation_screen.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/home/presentation/home_shell.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/domain/open_code_project.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/presentation/sessions_screen.dart';
import 'package:prompt/features/sessions/presentation/sessions_view_model.dart';

class _NoopAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

class _FakeConversationViewModel extends ConversationViewModel {
  final openedProfiles = <ServerProfile>[];
  int deleteCalls = 0;
  Completer<SessionMutationResult?>? pendingDelete;
  void Function(OpenCodeSession)? afterDelete;
  @override
  Future<SessionMutationResult?> deleteSession({
    required OpenCodeSession expectedSession,
    required ServerProfile expectedProfile,
  }) async {
    deleteCalls++;
    final result =
        await (pendingDelete?.future ??
            Future.value(const Ok<void, SessionsFailure>(null)));
    if (result is Ok<void, SessionsFailure>) afterDelete?.call(expectedSession);
    return result;
  }

  _FakeConversationViewModel()
    : super(
        chatRepository: ChatRepository(
          OpenCodeChatService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _PasswordStore(),
        ),
        sessionsRepository: SessionsRepository(
          OpenCodeSessionsService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _PasswordStore(),
        ),
        queueRepositoryProvider: () async => throw StateError('unused'),
        queueCoordinatorProvider: () async => throw StateError('unused'),
        attachmentPicker: _NoopAttachmentPicker(),
      );

  @override
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    openedProfiles.add(profile);
    messages.value = const ConversationReady([]);
  }

  @override
  Future<void> leaveSession(OpenCodeSession session) async {}
}

void main() {
  for (final width in [393.0, 1100.0]) {
    testWidgets(
      'gateway catalog opens same-ID rows with exact profile at width $width',
      (tester) async {
        final profile = ServerProfile(
          origin: Uri.parse('http://10.0.0.5:4097'),
          backend: AgentBackend.gatewayCodex,
        );
        final requested = <String>[];
        final deps = AppDependencies.create(
          credentialsStore: const _PasswordStore(),
          httpClient: MockClient((request) async {
            final path = request.url.path;
            requested.add(path);
            Object data = [];
            if (path == '/prompt/capabilities') {
              data = {
                'protocolVersion': 1,
                'engines': {
                  for (final engine in ['codex', 'claude'])
                    engine: {
                      'available': true,
                      'features': ['sessions', 'text', 'abort'],
                    },
                },
              };
            } else if (path.endsWith('/global/health')) {
              data = {};
            } else if (path.endsWith('/project')) {
              data = [
                {'id': 'same-project', 'worktree': '/workspace'},
              ];
            } else if (path.endsWith('/session/status')) {
              data = {
                'same': {'type': 'idle'},
              };
            } else if (path.endsWith('/session')) {
              final engine = request.url.pathSegments[1];
              data = [
                {
                  'id': 'same',
                  'projectID': 'same-project',
                  'directory': '/workspace',
                  'title': '$engine title',
                  'time': {'created': 1, 'updated': engine == 'codex' ? 2 : 1},
                },
              ];
            }
            return http.Response(jsonEncode(data), 200);
          }),
        );
        final conversation = _FakeConversationViewModel();
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() async {
          await deps.dispose();
          await conversation.dispose();
          await tester.binding.setSurfaceSize(null);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeShell(
                profile: profile,
                sessionsViewModel: deps.sessionsViewModel,
                conversationViewModel: conversation,
                capabilitiesViewModel: deps.capabilitiesViewModel,
                workspaceViewModel: deps.workspaceViewModel,
                terminalViewModel: deps.terminalViewModel,
                diagnosticsViewModel: deps.diagnosticsViewModel,
                voiceViewModel: deps.voiceViewModel,
                localNotificationService: deps.localNotificationService,
                themeViewModel: deps.themeViewModel,
                onReconnect: () async => true,
                onDisconnect: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('codex title'), findsWidgets);
        expect(find.text('claude title'), findsOneWidget);
        await tester.tap(find.text('claude title'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .profile
              .backend,
          AgentBackend.gatewayClaude,
        );
        expect(
          conversation.openedProfiles.last.backend,
          AgentBackend.gatewayClaude,
        );
        if (width < 1000) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        final claudeProfile = ServerProfile(
          origin: profile.origin,
          backend: AgentBackend.gatewayClaude,
        );
        await deps.sessionsViewModel.load(claudeProfile);
        await tester.pumpAndSettle();
        expect(find.text('codex title'), findsWidgets);
        await tester.tap(find.text('codex title').first);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .profile
              .backend,
          AgentBackend.gatewayCodex,
        );
        expect(
          conversation.openedProfiles.last.backend,
          AgentBackend.gatewayCodex,
        );
        expect(
          requested.any((path) => path.endsWith('/global/event')),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  Future<AppDependencies> dependencies({
    Set<String> removedIds = const {},
  }) async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"p","worktree":"/srv/p","name":"p"}]',
          200,
        );
      }
      if (request.url.path == '/session') {
        final records =
            jsonDecode(
                  '[{"id":"one","projectID":"p","directory":"/srv/p",'
                  '"title":"One","time":{"created":1000,"updated":1000}},'
                  '{"id":"two","projectID":"p","directory":"/srv/p",'
                  '"title":"Two","time":{"created":1000,"updated":1000}}]',
                )
                as List;
        return http.Response(
          jsonEncode(
            records
                .where((row) => !removedIds.contains((row as Map)['id']))
                .toList(),
          ),
          200,
        );
      }
      if (request.url.path == '/session/status') {
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    return AppDependencies.create(
      httpClient: client,
      credentialsStore: const _PasswordStore(),
    );
  }

  for (final (width, unrelatedRoute, switchSelection) in [
    (393.0, false, false),
    (1100.0, false, false),
    (393.0, true, false),
    (1100.0, true, false),
    (1100.0, false, true),
  ]) {
    testWidgets(
      'details deletion owns navigation width=$width unrelated=$unrelatedRoute switched=$switchSelection',
      (tester) async {
        final removedIds = <String>{};
        final deps = await dependencies(removedIds: removedIds);
        final conversation = _FakeConversationViewModel()
          ..pendingDelete = Completer<SessionMutationResult?>()
          ..afterDelete = (session) => removedIds.add(session.id);
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() async {
          await deps.dispose();
          await conversation.dispose();
          await tester.binding.setSurfaceSize(null);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeShell(
                profile: profile,
                sessionsViewModel: deps.sessionsViewModel,
                conversationViewModel: conversation,
                capabilitiesViewModel: deps.capabilitiesViewModel,
                workspaceViewModel: deps.workspaceViewModel,
                terminalViewModel: deps.terminalViewModel,
                diagnosticsViewModel: deps.diagnosticsViewModel,
                voiceViewModel: deps.voiceViewModel,
                localNotificationService: deps.localNotificationService,
                themeViewModel: deps.themeViewModel,
                onReconnect: () async => true,
                onDisconnect: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (width < 900) {
          await tester.tap(find.text('One'));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.descendant(
            of: find.byType(ConversationScreen),
            matching: find.text('One'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Delete session'), findsOneWidget);
        await tester.tap(find.text('Delete session'));
        await tester.pumpAndSettle();
        expect(conversation.deleteCalls, 0);
        await tester.tap(find.text('Delete'));
        await tester.pump();
        if (unrelatedRoute) {
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator).first,
          );
          unawaited(
            navigator.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Unrelated route')),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
        }
        if (switchSelection) {
          final catalog = tester.widget<SessionsScreen>(
            find.byType(SessionsScreen, skipOffstage: false),
          );
          final other = (deps.sessionsViewModel.value as SessionsReady).sessions
              .firstWhere((session) => session.id == 'two');
          conversation.rememberDraft(profile, other, 'Keep this draft');
          catalog.onOpenSession(other);
          await tester.pump();
        }
        conversation.pendingDelete!.complete(const Ok(null));
        await tester.pumpAndSettle();
        expect(conversation.deleteCalls, 1);
        if (unrelatedRoute) {
          expect(find.text('Unrelated route'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        if (switchSelection) {
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          expect(screen.session.id, 'two');
          expect(
            conversation.draftFor(profile, screen.session),
            'Keep this draft',
          );
        } else {
          expect(find.byType(ConversationScreen), findsNothing);
          if (width >= 900) {
            expect(find.text('Start a conversation'), findsOneWidget);
          }
        }
        expect(find.byType(SessionsScreen), findsOneWidget);
        expect(find.text('One'), findsNothing);
        expect(find.text('Two'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'wide shell keeps catalog and selects detail without navigation',
    (tester) async {
      final deps = await dependencies();
      final conversation = _FakeConversationViewModel();
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() async {
        await deps.dispose();
        await conversation.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeShell(
              profile: profile,
              sessionsViewModel: deps.sessionsViewModel,
              conversationViewModel: conversation,
              capabilitiesViewModel: deps.capabilitiesViewModel,
              workspaceViewModel: deps.workspaceViewModel,
              terminalViewModel: deps.terminalViewModel,
              diagnosticsViewModel: deps.diagnosticsViewModel,
              voiceViewModel: deps.voiceViewModel,
              localNotificationService: deps.localNotificationService,
              themeViewModel: deps.themeViewModel,
              onReconnect: () async => true,
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SessionsScreen), findsOneWidget);
      expect(find.byType(Navigator), findsNWidgets(2));
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(
        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .session
            .id,
        'one',
      );
      expect(find.byType(SessionsScreen), findsOneWidget);
      expect(find.text('Start a conversation'), findsNothing);
      expect(find.byTooltip('More actions'), findsOneWidget);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Browse workspace'), findsOneWidget);
      expect(find.text('Remote terminal'), findsOneWidget);
      expect(find.text('Server settings'), findsOneWidget);
      expect(find.text('Voice settings'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final catalogBefore = tester.getRect(find.byType(SessionsScreen)).width;
      await tester.drag(
        find.byKey(const ValueKey('home-session-catalog-divider')),
        const Offset(80, 0),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byType(SessionsScreen)).width,
        greaterThan(catalogBefore),
      );
      expect(find.byType(ConversationScreen), findsOneWidget);

      final replacement = OpenCodeSession(
        id: 'one',
        projectId: 'p',
        directory: '/srv/p',
        title: 'Renamed one',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      deps.sessionsViewModel.value = SessionsReady(
        [replacement],
        const [OpenCodeProject(id: 'p', directory: '/srv/p')],
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final selectedScreen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      expect(selectedScreen.session, same(replacement));
      expect(find.text('Renamed one'), findsNWidgets(2));

      deps.sessionsViewModel.value = const SessionsReady([], []);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.text('Start a conversation'), findsOneWidget);
      expect(
        find.text('Create a session from the catalog to get started.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'wide selection switches session identity and resize restores push navigation',
    (tester) async {
      final deps = await dependencies();
      final conversation = _FakeConversationViewModel();
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() async {
        await deps.dispose();
        await conversation.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeShell(
              profile: profile,
              sessionsViewModel: deps.sessionsViewModel,
              conversationViewModel: conversation,
              capabilitiesViewModel: deps.capabilitiesViewModel,
              workspaceViewModel: deps.workspaceViewModel,
              terminalViewModel: deps.terminalViewModel,
              diagnosticsViewModel: deps.diagnosticsViewModel,
              voiceViewModel: deps.voiceViewModel,
              localNotificationService: deps.localNotificationService,
              themeViewModel: deps.themeViewModel,
              onReconnect: () async => true,
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final firstKey = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .key;
      await tester.tap(find.text('Two'));
      await tester.pump();
      final secondKey = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .key;
      expect(secondKey, isNot(equals(firstKey)));
      expect(find.text('Two'), findsNWidgets(2));
      await tester.binding.setSurfaceSize(const Size(700, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two').first);
      await tester.pump();
      expect(find.byType(Navigator), findsNWidgets(2));
      expect(find.byType(SessionsScreen), findsOneWidget);
    },
  );

  testWidgets('desktop pane splitter is reachable by pointer and keyboard', (
    tester,
  ) async {
    final deps = await dependencies();
    final conversation = _FakeConversationViewModel();
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() async {
      await deps.dispose();
      await conversation.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeShell(
            profile: profile,
            sessionsViewModel: deps.sessionsViewModel,
            conversationViewModel: conversation,
            capabilitiesViewModel: deps.capabilitiesViewModel,
            workspaceViewModel: deps.workspaceViewModel,
            terminalViewModel: deps.terminalViewModel,
            diagnosticsViewModel: deps.diagnosticsViewModel,
            voiceViewModel: deps.voiceViewModel,
            localNotificationService: deps.localNotificationService,
            themeViewModel: deps.themeViewModel,
            onReconnect: () async => true,
            onDisconnect: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final splitter = find.byKey(const ValueKey('home-session-catalog-divider'));
    // WCAG 2.5.8 Target Size (Minimum), Level AA.
    expect(tester.getRect(splitter).width, greaterThanOrEqualTo(24));

    final focusNode = tester
        .widget<FocusableActionDetector>(
          find.descendant(
            of: splitter,
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    final widened = tester.getRect(find.byType(SessionsScreen)).width;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      tester.getRect(find.byType(SessionsScreen)).width,
      greaterThan(widened),
    );

    final narrowed = tester.getRect(find.byType(SessionsScreen)).width;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      tester.getRect(find.byType(SessionsScreen)).width,
      lessThan(narrowed),
    );
    expect(tester.takeException(), isNull);
  });
}
