import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/capabilities/data/capabilities_repository.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/capabilities/domain/open_code_capabilities.dart';
import 'package:prompt/features/capabilities/domain/open_code_model.dart';
import 'package:prompt/features/capabilities/presentation/capabilities_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/review/data/review_repository.dart';
import 'package:prompt/features/review/data/review_history_store.dart';
import 'package:prompt/features/review/domain/review_entities.dart';
import 'package:prompt/features/review/presentation/review_screen.dart';
import 'package:prompt/features/review/presentation/review_view_model.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

class _Credentials implements CredentialsStore {
  const _Credentials();
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

class _FakeRepository implements ReviewRepository {
  _FakeRepository(this.snapshot, {this.loadOverride});
  final ReviewSnapshot snapshot;
  final Future<ReviewSnapshot> Function()? loadOverride;
  final progressController = StreamController<ReviewRun>.broadcast();
  final started = <List<ReviewReviewerConfiguration>>[];
  var cancelled = false;
  var disposed = false;
  ReviewDiffSource? lastSource;

  @override
  Stream<ReviewRun> get progress => progressController.stream;
  @override
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) {
    lastSource = source;
    return loadOverride?.call() ?? Future.value(snapshot);
  }

  @override
  Future<ReviewRun> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations, {
    Duration timeout = const Duration(seconds: 120),
    Duration globalTimeout = const Duration(seconds: 240),
  }) async {
    started.add(configurations);
    return ReviewRun(state: ReviewRunState.completed, snapshot: snapshot);
  }

  @override
  Future<void> cancel() async => cancelled = true;
  @override
  Future<void> dispose() async {
    disposed = true;
    await progressController.close();
  }
}

final _target = ReviewTarget(
  profile: ServerProfile(origin: Uri.parse('http://10.0.0.1')),
  session: OpenCodeSession(
    id: 's',
    projectId: 'p',
    directory: '/w',
    title: 's',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
);
final _snapshot = ReviewSnapshot(
  target: _target,
  files: const [
    ReviewFile(
      path: 'a.dart',
      status: 'modified',
      patch: '@@ -1 +1 @@\n-a\n+b',
    ),
  ],
);
final _models = List.generate(
  3,
  (i) => OpenCodeModel(
    providerId: 'provider$i',
    id: 'model$i',
    name: 'Model $i',
    isProviderConnected: true,
  ),
);

CapabilitiesViewModel _capabilities(List<OpenCodeModel> models) {
  final viewModel = CapabilitiesViewModel(
    CapabilitiesRepository(
      OpenCodeCapabilitiesService(
        OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
      ),
      const _Credentials(),
    ),
  );
  viewModel.value = CapabilitiesReady(
    OpenCodeCapabilities(models: models, agents: const [], commands: const []),
  );
  return viewModel;
}

Widget _screen(ReviewViewModel review, CapabilitiesViewModel capabilities) =>
    MaterialApp(
      home: ReviewScreen(
        key: UniqueKey(),
        target: _target,
        viewModel: review,
        capabilitiesViewModel: capabilities,
      ),
    );

ReviewPass _pass(
  ReviewRole role,
  ReviewPassState state, {
  ReviewOpinion? opinion,
  ReviewFailure? error,
}) => ReviewPass(
  configuration: ReviewReviewerConfiguration(
    role: role,
    model: ReviewModelConfiguration(providerId: 'p', modelId: role.name),
  ),
  state: state,
  opinion: opinion,
  error: error,
);

ReviewOpinion _opinion(ReviewRole role, {bool finding = true}) => ReviewOpinion(
  role: role,
  summary: 'summary',
  findings: finding
      ? [
          ReviewFinding(
            file: 'a.dart',
            startLine: 1,
            endLine: 1,
            side: 'new',
            category: ReviewFindingCategory.correctness,
            severity: ReviewSeverity.low,
            confidence: .8,
            title: 'Finding',
            description: 'Description',
            expectedBehavior: 'Expected',
            observedBehavior: 'Observed',
            preconditions: 'Preconditions',
            reproduction: 'Reproduction',
            impact: 'Impact',
            evidence: const [
              ReviewEvidence(kind: ReviewEvidenceKind.diff, text: 'Evidence'),
            ],
            suggestedTest: 'Suggested test',
          ),
        ]
      : const [],
);

ReviewRun _historyRun() => ReviewRun(
  state: ReviewRunState.partiallyFailed,
  snapshot: ReviewSnapshot.stored(
    target: _target,
    files: const [
      ReviewFile(path: 'a.dart', status: 'modified', patch: 'patch'),
      ReviewFile(path: 'b.dart', status: 'added', patch: 'patch'),
    ],
  ),
  passes: [
    _pass(
      ReviewRole.correctness,
      ReviewPassState.succeeded,
      opinion: _opinion(ReviewRole.correctness),
    ),
    _pass(
      ReviewRole.security,
      ReviewPassState.failed,
      opinion: _opinion(ReviewRole.security),
    ),
  ],
);

StoredReview _stored(String id, ReviewRun run) => StoredReview(
  id: id,
  serverProfileId: _target.profile.id,
  sessionId: _target.session.id,
  createdAt: DateTime.utc(2026),
  run: run,
);

void main() {
  testWidgets('desktop review content grows when the window is resized', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeRepository(_snapshot);
    await tester.pumpWidget(
      _screen(ReviewViewModel(repository), _capabilities(_models)),
    );
    await tester.pump();

    final bodyScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.vertical,
    );
    final narrowWidth = tester.getSize(bodyScroll).width;

    tester.view.physicalSize = const Size(1600, 900);
    await tester.pump();
    final wideWidth = tester.getSize(bodyScroll).width;

    expect(narrowWidth, greaterThan(1100));
    expect(wideWidth, greaterThan(narrowWidth + 300));
  });

  testWidgets(
    'loads setup with two defaults and starts two distinct configurations',
    (tester) async {
      final repository = _FakeRepository(_snapshot);
      await tester.pumpWidget(
        _screen(ReviewViewModel(repository), _capabilities(_models)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Model 0'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      await tester.tap(find.text('Start review'));
      await tester.pump();
      expect(repository.started.single, hasLength(2));
      expect(
        repository.started.single
            .map((c) => '${c.model.providerId}/${c.model.modelId}')
            .toSet(),
        hasLength(2),
      );
    },
  );

  testWidgets('defaults to different providers when available', (tester) async {
    final repository = _FakeRepository(_snapshot);
    final models = [
      const OpenCodeModel(
        providerId: 'provider0',
        id: 'model0',
        name: 'Model 0',
        isProviderConnected: true,
      ),
      const OpenCodeModel(
        providerId: 'provider0',
        id: 'model1',
        name: 'Model 1',
        isProviderConnected: true,
      ),
      const OpenCodeModel(
        providerId: 'provider1',
        id: 'model2',
        name: 'Model 2',
        isProviderConnected: true,
      ),
    ];
    await tester.pumpWidget(
      _screen(ReviewViewModel(repository), _capabilities(models)),
    );
    await tester.pump();

    await tester.tap(find.text('Start review'));
    await tester.pump();
    expect(repository.started.single.map((config) => config.model.providerId), [
      'provider0',
      'provider1',
    ]);
  });

  testWidgets('adds and removes an optional third reviewer', (tester) async {
    final repository = _FakeRepository(_snapshot);
    await tester.pumpWidget(
      _screen(ReviewViewModel(repository), _capabilities(_models)),
    );
    await tester.pump();

    await tester.tap(find.text('Add reviewer'));
    await tester.pump();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('remove-reviewer-testsAndRegressions')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('remove-reviewer-testsAndRegressions')),
    );
    await tester.pump();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    await tester.tap(find.text('Add reviewer'));
    await tester.pump();

    await tester.tap(find.text('Start review'));
    await tester.pump();
    expect(repository.started.single, hasLength(3));
  });

  testWidgets(
    'fewer than two models disables Start and short mobile setup scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final repository = _FakeRepository(_snapshot);
      await tester.pumpWidget(
        _screen(
          ReviewViewModel(repository),
          _capabilities(_models.take(1).toList()),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start review'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(
        find.text('At least two connected models are required.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'progressive states keep Cancel accessible and show failed pass error',
    (tester) async {
      final repository = _FakeRepository(_snapshot);
      final vm = ReviewViewModel(repository);
      await tester.pumpWidget(_screen(vm, _capabilities(_models)));
      await tester.pump();
      vm.value = ReviewRun(
        state: ReviewRunState.running,
        snapshot: _snapshot,
        passes: [
          _pass(ReviewRole.correctness, ReviewPassState.running),
          _pass(ReviewRole.security, ReviewPassState.succeeded),
          _pass(ReviewRole.testsAndRegressions, ReviewPassState.pending),
        ],
      );
      await tester.pump();
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      vm.value = ReviewRun(
        state: ReviewRunState.partiallyFailed,
        snapshot: _snapshot,
        passes: [
          _pass(
            ReviewRole.correctness,
            ReviewPassState.succeeded,
            opinion: _opinion(ReviewRole.correctness),
          ),
          _pass(
            ReviewRole.security,
            ReviewPassState.failed,
            error: const ReviewProviderFailure(
              'The model is rate limited. Try again later.',
              kind: ReviewProviderFailureKind.rateLimited,
            ),
          ),
          _pass(
            ReviewRole.testsAndRegressions,
            ReviewPassState.succeeded,
            opinion: _opinion(ReviewRole.testsAndRegressions, finding: false),
          ),
        ],
      );
      await tester.pump();
      expect(find.text('Review partially failed'), findsOneWidget);
      expect(
        find.text('Reason: The model is rate limited. Try again later.'),
        findsOneWidget,
      );

      vm.value = ReviewRun(
        state: ReviewRunState.failed,
        snapshot: _snapshot,
        passes: [_pass(ReviewRole.security, ReviewPassState.failed)],
      );
      await tester.pump();
      expect(
        find.text('Reason: The provider returned no failure details.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cancel callback and finding details, tabs, and no-findings semantics render',
    (tester) async {
      final repository = _FakeRepository(_snapshot);
      final vm = ReviewViewModel(repository);
      await tester.pumpWidget(_screen(vm, _capabilities(_models)));
      await tester.pump();
      vm.value = ReviewRun(
        state: ReviewRunState.running,
        snapshot: _snapshot,
        passes: [
          _pass(ReviewRole.correctness, ReviewPassState.running),
          _pass(ReviewRole.security, ReviewPassState.pending),
          _pass(ReviewRole.testsAndRegressions, ReviewPassState.pending),
        ],
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(repository.cancelled, isTrue);
      vm.value = ReviewRun(
        state: ReviewRunState.completed,
        snapshot: _snapshot,
        passes: [
          _pass(
            ReviewRole.correctness,
            ReviewPassState.succeeded,
            opinion: _opinion(ReviewRole.correctness),
          ),
        ],
      );
      await tester.pump();
      await tester.tap(find.text('Findings'));
      await tester.pump();
      await tester.tap(find.text('Finding'));
      await tester.pump();
      for (final label in [
        'HYPOTHESIS',
        'Anchor',
        'Role',
        'Expected / observed',
        'Reproduction',
        'Evidence',
        'Suggested test',
        'Confidence',
      ]) {
        expect(find.textContaining(label), findsWidgets);
      }
      for (final tab in ['Disagreements', 'Metrics', 'Diff']) {
        await tester.tap(find.text(tab), warnIfMissed: false);
        await tester.pump();
        expect(find.text(tab), findsWidgets);
      }
    },
  );

  testWidgets('disposal closes repository and ignores late snapshot', (
    tester,
  ) async {
    final completer = Completer<ReviewSnapshot>();
    final repository = _FakeRepository(
      _snapshot,
      loadOverride: () => completer.future,
    );
    final vm = ReviewViewModel(repository);
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(repository.disposed, isTrue);
    completer.complete(_snapshot);
    await tester.pump();
  });

  testWidgets('pluralizes overview finding and file counts', (tester) async {
    final repository = _FakeRepository(_snapshot);
    final vm = ReviewViewModel(repository);
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    vm.value = ReviewRun(
      state: ReviewRunState.completed,
      snapshot: _snapshot,
      passes: [
        _pass(
          ReviewRole.correctness,
          ReviewPassState.succeeded,
          opinion: _opinion(ReviewRole.correctness),
        ),
        _pass(
          ReviewRole.security,
          ReviewPassState.succeeded,
          opinion: _opinion(ReviewRole.security),
        ),
      ],
    );
    await tester.pump();

    expect(find.text('2 hypotheses across 1 file.'), findsOneWidget);
  });

  testWidgets(
    'distinguishes a valid empty result from a partial empty result',
    (tester) async {
      final repository = _FakeRepository(_snapshot);
      final vm = ReviewViewModel(repository);
      await tester.pumpWidget(_screen(vm, _capabilities(_models)));
      await tester.pump();
      final emptyPasses = ReviewRole.values
          .map(
            (role) => _pass(
              role,
              ReviewPassState.succeeded,
              opinion: _opinion(role, finding: false),
            ),
          )
          .toList();
      vm.value = ReviewRun(
        state: ReviewRunState.completed,
        snapshot: _snapshot,
        passes: emptyPasses,
      );
      await tester.pump();
      expect(
        find.textContaining('all opinions completed without hypotheses'),
        findsOneWidget,
      );
      vm.value = ReviewRun(
        state: ReviewRunState.partiallyFailed,
        snapshot: _snapshot,
        passes: [
          _pass(
            ReviewRole.correctness,
            ReviewPassState.failed,
            error: const ReviewProviderFailure('error'),
          ),
          ...emptyPasses.skip(1),
        ],
      );
      await tester.pump();
      expect(
        find.textContaining('not an all-successful result'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders each history state explicitly', (tester) async {
    final vm = ReviewViewModel(_FakeRepository(_snapshot));
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    for (final stateAndText in <(ReviewHistoryState, String)>[
      (const ReviewHistoryLoading(), 'Loading review history…'),
      (const ReviewHistoryEmpty(), 'No stored reviews yet.'),
      (const ReviewHistoryFailed(), 'Review history is unavailable.'),
    ]) {
      vm.historyState.value = stateAndText.$1;
      await tester.pump();
      expect(find.text(stateAndText.$2), findsOneWidget);
    }
  });

  testWidgets('history rows show counts and open/delete safely', (
    tester,
  ) async {
    final store = InMemoryReviewHistoryStore();
    await store.save(_stored('history', _historyRun()));
    final repository = _FakeRepository(_snapshot);
    final vm = ReviewViewModel(
      repository,
      historyStoreProvider: () async => store,
    );
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    await tester.pump();
    expect(find.text('2 files · 2 reviewers · 2 hypotheses'), findsOneWidget);
    await tester.tap(find.byTooltip('Open stored review'));
    await tester.pump();
    expect(find.text('Review partially failed'), findsOneWidget);
    expect(repository.started, isEmpty);
    await tester.tap(find.text('New review'));
    await tester.pump();
    expect(find.text('Contingent review'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete stored review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(await store.load('history'), isNotNull);
    await tester.tap(find.byTooltip('Delete stored review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(await store.load('history'), isNull);
  });

  testWidgets(
    'cost card uses typed pricing, limits, and updates with reviewers',
    (tester) async {
      final models = [
        for (var i = 0; i < 3; i++)
          OpenCodeModel(
            providerId: 'provider$i',
            id: 'model$i',
            name: 'Model $i',
            isProviderConnected: true,
            pricing: const OpenCodeModelPricing(input: 2),
            limits: const OpenCodeModelLimits(input: 1),
          ),
      ];
      final vm = ReviewViewModel(_FakeRepository(_snapshot));
      await tester.pumpWidget(_screen(vm, _capabilities(models)));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('review-cost-estimate')),
        findsOneWidget,
      );
      expect(find.textContaining('input tokens'), findsOneWidget);
      expect(
        find.textContaining('Theoretical minimum input: USD'),
        findsOneWidget,
      );
      expect(find.textContaining('Context/input limit warning'), findsWidgets);
      await tester.tap(find.text('Add reviewer'));
      await tester.pump();
      expect(find.textContaining('input tokens'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('remove-reviewer-testsAndRegressions')),
      );
      await tester.pump();

      final unknownVm = ReviewViewModel(_FakeRepository(_snapshot));
      await tester.pumpWidget(_screen(unknownVm, _capabilities(_models)));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD: unavailable'), findsOneWidget);
      expect(find.textContaining('Unknown pricing:'), findsOneWidget);
    },
  );

  testWidgets('picks what the review compares', (tester) async {
    final snapshot = ReviewSnapshot.stored(
      target: _target,
      files: const [
        ReviewFile(path: 'a.dart', status: 'modified', patch: 'patch'),
      ],
    );
    final repository = _FakeRepository(snapshot);
    final vm = ReviewViewModel(repository);
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();

    // The session diff is what a review defaults to.
    expect(repository.lastSource, ReviewDiffSource.session);
    expect(find.byKey(const ValueKey('review-diff-source')), findsOneWidget);

    await tester.tap(find.text('Uncommitted'));
    await tester.pump();
    expect(repository.lastSource, ReviewDiffSource.uncommitted);

    await tester.tap(find.text('Branch'));
    await tester.pump();
    expect(repository.lastSource, ReviewDiffSource.branch);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a source with nothing to show keeps the picker reachable', (
    tester,
  ) async {
    final snapshot = ReviewSnapshot.stored(
      target: _target,
      files: const [
        ReviewFile(path: 'a.dart', status: 'modified', patch: 'patch'),
      ],
    );
    final repository = _FakeRepository(
      snapshot,
      loadOverride: () => Future.error(
        const ReviewValidationException('There are no uncommitted changes.'),
      ),
    );
    final vm = ReviewViewModel(repository);
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    await tester.pump();

    expect(find.text('There are no uncommitted changes.'), findsOneWidget);
    // Without the picker here, an empty source would be a dead end.
    expect(find.byKey(const ValueKey('review-diff-source')), findsOneWidget);
  });

  testWidgets('renders a snapshot of server-shaped patches', (tester) async {
    // Real patches from OpenCode open with their own `diff --git` header and
    // can carry several hunks. Fixtures made of bare @@ blocks exercise a
    // different branch of the parser and hid a collision between files.
    final snapshot = ReviewSnapshot.stored(
      target: _target,
      files: const [
        ReviewFile(
          path: 'lib/features/a.dart',
          status: 'modified',
          patch:
              'diff --git a/lib/features/a.dart b/lib/features/a.dart\n'
              'index 1111111..2222222 100644\n'
              '--- a/lib/features/a.dart\n'
              '+++ b/lib/features/a.dart\n'
              '@@ -1,3 +1,3 @@\n'
              ' const first = 1;\n'
              '-const second = 2;\n'
              '+const second = 22;\n'
              '@@ -40,2 +40,3 @@\n'
              ' const tail = 3;\n'
              '+const added = 4;\n',
        ),
        ReviewFile(
          path: 'lib/features/b.dart',
          status: 'added',
          patch:
              'diff --git a/lib/features/b.dart b/lib/features/b.dart\n'
              'new file mode 100644\n'
              '--- /dev/null\n'
              '+++ b/lib/features/b.dart\n'
              '@@ -0,0 +1,2 @@\n'
              '+const created = true;\n'
              '+const other = false;\n',
        ),
        ReviewFile(path: 'assets/logo.png', status: 'modified', patch: ''),
      ],
    );
    final vm = ReviewViewModel(_FakeRepository(snapshot));
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    vm.value = ReviewRun(state: ReviewRunState.completed, snapshot: snapshot);
    await tester.pump();

    final diffTab = find.text('Diff').first;
    await tester.ensureVisible(diffTab);
    await tester.tap(diffTab);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('lib/features/a.dart'), findsOneWidget);
    expect(find.text('lib/features/b.dart'), findsOneWidget);
    // Each hunk announces itself so a reader sees where lines were skipped.
    expect(find.text('@@ -1,3 +1,3 @@'), findsOneWidget);
  });

  testWidgets('review diff keeps raw file paths and independent controls', (
    tester,
  ) async {
    final snapshot = ReviewSnapshot.stored(
      target: _target,
      files: const [
        ReviewFile(
          path: 'lib/first.dart',
          status: 'modified',
          patch: '@@ -1 +1 @@\n-old\n+new',
        ),
        ReviewFile(
          path: 'lib/second.dart',
          status: 'added',
          patch: '@@ -1 +1 @@\n-old2\n+new2',
        ),
      ],
    );
    final vm = ReviewViewModel(_FakeRepository(snapshot));
    await tester.pumpWidget(_screen(vm, _capabilities(_models)));
    await tester.pump();
    vm.value = ReviewRun(state: ReviewRunState.completed, snapshot: snapshot);
    await tester.pump();
    final diffTab = find.text('Diff').first;
    await tester.ensureVisible(diffTab);
    await tester.tap(diffTab);
    await tester.pump();
    // The diff is shown directly: selecting the tab is enough, with no second
    // tap on an outer expansion tile.
    expect(find.text('Diff · 2 files'), findsOneWidget);
    expect(find.text('lib/first.dart'), findsOneWidget);
    expect(find.text('lib/second.dart'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byIcon(Icons.expand_less), findsNWidgets(2));
    // Tapping a file's header collapses that file and leaves the other alone.
    await tester.tap(find.text('lib/first.dart'));
    await tester.pump();
    expect(find.text('new'), findsNothing);
    expect(find.text('new2'), findsOneWidget);
  });
}
