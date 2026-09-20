import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/app/prompt_app.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/local/prompt_local_storage_handle.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/home/presentation/home_shell.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
  testWidgets(
    'disconnect prefills saved profile without reconnecting until requested',
    (tester) async {
      var healthChecks = 0;
      final credentials = _Credentials();
      final profile = ServerProfile(
        origin: Uri.parse('http://10.0.0.5:4096'),
        username: 'saved-user',
      );
      final client = MockClient((request) async {
        if (request.url.path == '/global/health') {
          healthChecks++;
          expect(
            request.headers['authorization'],
            'Basic ${base64Encode(utf8.encode('saved-user:synthetic-password'))}',
          );
          return http.Response('{}', 200);
        }
        if (request.url.path == '/provider') {
          return http.Response('{"all":[],"connected":[]}', 200);
        }
        if (request.url.path == '/session/status') {
          return http.Response('{}', 200);
        }
        return http.Response('[]', 200);
      });
      final dependencies = AppDependencies.create(
        httpClient: client,
        credentialsStore: credentials,
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.light),
        openStorage: () async => PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          reviewHistory: InMemoryReviewHistoryStore(),
          closeHandle: () async {},
        ),
      );
      await tester.pumpWidget(
        PromptApp(
          dependencies: dependencies,
          lastProfileLoader: () async => profile,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        healthChecks,
        1,
        reason: 'Startup must restore the saved connection.',
      );
      expect(find.byType(HomeShell), findsOneWidget);
      tester.widget<HomeShell>(find.byType(HomeShell)).onDisconnect();
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text(profile.displayOrigin), findsOneWidget);
      expect(find.text('saved-user'), findsOneWidget);
      expect(
        healthChecks,
        1,
        reason: 'Disconnect must not start another health check.',
      );
      expect(credentials.clears, 0);
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(healthChecks, 2);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(credentials.password, 'synthetic-password');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _Credentials implements CredentialsStore {
  String? password = 'synthetic-password';
  int clears = 0;
  @override
  Future<String?> readPassword(String profileId) async => password;
  @override
  Future<void> savePassword(String profileId, String? value) async {
    password = value;
  }

  @override
  Future<void> clearPassword(String profileId) async {
    clears++;
    password = null;
  }
}
