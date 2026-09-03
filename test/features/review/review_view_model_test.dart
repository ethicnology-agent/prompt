import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/review/data/review_repository.dart';
import 'package:prompt/features/review/domain/review_entities.dart';
import 'package:prompt/features/review/presentation/review_view_model.dart';
import 'package:prompt/features/review/data/review_history_store.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

class _Repository implements ReviewRepository {
  _Repository(this.snapshotFuture, {this.startResult});
  final Future<ReviewSnapshot> snapshotFuture;
  final ReviewRun? startResult;
  final progressController = StreamController<ReviewRun>.broadcast();
  var cancelCalls = 0;
  var disposeCalls = 0;
  @override
  Stream<ReviewRun> get progress => progressController.stream;
  @override
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) => snapshotFuture;
  @override
  Future<ReviewRun> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations, {
    Duration timeout = const Duration(seconds: 120),
    Duration globalTimeout = const Duration(seconds: 240),
  }) async => startResult ?? (throw UnimplementedError());
  @override
  Future<void> cancel() async => cancelCalls++;
  @override
  Future<void> dispose() async {
    disposeCalls++;
    await progressController.close();
  }
}

void main() {
  final snapshot = ReviewSnapshot(
    target: ReviewTarget(
      profile: ServerProfile(origin: Uri.parse('http://10.0.0.1')),
      session: OpenCodeSession(
        id: 's',
        projectId: 'p',
        directory: '/w',
        title: 's',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ),
    files: const [ReviewFile(path: 'a', status: 'M', patch: 'x')],
  );

  test(
    'cancel preserves the current run data while changing only run state',
    () async {
      final repository = _Repository(Future.value(snapshot));
      final viewModel = ReviewViewModel(repository);
      final pass = ReviewPass(
        configuration: const ReviewReviewerConfiguration(
          role: ReviewRole.security,
          model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
        ),
        state: ReviewPassState.succeeded,
      );
      final run = ReviewRun(
        state: ReviewRunState.running,
        snapshot: snapshot,
        passes: [pass],
        disagreements: [const ReviewDisagreement(sources: [])],
      );
      viewModel.value = run;
      await viewModel.cancel();
      expect(viewModel.value.state, ReviewRunState.cancelled);
      expect(viewModel.value.snapshot, same(snapshot));
      expect(viewModel.value.passes, same(run.passes));
      expect(viewModel.value.disagreements, same(run.disagreements));
      viewModel.dispose();
    },
  );

  test('loadSnapshot does not notify after disposal', () async {
    final completer = Completer<ReviewSnapshot>();
    final repository = _Repository(completer.future);
    final viewModel = ReviewViewModel(repository);
    viewModel.loadSnapshot(snapshot.target);
    viewModel.dispose();
    completer.complete(snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(repository.disposeCalls, 1);
  });

  test(
    'history follows external scoped deletion through one watcher',
    () async {
      final repository = _Repository(Future.value(snapshot));
      final store = InMemoryReviewHistoryStore();
      final viewModel = ReviewViewModel(
        repository,
        historyStoreProvider: () async => store,
      );
      await store.save(
        StoredReview(
          id: 'review',
          serverProfileId: snapshot.target.profile.id,
          sessionId: snapshot.target.session.id,
          createdAt: DateTime.utc(2026),
          run: const ReviewRun(state: ReviewRunState.completed),
        ),
      );
      await viewModel.history(
        snapshot.target.profile.id,
        snapshot.target.session.id,
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.historyState.value, isA<ReviewHistoryReady>());
      await store.deleteForSessions(snapshot.target.profile.id, ['s']);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.historyState.value, isA<ReviewHistoryEmpty>());
      viewModel.dispose();
      await store.close();
    },
  );

  test(
    'persists terminal states and a new view model can reopen them',
    () async {
      final store = InMemoryReviewHistoryStore();
      for (final state in [
        ReviewRunState.completed,
        ReviewRunState.partiallyFailed,
        ReviewRunState.cancelled,
      ]) {
        final first = ReviewViewModel(
          _Repository(
            Future.value(snapshot),
            startResult: ReviewRun(state: state, snapshot: snapshot),
          ),
          historyStoreProvider: () async => store,
        );
        await first.start(snapshot.target, const []);
        first.dispose();
        final reopened = ReviewViewModel(
          _Repository(Future.value(snapshot)),
          historyStoreProvider: () async => store,
        );
        final summaries = await reopened.history(
          snapshot.target.profile.id,
          snapshot.target.session.id,
        );
        final matching = summaries.firstWhere((item) => item.state == state);
        final loaded = await reopened.loadHistory(matching.id);
        expect(loaded!.run.state, state);
        reopened.dispose();
      }
      await store.close();
    },
  );

  test(
    'scope changes replace the watcher and provider failures are safe',
    () async {
      final store = InMemoryReviewHistoryStore();
      final viewModel = ReviewViewModel(
        _Repository(Future.value(snapshot)),
        historyStoreProvider: () async => store,
      );
      await viewModel.history('profile-a', 'session-a');
      await viewModel.history('profile-b', 'session-b');
      expect(viewModel.historyState.value, isA<ReviewHistoryEmpty>());
      viewModel.dispose();
      await store.close();

      final failing = ReviewViewModel(
        _Repository(Future.value(snapshot)),
        historyStoreProvider: () async =>
            throw StateError('storage unavailable'),
      );
      expect(await failing.loadHistory('missing'), isNull);
      expect(failing.historyState.value, isA<ReviewHistoryFailed>());
      await failing.deleteHistory('missing');
      expect(failing.historyState.value, isA<ReviewHistoryFailed>());
      failing.dispose();
    },
  );
}
