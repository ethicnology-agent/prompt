import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/presentation/sessions_screen.dart';
import 'package:prompt/features/sessions/presentation/sessions_view_model.dart';

void main() {
  testWidgets(
    'phone catalog centers its title and opens compact session rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = MockClient((request) async {
        if (request.url.path == '/session') {
          return http.Response(_renameSessionJson, 200);
        }
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"project","worktree":"/srv/project"}]',
            200,
          );
        }
        return http.Response('', 404);
      });
      final profile = ServerProfile(
        origin: Uri.parse('http://10.80.0.1:4096'),
        username: 'opencode',
      );
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );
      addTearDown(viewModel.dispose);
      OpenCodeSession? opened;
      var settingsOpened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: profile,
            viewModel: viewModel,
            onOpenSession: (session) => opened = session,
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onOpenSettings: () => settingsOpened++,
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final header = find.byType(AppBar);
      final title = find.descendant(
        of: header,
        matching: find.text('Sessions'),
      );
      expect(tester.getCenter(title).dx, closeTo(195, 1));
      expect(
        tester.getCenter(find.byTooltip('More actions')).dx,
        lessThan(tester.getCenter(title).dx),
      );
      expect(
        tester.getCenter(find.byTooltip('Settings')).dx,
        greaterThan(tester.getCenter(title).dx),
      );
      final tile = find.byType(SessionListTile);
      final row = tester.widget<SessionListTile>(tile);
      expect(row.title, 'Prompt');
      expect(row.project, 'project');
      expect(row.timestamp, isNotEmpty);
      expect(row.status, 'Status unavailable');
      expect(tester.getSize(tile).height, lessThanOrEqualTo(100));
      expect(find.byIcon(Icons.difference_outlined), findsNothing);
      await tester.tap(tile);
      expect(opened?.id, 'session-1');

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(settingsOpened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renames a session without disposing its dialog controller early',
    (tester) async {
      http.Request? renamed;
      final client = MockClient((request) async {
        if (request.method == 'PATCH' &&
            request.url.path == '/session/session-1') {
          renamed = request;
          return http.Response('{}', 200);
        }
        if (request.url.path == '/session') {
          return http.Response(_renameSessionJson, 200);
        }
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"project","worktree":"/srv/project"}]',
            200,
          );
        }
        return http.Response('', 404);
      });
      final profile = ServerProfile(
        origin: Uri.parse('http://10.80.0.1:4096'),
        username: 'opencode',
      );
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: profile,
            viewModel: viewModel,
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
      await tester.longPress(find.byType(SessionListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      final titleField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.enterText(titleField, 'Prompt renamed');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(renamed, isNotNull);
      expect(jsonDecode(renamed!.body), {'title': 'Prompt renamed'});
      expect(find.text('Prompt renamed'), findsOneWidget);
      viewModel.dispose();
    },
  );

  testWidgets(
    'creates a session from an editable server path without projects',
    (tester) async {
      http.Request? created;
      final client = MockClient((request) async {
        if (request.url.path == '/session' && request.method == 'POST') {
          created = request;
          return http.Response(_sessionJson, 200);
        }
        if (request.url.path == '/session') return http.Response('[]', 200);
        if (request.url.path == '/project') return http.Response('[]', 200);
        return http.Response('', 404);
      });
      final profile = ServerProfile(
        origin: Uri.parse('http://10.80.0.1:4096'),
        username: 'opencode',
      );
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );
      OpenCodeSession? opened;

      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: profile,
            viewModel: viewModel,
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

      expect(find.text('Server project path'), findsOneWidget);
      final pathField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Server project path',
      );
      await tester.enterText(pathField, 'relative/path');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create and open'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(pathField, r'\\server\share\project');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create and open'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.enterText(pathField, '/srv/new-project');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create and open'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Create and open'));
      await tester.pumpAndSettle();

      expect(created!.url.queryParameters['directory'], '/srv/new-project');
      expect(opened?.directory, '/srv/new-project');
      viewModel.dispose();
    },
  );

  testWidgets('auto-completes a server directory and selects the suggestion', (
    tester,
  ) async {
    http.Request? created;
    final client = MockClient((request) async {
      if (request.url.path == '/session' && request.method == 'POST') {
        created = request;
        return http.Response(_sessionJson, 200);
      }
      if (request.url.path == '/session') return http.Response('[]', 200);
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project","worktree":"/srv/project"}]',
          200,
        );
      }
      if (request.url.path == '/file') {
        expect(request.url.queryParameters['directory'], '/srv');
        expect(request.url.queryParameters['path'], '.');
        return http.Response(
          '[{"type":"directory","absolute":"/srv/new-project"},'
          '{"type":"file","absolute":"/srv/news.txt"}]',
          200,
        );
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
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
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();

    final pathField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Server project path',
    );
    await tester.enterText(pathField, '/srv/ne');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(find.text('/srv/new-project'), findsOneWidget);
    await tester.tap(find.text('/srv/new-project'));
    await tester.pump();
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      '/srv/new-project',
    );
    await tester.tap(find.text('Create and open'));
    await tester.pumpAndSettle();

    expect(created!.url.queryParameters['directory'], '/srv/new-project');
    viewModel.dispose();
  });

  testWidgets('shows distinct accessible activity indicators on session cards', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project","worktree":"/srv/project"}]',
          200,
        );
      }
      if (request.url.path == '/session' && request.method == 'GET') {
        return http.Response(
          '[${_activitySessionJson('working')},${_activitySessionJson('idle')},'
          '${_activitySessionJson('retrying')},$_unavailableSessionJson]',
          200,
        );
      }
      if (request.url.path == '/session/status' &&
          request.url.queryParameters['directory'] == '/srv/unavailable') {
        return http.Response('', 503);
      }
      if (request.url.path == '/session/status') {
        return http.Response(
          '{"working":{"type":"busy"},"idle":{"type":"idle"},'
          '"retrying":{"type":"retry","attempt":2,"message":"Retrying",'
          '"next":5}}',
          200,
        );
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
          onOpenSession: (_) {},
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    // A working session spins for as long as it works, so the tree never
    // settles: pump a bounded number of frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Retrying'), findsOneWidget);
    expect(find.text('Status unavailable'), findsOneWidget);
    // A session working in the list turns, exactly as it does once opened.
    final spinning = tester
        .widgetList<SpinningIcon>(
          find.byKey(const ValueKey('session-activity-spin')),
        )
        .where((icon) => icon.spinning)
        .length;
    expect(spinning, 2, reason: 'working and retrying both animate');
    expect(
      tester.getSemantics(find.text('Working')).label,
      contains('Session activity: Working'),
    );
    expect(
      tester.getSemantics(find.text('Status unavailable')).label,
      contains('Session activity: Status unavailable'),
    );
    viewModel.dispose();
  });

  testWidgets('explicit refresh reloads activity in the embedded catalog', (
    tester,
  ) async {
    var catalogLoads = 0;
    var statusLoads = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project","worktree":"/srv/project"}]',
          200,
        );
      }
      if (request.url.path == '/session' && request.method == 'GET') {
        catalogLoads++;
        return http.Response(_refreshSessionJson, 200);
      }
      if (request.url.path == '/session/status') {
        statusLoads++;
        return http.Response(
          statusLoads < 2
              ? '{"refresh":{"type":"idle"}}'
              : '{"refresh":{"type":"busy"}}',
          200,
        );
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionsScreen(
            profile: profile,
            viewModel: viewModel,
            embedded: true,
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
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh sessions'));
    // A working session spins for as long as it works, so the tree never
    // settles: pump a bounded number of frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(catalogLoads, greaterThan(2));
    expect(find.text('Working'), findsOneWidget);
    viewModel.dispose();
  });

  testWidgets('embedded catalog exposes destinations and server origin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project","worktree":"/srv/project"}]',
          200,
        );
      }
      if (request.url.path == '/session') {
        return http.Response(
          '[{"id":"session","projectID":"project","directory":"/srv/project",'
          '"title":"Session","time":{"created":1000,"updated":1000}}]',
          200,
        );
      }
      if (request.url.path == '/session/status') {
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );
    var workspaces = 0;
    var terminals = 0;
    var diagnostics = 0;
    var voiceSettings = 0;
    var disconnects = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionsScreen(
            embedded: true,
            profile: profile,
            viewModel: viewModel,
            onOpenSession: (_) {},
            onOpenWorkspace: (_) => workspaces++,
            onOpenTerminal: () => terminals++,
            onOpenDiagnostics: () => diagnostics++,
            onOpenVoiceSettings: () => voiceSettings++,
            onDisconnect: () => disconnects++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(profile.displayOrigin), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    final menu = find.byTooltip('More actions');
    for (final label in [
      'Browse workspace',
      'Remote terminal',
      'Server settings',
      'Voice settings',
      'Disconnect',
    ]) {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(workspaces, 1);
    expect(terminals, 1);
    expect(diagnostics, 1);
    expect(voiceSettings, 1);
    expect(disconnects, 1);
    viewModel.dispose();
  });

  testWidgets('offers known project paths before the server search', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"known","worktree":"/srv/known-project"}]',
          200,
        );
      }
      if (request.url.path == '/session') return http.Response('[]', 200);
      return http.Response('[]', 200);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
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
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();

    expect(find.text('/srv/known-project'), findsWidgets);
    viewModel.dispose();
  });

  testWidgets('reveals and opens a child session only through search', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project","worktree":"/srv/project"}]',
          200,
        );
      }
      if (request.url.path == '/session') {
        return http.Response(_parentAndChildSessionsJson, 200);
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );
    OpenCodeSession? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
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

    expect(find.text('Parent session'), findsOneWidget);
    expect(find.text('Child session'), findsNothing);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Filter sessions'),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'child-session');
    await tester.pump();

    expect(find.text('Child session'), findsOneWidget);
    await tester.tap(find.text('Child session'));
    expect(opened?.id, 'child-session');
    viewModel.dispose();
  });

  testWidgets('keeps project filter chips at an accessible height', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project","worktree":"/srv/a-very-long-project-name"}]',
          200,
        );
      }
      if (request.url.path == '/session') {
        return http.Response(
          '[{"id":"one","projectID":"project",'
          '"directory":"/srv/a-very-long-project-name","title":"One",'
          '"time":{"created":1000,"updated":1000}}]',
          200,
        );
      }
      if (request.url.path == '/session/status') {
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // Only the text scale is overridden: replacing the whole
          // MediaQueryData would zero the viewport, and a zero-width
          // horizontal ListView builds none of its children.
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: SessionsScreen(
              profile: profile,
              viewModel: viewModel,
              onOpenSession: (_) {},
              onOpenWorkspace: (_) {},
              onOpenTerminal: () {},
              onOpenDiagnostics: () {},
              onOpenVoiceSettings: () {},
              onDisconnect: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Filter sessions'),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(2));
    for (final chip in chips.evaluate()) {
      final chipFinder = find.byElementPredicate((element) => element == chip);
      expect(
        tester.getSize(chipFinder).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
    }
    expect(find.text('All'), findsOneWidget);
    expect(find.text('a-very-long-project-name'), findsWidgets);
    expect(tester.takeException(), isNull);
    viewModel.dispose();
  });

  testWidgets('reloads the catalog when the app regains focus', (tester) async {
    var sessionRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response('[{"id":"project","worktree":"/srv/p"}]', 200);
      }
      if (request.url.path == '/session') {
        sessionRequests += 1;
        return http.Response(_renameSessionJson, 200);
      }
      if (request.url.path == '/session/status') {
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
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
    // One load fans out to several /session calls: one global, one per project
    // directory. Compare load cycles rather than a raw request count.
    final afterInitialLoad = sessionRequests;
    expect(afterInitialLoad, greaterThan(0));

    // Losing and regaining focus is what a desktop window does on alt-tab.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // The cooldown suppresses the reload this soon after the initial load.
    expect(sessionRequests, afterInitialLoad);

    await tester.pump(const Duration(seconds: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(sessionRequests, greaterThan(afterInitialLoad));
    expect(tester.takeException(), isNull);
  });
}

const _sessionJson =
    '{"id":"new","projectID":"project","directory":"/srv/new-project",'
    '"title":"New","time":{"created":1000,"updated":1000}}';

const _renameSessionJson =
    '[{"id":"session-1","projectID":"project","directory":"/srv/project",'
    '"title":"Prompt","time":{"created":1000,"updated":1000}}]';

String _activitySessionJson(String id) =>
    '{"id":"$id","projectID":"project","directory":"/srv/project",'
    '"title":"$id","time":{"created":1000,"updated":1000}}';

const _unavailableSessionJson =
    '{"id":"unavailable","projectID":"project","directory":"/srv/unavailable",'
    '"title":"unavailable","time":{"created":1000,"updated":1000}}';

const _refreshSessionJson =
    '[{"id":"refresh","projectID":"project","directory":"/srv/project",'
    '"title":"Refresh","time":{"created":1000,"updated":1000}}]';

const _parentAndChildSessionsJson =
    '[{"id":"parent-session","projectID":"project","directory":"/srv/project",'
    '"title":"Parent session","time":{"created":1000,"updated":1000}},'
    '{"id":"child-session","projectID":"project","directory":"/srv/project",'
    '"title":"Child session","parentID":"parent-session",'
    '"time":{"created":1000,"updated":1000}}]';

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
