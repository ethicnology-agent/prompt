import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/data/remote/opencode_transport.dart';

class MemoryCredentials implements CredentialsStore {
  MemoryCredentials();
  final reads = <String>[];
  @override
  Future<String?> readPassword(String profileId) async {
    reads.add(profileId);
    return 'secret';
  }

  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

ReviewTarget target() => ReviewTarget(
  profile: ServerProfile(
    origin: Uri.parse('http://192.168.1.2'),
    username: 'alice',
  ),
  session: OpenCodeSession(
    id: 'session',
    projectId: 'project',
    directory: '/workspace',
    title: 'Review',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
);

ReviewSnapshot snapshot() => ReviewSnapshot(
  target: target(),
  files: const [
    ReviewFile(
      path: 'lib/a.dart',
      status: 'modified',
      patch: '@@ -1 +1 @@\n-a\n+b',
    ),
  ],
);

void main() {
  test('loads uncommitted work and the branch from the VCS endpoint', () async {
    final requests = <Uri>[];
    final service = OpenCodeReviewService(
      OpenCodeTransport(
        MockClient((incoming) async {
          requests.add(incoming.url);
          if (incoming.url.path == '/vcs/diff') {
            return http.Response(
              '[{"file":"lib/a.dart","status":"modified",'
              '"patch":"@@ -1 +1 @@\\n-a\\n+b","additions":1,"deletions":1}]',
              200,
            );
          }
          return http.Response('', 500);
        }),
      ),
      credentialsStore: MemoryCredentials(),
    );

    final uncommitted = await service.loadSnapshot(
      target(),
      source: ReviewDiffSource.uncommitted,
    );
    final branch = await service.loadSnapshot(
      target(),
      source: ReviewDiffSource.branch,
    );

    expect(uncommitted.source, ReviewDiffSource.uncommitted);
    expect(branch.source, ReviewDiffSource.branch);
    expect(uncommitted.files.single.path, 'lib/a.dart');
    expect(requests.map((url) => url.queryParameters['mode']), [
      'git',
      'branch',
    ]);
    // Context is bounded on purpose: omitting it returns close to whole files
    // and spends the snapshot budget on code nobody touched.
    expect(
      requests.map((url) => url.queryParameters['context']),
      everyElement('${OpenCodeReviewService.vcsContextLines}'),
    );
    expect(requests.map((url) => url.path), everyElement('/vcs/diff'));
  });

  test('reports an empty result in the words of the chosen source', () async {
    final service = OpenCodeReviewService(
      OpenCodeTransport(
        MockClient((incoming) async => http.Response('[]', 200)),
      ),
      credentialsStore: MemoryCredentials(),
    );

    await expectLater(
      service.loadSnapshot(target(), source: ReviewDiffSource.uncommitted),
      throwsA(
        isA<ReviewValidationException>().having(
          (error) => error.message,
          'message',
          'There are no uncommitted changes.',
        ),
      ),
    );
  });

  test(
    'keeps a snapshot whose entries omit the optional diff fields',
    () async {
      // The server schema marks only additions and deletions as required, so a
      // binary file can arrive without a patch. One such entry must not discard
      // the whole review.
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient((incoming) async {
            if (incoming.url.path == '/session/session/message') {
              return http.Response('[{"info":{"id":"m1","role":"user"}}]', 200);
            }
            if (incoming.url.path == '/session/session/diff') {
              return http.Response(
                '[{"file":"assets/logo.png","status":"added",'
                '"additions":0,"deletions":0},'
                '{"file":"lib/a.dart","patch":"@@ -1 +1 @@\\n-a\\n+b",'
                '"additions":1,"deletions":1},'
                '{"additions":0,"deletions":0}]',
                200,
              );
            }
            return http.Response('', 500);
          }),
        ),
        credentialsStore: MemoryCredentials(),
      );

      final result = await service.loadSnapshot(target());

      expect(result.files.map((file) => file.path), [
        'assets/logo.png',
        'lib/a.dart',
      ]);
      expect(result.files.first.patch, isEmpty);
      expect(result.files.last.status, 'modified');
    },
  );

  test(
    'loads the newest non-empty message diff using the profile credential',
    () async {
      final credentials = MemoryCredentials();
      final requests = <http.Request>[];
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient((incoming) async {
            requests.add(incoming);
            if (incoming.url.path == '/session/session/message') {
              return http.Response(
                '[{"info":{"id":"older","role":"user"}},'
                '{"info":{"id":"newer","role":"user"}}]',
                200,
              );
            }
            if (incoming.url.path == '/session/session/diff' &&
                incoming.url.queryParameters['messageID'] == 'newer') {
              return http.Response('[]', 200);
            }
            if (incoming.url.path == '/session/session/diff' &&
                incoming.url.queryParameters['messageID'] == 'older') {
              return http.Response(
                '[{"file":"lib/a.dart","status":"modified","patch":"x"}]',
                200,
              );
            }
            return http.Response('', 500);
          }),
        ),
        credentialsStore: credentials,
      );

      final result = await service.loadSnapshot(target());
      expect(result.files.single.path, 'lib/a.dart');
      expect(requests.map((request) => request.url.queryParameters).toList(), [
        {'directory': '/workspace'},
        {'directory': '/workspace', 'messageID': 'newer'},
        {'directory': '/workspace', 'messageID': 'older'},
      ]);
      expect(requests.map((request) => request.method), everyElement('GET'));
      expect(
        requests.map((request) => request.headers['authorization']),
        everyElement(isNot(contains('secret'))),
      );
      expect(credentials.reads, [
        target().profile.id,
        target().profile.id,
        target().profile.id,
      ]);
    },
  );

  test('creates a deny-all child with the selected model and parent', () async {
    final credentials = MemoryCredentials();
    late http.Request request;
    final service = OpenCodeReviewService(
      OpenCodeTransport(
        MockClient((incoming) async {
          request = incoming;
          return http.Response('{"id":"child"}', 200);
        }),
      ),
      credentialsStore: credentials,
    );
    await service.createChild(
      snapshot(),
      const ReviewReviewerConfiguration(
        role: ReviewRole.security,
        model: ReviewModelConfiguration(
          providerId: 'provider',
          modelId: 'model',
        ),
      ),
    );
    expect(request.url.path, '/session');
    expect(request.url.queryParameters, {'directory': '/workspace'});
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['parentID'], 'session');
    expect(body['model'], {'providerID': 'provider', 'id': 'model'});
    expect(body['permission'], [
      {'permission': '*', 'pattern': '*', 'action': 'deny'},
    ]);
    expect(body.containsKey('workspaceID'), isFalse);
    expect(body.containsKey('agent'), isFalse);
  });

  test(
    'runPass sends the exact tool-free structured prompt with the full diff',
    () async {
      final requests = <http.Request>[];
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient((request) async {
            requests.add(request);
            if (request.url.path != '/session/child/message') {
              return http.Response('', 500);
            }
            return http.Response(
              jsonEncode({
                'info': {
                  'role': 'assistant',
                  'structured': {'summary': 'ok', 'findings': []},
                },
                'parts': [],
              }),
              200,
            );
          }),
        ),
        credentialsStore: MemoryCredentials(),
        pollInterval: Duration.zero,
      );
      final config = const ReviewReviewerConfiguration(
        role: ReviewRole.correctness,
        model: ReviewModelConfiguration(
          providerId: 'provider',
          modelId: 'model',
        ),
      );
      final result = await service.runPass(snapshot(), 'child', config);
      expect(result.opinion!.findings, isEmpty);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/session/child/message');
      expect(request.url.queryParameters, {'directory': '/workspace'});
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], {'providerID': 'provider', 'modelID': 'model'});
      expect(body.containsKey('agent'), isFalse);
      expect((body['tools'] as Map).values, everyElement(false));
      expect(body['format'], {
        'type': 'json_schema',
        'schema': reviewResultSchema,
        'retryCount': 0,
      });
      expect(
        (body['parts'] as List).single['text'],
        contains(snapshot().fullDiff),
      );
    },
  );

  test(
    'runPass returns structured metrics including nested cache tokens',
    () async {
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient((request) async {
            return http.Response(
              jsonEncode({
                'info': {
                  'role': 'assistant',
                  'structured': {'summary': 'ok', 'findings': []},
                  'tokens': {
                    'input': 4,
                    'output': 5,
                    'reasoning': 6,
                    'cache': {'read': 7, 'write': 8},
                  },
                  'cost': 0.25,
                },
                'parts': [],
              }),
              200,
            );
          }),
        ),
        credentialsStore: MemoryCredentials(),
        pollInterval: Duration.zero,
      );
      final pass = await service.runPass(
        snapshot(),
        'child',
        const ReviewReviewerConfiguration(
          role: ReviewRole.security,
          model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
        ),
      );
      expect(pass.metrics.inputTokens, 4);
      expect(pass.metrics.outputTokens, 5);
      expect(pass.metrics.reasoningTokens, 6);
      expect(pass.metrics.cacheTokens, 15);
      expect(pass.metrics.cost, .25);
      expect(pass.metrics.duration, isNotNull);
    },
  );

  test('runPass maps provider errors to safe actionable failures', () async {
    Future<Object> failureFor(Map<String, dynamic> error) async {
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient(
            (request) async => http.Response(
              jsonEncode({
                'info': {
                  'role': 'assistant',
                  'error': error,
                  'tokens': {'input': 4, 'output': 5},
                  'cost': 0.25,
                },
                'parts': [],
              }),
              200,
            ),
          ),
        ),
        credentialsStore: MemoryCredentials(),
        pollInterval: Duration.zero,
      );
      try {
        await service.runPass(
          snapshot(),
          'child',
          const ReviewReviewerConfiguration(
            role: ReviewRole.security,
            model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
          ),
        );
        fail('expected provider failure');
      } on ReviewProviderFailure catch (error) {
        return error;
      }
    }

    final structured =
        await failureFor({
              'name': 'StructuredOutputError',
              'data': {'message': 'raw model text and URL'},
            })
            as ReviewProviderFailure;
    expect(structured.kind, ReviewProviderFailureKind.structuredOutputFailed);
    expect(structured.message, contains('Choose another model'));
    expect(structured.message, isNot(contains('raw model text')));
    expect(structured.metrics.outputTokens, 5);
    expect(structured.metrics.cost, .25);
    expect(structured.metrics.duration, isNotNull);

    final denied =
        await failureFor({
              'name': 'APIError',
              'data': {
                'statusCode': 403,
                'message': 'raw URL and region restriction',
                'responseBody': 'secret details',
              },
            })
            as ReviewProviderFailure;
    expect(denied.kind, ReviewProviderFailureKind.accessDenied);
    expect(denied.message, contains('Access to this model is denied'));
    expect(denied.message, isNot(contains('raw URL')));
    expect(denied.message, isNot(contains('secret details')));

    for (final testCase in [
      (
        error: {
          'name': 'APIError',
          'data': {'statusCode': 429},
        },
        kind: ReviewProviderFailureKind.rateLimited,
        text: 'rate limited',
      ),
      (
        error: {
          'name': 'APIError',
          'data': {'statusCode': 404},
        },
        kind: ReviewProviderFailureKind.unavailable,
        text: 'temporarily unavailable',
      ),
      (
        error: {
          'name': 'APIError',
          'data': {'statusCode': 503},
        },
        kind: ReviewProviderFailureKind.unavailable,
        text: 'temporarily unavailable',
      ),
      (
        error: {
          'name': 'APIError',
          'data': {'isRetryable': true},
        },
        kind: ReviewProviderFailureKind.unavailable,
        text: 'temporarily unavailable',
      ),
    ]) {
      final failure = await failureFor(testCase.error) as ReviewProviderFailure;
      expect(failure.kind, testCase.kind);
      expect(failure.message, contains(testCase.text));
      expect(failure.message, isNot(contains('statusCode')));
    }
  });

  test(
    'runPass converts malformed structured output to a safe failure',
    () async {
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient(
            (request) async => http.Response(
              jsonEncode({
                'info': {
                  'role': 'assistant',
                  'structured': {'unexpected': true},
                  'tokens': {'output': 5},
                },
                'parts': [],
              }),
              200,
            ),
          ),
        ),
        credentialsStore: MemoryCredentials(),
        pollInterval: Duration.zero,
      );
      await expectLater(
        service.runPass(
          snapshot(),
          'child',
          const ReviewReviewerConfiguration(
            role: ReviewRole.security,
            model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
          ),
        ),
        throwsA(
          isA<ReviewProviderFailure>().having(
            (failure) => failure.kind,
            'kind',
            ReviewProviderFailureKind.structuredOutputInvalid,
          ),
        ),
      );
    },
  );

  test(
    'runPass preserves timeout while the synchronous request is pending',
    () async {
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient((request) => Completer<http.Response>().future),
        ),
        credentialsStore: MemoryCredentials(),
        pollInterval: const Duration(milliseconds: 1),
      );

      await expectLater(
        service.runPass(
          snapshot(),
          'child',
          const ReviewReviewerConfiguration(
            role: ReviewRole.security,
            model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
          ),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<ReviewTimeoutFailure>()),
      );
    },
  );

  test(
    'runPass preserves cancellation while the synchronous request is pending',
    () async {
      var checks = 0;
      final service = OpenCodeReviewService(
        OpenCodeTransport(
          MockClient((request) => Completer<http.Response>().future),
        ),
        credentialsStore: MemoryCredentials(),
        pollInterval: const Duration(milliseconds: 1),
      );

      await expectLater(
        service.runPass(
          snapshot(),
          'child',
          const ReviewReviewerConfiguration(
            role: ReviewRole.security,
            model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
          ),
          isCancelled: () => ++checks > 1,
        ),
        throwsA(isA<ReviewCancelledFailure>()),
      );
    },
  );

  test('abort requires a true JSON response and uses the exact path', () async {
    late http.Request request;
    final service = OpenCodeReviewService(
      OpenCodeTransport(
        MockClient((incoming) async {
          request = incoming;
          return http.Response('true', 200);
        }),
      ),
      credentialsStore: MemoryCredentials(),
    );
    await service.abort(target(), 'child/id');
    expect(request.method, 'POST');
    expect(request.url.path, '/session/child%2Fid/abort');
    expect(request.url.queryParameters, {'directory': '/workspace'});
  });

  test('abort rejects false, malformed, and non-success responses', () async {
    Future<void> expectAbort(http.Response response, Matcher failure) async {
      final service = OpenCodeReviewService(
        OpenCodeTransport(MockClient((_) async => response)),
        credentialsStore: MemoryCredentials(),
      );
      await expectLater(service.abort(target(), 'child'), throwsA(failure));
    }

    await expectAbort(http.Response('false', 200), isA<FormatException>());
    await expectAbort(http.Response('{}', 200), isA<FormatException>());
    await expectAbort(http.Response('true', 500), isA<OpenCodeHttpFailure>());
  });
}
