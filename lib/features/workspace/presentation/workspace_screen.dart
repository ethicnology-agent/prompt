import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../domain/workspace_entry.dart';
import '../domain/workspace_failure.dart';
import 'workspace_view_model.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    required this.profile,
    required this.projects,
    required this.viewModel,
    super.key,
  });

  final ServerProfile profile;
  final List<OpenCodeProject> projects;
  final WorkspaceViewModel viewModel;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  OpenCodeProject? _selectedProject;

  @override
  void dispose() {
    // The app owns this view model, but workspace paths and content are only
    // valid for this route and must not become an in-memory workspace cache.
    widget.viewModel.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasProjects = widget.projects.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace'),
        actions: [
          AppIconButton(
            icon: Icons.drive_folder_upload_outlined,
            tooltip: 'Parent directory',
            onPressed: () => widget.viewModel.goUp(widget.profile),
          ),
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh workspace',
            onPressed: () => widget.viewModel.refresh(widget.profile),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<OpenCodeProject>(
              initialValue: _selectedProject,
              decoration: const InputDecoration(labelText: 'Server project'),
              hint: const Text('Select a project'),
              items: [
                for (final project in widget.projects)
                  DropdownMenuItem(
                    value: project,
                    child: Text(
                      project.id == 'global' ? 'Global' : project.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: hasProjects
                  ? (project) {
                      if (project == null) return;
                      setState(() => _selectedProject = project);
                      widget.viewModel.selectProject(widget.profile, project);
                    }
                  : null,
            ),
          ),
          Expanded(
            child: hasProjects
                ? ValueListenableBuilder<WorkspaceUiState>(
                    valueListenable: widget.viewModel,
                    builder: (context, state, _) => switch (state) {
                      WorkspaceIdle() => const _WorkspacePrompt(),
                      WorkspaceLoading() => Center(
                        child: Semantics(
                          label: 'Loading workspace',
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      WorkspaceError(:final failure) => _WorkspaceError(
                        failure.message,
                        onRetry: () => widget.viewModel.refresh(widget.profile),
                      ),
                      WorkspaceReady() => _WorkspaceContent(
                        state: state,
                        onSearch: (kind, query) => widget.viewModel.search(
                          widget.profile,
                          kind,
                          query,
                        ),
                        onOpen: (entry) => entry.isDirectory
                            ? widget.viewModel.openDirectory(
                                widget.profile,
                                entry,
                              )
                            : widget.viewModel.openFile(widget.profile, entry),
                      ),
                    },
                  )
                : const _WorkspacePrompt(
                    message: 'No server project is available to browse.',
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkspacePrompt extends StatelessWidget {
  const _WorkspacePrompt({
    this.message = 'Select a server project to browse files.',
  });

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError(this.message, {required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync_problem_rounded, size: 48),
          const SizedBox(height: 16),
          const Text('Cannot load workspace'),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          AppButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    ),
  );
}

class _WorkspaceContent extends StatefulWidget {
  const _WorkspaceContent({
    required this.state,
    required this.onOpen,
    required this.onSearch,
  });

  final WorkspaceReady state;
  final ValueChanged<WorkspaceEntry> onOpen;
  final void Function(WorkspaceSearchKind kind, String query) onSearch;

  @override
  State<_WorkspaceContent> createState() => _WorkspaceContentState();
}

class _WorkspaceContentState extends State<_WorkspaceContent> {
  late final TextEditingController _searchController;
  WorkspaceSearchKind _searchKind = WorkspaceSearchKind.text;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sizeClass = promptSizeClassForWidth(constraints.maxWidth);
        final browser = _WorkspaceBrowser(
          entries: widget.state.snapshot.entries,
          search: widget.state.search,
          controller: _searchController,
          kind: _searchKind,
          onKindChanged: (kind) {
            setState(() => _searchKind = kind);
            widget.onSearch(kind, _searchController.text);
          },
          onQueryChanged: (query) => widget.onSearch(_searchKind, query),
          onOpen: widget.onOpen,
        );
        final details = _WorkspaceDetails(state: widget.state);
        final showSplitView =
            sizeClass.isDesktop ||
            sizeClass.isTablet && constraints.maxWidth >= 760;
        if (showSplitView) {
          return Row(
            children: [
              SizedBox(width: 300, child: browser),
              const VerticalDivider(width: 1),
              Expanded(child: details),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: browser),
            const Divider(height: 1),
            Expanded(child: details),
          ],
        );
      },
    );
  }
}

class _WorkspaceBrowser extends StatelessWidget {
  const _WorkspaceBrowser({
    required this.entries,
    required this.search,
    required this.controller,
    required this.kind,
    required this.onKindChanged,
    required this.onQueryChanged,
    required this.onOpen,
  });

  final List<WorkspaceEntry> entries;
  final WorkspaceSearchState search;
  final TextEditingController controller;
  final WorkspaceSearchKind kind;
  final ValueChanged<WorkspaceSearchKind> onKindChanged;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<WorkspaceEntry> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: controller,
              onChanged: onQueryChanged,
              label: 'Search workspace',
              hint: _hintFor(kind),
              prefixIcon: Icons.search,
              suffix: controller.text.isEmpty
                  ? null
                  : AppIconButton(
                      icon: Icons.clear,
                      tooltip: 'Clear workspace search',
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final option in WorkspaceSearchKind.values)
                  ChoiceChip(
                    label: Text(_labelFor(option)),
                    selected: kind == option,
                    onSelected: (_) => onKindChanged(option),
                  ),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: switch (search) {
          WorkspaceSearchIdle() => _FileBrowser(
            entries: entries,
            onOpen: onOpen,
          ),
          WorkspaceSearchLoading() => Center(
            child: Semantics(
              label: 'Searching workspace',
              child: const CircularProgressIndicator(),
            ),
          ),
          WorkspaceSearchError(:final failure) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(failure.message, textAlign: TextAlign.center),
            ),
          ),
          WorkspaceSearchReady(:final results) => _SearchResults(
            results: results,
          ),
        },
      ),
    ],
  );

  static String _labelFor(WorkspaceSearchKind kind) => switch (kind) {
    WorkspaceSearchKind.text => 'Text',
    WorkspaceSearchKind.file => 'Files',
    WorkspaceSearchKind.symbol => 'Symbols',
  };

  static String _hintFor(WorkspaceSearchKind kind) => switch (kind) {
    WorkspaceSearchKind.text => 'Text pattern',
    WorkspaceSearchKind.file => 'File or directory name',
    WorkspaceSearchKind.symbol => 'Symbol name',
  };
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results});

  final List<WorkspaceSearchResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(child: Text('No workspace results found.'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final (title, subtitle, icon) = switch (result) {
          WorkspaceTextSearchResult(:final line, :final lineNumber) => (
            line,
            '${result.path}:${lineNumber + 1}',
            Icons.subject_outlined,
          ),
          WorkspaceFileSearchResult() => (
            result.path,
            'File or directory',
            Icons.insert_drive_file_outlined,
          ),
          WorkspaceSymbolSearchResult(:final name, :final line) => (
            name,
            '${result.path}:${line + 1}',
            Icons.account_tree_outlined,
          ),
        };
        final type = switch (result) {
          WorkspaceTextSearchResult() => 'Text search result',
          WorkspaceFileSearchResult() => 'File search result',
          WorkspaceSymbolSearchResult() => 'Symbol search result',
        };
        return Semantics(
          label: '$type: $title, $subtitle',
          child: ListTile(
            leading: Icon(icon),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}

class _FileBrowser extends StatelessWidget {
  const _FileBrowser({required this.entries, required this.onOpen});

  final List<WorkspaceEntry> entries;
  final ValueChanged<WorkspaceEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('This directory is empty.'));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.description_outlined,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: entry.isIgnored ? const Text('Ignored') : null,
          trailing: entry.isDirectory ? const Icon(Icons.chevron_right) : null,
          onTap: () => onOpen(entry),
        );
      },
    );
  }
}

class _WorkspaceDetails extends StatelessWidget {
  const _WorkspaceDetails({required this.state});

  final WorkspaceReady state;

  @override
  Widget build(BuildContext context) {
    final content = state.content;
    final status = state.snapshot.status;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VCS', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Semantics(
                  label: 'Current branch ${state.snapshot.vcs.branch}',
                  child: Text(state.snapshot.vcs.branch),
                ),
                const SizedBox(height: 20),
                Text(
                  'Changed files',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (status.isEmpty) const Text('No tracked file changes.'),
              ],
            ),
          ),
        ),
        if (status.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: status.length,
              itemBuilder: (context, index) {
                final entry = status[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(entry.status.name),
                  title: Text(
                    entry.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('+${entry.added} -${entry.removed}'),
                );
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File content',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (state.isLoadingContent) const LinearProgressIndicator(),
                if (state.contentFailure != null)
                  Text(state.contentFailure!.message),
                if (content?.isText == true)
                  SelectableText(
                    content!.value!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                if (content?.isText == false)
                  const Text('Binary file. Preview is unavailable.'),
                if (content == null &&
                    !state.isLoadingContent &&
                    state.contentFailure == null)
                  const Text('Select a file to view its read-only content.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
