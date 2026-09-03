import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/review_repository.dart';
import '../domain/review_entities.dart';
import '../data/review_history_store.dart';
import '../data/review_cost_estimator.dart';
import '../../capabilities/capabilities.dart';
import '../domain/review_cost_estimate.dart';

class ReviewViewModel extends ValueNotifier<ReviewRun> {
  ReviewViewModel(this.repository, {this.historyStoreProvider})
    : super(const ReviewRun(state: ReviewRunState.idle)) {
    _progressSubscription = repository.progress.listen((snapshot) {
      if (!_disposed) value = snapshot;
    });
  }
  final ReviewRepository repository;
  final Future<ReviewHistoryStore> Function()? historyStoreProvider;
  final historyState = ValueNotifier<ReviewHistoryState>(
    const ReviewHistoryLoading(),
  );
  StreamSubscription<List<StoredReviewSummary>>? _historySubscription;
  String? _historyProfileId;
  String? _historySessionId;

  ReviewCostEstimate? estimate(
    ReviewSnapshot snapshot,
    List<OpenCodeModel> models,
    List<ReviewReviewerConfiguration> configurations,
  ) => const ReviewCostEstimator().estimateReview(
    snapshot,
    models,
    configurations,
  );

  Future<List<StoredReviewSummary>> history(
    String profileId,
    String sessionId,
  ) async {
    if (_disposed) return const [];
    if (_historyProfileId == profileId &&
        _historySessionId == sessionId &&
        _historySubscription != null) {
      final state = historyState.value;
      return state is ReviewHistoryReady ? state.items : const [];
    }
    await _historySubscription?.cancel();
    _historySubscription = null;
    _historyProfileId = profileId;
    _historySessionId = sessionId;
    historyState.value = const ReviewHistoryLoading();
    try {
      if (historyStoreProvider == null) {
        historyState.value = const ReviewHistoryEmpty();
        return const [];
      }
      final store = await historyStoreProvider!();
      if (_disposed) return const [];
      final firstEmission = Completer<List<StoredReviewSummary>>();
      _historySubscription = store
          .watchSummaries(profileId, sessionId)
          .listen(
            (items) {
              if (!firstEmission.isCompleted) firstEmission.complete(items);
              if (_disposed) return;
              historyState.value = items.isEmpty
                  ? const ReviewHistoryEmpty()
                  : ReviewHistoryReady(items);
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!firstEmission.isCompleted) firstEmission.complete(const []);
              if (!_disposed) historyState.value = const ReviewHistoryFailed();
            },
          );
      return firstEmission.future;
    } on Object {
      if (!_disposed) historyState.value = const ReviewHistoryFailed();
      return const [];
    }
  }

  Future<StoredReview?> loadHistory(String id) async {
    try {
      final stored = historyStoreProvider == null
          ? null
          : await (await historyStoreProvider!()).load(id);
      if (stored != null && !_disposed) value = stored.run;
      return stored;
    } on Object {
      if (!_disposed) historyState.value = const ReviewHistoryFailed();
      return null;
    }
  }

  Future<void> deleteHistory(
    String id, {
    String? profileId,
    String? sessionId,
  }) async {
    if (!_disposed && historyStoreProvider != null) {
      historyState.value = const ReviewHistoryLoading();
      try {
        await (await historyStoreProvider!()).delete(id);
      } on Object {
        historyState.value = const ReviewHistoryFailed();
        return;
      }
    }
  }

  late final StreamSubscription<ReviewRun> _progressSubscription;
  bool _disposed = false;

  Future<void> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) async {
    if (_disposed) return;
    value = ReviewRun(state: ReviewRunState.loading);
    try {
      final snapshot = await repository.loadSnapshot(target, source: source);
      if (_disposed) return;
      value = ReviewRun(state: ReviewRunState.idle, snapshot: snapshot);
    } on ReviewValidationException catch (error) {
      if (_disposed) return;
      value = ReviewRun(
        state: ReviewRunState.failed,
        error: ReviewValidationFailure(error.message),
      );
    } on Object catch (_) {
      if (!_disposed) {
        value = const ReviewRun(
          state: ReviewRunState.failed,
          error: ReviewProviderFailure('Unable to load the session diff.'),
        );
      }
    }
  }

  Future<void> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations,
  ) async {
    if (_disposed) return;
    value = ReviewRun(state: ReviewRunState.running);
    try {
      final result = await repository.start(target, configurations);
      if (historyStoreProvider != null) {
        final now = DateTime.now().toUtc();
        final store = await historyStoreProvider!();
        await store.replace(
          StoredReview(
            id: '${target.profile.id}:${target.session.id}:${now.microsecondsSinceEpoch}',
            serverProfileId: target.profile.id,
            sessionId: target.session.id,
            createdAt: now,
            run: result,
          ),
        );
      }
      if (!_disposed) value = result;
    } on ReviewValidationException catch (error) {
      if (_disposed) return;
      value = ReviewRun(
        state: ReviewRunState.failed,
        error: ReviewValidationFailure(error.message),
      );
    } on Object catch (_) {
      if (!_disposed) {
        value = const ReviewRun(
          state: ReviewRunState.failed,
          error: ReviewProviderFailure('Review could not be completed.'),
        );
      }
    }
  }

  Future<void> cancel() async {
    await repository.cancel();
    if (!_disposed) value = value.copyWith(state: ReviewRunState.cancelled);
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSubscription.cancel();
    unawaited(_historySubscription?.cancel());
    _historySubscription = null;
    unawaited(repository.dispose());
    historyState.dispose();
    super.dispose();
  }
}

sealed class ReviewHistoryState {
  const ReviewHistoryState();
}

class ReviewHistoryLoading extends ReviewHistoryState {
  const ReviewHistoryLoading();
}

class ReviewHistoryEmpty extends ReviewHistoryState {
  const ReviewHistoryEmpty();
}

class ReviewHistoryReady extends ReviewHistoryState {
  const ReviewHistoryReady(this.items);
  final List<StoredReviewSummary> items;
}

class ReviewHistoryFailed extends ReviewHistoryState {
  const ReviewHistoryFailed();
}
