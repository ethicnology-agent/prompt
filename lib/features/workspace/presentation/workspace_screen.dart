import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../domain/workspace_entry.dart';
import '../domain/workspace_failure.dart';
import 'workspace_file_screen.dart';
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
  final _search = TextEditingController();
  final _scroll = ScrollController();
  WorkspaceSearchKind _kind = WorkspaceSearchKind.file;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    widget.viewModel.clear();
    super.dispose();
  }

  void _resetSearch() {
    _search.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openFile(String path, String directory) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceFileScreen(
          profile: widget.profile,
          directory: directory,
          path: path,
          viewModel: widget.viewModel.createFileViewModel(),
        ),
      ),
    );
  }

  void _openEntry(WorkspaceReady state, WorkspaceEntry entry) {
    if (entry.isDirectory) {
      _resetSearch();
      widget.viewModel.openDirectory(widget.profile, entry);
    } else {
      _openFile(entry.path, state.project.directory);
    }
  }

  void _showDetails() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Workspace details')),
          body: SafeArea(
            top: false,
            child: ValueListenableBuilder<WorkspaceUiState>(
              valueListenable: widget.viewModel,
              builder: (context, state, _) => state is WorkspaceReady
                  ? _WorkspaceDetails(
                      state: state,
                      onOpen: (path) =>
                          _openFile(path, state.project.directory),
                    )
                  : const Center(child: Text('Workspace is unavailable.')),
            ),
          ),
        ),
      ),
    );
  }

  Widget _projectPicker() => Padding(
    padding: const EdgeInsets.all(16),
    child: DropdownButtonFormField<OpenCodeProject>(
      initialValue: _selectedProject,
      isExpanded: true,
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
      onChanged: widget.projects.isEmpty
          ? null
          : (project) {
              if (project == null) return;
              _resetSearch();
              setState(() => _selectedProject = project);
              widget.viewModel.selectProject(widget.profile, project);
            },
    ),
  );

  Widget _searchHeader(WorkspaceReady state) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(state.currentPath),
        const SizedBox(height: 12),
        AppTextField(
          controller: _search,
          label: 'Search workspace',
          hint: switch (_kind) {
            WorkspaceSearchKind.file => 'File name or path',
            WorkspaceSearchKind.text => 'Text pattern',
            WorkspaceSearchKind.symbol => 'Symbol name',
          },
          prefixIcon: Icons.search,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (query) {
            setState(() {});
            widget.viewModel.search(widget.profile, _kind, query);
          },
          suffix: _search.text.isEmpty
              ? null
              : AppIconButton(
                  icon: Icons.clear,
                  tooltip: 'Clear workspace search',
                  onPressed: () {
                    setState(_search.clear);
                    widget.viewModel.search(widget.profile, _kind, '');
                  },
                ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final kind in WorkspaceSearchKind.values)
              ChoiceChip(
                label: Text(switch (kind) {
                  WorkspaceSearchKind.file => 'Files',
                  WorkspaceSearchKind.text => 'Text',
                  WorkspaceSearchKind.symbol => 'Symbols',
                }),
                selected: _kind == kind,
                onSelected: (_) {
                  setState(() => _kind = kind);
                  widget.viewModel.search(widget.profile, kind, _search.text);
                },
              ),
          ],
        ),
      ],
    ),
  );

  Widget _notice(String message, {VoidCallback? retry}) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry != null) AppButton(label: 'Try again', onPressed: retry),
        ],
      ),
    ),
  );

  Widget _results(WorkspaceReady state) {
    final search = state.search;
    if (search is WorkspaceSearchLoading) {
      return const SliverToBoxAdapter(
        child: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Searching workspace',
          ),
        ),
      );
    }
    if (search is WorkspaceSearchError) {
      return _notice(
        search.failure.message,
        retry: () =>
            widget.viewModel.search(widget.profile, search.kind, search.query),
      );
    }
    if (search is WorkspaceSearchReady) {
      if (search.results.isEmpty) return _notice('No workspace results found.');
      return SliverList.builder(
        itemCount: search.results.length,
        itemBuilder: (context, index) {
          final result = search.results[index];
          final path = result.filePath;
          final (title, subtitle, icon) = switch (result) {
            WorkspaceTextSearchResult(:final line, :final lineNumber) => (
              line,
              '${result.path}:$lineNumber',
              Icons.subject_outlined,
            ),
            WorkspaceFileSearchResult() => (
              result.path,
              'Search result',
              Icons.description_outlined,
            ),
            WorkspaceSymbolSearchResult(:final name, :final line) => (
              name,
              '${result.path}:${line + 1}',
              Icons.account_tree_outlined,
            ),
          };
          return ListTile(
            leading: Icon(icon),
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              path == null ? 'Unsupported file location' : subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: path == null ? null : const Icon(Icons.chevron_right),
            onTap: path == null
                ? null
                : () => _openFile(path, state.currentPath),
          );
        },
      );
    }
    final entries = state.snapshot.entries;
    if (entries.isEmpty) return _notice('This directory is empty.');
    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.description_outlined,
          ),
          title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: entry.isIgnored ? const Text('Ignored') : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openEntry(state, entry),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<WorkspaceUiState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Workspace'),
            actions: [
              AppIconButton(
                icon: Icons.drive_folder_upload_outlined,
                tooltip: 'Parent directory',
                onPressed: widget.viewModel.canGoUp
                    ? () {
                        _resetSearch();
                        widget.viewModel.goUp(widget.profile);
                      }
                    : null,
              ),
              AppIconButton(
                icon: Icons.difference_outlined,
                tooltip: 'Workspace details',
                onPressed: state is WorkspaceReady ? _showDetails : null,
              ),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh workspace',
                onPressed: state is WorkspaceReady || state is WorkspaceError
                    ? () {
                        _resetSearch();
                        widget.viewModel.refresh(widget.profile);
                      }
                    : null,
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final browser = CustomScrollView(
                  key: const ValueKey('workspace-browser'),
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(child: _projectPicker()),
                    if (state is WorkspaceReady) ...[
                      SliverToBoxAdapter(child: _searchHeader(state)),
                      _results(state),
                    ] else if (state is WorkspaceLoading)
                      const SliverToBoxAdapter(
                        child: Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Loading workspace',
                          ),
                        ),
                      )
                    else if (state is WorkspaceError)
                      _notice(
                        state.failure.message,
                        retry: () => widget.viewModel.refresh(widget.profile),
                      ),
                    if (state is WorkspaceIdle)
                      _notice(
                        widget.projects.isEmpty
                            ? 'No server project is available to browse.'
                            : 'Select a server project to browse files.',
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
                if (!promptSizeClassForWidth(constraints.maxWidth).isDesktop ||
                    state is! WorkspaceReady) {
                  return browser;
                }
                return Row(
                  children: [
                    SizedBox(width: 360, child: browser),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _WorkspaceDetails(
                        state: state,
                        onOpen: (path) =>
                            _openFile(path, state.project.directory),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

class _WorkspaceDetails extends StatelessWidget {
  const _WorkspaceDetails({required this.state, required this.onOpen});
  final WorkspaceReady state;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current branch',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(state.snapshot.vcs.branch),
              const SizedBox(height: 20),
              Text(
                'Changed files',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (state.snapshot.status.isEmpty)
                const Text('No tracked file changes.'),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: state.snapshot.status.length,
        itemBuilder: (context, index) {
          final entry = state.snapshot.status[index];
          final deleted = entry.status == WorkspaceFileStatus.deleted;
          return ListTile(
            leading: Icon(
              deleted ? Icons.delete_outline : Icons.difference_outlined,
            ),
            title: Text(
              entry.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              deleted
                  ? 'Deleted · Current file unavailable'
                  : '${entry.status.name} · +${entry.added} −${entry.removed}',
            ),
            trailing: deleted ? null : const Icon(Icons.chevron_right),
            onTap: deleted ? null : () => onOpen(entry.path),
          );
        },
      ),
    ],
  );
}
