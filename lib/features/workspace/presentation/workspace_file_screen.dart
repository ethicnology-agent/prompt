import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../domain/workspace_failure.dart';
import 'workspace_file_view_model.dart';

/// Owns its file-specific view model; pass a fresh instance for each route.
class WorkspaceFileScreen extends StatefulWidget {
  const WorkspaceFileScreen({
    required this.profile,
    required this.directory,
    required this.path,
    required this.viewModel,
    super.key,
  });

  final ServerProfile profile;
  final String directory;
  final String path;
  final WorkspaceFileViewModel viewModel;

  @override
  State<WorkspaceFileScreen> createState() => _WorkspaceFileScreenState();
}

class _WorkspaceFileScreenState extends State<WorkspaceFileScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => unawaited(
    widget.viewModel.load(widget.profile, widget.directory, widget.path),
  );

  @override
  void didUpdateWidget(covariant WorkspaceFileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.dispose();
    }
    if (oldWidget.viewModel != widget.viewModel ||
        oldWidget.profile.id != widget.profile.id ||
        oldWidget.directory != widget.directory ||
        oldWidget.path != widget.path) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(widget.path, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Current server file · read-only',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('File'), centerTitle: false),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<WorkspaceFileState>(
          valueListenable: widget.viewModel,
          builder: (context, state, _) {
            if (state is WorkspaceFileReady &&
                state.content.isText &&
                state.lines.isNotEmpty) {
              return CodeLineViewer(lines: state.lines, header: header);
            }
            return ListView(
              children: [
                header,
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: switch (state) {
                    WorkspaceFileIdle() ||
                    WorkspaceFileLoading() => const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading file',
                      ),
                    ),
                    WorkspaceFileReady(:final content) => Text(
                      content.isText
                          ? 'This file is empty.'
                          : 'Binary file preview is unavailable.',
                    ),
                    WorkspaceFileError(:final failure) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(failure.message),
                        const SizedBox(height: 12),
                        AppButton(label: 'Retry', onPressed: _load),
                      ],
                    ),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
