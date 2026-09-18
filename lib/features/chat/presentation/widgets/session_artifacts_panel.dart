import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import 'package:flutter/foundation.dart';

import '../../domain/session_artifacts.dart';

/// Shows the todos and file diffs OpenCode reports for the active session.
class SessionArtifactsPanel extends StatelessWidget {
  const SessionArtifactsPanel({
    required this.state,
    required this.onRefresh,
    this.lazy = false,
    super.key,
  });

  final SessionArtifactsState state;
  final Future<void> Function({String? messageId}) onRefresh;

  /// Set this only when the parent gives the panel a finite height. The
  /// default keeps the panel composable in an outer scroll view.
  final bool lazy;

  @override
  Widget build(BuildContext context) {
    if (lazy && state is SessionArtifactsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Semantics(
      container: true,
      label: 'Session artifacts',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Session artifacts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            switch (state) {
              SessionArtifactsLoading() => Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(
                  label: 'Loading session artifacts',
                  child: const CircularProgressIndicator(),
                ),
              ),
              SessionArtifactsError(:final failure) => Row(
                children: [
                  Expanded(child: Text(failure.message)),
                  AppButton(
                    label: 'Retry',
                    variant: AppButtonVariant.tertiary,
                    onPressed: onRefresh,
                  ),
                ],
              ),
              SessionArtifactsReady(:final todos, :final diffs) =>
                lazy
                    ? Expanded(
                        child: _LazyArtifactList(
                          todos: todos,
                          diffs: diffs,
                          onRefresh: onRefresh,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Todos (${todos.length}) · Changed files (${diffs.length})',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              AppIconButton(
                                icon: Icons.refresh_rounded,
                                tooltip: 'Refresh session artifacts',
                                onPressed: onRefresh,
                              ),
                            ],
                          ),
                          if (todos.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No todos reported for this session.',
                              ),
                            )
                          else
                            for (final todo in todos) _TodoRow(todo: todo),
                          if (diffs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No changed files reported for this session.',
                              ),
                            )
                          else
                            for (final diff in diffs) _DiffRow(diff: diff),
                        ],
                      ),
            },
          ],
        ),
      ),
    );
  }
}

class _LazyArtifactList extends StatelessWidget {
  const _LazyArtifactList({
    required this.todos,
    required this.diffs,
    required this.onRefresh,
  });

  final List<SessionTodo> todos;
  final List<SessionFileDiff> diffs;
  final Future<void> Function({String? messageId}) onRefresh;

  @override
  Widget build(BuildContext context) {
    final itemCount =
        1 +
        (todos.isEmpty ? 1 : todos.length) +
        (diffs.isEmpty ? 1 : diffs.length);
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'Todos (${todos.length}) · Changed files (${diffs.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh session artifacts',
                onPressed: onRefresh,
              ),
            ],
          );
        }
        if (todos.isEmpty && index == 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No todos reported for this session.'),
          );
        }
        final todoOffset = todos.isEmpty ? 2 : 1;
        if (index < todoOffset + todos.length) {
          return _TodoRow(todo: todos[index - todoOffset]);
        }
        if (diffs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No changed files reported for this session.'),
          );
        }
        return _DiffRow(diff: diffs[index - todoOffset - todos.length]);
      },
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.todo});

  final SessionTodo todo;

  @override
  Widget build(BuildContext context) {
    final complete = todo.status == SessionTodoStatus.completed;
    return Semantics(
      label:
          '${todo.content}, ${todo.status.name}, ${todo.priority.name} priority',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          complete ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        ),
        title: SelectableText(
          todo.content,
          style: complete
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          '${_todoStatusLabel(todo.status)} · ${todo.priority.name}',
        ),
      ),
    );
  }
}

class _DiffRow extends StatefulWidget {
  const _DiffRow({required this.diff});

  final SessionFileDiff diff;

  @override
  State<_DiffRow> createState() => _DiffRowState();
}

class _DiffRowState extends State<_DiffRow> {
  static const _previewLines = 12;
  bool _expanded = false;
  bool _loading = false;
  List<String>? _lines;

  SessionFileDiff get diff => widget.diff;

  Future<void> _expand() async {
    setState(() => _loading = true);
    final lines = await compute(_splitPatch, diff.patch);
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _expanded = true;
      _loading = false;
    });
  }

  Widget _patch(BuildContext context) {
    if (diff.patch.isEmpty) {
      return const Text('The server reported no patch for this file.');
    }
    final lines = _lines;
    if (!_expanded || lines == null) {
      final preview = diff.patch.split('\n').take(_previewLines).join('\n');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(preview, style: _codeStyle(context)),
          if (diff.patch.split('\n').length > _previewLines)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Load full patch',
                variant: AppButtonVariant.tertiary,
                busy: _loading,
                icon: Icons.unfold_more,
                onPressed: _loading ? null : _expand,
              ),
            ),
        ],
      );
    }
    return SizedBox(
      height: 280,
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, index) =>
            SelectableText(lines[index], style: _codeStyle(context)),
      ),
    );
  }

  TextStyle? _codeStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

  @override
  Widget build(BuildContext context) {
    final counters = '+${diff.additions} · -${diff.deletions}';
    return ExpansionTile(
      initiallyExpanded: diff.patch.split('\n').length > _previewLines,
      tilePadding: EdgeInsets.zero,
      title: SelectableText(diff.file.isEmpty ? 'Changed file' : diff.file),
      subtitle: Text(
        diff.status == null ? counters : '${diff.status} · $counters',
      ),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: _patch(context),
        ),
      ],
    );
  }
}

List<String> _splitPatch(String patch) => patch.split('\n');

String _todoStatusLabel(SessionTodoStatus status) => switch (status) {
  SessionTodoStatus.pending => 'Pending',
  SessionTodoStatus.inProgress => 'In progress',
  SessionTodoStatus.completed => 'Completed',
  SessionTodoStatus.cancelled => 'Cancelled',
};
