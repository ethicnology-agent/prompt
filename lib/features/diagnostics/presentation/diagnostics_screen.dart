import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../../core/platform/local_notification_service.dart';
import '../../settings/settings.dart';
import '../../connection/connection.dart';
import '../domain/diagnostics_snapshot.dart';
import '../domain/diagnostics_load_result.dart';
import 'diagnostics_view_model.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    required this.profile,
    required this.viewModel,
    required this.localNotificationService,
    required this.themeViewModel,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onReloadReconciled,
    super.key,
  });

  final ServerProfile profile;
  final DiagnosticsViewModel viewModel;
  final LocalNotificationService localNotificationService;
  final ThemeViewModel themeViewModel;
  final Future<bool> Function() onReconnect;
  final VoidCallback onDisconnect;
  final Future<void> Function() onReloadReconciled;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _reconnecting = false;
  bool _reloading = false;
  bool _reloadDialogOpen = false;
  int _scopeRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load(widget.profile);
  }

  @override
  void didUpdateWidget(DiagnosticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.viewModel != widget.viewModel) {
      _scopeRevision++;
      _reloading = false;
      _reconnecting = false;
      widget.viewModel.load(widget.profile);
    }
  }

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    final succeeded = await widget.onReconnect();
    if (!mounted) {
      return;
    }
    setState(() => _reconnecting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded ? 'Connection restored' : 'Unable to reconnect right now',
        ),
      ),
    );
  }

  Future<void> _reload() async {
    if (!mounted || _reloading || _reloadDialogOpen) return;
    final revision = _scopeRevision;
    final profile = widget.profile;
    final viewModel = widget.viewModel;
    final reconcile = widget.onReloadReconciled;
    _reloadDialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Reload OpenCode?'),
        content: const Text(
          'Active generations across this server will stop. All project '
          'instances will be recreated, and configuration, skills, and MCP '
          'will reload. Sessions remain available. The OpenCode server '
          'process itself will not be restarted.',
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: 'Reload OpenCode',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    _reloadDialogOpen = false;
    if (!mounted ||
        revision != _scopeRevision ||
        confirmed != true ||
        _reloading) {
      return;
    }
    setState(() => _reloading = true);
    final result = await viewModel.reload(expectedProfile: profile);
    if (!mounted || revision != _scopeRevision) return;
    if (result is DiagnosticsReloaded) {
      await reconcile();
    }
    if (!mounted || revision != _scopeRevision) return;
    setState(() => _reloading = false);
    final message = switch (result) {
      DiagnosticsReloaded() => 'OpenCode reloaded',
      DiagnosticsReloadFailed(:final failure) => switch (failure) {
        DiagnosticsFailure.unavailable => 'OpenCode is unavailable',
        DiagnosticsFailure.unauthorized => 'OpenCode authorization failed',
        DiagnosticsFailure.unexpectedResponse => 'Unable to reload OpenCode',
      },
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Grouped cards need the grey page behind them, or they are white on
      // white. The other four grouped surfaces already set it; this one was
      // missed.
      backgroundColor: SettingsGroup.pageColor(Theme.of(context)),
      appBar: AppBar(title: const Text('Server settings'), centerTitle: false),
      body: PromptAdaptiveBuilder(
        builder: (context, sizeClass) {
          return ValueListenableBuilder<DiagnosticsUiState>(
            valueListenable: widget.viewModel,
            builder: (context, state, _) => RefreshIndicator(
              onRefresh: widget.viewModel.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: promptPagePadding(sizeClass),
                children: [
                  _ConnectionCard(
                    profile: widget.profile,
                    reconnecting: _reconnecting,
                    onReconnect: _reconnecting ? null : _reconnect,
                    onDisconnect: widget.onDisconnect,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      subtitle: const Text('Opt in to generic session alerts'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NotificationSettingsScreen(
                            service: widget.localNotificationService,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SettingsGroup(
                    title: 'PREFERENCES',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.contrast_rounded),
                        title: const Text('Appearance'),
                        subtitle: const Text(
                          'Choose your preferred color scheme',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => AppearanceScreen(
                              themeViewModel: widget.themeViewModel,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  switch (state) {
                    DiagnosticsIdle() ||
                    DiagnosticsLoading() => const _LoadingDiagnostics(),
                    DiagnosticsReady(:final snapshot) => _DiagnosticsSummary(
                      snapshot: snapshot,
                    ),
                    DiagnosticsError() => _DiagnosticsUnavailable(
                      onRetry: widget.viewModel.refresh,
                    ),
                  },
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: _reloading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      title: const Text('Reload OpenCode'),
                      subtitle: const Text(
                        'Reload configuration, skills, and MCP on this server',
                      ),
                      onTap: _reloading ? null : _reload,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.profile,
    required this.reconnecting,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final ServerProfile profile;
  final bool reconnecting;
  final VoidCallback? onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(profile.displayOrigin, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                AppButton(
                  variant: AppButtonVariant.secondary,
                  loading: reconnecting,
                  onPressed: onReconnect,
                  icon: Icons.refresh_rounded,
                  label: 'Reconnect',
                ),
                AppButton(
                  label: 'Disconnect',
                  variant: AppButtonVariant.tertiary,
                  icon: Icons.power_settings_new_rounded,
                  onPressed: onDisconnect,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDiagnostics extends StatelessWidget {
  const _LoadingDiagnostics();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Semantics(
          label: 'Loading server diagnostics',
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _DiagnosticsUnavailable extends StatelessWidget {
  const _DiagnosticsUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostics unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'The server did not provide a safe diagnostics summary.',
            ),
            const SizedBox(height: 12),
            AppButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsSummary extends StatelessWidget {
  const _DiagnosticsSummary({required this.snapshot});

  final DiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * PromptUiTokens.panelGap) /
            columns;
        return Wrap(
          spacing: PromptUiTokens.panelGap,
          runSpacing: PromptUiTokens.panelGap,
          children: [
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'Server health',
                status: snapshot.isHealthy ? 'Healthy' : 'Needs attention',
                detail: 'Health check completed',
              ),
            ),
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'MCP servers',
                status: '${snapshot.mcp.total} configured',
                detail:
                    '${snapshot.mcp.connected} connected, '
                    '${snapshot.mcp.needsAttention} need attention, '
                    '${snapshot.mcp.disabled} disabled',
                footer: 'MCP changes are unavailable in this read-only screen.',
              ),
            ),
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'Language servers',
                status: '${snapshot.lsp.total} reported',
                detail:
                    '${snapshot.lsp.connected} connected, '
                    '${snapshot.lsp.unavailable} unavailable',
              ),
            ),
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'Formatters',
                status: '${snapshot.formatters.total} reported',
                detail:
                    '${snapshot.formatters.enabled} enabled, '
                    '${snapshot.formatters.disabled} disabled',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.status,
    required this.detail,
    this.footer,
  });

  final String title;
  final String status;
  final String detail;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title: $status. $detail',
      child: PromptPanel(
        padding: const EdgeInsets.all(PromptUiTokens.compactPagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(status, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(detail),
            if (footer != null) ...[
              const SizedBox(height: 12),
              Text(footer!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
