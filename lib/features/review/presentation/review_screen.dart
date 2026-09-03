import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/capabilities.dart';
import '../../diff/diff.dart';
import '../domain/review_entities.dart';
import 'review_view_model.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    required this.target,
    required this.viewModel,
    required this.capabilitiesViewModel,
    super.key,
  });

  final ReviewTarget target;
  final ReviewViewModel viewModel;
  final CapabilitiesViewModel capabilitiesViewModel;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _roles = <ReviewRole>[ReviewRole.correctness, ReviewRole.security];
  final _selection = <ReviewRole, String?>{};
  int _tab = 0;
  ReviewDiffSource _source = ReviewDiffSource.session;
  ReviewSnapshot? _parsedSnapshot;
  List<DiffFile> _parsedFiles = const <DiffFile>[];

  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.loadSnapshot(widget.target, source: _source));
    unawaited(
      widget.viewModel.history(
        widget.target.profile.id,
        widget.target.session.id,
      ),
    );
    widget.capabilitiesViewModel.addListener(_selectDefaults);
    _selectDefaults();
  }

  @override
  void dispose() {
    widget.capabilitiesViewModel.removeListener(_selectDefaults);
    widget.viewModel.dispose();
    super.dispose();
  }

  void _selectDefaults() {
    final state = widget.capabilitiesViewModel.value;
    if (state is! CapabilitiesReady) return;
    final models = state.capabilities.models
        .where((model) => model.isProviderConnected)
        .toList();
    final available = models.map(_modelKey).toSet();
    final used = <String>{};
    final usedProviders = <String>{};
    for (var i = 0; i < _roles.length; i++) {
      final role = _roles[i];
      final selected = _selection[role];
      if (selected != null &&
          available.contains(selected) &&
          used.add(selected)) {
        usedProviders.add(
          models.firstWhere((model) => _modelKey(model) == selected).providerId,
        );
        continue;
      }
      final candidates = models
          .where((model) => !used.contains(_modelKey(model)))
          .toList();
      OpenCodeModel? replacement;
      for (final candidate in candidates) {
        if (!usedProviders.contains(candidate.providerId)) {
          replacement = candidate;
          break;
        }
      }
      replacement ??= candidates.isEmpty ? null : candidates.first;
      final replacementKey = replacement == null
          ? null
          : _modelKey(replacement);
      _selection[role] = replacementKey;
      if (replacementKey != null) {
        used.add(replacementKey);
        usedProviders.add(replacement!.providerId);
      }
    }
    if (mounted) setState(() {});
  }

  void _addReviewer() {
    for (final role in ReviewRole.values) {
      if (!_roles.contains(role)) {
        _roles.add(role);
        _selectDefaults();
        return;
      }
    }
  }

  void _removeReviewer(ReviewRole role) {
    if (_roles.length <= 2) return;
    setState(() {
      _roles.remove(role);
      _selection.remove(role);
    });
  }

  String _role(ReviewRole role) => switch (role) {
    ReviewRole.correctness => 'Correctness',
    ReviewRole.security => 'Security',
    ReviewRole.testsAndRegressions => 'Tests & regressions',
  };

  String _passState(ReviewPassState state) => switch (state) {
    ReviewPassState.pending => 'Pending',
    ReviewPassState.running => 'Running',
    ReviewPassState.succeeded => 'Succeeded',
    ReviewPassState.failed => 'Failed',
    ReviewPassState.timedOut => 'Timed out',
    ReviewPassState.cancelled => 'Cancelled',
  };

  bool get _valid {
    final selected = _selection.values.whereType<String>().toList();
    return _roles.length >= 2 &&
        selected.length == _roles.length &&
        selected.toSet().length == _roles.length;
  }

  Future<void> _start() async {
    if (!_valid) return;
    await widget.viewModel.start(
      widget.target,
      _roles
          .map(
            (role) => ReviewReviewerConfiguration(
              role: role,
              model: ReviewModelConfiguration(
                providerId: _selection[role]!.split('\u0000').first,
                modelId: _selection[role]!
                    .split('\u0000')
                    .skip(1)
                    .join('\u0000'),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review diff')),
      body: ValueListenableBuilder<ReviewRun>(
        valueListenable: widget.viewModel,
        builder: (context, run, _) => LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth,
            child: run.state != ReviewRunState.idle && _tab == 5
                // The diff runs to both edges: on a phone a 16px gutter on each
                // side is width taken from the code. Its own header and tabs
                // keep their gutter, see _gutter.
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _body(run),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _body(run),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _body(ReviewRun run) {
    if (run.state == ReviewRunState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (run.state == ReviewRunState.failed && run.snapshot == null) {
      // The picker stays: a source with nothing to show is a normal answer,
      // and the way out of it is to pick another one.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sourcePicker(),
          const SizedBox(height: 24),
          _message(
            run.error?.message ?? 'Unable to load the diff.',
            retry: true,
          ),
        ],
      );
    }
    final snapshot = run.snapshot;
    if (snapshot == null) return _message('Loading the diff…');
    if (run.state == ReviewRunState.idle) return _setup(snapshot);
    return _results(run);
  }

  Widget _message(String text, {bool retry = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, textAlign: TextAlign.center),
      if (retry) ...[
        const SizedBox(height: 12),
        FilledButton(onPressed: _reload, child: const Text('Retry')),
      ],
    ],
  );

  Widget _setup(ReviewSnapshot snapshot) {
    final capabilityState = widget.capabilitiesViewModel.value;
    final models = capabilityState is CapabilitiesReady
        ? capabilityState.capabilities.models
              .where((m) => m.isProviderConnected)
              .toList()
        : const <OpenCodeModel>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sourcePicker(),
        const SizedBox(height: 16),
        ValueListenableBuilder<ReviewHistoryState>(
          valueListenable: widget.viewModel.historyState,
          builder: (context, historyState, _) {
            if (historyState is ReviewHistoryLoading) {
              return const _HistoryState(message: 'Loading review history…');
            }
            if (historyState is ReviewHistoryEmpty) {
              return const _HistoryState(message: 'No stored reviews yet.');
            }
            if (historyState is ReviewHistoryFailed) {
              return const _HistoryState(
                message: 'Review history is unavailable.',
              );
            }
            final summaries = (historyState as ReviewHistoryReady).items;
            return Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Review history'),
                ),
                for (final summary in summaries)
                  ListTile(
                    key: ValueKey('review-history-${summary.id}'),
                    title: Text(
                      '${summary.state.name} · ${summary.createdAt.toLocal()}',
                    ),
                    subtitle: Text(
                      '${summary.fileCount} ${summary.fileCount == 1 ? 'file' : 'files'} · '
                      '${summary.passCount} ${summary.passCount == 1 ? 'reviewer' : 'reviewers'} · '
                      '${summary.findingCount} ${summary.findingCount == 1 ? 'hypothesis' : 'hypotheses'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.open_in_new),
                          tooltip: 'Open stored review',
                          onPressed: () =>
                              widget.viewModel.loadHistory(summary.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete stored review',
                          onPressed: () async {
                            if (!context.mounted) return;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete review?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await widget.viewModel.deleteHistory(
                                summary.id,
                                profileId: widget.target.profile.id,
                                sessionId: widget.target.session.id,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                const Divider(),
              ],
            );
          },
        ),
        Text(
          'Contingent review',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${snapshot.files.length} files · ${snapshot.files.fold<int>(0, (n, f) => n + _additions(f.patch))} additions · ${snapshot.files.fold<int>(0, (n, f) => n + _deletions(f.patch))} deletions',
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Privacy: the diff is sent to the providers selected below. Every result starts as a hypothesis and requires human review.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (capabilityState is CapabilitiesLoading ||
            capabilityState is CapabilitiesIdle)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading connected models',
          ),
        if (capabilityState is CapabilitiesError)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Connected models unavailable: ${capabilityState.failure.message}',
                ),
              ),
              TextButton(
                onPressed: widget.capabilitiesViewModel.retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        for (final role in _roles)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('review-selector-${role.name}'),
                    initialValue: _selection[role],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _role(role)),
                    items: models
                        .map(
                          (model) => DropdownMenuItem(
                            value: _modelKey(model),
                            child: Text(
                              '${model.providerId} · ${model.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (model) =>
                        setState(() => _selection[role] = model),
                  ),
                ),
                if (_roles.length > 2) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('remove-reviewer-${role.name}'),
                    tooltip: 'Remove ${_role(role)} reviewer',
                    onPressed: () => _removeReviewer(role),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ],
            ),
          ),
        if (_roles.length < ReviewRole.values.length)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: models.length > _roles.length ? _addReviewer : null,
              icon: const Icon(Icons.add),
              label: const Text('Add reviewer'),
            ),
          ),
        if (_roles.length < ReviewRole.values.length)
          const SizedBox(height: 12),
        if (models.length < _roles.length)
          Text(
            'At least ${_roles.length == 2 ? 'two' : 'three'} connected models are required.',
          ),
        if (models.length >= _roles.length && !_valid)
          const Text('Select a distinct connected model for each reviewer.'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _valid ? _start : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start review'),
        ),
        if (_valid) _costCard(snapshot, models),
        const SizedBox(height: 24),
        _diff(snapshot, fillAvailableSpace: false),
      ],
    );
  }

  Widget _costCard(ReviewSnapshot snapshot, List<OpenCodeModel> models) {
    final selected = models
        .where((model) => _selection.values.contains(_modelKey(model)))
        .toList();
    final configurations = [
      for (final role in _roles)
        ReviewReviewerConfiguration(
          role: role,
          model: ReviewModelConfiguration(
            providerId: _selection[role]!.split('\u0000').first,
            modelId: _selection[role]!.split('\u0000').skip(1).join('\u0000'),
          ),
        ),
    ];
    final estimate = widget.viewModel.estimate(
      snapshot,
      selected,
      configurations,
    );
    if (estimate == null) return const SizedBox.shrink();
    final usd = estimate.totalUsdRange;
    return Card(
      key: const ValueKey('review-cost-estimate'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approximate input estimate (not a quote)'),
            Text(
              '${estimate.totalTokenRange.lower}–${estimate.totalTokenRange.upper} input tokens',
            ),
            Text(
              usd == null
                  ? 'Theoretical minimum USD: unavailable (model pricing unknown).'
                  : 'Theoretical minimum input: USD ${usd.lower.toStringAsFixed(4)}–${usd.upper.toStringAsFixed(4)}.',
            ),
            if (estimate.unavailableModelIds.isNotEmpty)
              Text(
                'Unknown pricing: ${estimate.unavailableModelIds.join(', ')}',
              ),
            for (final violation in estimate.violations)
              Text(
                'Context/input limit warning for ${violation.modelId}: estimated upper bound ${violation.estimatedUpperBound}, limit ${violation.limit}.',
              ),
          ],
        ),
      ),
    );
  }

  void _reload() {
    _parsedSnapshot = null;
    unawaited(widget.viewModel.loadSnapshot(widget.target, source: _source));
  }

  /// Chooses what the review compares.
  ///
  /// Only the new side varies: the server offers the working tree and the
  /// current branch, each against its natural base. Comparing two arbitrary
  /// refs needs parameters the diff endpoint does not accept yet.
  Widget _sourcePicker() => Align(
    alignment: Alignment.centerLeft,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<ReviewDiffSource>(
        key: const ValueKey('review-diff-source'),
        segments: [
          for (final source in ReviewDiffSource.values)
            ButtonSegment(value: source, label: Text(source.label)),
        ],
        selected: {_source},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _source = selection.first);
          _reload();
        },
      ),
    ),
  );

  /// Restores the side gutter the diff tab drops from the page padding.
  ///
  /// Only the diff itself should reach the screen edges; the run header, the
  /// pass list and the tab bar still read better inset.
  Widget _gutter(Widget child) => _tab == 5
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        )
      : child;

  Widget _results(ReviewRun run) {
    final findings = [
      for (final pass in run.passes)
        for (final finding in pass.opinion?.findings ?? const <ReviewFinding>[])
          (pass.configuration.role, finding),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _gutter(
          Row(
            children: [
              Expanded(
                child: Text(
                  _runTitle(run),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (run.state == ReviewRunState.running)
                OutlinedButton(
                  onPressed: widget.viewModel.cancel,
                  child: const Text('Cancel'),
                ),
              if (run.state != ReviewRunState.running)
                TextButton(onPressed: _reload, child: const Text('New review')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final pass in run.passes) _gutter(_passTile(pass)),
        const SizedBox(height: 8),
        _gutter(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Overview')),
                ButtonSegment(value: 1, label: Text('Findings')),
                ButtonSegment(value: 2, label: Text('Opinions')),
                ButtonSegment(value: 3, label: Text('Disagreements')),
                ButtonSegment(value: 4, label: Text('Metrics')),
                ButtonSegment(value: 5, label: Text('Diff')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          0 => _overview(run, findings.map((e) => e.$2).toList()),
          1 => _findings(findings),
          2 => _opinions(run),
          3 => _disagreements(run),
          4 => _metrics(run),
          5 => _diff(run.snapshot!, fillAvailableSpace: true),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }

  Widget _passTile(ReviewPass pass) {
    final reason = _failureReason(pass);
    return ListTile(
      leading: Icon(_icon(pass.state)),
      title: Text(_role(pass.configuration.role)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pass.configuration.model.providerId} · ${pass.configuration.model.modelId}',
          ),
          if (reason != null)
            Text(
              'Reason: $reason',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing: Semantics(
        label: '${_role(pass.configuration.role)}: ${_passState(pass.state)}',
        liveRegion: true,
        child: Text(_passState(pass.state)),
      ),
    );
  }

  String? _failureReason(ReviewPass pass) {
    if (pass.state != ReviewPassState.failed &&
        pass.state != ReviewPassState.timedOut &&
        pass.state != ReviewPassState.cancelled) {
      return null;
    }
    final message = pass.error?.message.trim();
    if (message != null && message.isNotEmpty) return message;
    return switch (pass.state) {
      ReviewPassState.failed => 'The provider returned no failure details.',
      ReviewPassState.timedOut => 'The reviewer timed out.',
      ReviewPassState.cancelled => 'The reviewer was cancelled.',
      _ => null,
    };
  }

  Widget _overview(ReviewRun run, List<ReviewFinding> findings) {
    if (findings.isNotEmpty) {
      final findingCount = findings.length;
      final fileCount = run.snapshot?.files.length ?? 0;
      return Text(
        '$findingCount ${findingCount == 1 ? 'hypothesis' : 'hypotheses'} across $fileCount ${fileCount == 1 ? 'file' : 'files'}.',
      );
    }
    return Text(
      run.state == ReviewRunState.completed &&
              run.passes.every((p) => p.state == ReviewPassState.succeeded)
          ? 'No findings. This is a valid positive result; all opinions completed without hypotheses.'
          : 'No findings were produced by the completed passes. The review is not an all-successful result.',
    );
  }

  Widget _opinions(ReviewRun run) => Column(
    children: [
      for (final p in run.passes)
        if (p.opinion != null)
          ListTile(
            title: Text(_role(p.configuration.role)),
            subtitle: Text(p.opinion!.summary),
          ),
    ],
  );
  Widget _disagreements(ReviewRun run) => run.disagreements.isEmpty
      ? const Text('No disagreements.')
      : Column(
          children: [
            for (final d in run.disagreements)
              Card(
                child: Text(
                  '${d.sources.length} reviewers disagree at ${d.findings.first.file}:${d.findings.first.startLine}',
                ),
              ),
          ],
        );
  Widget _metrics(ReviewRun run) => Column(
    children: [
      for (final p in run.passes)
        ListTile(
          title: Text(_role(p.configuration.role)),
          subtitle: Text(
            'Input ${p.metrics.inputTokens} · output ${p.metrics.outputTokens} · cost ${p.metrics.cost}',
          ),
        ),
    ],
  );
  Widget _findings(List<(ReviewRole, ReviewFinding)> findings) =>
      findings.isEmpty
      ? const Text('No findings.')
      : ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: findings.length,
          itemBuilder: (context, i) {
            final (role, f) = findings[i];
            return Card(
              child: ExpansionTile(
                title: Text(f.title),
                subtitle: Text(
                  '${f.severity.name.toUpperCase()} · HYPOTHESIS · ${_role(role)} · ${f.file}:${f.startLine}–${f.endLine}',
                ),
                children: [
                  ListTile(
                    title: const Text('Description'),
                    subtitle: Text(f.description),
                  ),
                  ListTile(
                    title: const Text('Anchor'),
                    subtitle: Text(
                      '${f.file}:${f.startLine}–${f.endLine} (${f.side})',
                    ),
                  ),
                  ListTile(
                    title: const Text('Role'),
                    subtitle: Text(_role(role)),
                  ),
                  ListTile(
                    title: const Text('Expected / observed'),
                    subtitle: Text(
                      '${f.expectedBehavior}\n${f.observedBehavior}',
                    ),
                  ),
                  ListTile(
                    title: const Text('Reproduction'),
                    subtitle: Text('${f.preconditions}\n${f.reproduction}'),
                  ),
                  ListTile(
                    title: const Text('Evidence'),
                    subtitle: Text(f.evidence.map((e) => e.text).join('\n')),
                  ),
                  ListTile(
                    title: const Text('Suggested test'),
                    subtitle: Text(f.suggestedTest),
                  ),
                  ListTile(
                    title: const Text('Confidence'),
                    subtitle: Text('Uncalibrated confidence: ${f.confidence}'),
                  ),
                ],
              ),
            );
          },
        );

  /// Parses a snapshot's patches once and reuses the result.
  ///
  /// A snapshot is immutable and bounded to 200,000 patch characters, while
  /// this screen rebuilds on every view-model notification — which arrive
  /// steadily during a run. Re-parsing that text on each build is work whose
  /// result cannot differ.
  List<DiffFile> _diffFiles(ReviewSnapshot snapshot) {
    if (identical(_parsedSnapshot, snapshot)) return _parsedFiles;
    _parsedFiles = [
      for (final file in snapshot.files)
        ...UnifiedDiffParser.parseFile(file.path, file.patch).files,
    ];
    _parsedSnapshot = snapshot;
    return _parsedFiles;
  }

  /// The diff, shown directly rather than behind an expansion tile.
  ///
  /// [fillAvailableSpace] must be true only where the surrounding column has a
  /// bounded height, which is the dedicated Diff tab. Everywhere else the diff
  /// sits inside a scrolling column, where it must carry its own height and
  /// where an [Expanded] would have no space to claim.
  Widget _diff(ReviewSnapshot snapshot, {required bool fillAvailableSpace}) {
    final files = _diffFiles(snapshot);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        files.length == 1 ? 'Diff · 1 file' : 'Diff · ${files.length} files',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    final viewer = DiffViewer(document: DiffDocument(files: files));
    if (fillAvailableSpace) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: viewer),
          ],
        ),
      );
    }
    // A preview inside a scrolling page: follow the viewport rather than a
    // fixed window, which left the diff letterboxed on a desktop pane.
    final height = (MediaQuery.sizeOf(context).height * 0.62).clamp(
      280.0,
      900.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: height, child: viewer),
      ],
    );
  }

  IconData _icon(ReviewPassState state) => switch (state) {
    ReviewPassState.succeeded => Icons.check_circle,
    ReviewPassState.failed => Icons.error,
    ReviewPassState.timedOut => Icons.timer_off,
    ReviewPassState.cancelled => Icons.cancel,
    _ => Icons.hourglass_empty,
  };
  int _additions(String patch) => patch
      .split('\n')
      .where((l) => l.startsWith('+') && !l.startsWith('+++'))
      .length;
  int _deletions(String patch) => patch
      .split('\n')
      .where((l) => l.startsWith('-') && !l.startsWith('---'))
      .length;
  String _modelKey(OpenCodeModel model) =>
      '${model.providerId}\u0000${model.id}';
  String _runTitle(ReviewRun run) => switch (run.state) {
    ReviewRunState.running => 'Review in progress',
    ReviewRunState.completed => 'Review complete',
    ReviewRunState.partiallyFailed => 'Review partially failed',
    ReviewRunState.failed => 'Review failed',
    ReviewRunState.cancelled => 'Review cancelled',
    _ => 'Review',
  };
}

class _HistoryState extends StatelessWidget {
  const _HistoryState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(message));
}
