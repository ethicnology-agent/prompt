import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/local/prompt_local_storage_handle.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/settings/settings.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
  for (final parentFails in [false, true]) {
    test(
      'composition blocks descendants before abort and cleans confirmed queue (partial: $parentFails)',
      () async {
        final profile = ServerProfile(
          origin: Uri.parse('http://10.80.0.1:4096'),
          username: 'opencode',
        );
        final otherProfile = ServerProfile(
          origin: Uri.parse('http://10.80.0.2:4096'),
          username: 'opencode',
        );
        final dao = InMemoryQueuePromptsDao();
        final now = DateTime.fromMillisecondsSinceEpoch(1000);
        final session = OpenCodeSession(
          id: 'parent',
          projectId: 'project',
          directory: '/workspace',
          title: 'Parent',
          createdAt: now,
          updatedAt: now,
        );
        for (final id in ['parent', 'child', 'unrelated']) {
          await dao.enqueue(
            id: id,
            serverProfileId: profile.id,
            sessionId: id,
            directory: '/workspace',
            promptText: 'queued content',
            attachments: [
              QueuedAttachment(
                name: 'test.txt',
                mediaType: 'text/plain',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ],
            now: now,
          );
        }
        await dao.enqueue(
          id: 'other-profile',
          serverProfileId: otherProfile.id,
          sessionId: 'parent',
          directory: '/workspace',
          promptText: 'unrelated profile',
          now: now,
        );
        final dependencies = AppDependencies.create(
          credentialsStore: _DeletionCredentials(),
          themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
          openStorage: () async => PromptLocalStorageHandle(
            serverProfiles: InMemoryServerProfileStore(),
            queuedPrompts: dao,
            reviewHistory: InMemoryReviewHistoryStore(),
            closeHandle: () async {},
          ),
          httpClient: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(
                '[{"id":"child","parentID":"parent","projectID":"project","directory":"/workspace","title":"Child","time":{"created":1000,"updated":1000}}]',
                200,
              );
            }
            if (request.url.path.endsWith('/abort')) {
              for (final id in ['parent', 'child']) {
                final rows = await dao
                    .watchQueue(serverProfileId: profile.id, sessionId: id)
                    .first;
                if (rows.isNotEmpty) {
                  expect(rows.single.pauseReason, 'sessionDeleted');
                }
              }
              return http.Response('true', 200);
            }
            if (parentFails && request.url.path.endsWith('/parent')) {
              return http.Response('', 500);
            }
            return http.Response('true', 200);
          }),
        );
        final failure = await dependencies.sessionsViewModel.delete(
          profile,
          session,
        );
        expect(failure, parentFails ? isNotNull : isNull);
        expect(
          await dao
              .watchQueue(serverProfileId: profile.id, sessionId: 'child')
              .first,
          isEmpty,
        );
        final parentRows = await dao
            .watchQueue(serverProfileId: profile.id, sessionId: 'parent')
            .first;
        if (parentFails) {
          expect(parentRows.single.pauseReason, 'sessionDeleted');
          expect(parentRows.single.attachmentsJson, isNotNull);
        } else {
          expect(parentRows, isEmpty);
        }
        expect(
          await dao
              .watchQueue(serverProfileId: profile.id, sessionId: 'unrelated')
              .first,
          hasLength(1),
        );
        expect(
          await dao
              .watchQueue(serverProfileId: otherProfile.id, sessionId: 'parent')
              .first,
          hasLength(1),
        );
        await dependencies.dispose();
      },
    );
  }

  test('composition accepts an injected lazy storage backend', () async {
    final serverProfiles = InMemoryServerProfileStore();
    final queuedPrompts = InMemoryQueuePromptsDao();
    var opens = 0;
    final dependencies = AppDependencies.create(
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      openStorage: () async {
        opens++;
        return PromptLocalStorageHandle(
          serverProfiles: serverProfiles,
          queuedPrompts: queuedPrompts,
          reviewHistory: InMemoryReviewHistoryStore(),
          closeHandle: () async {},
        );
      },
    );

    expect(await dependencies.ensureStorage(), isA<PromptLocalStorageHandle>());
    expect(
      await dependencies.ensureStorage(),
      same(await dependencies.ensureStorage()),
    );
    expect(opens, 1);

    await dependencies.dispose();
  });

  test(
    'concurrent storage initialization opens the backend only once',
    () async {
      final opened = Completer<PromptLocalStorageHandle>();
      var opens = 0;
      final dependencies = AppDependencies.create(
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
        openStorage: () {
          opens++;
          return opened.future;
        },
      );

      final first = dependencies.ensureStorage();
      final second = dependencies.ensureStorage();
      await Future<void>.delayed(Duration.zero);
      expect(opens, 1);

      opened.complete(
        PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          reviewHistory: InMemoryReviewHistoryStore(),
          closeHandle: () async {},
        ),
      );
      expect(await first, same(await second));
      await dependencies.dispose();
    },
  );

  test('failed storage initialization can be retried', () async {
    var opens = 0;
    final dependencies = AppDependencies.create(
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      openStorage: () async {
        opens++;
        if (opens == 1) {
          throw StateError('open failed');
        }
        return PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          reviewHistory: InMemoryReviewHistoryStore(),
          closeHandle: () async {},
        );
      },
    );

    await expectLater(dependencies.ensureStorage(), throwsStateError);
    expect(await dependencies.ensureStorage(), isA<PromptLocalStorageHandle>());
    expect(opens, 2);
    await dependencies.dispose();
  });

  test(
    'disposal closes storage that finishes opening after disposal starts',
    () async {
      final opened = Completer<PromptLocalStorageHandle>();
      var closes = 0;
      final dependencies = AppDependencies.create(
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
        openStorage: () => opened.future,
      );

      final pending = dependencies.ensureStorage();
      final disposing = dependencies.dispose();
      await Future<void>.delayed(Duration.zero);
      opened.complete(
        PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          reviewHistory: InMemoryReviewHistoryStore(),
          closeHandle: () async => closes++,
        ),
      );

      await expectLater(pending, throwsStateError);
      await disposing;
      expect(closes, 1);
    },
  );

  test('concurrent queue initialization creates one coordinator', () async {
    final opened = Completer<PromptLocalStorageHandle>();
    final dependencies = AppDependencies.create(
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      openStorage: () => opened.future,
    );

    final first = dependencies.ensureQueueCoordinator();
    final second = dependencies.ensureQueueCoordinator();
    opened.complete(
      PromptLocalStorageHandle(
        serverProfiles: InMemoryServerProfileStore(),
        queuedPrompts: InMemoryQueuePromptsDao(),
        reviewHistory: InMemoryReviewHistoryStore(),
        closeHandle: () async {},
      ),
    );

    expect(await first, same(await second));
    await dependencies.dispose();
  });
}

class _DeletionCredentials implements CredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
  @override
  Future<void> clearPassword(String profileId) async {}
}
