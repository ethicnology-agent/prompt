import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../domain/session_worktree.dart';
import 'session_creation_view_model.dart';

class WorktreePicker extends StatefulWidget {
  const WorktreePicker({required this.viewModel, super.key});

  final SessionCreationViewModel viewModel;

  @override
  State<WorktreePicker> createState() => _WorktreePickerState();
}

class _WorktreePickerState extends State<WorktreePicker> {
  final _name = TextEditingController();

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
              Text('Worktree', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (state.worktreeFailure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(state.worktreeFailure!.message),
                ),
              for (final worktree in state.worktrees)
                CreationConfigurationRow(
                  icon: Icons.account_tree_outlined,
                  label: worktree.directory,
                  value: worktree.branch ?? worktree.directory,
                  onTap: busy
                      ? null
                      : () {
                          widget.viewModel.selectWorktree(worktree);
                          Navigator.of(context).pop();
                        },
                ),
              if (state.canCreateWorktree) ...[
                const SizedBox(height: 12),
                AppTextField(
                  controller: _name,
                  enabled: !busy,
                  label: 'New worktree name',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Creates a separate folder and a new branch on your machine.',
                ),
                AppButton(
                  label: 'Create worktree',
                  onPressed: busy
                      ? null
                      : () async {
                          await widget.viewModel.createWorktree(
                            _name.text.trim(),
                          );
                          if (!context.mounted) return;
                          if (widget.viewModel.value.worktreePhase ==
                                  WorktreePhase.ready &&
                              widget.viewModel.value.worktreeFailure == null) {
                            Navigator.of(context).pop();
                          }
                        },
                ),
              ],
              AppButton(
                label: 'Refresh worktrees',
                variant: AppButtonVariant.tertiary,
                onPressed: busy ? null : widget.viewModel.refreshWorktrees,
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
