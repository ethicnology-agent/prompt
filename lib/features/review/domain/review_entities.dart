import '../../connection/connection.dart';
import '../../sessions/sessions.dart';

enum ReviewRole { correctness, security, testsAndRegressions }

enum ReviewSeverity { info, low, medium, high, critical }

enum ReviewFindingCategory { correctness, security, testsAndRegressions }

enum ReviewEvidenceKind { diff, documentation, test, external }

enum ReviewPassState {
  pending,
  running,
  succeeded,
  failed,
  timedOut,
  cancelled,
}

enum ReviewRunState {
  idle,
  loading,
  running,
  completed,
  partiallyFailed,
  failed,
  cancelled,
}

enum ReviewFindingStatus { hypothesis }

class ReviewTarget {
  const ReviewTarget({required this.profile, required this.session});
  final ServerProfile profile;
  final OpenCodeSession session;
}

/// What a review compares.
///
/// A comparison has two sides, and only the new one varies here: the server
/// exposes the working tree and the current branch, each against its natural
/// base. Comparing two arbitrary refs would need parameters `GET /vcs/diff`
/// does not accept yet.
enum ReviewDiffSource {
  /// The newest non-empty diff produced by a message in this session.
  session('Session'),

  /// Everything not yet committed in the working tree.
  uncommitted('Uncommitted'),

  /// The current branch against the repository's default branch.
  branch('Branch');

  const ReviewDiffSource(this.label);

  final String label;

  String get emptyMessage => switch (this) {
    ReviewDiffSource.session => 'The session diff is empty.',
    ReviewDiffSource.uncommitted => 'There are no uncommitted changes.',
    ReviewDiffSource.branch =>
      'This branch has no changes against the default branch.',
  };
}

class ReviewFile {
  const ReviewFile({
    required this.path,
    required this.status,
    required this.patch,
  });
  final String path;
  final String status;
  final String patch;
}

class ReviewSnapshot {
  ReviewSnapshot({
    required this.target,
    required List<ReviewFile> files,
    this.source = ReviewDiffSource.session,
  }) : files = List.unmodifiable(files) {
    if (files.isEmpty) {
      throw ReviewValidationException(source.emptyMessage);
    }
  }

  /// Reopens a persisted snapshot, including a server response with no files.
  ReviewSnapshot.stored({
    required this.target,
    required List<ReviewFile> files,
    this.source = ReviewDiffSource.session,
  }) : files = List.unmodifiable(files);
  final ReviewTarget target;
  final ReviewDiffSource source;
  final List<ReviewFile> files;
  String get fullDiff => files
      .map((file) => '--- ${file.path} (${file.status})\n${file.patch}')
      .join('\n');
}

class ReviewModelConfiguration {
  const ReviewModelConfiguration({
    required this.providerId,
    required this.modelId,
  });
  final String providerId;
  final String modelId;
}

class ReviewReviewerConfiguration {
  const ReviewReviewerConfiguration({required this.role, required this.model});
  final ReviewRole role;
  final ReviewModelConfiguration model;
}

class ReviewEvidence {
  const ReviewEvidence({required this.kind, required this.text});
  final ReviewEvidenceKind kind;
  final String text;
}

class ReviewFinding {
  const ReviewFinding({
    required this.file,
    required this.startLine,
    required this.endLine,
    required this.side,
    required this.category,
    required this.severity,
    required this.confidence,
    required this.title,
    required this.description,
    required this.expectedBehavior,
    required this.observedBehavior,
    required this.preconditions,
    required this.reproduction,
    required this.impact,
    required this.evidence,
    required this.suggestedTest,
  });
  final String file;
  final int startLine;
  final int endLine;
  final String side;
  final ReviewFindingCategory category;
  final ReviewSeverity severity;
  final double confidence;
  final String title;
  final String description;
  final String expectedBehavior;
  final String observedBehavior;
  final String preconditions;
  final String reproduction;
  final String impact;
  final List<ReviewEvidence> evidence;
  final String suggestedTest;
  ReviewFindingStatus get status => ReviewFindingStatus.hypothesis;
}

class ReviewOpinion {
  const ReviewOpinion({
    required this.role,
    required this.findings,
    required this.summary,
  });
  final ReviewRole role;
  final List<ReviewFinding> findings;
  final String summary;
}

class ReviewPassMetrics {
  const ReviewPassMetrics({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.cacheTokens = 0,
    this.cost = 0,
    this.duration,
  });
  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cacheTokens;
  final double cost;
  final Duration? duration;
}

class ReviewDisagreement {
  const ReviewDisagreement({required this.sources});
  final List<ReviewFindingSource> sources;
  List<ReviewFinding> get findings =>
      sources.map((source) => source.finding).toList(growable: false);
}

class ReviewFindingSource {
  const ReviewFindingSource({required this.role, required this.finding});
  final ReviewRole role;
  final ReviewFinding finding;
}

class ReviewPass {
  const ReviewPass({
    required this.configuration,
    required this.state,
    this.childSessionId,
    this.opinion,
    this.metrics = const ReviewPassMetrics(),
    this.error,
  });
  final ReviewReviewerConfiguration configuration;
  final ReviewPassState state;
  final String? childSessionId;
  final ReviewOpinion? opinion;
  final ReviewPassMetrics metrics;
  final ReviewFailure? error;

  ReviewPass copyWith({
    ReviewPassState? state,
    String? childSessionId,
    ReviewOpinion? opinion,
    ReviewPassMetrics? metrics,
    ReviewFailure? error,
  }) => ReviewPass(
    configuration: configuration,
    state: state ?? this.state,
    childSessionId: childSessionId ?? this.childSessionId,
    opinion: opinion ?? this.opinion,
    metrics: metrics ?? this.metrics,
    error: error ?? this.error,
  );
}

class ReviewRun {
  const ReviewRun({
    required this.state,
    this.snapshot,
    this.passes = const [],
    this.disagreements = const [],
    this.error,
  });
  final ReviewRunState state;
  final ReviewSnapshot? snapshot;
  final List<ReviewPass> passes;
  final List<ReviewDisagreement> disagreements;
  final ReviewFailure? error;

  ReviewRun copyWith({
    ReviewRunState? state,
    ReviewSnapshot? snapshot,
    List<ReviewPass>? passes,
    List<ReviewDisagreement>? disagreements,
    ReviewFailure? error,
  }) => ReviewRun(
    state: state ?? this.state,
    snapshot: snapshot ?? this.snapshot,
    passes: passes ?? this.passes,
    disagreements: disagreements ?? this.disagreements,
    error: error ?? this.error,
  );
}

sealed class ReviewFailure {
  const ReviewFailure(this.message);
  final String message;
}

class ReviewValidationFailure extends ReviewFailure {
  const ReviewValidationFailure(super.message);
}

enum ReviewProviderFailureKind {
  structuredOutputFailed,
  structuredOutputInvalid,
  accessDenied,
  rateLimited,
  unavailable,
  unknown,
}

class ReviewProviderFailure extends ReviewFailure {
  const ReviewProviderFailure(
    super.message, {
    this.kind = ReviewProviderFailureKind.unknown,
    this.metrics = const ReviewPassMetrics(),
  });

  final ReviewProviderFailureKind kind;
  final ReviewPassMetrics metrics;
}

class ReviewTimeoutFailure extends ReviewFailure {
  const ReviewTimeoutFailure(super.message);
}

class ReviewCancelledFailure extends ReviewFailure {
  const ReviewCancelledFailure([super.message = 'Review cancelled.']);
}

class ReviewValidationException implements Exception {
  const ReviewValidationException(this.message);
  final String message;
}
