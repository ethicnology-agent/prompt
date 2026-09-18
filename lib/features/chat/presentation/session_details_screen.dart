import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../sessions/sessions.dart';

/// Session metadata and existing actions; this view never accesses a backend.
class SessionDetailsScreen extends StatelessWidget {
  const SessionDetailsScreen({
    required this.session,
    required this.backendLabel,
    required this.serverOriginLabel,
    required this.executionLabel,
    this.onRefresh,
    this.onReview,
    this.onOpenArtifacts,
    this.onFork,
    this.forkInProgress = false,
    super.key,
  });

  final OpenCodeSession session;
  final String backendLabel;
  final String serverOriginLabel;
  final String executionLabel;
  final VoidCallback? onRefresh;
  final VoidCallback? onReview;
  final VoidCallback? onOpenArtifacts;
  final VoidCallback? onFork;
  final bool forkInProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    String dateLabel(DateTime value) {
      final local = value.toLocal();
      return '${localizations.formatCompactDate(local)} · '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
    }

    return Scaffold(
      backgroundColor: SettingsGroup.pageColor(theme),
      appBar: AppBar(title: const Text('Session details'), centerTitle: false),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            if (onRefresh != null ||
                onReview != null ||
                onOpenArtifacts != null ||
                onFork != null) ...[
              SettingsGroup(
                title: 'QUICK ACTIONS',
                children: [
                  if (onReview != null)
                    _Action(
                      icon: Icons.rate_review_outlined,
                      title: 'Review diff',
                      onTap: onReview!,
                    ),
                  if (onRefresh != null)
                    _Action(
                      icon: Icons.refresh_rounded,
                      title: 'Refresh transcript',
                      onTap: onRefresh!,
                    ),
                  if (onOpenArtifacts != null)
                    _Action(
                      icon: Icons.folder_open_outlined,
                      title: 'Session artifacts',
                      onTap: onOpenArtifacts!,
                    ),
                  if (onFork != null)
                    _Action(
                      icon: Icons.fork_right_rounded,
                      title: forkInProgress
                          ? 'Forking session…'
                          : 'Fork session',
                      onTap: onFork!,
                      enabled: !forkInProgress,
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            SettingsGroup(
              title: 'SESSION',
              children: [
                _Detail(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Title',
                  value: session.title.isEmpty
                      ? 'Untitled session'
                      : session.title,
                ),
                _Detail(
                  icon: Icons.info_outline_rounded,
                  title: 'Execution status',
                  value: executionLabel,
                ),
                _Detail(
                  icon: Icons.terminal_rounded,
                  title: 'Backend',
                  value: backendLabel,
                ),
                _Detail(
                  icon: Icons.dns_outlined,
                  title: 'Server',
                  value: serverOriginLabel,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SettingsGroup(
              title: 'METADATA',
              children: [
                _Detail(
                  icon: Icons.fingerprint_rounded,
                  title: 'Session ID',
                  value: session.id,
                ),
                _Detail(
                  icon: Icons.folder_outlined,
                  title: 'Directory',
                  value: session.directory,
                ),
                _Detail(
                  icon: Icons.workspaces_outline,
                  title: 'Project ID',
                  value: session.projectId,
                ),
                if (session.parentId case final String parentId)
                  _Detail(
                    icon: Icons.account_tree_outlined,
                    title: 'Parent session ID',
                    value: parentId,
                  ),
                _Detail(
                  icon: Icons.calendar_today_outlined,
                  title: 'Created',
                  value: dateLabel(session.createdAt),
                ),
                _Detail(
                  icon: Icons.update_rounded,
                  title: 'Updated',
                  value: dateLabel(session.updatedAt),
                ),
                if (session.agentName case final String agent)
                  _Detail(
                    icon: Icons.smart_toy_outlined,
                    title: 'Agent',
                    value: agent,
                  ),
                if (session.modelId case final String model)
                  _Detail(
                    icon: Icons.tune_rounded,
                    title: 'Model',
                    value: model,
                  ),
                if (session.modelProviderId case final String provider)
                  _Detail(
                    icon: Icons.hub_outlined,
                    title: 'Model provider',
                    value: provider,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: SelectableText(value),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    enabled: enabled,
    onTap: enabled ? onTap : null,
  );
}
