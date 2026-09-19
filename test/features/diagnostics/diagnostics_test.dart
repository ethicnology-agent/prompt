import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/platform/local_notification_service.dart';
import 'package:prompt/core/platform/local_notification_types.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/diagnostics/data/diagnostics_repository.dart';
import 'package:prompt/features/diagnostics/data/opencode_diagnostics_service.dart';
import 'package:prompt/features/diagnostics/domain/diagnostics_load_result.dart';
import 'package:prompt/features/diagnostics/presentation/diagnostics_view_model.dart';
import 'package:prompt/features/diagnostics/presentation/diagnostics_screen.dart';
import 'package:prompt/features/settings/data/theme_preference_store.dart';
import 'package:prompt/features/settings/presentation/theme_view_model.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'prompt',
  );

  ThemeViewModel themeViewModel() =>
      ThemeViewModel(InMemoryThemePreferenceStore());

  DiagnosticsRepository repositoryFor(http.Client client) {
    return DiagnosticsRepository(
      OpenCodeDiagnosticsService(OpenCodeTransport(client)),
      const _PasswordStore(),
    );
  }

  test('pending diagnostics load cannot notify after disposal', () async {
    final repository = _ControlledRepository();
    repository.pendingLoad = Completer<DiagnosticsLoadResult>();
    final viewModel = DiagnosticsViewModel(repository);
    final loading = viewModel.load(profile);
    viewModel.dispose();
    repository.pendingLoad!.complete(
      const DiagnosticsLoadFailed(DiagnosticsFailure.unavailable),
    );
    await expectLater(loading, completes);
  });

  for (final dispose in [false, true]) {
    test('late reload cannot restore old profile dispose=$dispose', () async {
      final repository = _ControlledRepository();
      final viewModel = DiagnosticsViewModel(repository);
      await viewModel.load(profile);
      final reloading = viewModel.reload();
      if (dispose) {
        viewModel.dispose();
      } else {
        await viewModel.load(
          ServerProfile(origin: Uri.parse('http://10.80.0.2')),
        );
      }
      final count = repository.loaded.length;
      repository.pendingReload.complete(const DiagnosticsReloaded());
      await expectLater(reloading, completes);
      expect(repository.loaded.length, count);
      if (!dispose) viewModel.dispose();
    });
  }

  for (final replace in [false, true]) {
    testWidgets(
      'reload confirmation cannot outlive diagnostics owner replace=$replace',
      (tester) async {
        final repository = _ControlledRepository();
        final viewModel = DiagnosticsViewModel(repository);
        final current = ValueNotifier<ServerProfile?>(profile);
        final theme = themeViewModel();
        addTearDown(current.dispose);
        addTearDown(theme.dispose);
        addTearDown(viewModel.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<ServerProfile?>(
              valueListenable: current,
              builder: (_, owner, _) => owner == null
                  ? const SizedBox()
                  : DiagnosticsScreen(
                      profile: owner,
                      viewModel: viewModel,
                      localNotificationService: LocalNotificationService(
                        const _UnavailableNotifications(),
                      ),
                      themeViewModel: theme,
                      onReconnect: () async => true,
                      onDisconnect: () {},
                      onReloadReconciled: () async {},
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Reload OpenCode'),
          400,
          scrollable: find.byType(Scrollable),
        );
        await tester.tap(find.widgetWithText(ListTile, 'Reload OpenCode'));
        await tester.pumpAndSettle();
        current.value = replace
            ? ServerProfile(origin: Uri.parse('http://10.80.0.2'))
            : null;
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Reload OpenCode'));
        await tester.pump();
        expect(repository.reloads, isEmpty);
        expect(tester.takeException(), isNull);
        repository.pendingReload.complete(const DiagnosticsReloaded());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'loads only safe diagnostic aggregates from official GET endpoints',
    () async {
      final paths = <String>[];
      final result = await repositoryFor(
        MockClient((request) async {
          paths.add(request.url.path);
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': '1.2.3'}),
              200,
            ),
            '/mcp' => http.Response(
              jsonEncode({
                'safe-name': {'status': 'connected'},
                'other': {'status': 'needs_auth'},
                'disabled': {'status': 'disabled'},
              }),
              200,
            ),
            '/lsp' => http.Response(
              jsonEncode([
                {
                  'id': 'typescript',
                  'name': 'TypeScript',
                  'root': '/private',
                  'status': 'connected',
                },
                {
                  'id': 'dart',
                  'name': 'Dart',
                  'root': '/private',
                  'status': 'error',
                },
              ]),
              200,
            ),
            '/formatter' => http.Response(
              jsonEncode([
                {
                  'name': 'prettier',
                  'extensions': ['.ts'],
                  'enabled': true,
                },
                {
                  'name': 'private',
                  'extensions': ['.secret'],
                  'enabled': false,
                },
              ]),
              200,
            ),
            _ => http.Response('', 404),
          };
        }),
      ).load(profile);

      expect(
        paths,
        containsAll(['/global/health', '/mcp', '/lsp', '/formatter']),
      );
      final snapshot = (result as DiagnosticsLoaded).snapshot;
      expect(snapshot.isHealthy, isTrue);
      expect(snapshot.version, '1.2.3');
      expect(snapshot.mcp.connected, 1);
      expect(snapshot.mcp.needsAttention, 1);
      expect(snapshot.mcp.disabled, 1);
      expect(snapshot.lsp.connected, 1);
      expect(snapshot.lsp.unavailable, 1);
      expect(snapshot.formatters.enabled, 1);
      expect(snapshot.formatters.disabled, 1);
    },
  );

  test('maps malformed responses to a safe failure', () async {
    final result = await repositoryFor(
      MockClient((request) async {
        return request.url.path == '/global/health'
            ? http.Response('{"healthy":true}', 200)
            : http.Response('[]', 200);
      }),
    ).load(profile);

    expect(result, isA<DiagnosticsLoadFailed>());
    expect(
      (result as DiagnosticsLoadFailed).failure,
      DiagnosticsFailure.unexpectedResponse,
    );
  });

  test('reload posts to global dispose and accepts only true', () async {
    String? method;
    String? path;
    final result = await repositoryFor(
      MockClient((request) async {
        method = request.method;
        path = request.url.path;
        return http.Response('true', 200);
      }),
    ).reload(profile);

    expect(method, 'POST');
    expect(path, '/global/dispose');
    expect(result, isA<DiagnosticsReloaded>());
  });

  test('maps an invalid reload response to a typed failure', () async {
    final result = await repositoryFor(
      MockClient((_) async => http.Response('false', 200)),
    ).reload(profile);

    expect(result, isA<DiagnosticsReloadFailed>());
    expect(
      (result as DiagnosticsReloadFailed).failure,
      DiagnosticsFailure.unexpectedResponse,
    );
  });

  test('maps an unauthorized reload to a typed failure', () async {
    final result = await repositoryFor(
      MockClient((_) async => http.Response('', 401)),
    ).reload(profile);

    expect(result, isA<DiagnosticsReloadFailed>());
    expect(
      (result as DiagnosticsReloadFailed).failure,
      DiagnosticsFailure.unauthorized,
    );
  });

  test(
    'view model exposes loading result and refreshes the active profile',
    () async {
      var calls = 0;
      final viewModel = DiagnosticsViewModel(
        repositoryFor(
          MockClient((request) async {
            calls++;
            return switch (request.url.path) {
              '/global/health' => http.Response(
                jsonEncode({'healthy': true, 'version': '1.2.3'}),
                200,
              ),
              '/mcp' => http.Response('{}', 200),
              '/lsp' => http.Response('[]', 200),
              '/formatter' => http.Response('[]', 200),
              _ => http.Response('', 404),
            };
          }),
        ),
      );

      await viewModel.load(profile);
      expect(viewModel.value, isA<DiagnosticsReady>());
      await viewModel.refresh();
      expect(viewModel.value, isA<DiagnosticsReady>());
      expect(calls, 8);
      viewModel.dispose();
    },
  );

  test(
    'successful reload refreshes diagnostics for the active profile',
    () async {
      var mcpCalls = 0;
      var reloadCalls = 0;
      final viewModel = DiagnosticsViewModel(
        repositoryFor(
          MockClient((request) async {
            if (request.url.path == '/global/dispose') {
              reloadCalls++;
              return http.Response('true', 200);
            }
            return switch (request.url.path) {
              '/global/health' => http.Response(
                jsonEncode({'healthy': true, 'version': '1.2.3'}),
                200,
              ),
              '/mcp' => http.Response(
                jsonEncode(
                  mcpCalls++ == 0
                      ? <String, dynamic>{}
                      : {
                          'reloaded': {'status': 'connected'},
                        },
                ),
                200,
              ),
              '/lsp' || '/formatter' => http.Response('[]', 200),
              _ => http.Response('', 404),
            };
          }),
        ),
      );

      await viewModel.load(profile);
      expect((viewModel.value as DiagnosticsReady).snapshot.mcp.total, 0);
      final result = await viewModel.reload();

      expect(result, isA<DiagnosticsReloaded>());
      expect(reloadCalls, 1);
      expect((viewModel.value as DiagnosticsReady).snapshot.mcp.connected, 1);
      viewModel.dispose();
    },
  );

  testWidgets('renders aggregates without server labels or paths', (
    tester,
  ) async {
    final viewModel = DiagnosticsViewModel(
      repositoryFor(
        MockClient((request) async {
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': 'not-shown'}),
              200,
            ),
            '/mcp' => http.Response(
              jsonEncode({
                'internal-tool': {'status': 'connected'},
              }),
              200,
            ),
            '/lsp' => http.Response(
              jsonEncode([
                {
                  'id': 'dart',
                  'name': 'Internal Dart',
                  'root': '/private/workspace',
                  'status': 'connected',
                },
              ]),
              200,
            ),
            '/formatter' => http.Response(
              jsonEncode([
                {
                  'name': 'private-formatter',
                  'extensions': ['.x'],
                  'enabled': true,
                },
              ]),
              200,
            ),
            _ => http.Response('', 404),
          };
        }),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          profile: profile,
          viewModel: viewModel,
          localNotificationService: LocalNotificationService(
            const _UnavailableNotifications(),
          ),
          themeViewModel: themeViewModel(),
          onReconnect: () async => true,
          onDisconnect: () {},
          onReloadReconciled: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 configured'), findsOneWidget);
    expect(find.text('1 reported'), findsNWidgets(2));
    expect(find.text('internal-tool'), findsNothing);
    expect(find.text('Internal Dart'), findsNothing);
    expect(find.text('/private/workspace'), findsNothing);
    expect(find.text('private-formatter'), findsNothing);
    viewModel.dispose();
  });

  testWidgets(
    'confirms and executes reload once, then invokes reconciliation',
    (tester) async {
      var disposeCalls = 0;
      var reconciliationCalls = 0;
      final viewModel = DiagnosticsViewModel(
        repositoryFor(
          MockClient((request) async {
            if (request.url.path == '/global/dispose') {
              disposeCalls++;
              return http.Response('true', 200);
            }
            return switch (request.url.path) {
              '/global/health' => http.Response(
                jsonEncode({'healthy': true, 'version': '1.2.3'}),
                200,
              ),
              '/mcp' => http.Response('{}', 200),
              '/lsp' || '/formatter' => http.Response('[]', 200),
              _ => http.Response('', 404),
            };
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            profile: profile,
            viewModel: viewModel,
            localNotificationService: LocalNotificationService(
              const _UnavailableNotifications(),
            ),
            themeViewModel: themeViewModel(),
            onReconnect: () async => true,
            onDisconnect: () {},
            onReloadReconciled: () async => reconciliationCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Reload OpenCode'),
        400,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.widgetWithText(ListTile, 'Reload OpenCode'));
      await tester.pump();

      expect(
        find.textContaining('Active generations across this server will stop.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'The OpenCode server process itself will not be restarted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reload OpenCode'));
      await tester.pumpAndSettle();

      expect(disposeCalls, 1);
      expect(reconciliationCalls, 1);
      expect(find.text('OpenCode reloaded'), findsOneWidget);
      viewModel.dispose();
    },
  );

  testWidgets('refreshes server settings with pull to refresh', (tester) async {
    var calls = 0;
    final viewModel = DiagnosticsViewModel(
      repositoryFor(
        MockClient((request) async {
          calls++;
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': '1.2.3'}),
              200,
            ),
            '/mcp' => http.Response('{}', 200),
            '/lsp' || '/formatter' => http.Response('[]', 200),
            _ => http.Response('', 404),
          };
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          profile: profile,
          viewModel: viewModel,
          localNotificationService: LocalNotificationService(
            const _UnavailableNotifications(),
          ),
          themeViewModel: themeViewModel(),
          onReconnect: () async => true,
          onDisconnect: () {},
          onReloadReconciled: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(calls, 8);
    viewModel.dispose();
  });

  testWidgets('selects and persists dark appearance', (tester) async {
    final store = InMemoryThemePreferenceStore();
    final theme = ThemeViewModel(store);
    final viewModel = DiagnosticsViewModel(
      repositoryFor(
        MockClient((request) async {
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': '1.2.3'}),
              200,
            ),
            '/mcp' => http.Response('{}', 200),
            '/lsp' || '/formatter' => http.Response('[]', 200),
            _ => http.Response('', 404),
          };
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          profile: profile,
          viewModel: viewModel,
          localNotificationService: LocalNotificationService(
            const _UnavailableNotifications(),
          ),
          themeViewModel: theme,
          onReconnect: () async => true,
          onDisconnect: () {},
          onReloadReconciled: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(theme.value, ThemeMode.dark);
    expect(store.value, ThemeMode.dark);
    theme.dispose();
    viewModel.dispose();
  });
}

class _ControlledRepository implements DiagnosticsRepository {
  final loaded = <ServerProfile>[];
  final reloads = <ServerProfile>[];
  Completer<DiagnosticsLoadResult>? pendingLoad;
  final pendingReload = Completer<DiagnosticsReloadResult>();

  @override
  Future<DiagnosticsLoadResult> load(ServerProfile profile) {
    loaded.add(profile);
    return pendingLoad?.future ??
        Future.value(
          const DiagnosticsLoadFailed(DiagnosticsFailure.unavailable),
        );
  }

  @override
  Future<DiagnosticsReloadResult> reload(ServerProfile profile) {
    reloads.add(profile);
    return pendingReload.future;
  }
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

class _UnavailableNotifications implements LocalNotificationPlatform {
  const _UnavailableNotifications();

  @override
  Future<LocalNotificationPermission> requestPermission() async =>
      LocalNotificationPermission.unavailable;

  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {}
}
