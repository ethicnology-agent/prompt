import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/sessions/sessions.dart';

class FakeReviewService implements ReviewExecutionService {
  FakeReviewService({
    this.failRole,
    this.timeoutRole,
    this.waitRole,
    this.abortFailures = 0,
    this.failure,
  });
  final ReviewRole? failRole;
  final ReviewRole? timeoutRole;
  final ReviewRole? waitRole;
  final int abortFailures;
  final ReviewProviderFailure? failure;
  final calls = <String>[];
  final aborted = <String>[];
  final timeouts = <Duration>[];
  final completers = <String, Completer<ReviewPass>>{};

  @override
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) async => ReviewSnapshot(
    target: target,
    files: const [
      ReviewFile(
        path: 'lib/a.dart',
        status: 'modified',
        patch: '@@ -1 +1 @@\n-a\n+b',
      ),
    ],
  );
  @override
  Future<String> createChild(
    ReviewSnapshot snapshot,
    ReviewReviewerConfiguration config,
  ) async {
    calls.add('child:${config.role.name}');
    return 'child-${config.role.name}';
  }

  @override
  Future<ReviewPass> runPass(
    ReviewSnapshot snapshot,
    String childId,
    ReviewReviewerConfiguration config, {
    Duration timeout = const Duration(seconds: 120),
    bool Function()? isCancelled,
  }) {
    calls.add('run:${config.role.name}');
    timeouts.add(timeout);
    if (timeoutRole == config.role) {
      return Future.error(const ReviewTimeoutFailure('timed out'));
    }
    if (failRole == config.role ||
        failure != null && config.role == ReviewRole.security) {
      return Future.error(failure ?? const ReviewProviderFailure('failed'));
    }
    final opinion = ReviewOpinion(
      role: config.role,
      summary: 's',
      findings: [
        ReviewFinding(
          file: 'lib/a.dart',
          startLine: 1,
          endLine: 1,
          side: 'new',
          category: config.role == ReviewRole.security
              ? ReviewFindingCategory.security
              : ReviewFindingCategory.correctness,
          severity: config.role == ReviewRole.security
              ? ReviewSeverity.high
              : ReviewSeverity.low,
          confidence: .5,
          title: 'x',
          description: 'x',
          expectedBehavior: 'x',
          observedBehavior: 'x',
          preconditions: 'x',
          reproduction: 'x',
          impact: 'x',
          evidence: const [
            ReviewEvidence(kind: ReviewEvidenceKind.diff, text: 'x'),
          ],
          suggestedTest: 'x',
        ),
      ],
    );
    final pass = ReviewPass(
      configuration: config,
      state: ReviewPassState.succeeded,
      childSessionId: childId,
      opinion: opinion,
    );
    if (waitRole == config.role) {
      final completer = Completer<ReviewPass>();
      completers[childId] = completer;
      return completer.future;
    }
    return Future.value(pass);
  }

  @override
  Future<void> abort(ReviewTarget target, String childId) async {
    aborted.add(childId);
    if (aborted.where((id) => id == childId).length <= abortFailures) {
      throw StateError('abort failed');
    }
  }
}

ReviewTarget target() => ReviewTarget(
  profile: ServerProfile(origin: Uri.parse('http://192.168.1.2')),
  session: OpenCodeSession(
    id: 's',
    projectId: 'p',
    directory: '/w',
    title: 's',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
);
List<ReviewReviewerConfiguration> configs([int count = 3]) => ReviewRole.values
    .take(count)
    .map(
      (role) => ReviewReviewerConfiguration(
        role: role,
        model: ReviewModelConfiguration(providerId: 'p', modelId: role.name),
      ),
    )
    .toList();

void main() {
  test('accepts two distinct reviewers', () async {
    final run = await InMemoryReviewRepository(
      FakeReviewService(),
    ).start(target(), configs(2));

    expect(run.state, ReviewRunState.completed);
    expect(run.passes, hasLength(2));
  });

  test(
    'creates three children then launches three passes and preserves disagreement provenance',
    () async {
      final fake = FakeReviewService();
      final repository = InMemoryReviewRepository(fake);
      final progress = <ReviewRun>[];
      final subscription = repository.progress.listen(progress.add);
      final run = await repository.start(target(), configs());
      await subscription.cancel();
      expect(run.state, ReviewRunState.completed);
      expect(run.passes, hasLength(3));
      expect(run.disagreements, hasLength(1));
      expect(fake.calls.where((call) => call.startsWith('run:')), hasLength(3));
      expect(progress, isNotEmpty);
      expect(fake.aborted, isEmpty);
    },
  );

  test('one provider failure preserves the other opinions', () async {
    final run = await InMemoryReviewRepository(
      FakeReviewService(failRole: ReviewRole.security),
    ).start(target(), configs());
    expect(run.state, ReviewRunState.partiallyFailed);
    expect(run.passes.where((pass) => pass.opinion != null), hasLength(2));
    expect(
      run.passes
          .singleWhere((pass) => pass.configuration.role == ReviewRole.security)
          .error,
      isA<ReviewProviderFailure>(),
    );
  });

  test('preserves typed provider failure and its observed metrics', () async {
    final failure = ReviewProviderFailure(
      'Model access is denied. Check access, region, or opt-in.',
      kind: ReviewProviderFailureKind.accessDenied,
      metrics: const ReviewPassMetrics(
        outputTokens: 5,
        cost: .25,
        duration: Duration(seconds: 2),
      ),
    );
    final run = await InMemoryReviewRepository(
      FakeReviewService(failure: failure),
    ).start(target(), configs(2));
    final pass = run.passes[1];

    expect(pass.error, same(failure));
    expect(pass.error, isA<ReviewProviderFailure>());
    expect(
      (pass.error! as ReviewProviderFailure).kind,
      ReviewProviderFailureKind.accessDenied,
    );
    expect(pass.metrics.outputTokens, 5);
    expect(pass.metrics.cost, .25);
    expect(pass.metrics.duration, const Duration(seconds: 2));
  });

  test('uses the 30 minute default pass timeout', () async {
    final fake = FakeReviewService();
    await InMemoryReviewRepository(fake).start(target(), configs(2));
    expect(fake.timeouts, everyElement(const Duration(minutes: 30)));
  });

  test('rejects an overlapping run on the same repository', () async {
    final fake = FakeReviewService(waitRole: ReviewRole.correctness);
    final repository = InMemoryReviewRepository(fake);
    final first = repository.start(target(), configs(2));
    while (!fake.completers.containsKey('child-correctness')) {
      await Future<void>.delayed(Duration.zero);
    }

    await expectLater(
      repository.start(target(), configs(2)),
      throwsA(isA<ReviewValidationException>()),
    );
    fake.completers['child-correctness']!.complete(
      ReviewPass(
        configuration: configs(2).first,
        state: ReviewPassState.succeeded,
        childSessionId: 'child-correctness',
        opinion: const ReviewOpinion(
          role: ReviewRole.correctness,
          summary: 'done',
          findings: [],
        ),
      ),
    );
    await first;
  });

  test(
    'preserves a successful opinion and aborts a timed-out child immediately',
    () async {
      final fake = FakeReviewService(timeoutRole: ReviewRole.security);
      final run = await InMemoryReviewRepository(
        fake,
      ).start(target(), configs(2));

      expect(run.state, ReviewRunState.partiallyFailed);
      expect(run.passes[0].state, ReviewPassState.succeeded);
      expect(run.passes[0].opinion, isNotNull);
      expect(run.passes[1].state, ReviewPassState.timedOut);
      expect(fake.aborted, ['child-security']);
    },
  );

  test('confirms cleanup when the bounded abort retry succeeds', () async {
    final fake = FakeReviewService(
      timeoutRole: ReviewRole.security,
      abortFailures: 1,
    );
    final run = await InMemoryReviewRepository(
      fake,
    ).start(target(), configs(2));
    final timedOut = run.passes[1];

    expect(fake.aborted, ['child-security', 'child-security']);
    expect(timedOut.state, ReviewPassState.timedOut);
    expect(timedOut.error!.message, isNot(contains('cleanup')));
  });

  test(
    'retries a failed abort once and surfaces cleanup uncertainty safely',
    () async {
      final fake = FakeReviewService(
        timeoutRole: ReviewRole.security,
        abortFailures: 2,
      );
      final run = await InMemoryReviewRepository(
        fake,
      ).start(target(), configs(2));
      final timedOut = run.passes[1];

      expect(fake.aborted, ['child-security', 'child-security']);
      expect(timedOut.state, ReviewPassState.timedOut);
      expect(timedOut.error, isA<ReviewTimeoutFailure>());
      expect(
        timedOut.error!.message,
        contains('cleanup could not be confirmed'),
      );
      expect(timedOut.error!.message, isNot(contains('abort failed')));
    },
  );

  test('rejects duplicate selected models', () async {
    final duplicate = configs()
        .map(
          (config) => ReviewReviewerConfiguration(
            role: config.role,
            model: const ReviewModelConfiguration(
              providerId: 'p',
              modelId: 'same',
            ),
          ),
        )
        .toList();
    expect(
      () => InMemoryReviewRepository(
        FakeReviewService(),
      ).start(target(), duplicate),
      throwsA(isA<ReviewValidationException>()),
    );
  });

  test('rejects fewer than two reviewers', () async {
    expect(
      () => InMemoryReviewRepository(
        FakeReviewService(),
      ).start(target(), configs(1)),
      throwsA(isA<ReviewValidationException>()),
    );
  });

  test('cancel is idempotent', () async {
    final fake = FakeReviewService();
    final repository = InMemoryReviewRepository(fake);
    final future = repository.start(target(), configs());
    await Future<void>.delayed(Duration.zero);
    await repository.cancel();
    await repository.cancel();
    await future;
    expect(fake.aborted.toSet(), hasLength(fake.aborted.length));
  });
}
