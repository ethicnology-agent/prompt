import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/capabilities/capabilities.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/sessions/presentation/new_session_dock.dart';
import 'package:prompt/features/sessions/presentation/session_creation_dock.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';

void main() {
  testWidgets(
    'creation seeds only the active engine project in a scoped catalog',
    (tester) async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final transport = OpenCodeTransport(client);
      final credentials = _NoCredentials();
      final repository = SessionsRepository(
        OpenCodeSessionsService(transport),
        credentials,
      );
      final profile = ServerProfile(
        origin: Uri.parse('http://10.0.0.2:4097'),
        backend: AgentBackend.gatewayClaude,
      );
      final other = ServerProfile(
        origin: profile.origin,
        backend: AgentBackend.gatewayOpenCode,
      );
      final model = _CreationCatalogModel(repository);
      final creation = SessionCreationViewModel(
        connections: ConnectionRepository(
          OpenCodeHealthService(transport),
          credentials,
          InMemoryServerProfileStore(),
        ),
        sessions: repository,
        capabilities: CapabilitiesRepository(
          OpenCodeCapabilitiesService(transport),
          credentials,
        ),
      );
      addTearDown(client.close);
      addTearDown(model.dispose);
      addTearDown(creation.dispose);
      final groups = [
        SessionCatalogGroup(
          profile: other,
          projects: const [OpenCodeProject(id: 'global', directory: '/')],
        ),
        SessionCatalogGroup(
          profile: profile,
          projects: const [
            OpenCodeProject(id: 'a', directory: '/fixture/a'),
            OpenCodeProject(id: 'b', directory: '/fixture/b'),
          ],
        ),
      ];
      model.value = SessionsReady(
        [
          for (final id in ['a', 'b'])
            OpenCodeSession(
              id: id,
              projectId: id,
              directory: '/fixture/$id',
              title: id,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
        ],
        [
          for (final group in groups)
            for (final project in group.projects)
              OpenCodeProject(
                id: scopedProjectKey(group.profile, project.id),
                directory: project.directory,
              ),
        ],
        catalogGroups: [
          groups.first,
          SessionCatalogGroup(
            profile: profile,
            projects: groups.last.projects,
            sessions: [
              for (final id in ['a', 'b'])
                OpenCodeSession(
                  id: id,
                  projectId: id,
                  directory: '/fixture/$id',
                  title: id,
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: profile,
            viewModel: model,
            sessionCreationViewModel: creation,
            onSessionLaunched: (_) {},
            onOpenSession: (_) {},
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      SessionCreationDock dock() =>
          tester.widget<SessionCreationDock>(find.byType(SessionCreationDock));
      expect(dock().initialDirectory, '/fixture/a');
      dock().controller.text = 'Keep my draft';
      // A project filter may select a different legitimate root of this engine.
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem),
      );
      await tester.pumpAndSettle();
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      final b = chips
          .where(
            (chip) =>
                chip.label is Text && (chip.label as Text).data!.contains('b'),
          )
          .firstOrNull;
      expect(b, isNotNull);
      b!.onSelected!(true);
      await tester.pumpAndSettle();
      expect(dock().initialDirectory, '/fixture/b');
      expect(dock().controller.text, 'Keep my draft');
      model.value = SessionsReady(
        const [],
        [
          OpenCodeProject(
            id: scopedProjectKey(other, 'global'),
            directory: '/',
          ),
        ],
        catalogGroups: [groups.first],
      );
      await tester.pumpAndSettle();
      expect(
        dock().initialDirectory,
        isEmpty,
        reason:
            'Missing active-engine roots must be loaded by creation, never borrowed from another engine.',
      );
      expect(dock().controller.text, 'Keep my draft');
    },
  );
  for (final scenario in [
    'cancel retention',
    'selected project',
    'native gateway suggestions',
    'pre-send options',
    'native pre-send defaults',
  ]) {
    testWidgets('creation preserves intent: $scenario', (tester) async {
      var fileCalls = 0;
      Map<String, dynamic>? creationBody;
      PromptExecutionOptions? transferredOptions;
      var attempts = 0;
      final gateway = scenario.startsWith('native');
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/file')) {
          fileCalls++;
          return http.Response('[]', 200);
        }
        if (path.endsWith('/project')) {
          return http.Response(
            '[{"id":"a","worktree":"/fixture/a"},{"id":"b","worktree":"/fixture/b"}]',
            200,
          );
        }
        if (path.endsWith('/session') && request.method == 'POST') {
          creationBody = jsonDecode(request.body) as Map<String, dynamic>;
          attempts++;
          if (scenario == 'pre-send options' && attempts == 1) {
            return http.Response('{}', 500);
          }
          return http.Response(
            '{"id":"created","projectID":"a","directory":"/fixture/edited","title":"Edited","time":{"created":1,"updated":1}}',
            200,
          );
        }
        if (path.endsWith('/session')) {
          return http.Response(
            '[{"id":"a-session","projectID":"a","directory":"/fixture/a","title":"A","time":{"created":1,"updated":1}},{"id":"b-session","projectID":"b","directory":"/fixture/b","title":"B","time":{"created":1,"updated":1}}]',
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final model = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          _NoCredentials(),
        ),
      );
      addTearDown(model.dispose);
      addTearDown(client.close);
      final capabilities =
          CapabilitiesViewModel(
              CapabilitiesRepository(
                OpenCodeCapabilitiesService(OpenCodeTransport(client)),
                _NoCredentials(),
              ),
            )
            ..value = const CapabilitiesReady(
              OpenCodeCapabilities(
                models: [
                  OpenCodeModel(
                    providerId: 'fixture',
                    id: 'model',
                    name: 'Fixture model',
                    isProviderConnected: true,
                  ),
                ],
                agents: [
                  OpenCodeAgent(
                    name: 'build',
                    mode: OpenCodeAgentMode.primary,
                    isBuiltIn: true,
                  ),
                ],
                commands: [],
              ),
            );
      addTearDown(capabilities.dispose);
      if (scenario == 'native pre-send defaults') {
        capabilities.value = const CapabilitiesReady(
          OpenCodeCapabilities(
            models: [
              OpenCodeModel(
                providerId: 'claude',
                id: 'default',
                name: 'CLI default',
                isProviderConnected: true,
              ),
            ],
            agents: [
              OpenCodeAgent(
                name: 'claude',
                mode: OpenCodeAgentMode.primary,
                isBuiltIn: true,
              ),
            ],
            commands: [],
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionsScreen(
              embedded: true,
              profile: ServerProfile(
                origin: Uri.parse('http://10.23.42.1:4096'),
                backend: gateway
                    ? AgentBackend.gatewayClaude
                    : AgentBackend.directOpenCode,
                capabilities: gateway
                    ? BackendCapabilities([
                        BackendFeature.sessions,
                        BackendFeature.text,
                      ])
                    : null,
              ),
              viewModel: model,
              capabilitiesViewModel: scenario.contains('pre-send')
                  ? capabilities
                  : null,
              onSessionCreated: scenario.contains('pre-send')
                  ? (_, draft, options) => transferredOptions = options
                  : null,
              onOpenSession: (_) {},
              onOpenWorkspace: (_) {},
              onOpenTerminal: () {},
              onOpenDiagnostics: () {},
              onOpenVoiceSettings: () {},
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scenario == 'selected project') {
        await tester.tap(find.widgetWithText(ChoiceChip, 'b'));
        await tester.pumpAndSettle();
      }
      Future<void> open() async {
        await tester.tap(find.byTooltip('New session'));
        await tester.pumpAndSettle();
      }

      final path = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Server project path',
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Title (optional)',
      );
      await open();
      if (scenario == 'native pre-send defaults') {
        expect(find.text('CLI default'), findsNWidgets(2));
        expect(find.text('Effort'), findsNothing);
        expect(find.text('Permissions'), findsNothing);
        await tester.ensureVisible(find.text('Model'));
        await tester.tap(find.text('Model'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(SelectionPicker<OpenCodeModel>),
            matching: find.text('CLI default'),
          ),
          findsOneWidget,
        );
        expect(find.text('Fixture model'), findsNothing);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Create and open'));
        await tester.tap(find.text('Create and open'));
        await tester.pumpAndSettle();
        expect(transferredOptions?.isEmpty, isTrue);
        expect(creationBody, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      if (scenario == 'pre-send options') {
        for (final choice in [('Model', 'Fixture model'), ('Agent', 'build')]) {
          await tester.ensureVisible(find.text(choice.$1));
          await tester.tap(find.text(choice.$1));
          await tester.pumpAndSettle();
          await tester.tap(find.text(choice.$2));
          await tester.tap(find.text('Apply'));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('Create and open'));
        await tester.tap(find.text('Create and open'));
        await tester.pumpAndSettle();
        expect(transferredOptions, isNull);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await open();
        expect(find.text('Fixture model'), findsOneWidget);
        expect(find.text('build'), findsOneWidget);
        await tester.ensureVisible(find.text('Create and open'));
        await tester.tap(find.text('Create and open'));
        await tester.pumpAndSettle();
        expect(transferredOptions?.modelProviderId, 'fixture');
        expect(transferredOptions?.modelId, 'model');
        expect(transferredOptions?.agentName, 'build');
        expect(
          creationBody,
          isEmpty,
          reason:
              'Execution options belong to the first prompt, never POST /session.',
        );
        await open();
        expect(find.text('Fixture model'), findsNothing);
        expect(find.text('build'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      if (scenario == 'selected project') {
        expect(tester.widget<TextField>(path).controller!.text, '/fixture/b');
      } else {
        await tester.enterText(path, '/fixture/edited');
        await tester.enterText(title, 'Edited title');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        if (gateway) {
          expect(fileCalls, 0);
          expect(
            tester.widget<TextField>(path).controller!.text,
            '/fixture/edited',
          );
        } else {
          await tester.ensureVisible(find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await open();
          expect(
            tester.widget<TextField>(path).controller!.text,
            '/fixture/edited',
          );
          expect(
            tester.widget<TextField>(title).controller!.text,
            'Edited title',
          );
          await tester.ensureVisible(find.text('Create and open'));
          await tester.tap(find.text('Create and open'));
          await tester.pumpAndSettle();
          await open();
          expect(tester.widget<TextField>(path).controller!.text, '/fixture/a');
          expect(tester.widget<TextField>(title).controller!.text, isEmpty);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'failed creation keeps the sheet below the status bar with IME open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 851);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      var attempts = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/session') {
          attempts++;
          return http.Response('{}', 500);
        }
        if (request.url.path == '/session') return http.Response('[]', 200);
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"a","worktree":"/fixture/a"},{"id":"b","worktree":"/fixture/b"},{"id":"c","worktree":"/fixture/c"}]',
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final model = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          _NoCredentials(),
        ),
      );
      addTearDown(model.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
            viewModel: model,
            onOpenSession: (_) => fail('Failed creation must not navigate.'),
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New session from draft'));
      await tester.pumpAndSettle();
      final path = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Server project path',
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Title (optional)',
      );
      await tester.enterText(path, '/fixture');
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Keep this title');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create and open'));
      await tester.tap(find.text('Create and open'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(tester.widget<TextField>(path).controller!.text, '/fixture');
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Keep this title',
      );
      final sheet = find.byType(BottomSheet);
      final heading = find.descendant(
        of: sheet,
        matching: find.text('New session'),
      );
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(sheet).dy,
        greaterThanOrEqualTo(24),
        reason: 'Sheet chrome must not occupy the system status bar.',
      );
      expect(tester.getTopLeft(heading).dy, greaterThanOrEqualTo(24));
      expect(
        find.byIcon(Icons.drag_handle_rounded),
        findsNothing,
        reason: 'Dragging is disabled; no handle should suggest otherwise.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('creation keeps input and prevents duplicates while retrying', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<http.Response>();
    var creates = 0;
    OpenCodeSession? opened;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/session') {
        creates++;
        if (creates == 1) return pending.future;
        return http.Response(
          '{"id":"created","projectID":"fixture","directory":"/fixture",'
          '"title":"Keep this title","time":{"created":1,"updated":1}}',
          200,
        );
      }
      return http.Response('[]', 200);
    });
    final model = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        _NoCredentials(),
      ),
    );
    addTearDown(model.dispose);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
          viewModel: model,
          onOpenSession: (session) => opened = session,
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(field('Server project path'), '/fixture');
    await tester.enterText(field('Title (optional)'), 'Keep this title');
    await tester.pumpAndSettle();
    final create = find.widgetWithText(AppButton, 'Create and open');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump(const Duration(milliseconds: 500));
    expect(creates, 1);
    expect(field('Server project path'), findsOneWidget);
    expect(tester.widget<AppButton>(create).busy, isTrue);
    await tester.tap(create);
    await tester.pump();
    expect(creates, 1);
    pending.complete(http.Response('', 503));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Server project path')).controller!.text,
      '/fixture',
    );
    expect(
      tester.widget<TextField>(field('Title (optional)')).controller!.text,
      'Keep this title',
    );
    expect(
      find.text(SessionsFailure.unexpectedResponse.message),
      findsOneWidget,
    );
    expect(opened, isNull);
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(creates, 2);
    expect(opened?.id, 'created');
    expect(field('Server project path'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (size, keyboardHeight) in [
    (const Size(393, 851), 300.0),
    (const Size(851, 393), 150.0),
    (const Size(851, 393), 300.0),
  ]) {
    testWidgets('home draft stays above $keyboardHeight keyboard at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final client = MockClient((_) async => http.Response('[]', 200));
      final model = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          _NoCredentials(),
        ),
      );
      addTearDown(model.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
            viewModel: model,
            onOpenSession: (_) {},
            onOpenSessionWithDraft: (_, _) {},
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final draft = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'What would you like to do?',
      );
      final create = find.byTooltip('New session from draft');
      const text = 'A draft kept through keyboard changes';
      await tester.enterText(draft, text);
      await tester.pumpAndSettle();
      final initialBottom = tester.getBottomRight(create).dy;
      expect(
        tester.getBottomRight(find.byType(NewSessionDock)).dy,
        closeTo(size.height - 12, 1),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        await tester.pumpAndSettle();
        if (size.height - keyboardHeight >= 200) {
          expect(
            tester.getBottomRight(find.byType(NewSessionDock)).dy,
            closeTo(size.height - keyboardHeight - 12, 1),
          );
        }
        expect(
          tester.getBottomRight(create).dy,
          lessThanOrEqualTo(size.height - keyboardHeight),
          reason: 'The draft creation action must not be hidden by the IME.',
        );
        expect(
          tester.getBottomRight(draft).dy,
          lessThanOrEqualTo(size.height - keyboardHeight),
        );
        expect(tester.getTopLeft(draft).dy, greaterThanOrEqualTo(0));
        expect(tester.widget<TextField>(draft).controller!.text, text);
        expect(tester.takeException(), isNull);

        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.getBottomRight(create).dy, closeTo(initialBottom, 1));
        expect(tester.widget<TextField>(draft).controller!.text, text);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('home draft transfers only after explicit session creation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    var submitted = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/prompt_async')) submitted++;
      if (request.method == 'POST' && request.url.path == '/session') {
        created++;
        return http.Response(
          '{"id":"fixture","projectID":"fixture","directory":"/fixture",'
          '"title":"Draft","time":{"created":1,"updated":1}}',
          200,
        );
      }
      if (request.url.path == '/session' || request.url.path == '/project') {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 200);
    });
    final model = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        _NoCredentials(),
      ),
    );
    String? transferred;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
          viewModel: model,
          onOpenSession: (_) =>
              fail('Draft must be transferred with the session.'),
          onOpenSessionWithDraft: (_, draft) => transferred = draft,
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final draft = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'What would you like to do?',
    );
    await tester.enterText(draft, 'An unsent synthetic draft');
    expect(created, 0);
    expect(submitted, 0);
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();
    final path = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Server project path',
    );
    await tester.enterText(path, '/fixture');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create and open'));
    await tester.tap(find.text('Create and open'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(transferred, 'An unsent synthetic draft');
    expect(submitted, 0, reason: 'Create and open does not imply send.');
    expect(tester.widget<TextField>(draft).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    client.close();
  });
}

class _CreationCatalogModel extends SessionsViewModel {
  _CreationCatalogModel(super.repository);
  @override
  Future<void> load(ServerProfile profile) async {}
}

class _NoCredentials implements CredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
  @override
  Future<void> clearPassword(String profileId) async {}
}
