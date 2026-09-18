import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../domain/session_worktree.dart';
import 'session_creation_view_model.dart';

/// Explicit creation form; existing worktrees are chosen in the composer card.
class WorktreePicker extends StatefulWidget {
  const WorktreePicker({required this.viewModel, super.key});

  final SessionCreationViewModel viewModel;

  @override
  State<WorktreePicker> createState() => _WorktreePickerState();
}

class _WorktreePickerState extends State<WorktreePicker> {
  final _name = TextEditingController();
  late final String? _profileId;
  late final Object? _backend;
  late final String _directory;

  bool _sameScope(SessionCreationState state) =>
      state.profile?.id == _profileId &&
      state.backend == _backend &&
      state.directory == _directory;

  @override
  void initState() {
    super.initState();
    // Capture the scope before the first rebuild or asynchronous refresh.
    _profileId = widget.viewModel.value.profile?.id;
    _backend = widget.viewModel.value.backend;
    _directory = widget.viewModel.value.directory;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<SessionCreationState>(
    valueListenable: widget.viewModel,
    builder: (context, state, _) {
      final busy =
          state.worktreePhase == WorktreePhase.loading ||
          state.worktreePhase == WorktreePhase.creating;
      final enabled = !busy && _sameScope(state) && state.canCreateWorktree;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create worktree',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (state.worktreeFailure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(state.worktreeFailure!.message),
                ),
              if (!_sameScope(state))
                const Text(
                  'The selected machine or folder changed. Close and reopen worktree creation.',
                ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _name,
                enabled: enabled,
                label: 'New worktree name',
              ),
              const SizedBox(height: 8),
              const Text(
                'Creates a separate folder and a new branch on your machine.',
              ),
              AppButton(
                label: 'Create worktree',
                onPressed: !enabled
                    ? null
                    : () async {
                        final current = widget.viewModel.value;
                        if (!_sameScope(current) ||
                            !current.canCreateWorktree ||
                            current.worktreePhase == WorktreePhase.creating) {
                          return;
                        }
                        final navigator = Navigator.of(context);
                        final route = ModalRoute.of(context);
                        await widget.viewModel.createWorktree(
                          _name.text.trim(),
                        );
                        if (!context.mounted) return;
                        final completed = widget.viewModel.value;
                        if (completed.profile?.id == _profileId &&
                            completed.backend == _backend &&
                            completed.worktreePhase == WorktreePhase.ready &&
                            completed.worktreeFailure == null &&
                            route?.navigator == navigator) {
                          navigator.removeRoute(route!);
                        }
                      },
              ),
              AppButton(
                label: 'Close',
                variant: AppButtonVariant.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
