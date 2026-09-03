import 'dart:async';

import '../domain/review_entities.dart';
import 'opencode_review_service.dart';

abstract interface class ReviewRepository {
  Stream<ReviewRun> get progress;
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source,
  });
  Future<ReviewRun> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations, {
    Duration timeout = const Duration(minutes: 30),
    Duration globalTimeout = const Duration(minutes: 35),
  });
  Future<void> cancel();
  Future<void> dispose();
}

class InMemoryReviewRepository implements ReviewRepository {
  InMemoryReviewRepository(this.service);
  final ReviewExecutionService service;
  final _progress = StreamController<ReviewRun>.broadcast();
  ReviewTarget? _target;
  final _children = <String>[];
  final _abortStates = <String, _AbortState>{};
  bool _cancelled = false;
  bool _globalTimedOut = false;
  bool _disposed = false;
  bool _running = false;

  @override
  Stream<ReviewRun> get progress => _progress.stream;

  @override
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) => service.loadSnapshot(target, source: source);

  void _publish(ReviewRun run) {
    if (!_disposed && !_progress.isClosed) _progress.add(run);
  }

  @override
  Future<ReviewRun> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations, {
    Duration timeout = const Duration(minutes: 30),
    Duration globalTimeout = const Duration(minutes: 35),
  }) async {
    if (configurations.length < 2 ||
        configurations.length > ReviewRole.values.length ||
        configurations.map((c) => c.role).toSet().length !=
            configurations.length ||
        configurations
                .map((c) => '${c.model.providerId}/${c.model.modelId}')
                .toSet()
                .length !=
            configurations.length) {
      throw const ReviewValidationException(
        'Between two and three distinct reviewer roles and models are required.',
      );
    }
    if (_running) {
      throw const ReviewValidationException('A review is already running.');
    }
    _running = true;
    try {
      _target = target;
      _cancelled = false;
      _globalTimedOut = false;
      _abortStates.clear();
      final snapshot = await service.loadSnapshot(target);
      var run = ReviewRun(
        state: ReviewRunState.running,
        snapshot: snapshot,
        passes: configurations
            .map(
              (configuration) => ReviewPass(
                configuration: configuration,
                state: ReviewPassState.pending,
              ),
            )
            .toList(growable: false),
      );
      _publish(run);
      final children = <String>[];
      try {
        for (final configuration in configurations) {
          if (_cancelled) throw const ReviewCancelledFailure();
          final child = await service.createChild(snapshot, configuration);
          children.add(child);
          _children.add(child);
          final index = children.length - 1;
          final passes = [...run.passes];
          passes[index] = passes[index].copyWith(
            childSessionId: child,
            state: ReviewPassState.running,
          );
          run = run.copyWith(passes: passes);
          _publish(run);
        }

        final tasks = <Future<void>>[];
        for (var index = 0; index < configurations.length; index++) {
          tasks.add(
            _executePass(
              snapshot,
              children[index],
              configurations[index],
              index,
              timeout,
              () => run,
              (next) {
                run = next;
                _publish(run);
              },
            ),
          );
        }
        try {
          await Future.wait(tasks).timeout(globalTimeout);
        } on TimeoutException {
          _globalTimedOut = true;
          _cancelled = true;
          final passes = [...run.passes];
          for (var i = 0; i < passes.length; i++) {
            if (passes[i].state == ReviewPassState.running) {
              passes[i] = passes[i].copyWith(
                state: ReviewPassState.timedOut,
                error: const ReviewTimeoutFailure('Global review timeout.'),
              );
            }
          }
          run = run.copyWith(passes: passes);
          _publish(run);
        }
        final failed = run.passes.any(
          (p) => p.state != ReviewPassState.succeeded,
        );
        final state = _cancelled && !_globalTimedOut
            ? ReviewRunState.cancelled
            : failed
            ? ReviewRunState.partiallyFailed
            : ReviewRunState.completed;
        run = run.copyWith(
          state: state,
          disagreements: _findDisagreements(run.passes),
        );
        _publish(run);
        return run;
      } on ReviewCancelledFailure {
        run = run.copyWith(
          state: ReviewRunState.cancelled,
          passes: run.passes
              .map(
                (p) => p.state == ReviewPassState.succeeded
                    ? p
                    : p.copyWith(
                        state: ReviewPassState.cancelled,
                        error: const ReviewCancelledFailure(),
                      ),
              )
              .toList(growable: false),
        );
        _publish(run);
        return run;
      } finally {
        for (var i = 0; i < children.length; i++) {
          final pass = run.passes[i];
          if (pass.state != ReviewPassState.succeeded) {
            await _abortOnce(target, children[i]);
          }
        }
        _children.clear();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _executePass(
    ReviewSnapshot snapshot,
    String child,
    ReviewReviewerConfiguration configuration,
    int index,
    Duration timeout,
    ReviewRun Function() current,
    void Function(ReviewRun) update,
  ) async {
    try {
      final result = await service.runPass(
        snapshot,
        child,
        configuration,
        timeout: timeout,
        isCancelled: () => _cancelled,
      );
      if (!_globalTimedOut) {
        final passes = [...current().passes];
        passes[index] = result;
        update(current().copyWith(passes: passes));
      }
    } on ReviewTimeoutFailure catch (error) {
      if (!_globalTimedOut) {
        final cleanupConfirmed = await _abortOnce(snapshot.target, child);
        _setPass(
          current,
          update,
          index,
          ReviewPassState.timedOut,
          cleanupConfirmed
              ? error
              : const ReviewTimeoutFailure(
                  'Reviewer timed out; server cleanup could not be confirmed.',
                ),
        );
      }
    } on ReviewCancelledFailure catch (error) {
      if (!_globalTimedOut) {
        _setPass(current, update, index, ReviewPassState.cancelled, error);
      }
    } on ReviewProviderFailure catch (error) {
      if (!_globalTimedOut) {
        _setPass(
          current,
          update,
          index,
          ReviewPassState.failed,
          error,
          error.metrics,
        );
      }
    } catch (_) {
      if (!_globalTimedOut) {
        _setPass(
          current,
          update,
          index,
          ReviewPassState.failed,
          const ReviewProviderFailure('Reviewer provider failed.'),
        );
      }
    }
  }

  void _setPass(
    ReviewRun Function() current,
    void Function(ReviewRun) update,
    int index,
    ReviewPassState state,
    ReviewFailure error, [
    ReviewPassMetrics metrics = const ReviewPassMetrics(),
  ]) {
    final passes = [...current().passes];
    passes[index] = passes[index].copyWith(
      state: state,
      error: error,
      metrics: metrics,
    );
    update(current().copyWith(passes: passes));
  }

  List<ReviewDisagreement> _findDisagreements(List<ReviewPass> passes) {
    final opinions = passes.where((p) => p.opinion != null).toList();
    final groups = <ReviewDisagreement>[];
    for (var i = 0; i < opinions.length; i++) {
      for (final left in opinions[i].opinion!.findings) {
        final sources = <ReviewFindingSource>[];
        for (var j = i + 1; j < opinions.length; j++) {
          for (final right in opinions[j].opinion!.findings) {
            if (_overlaps(left, right) && _materiallyDiffers(left, right)) {
              sources.add(
                ReviewFindingSource(
                  role: opinions[i].configuration.role,
                  finding: left,
                ),
              );
              sources.add(
                ReviewFindingSource(
                  role: opinions[j].configuration.role,
                  finding: right,
                ),
              );
            }
          }
        }
        if (sources.isNotEmpty && !groups.any((g) => _sameGroup(g, sources))) {
          groups.add(ReviewDisagreement(sources: _uniqueSources(sources)));
        }
      }
    }
    return groups;
  }

  bool _sameGroup(
    ReviewDisagreement group,
    List<ReviewFindingSource> sources,
  ) => group.sources.any(
    (a) => sources.any(
      (b) =>
          a.role == b.role &&
          a.finding.file == b.finding.file &&
          a.finding.startLine == b.finding.startLine,
    ),
  );
  List<ReviewFindingSource> _uniqueSources(List<ReviewFindingSource> input) =>
      input.fold(<ReviewFindingSource>[], (out, source) {
        if (!out.any(
          (x) =>
              x.role == source.role &&
              x.finding.file == source.finding.file &&
              x.finding.startLine == source.finding.startLine,
        )) {
          out.add(source);
        }
        return out;
      });
  bool _overlaps(ReviewFinding a, ReviewFinding b) =>
      a.file == b.file && a.startLine <= b.endLine && b.startLine <= a.endLine;
  bool _materiallyDiffers(ReviewFinding a, ReviewFinding b) =>
      a.category != b.category ||
      a.severity != b.severity ||
      a.title != b.title ||
      a.description != b.description;

  @override
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    final target = _target;
    if (target != null) {
      for (final child in List<String>.from(_children)) {
        await _abortOnce(target, child);
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    await _progress.close();
  }

  Future<bool> _abortOnce(ReviewTarget target, String child) {
    final state = _abortStates.putIfAbsent(child, _AbortState.new);
    if (state.confirmed) return Future.value(true);
    final inFlight = state.inFlight;
    if (inFlight != null) return inFlight;
    if (state.attempts >= 2) return Future.value(false);
    final attempt = () async {
      while (state.attempts < 2) {
        state.attempts++;
        try {
          await service.abort(target, child);
          state.confirmed = true;
          return true;
        } on Object {
          // Retry once before reporting that cleanup could not be confirmed.
        }
      }
      return false;
    }();
    state.inFlight = attempt.whenComplete(() {
      state.inFlight = null;
    });
    return state.inFlight!;
  }
}

final class _AbortState {
  int attempts = 0;
  bool confirmed = false;
  Future<bool>? inFlight;
}
