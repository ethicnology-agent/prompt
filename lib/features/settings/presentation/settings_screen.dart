import 'package:flutter/material.dart';

import 'theme_view_model.dart';

/// The settings landing page contains navigation and local appearance only.
/// Server operations remain in their existing feature repositories.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.serverLabel,
    required this.themeViewModel,
    required this.onOpenServer,
    required this.onOpenVoice,
    required this.onOpenNotifications,
    required this.onDisconnect,
    this.onOpenWorkspace,
    this.onOpenTerminal,
    super.key,
  });

  final String serverLabel;
  final ThemeViewModel themeViewModel;
  final VoidCallback? onOpenServer;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenNotifications;
  final VoidCallback onDisconnect;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _Group(
            title: 'CONNECTION',
            children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Your server'),
                subtitle: Text(serverLabel),
                trailing: onOpenServer == null
                    ? null
                    : const Icon(Icons.chevron_right),
                onTap: onOpenServer,
              ),
              const ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Private connection'),
                subtitle: Text('WireGuard or Tailscale · no public relay'),
              ),
              if (onOpenWorkspace != null)
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Browse workspace'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenWorkspace,
                ),
              if (onOpenTerminal != null)
                ListTile(
                  leading: const Icon(Icons.terminal_outlined),
                  title: const Text('Remote terminal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenTerminal,
                ),
            ],
          ),
          const SizedBox(height: 24),
          _Group(
            title: 'PREFERENCES',
            children: [
              ExpansionTile(
                leading: const Icon(Icons.contrast_rounded),
                title: const Text('Appearance'),
                children: [
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeViewModel,
                    builder: (context, mode, _) => Column(
                      children: [
                        for (final option in ThemeMode.values)
                          ListTile(
                            title: Text(switch (option) {
                              ThemeMode.system => 'System',
                              ThemeMode.light => 'Light',
                              ThemeMode.dark => 'Dark',
                            }),
                            selected: mode == option,
                            trailing: mode == option
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => themeViewModel.select(option),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.mic_none_rounded),
                title: const Text('Voice input'),
                subtitle: const Text('Transcription stays on this device'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenVoice,
              ),
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: const Text('Notifications'),
                subtitle: const Text('Opt-in · no conversation content'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenNotifications,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Group(
            title: 'SESSION',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About Prompt'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Prompt',
                  applicationLegalese: 'Your agents, your infrastructure.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Disconnect'),
                onTap: onDisconnect,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Prompt',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.labelSmall),
      ),
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 56),
                  child: Divider(height: 1, thickness: 0.5),
                ),
              children[index],
            ],
          ],
        ),
      ),
    ],
  );
}
