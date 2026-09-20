import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import 'appearance_screen.dart';
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
    this.onScanPairing,
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
  final VoidCallback? onScanPairing;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: SettingsGroup.pageColor(theme),
      appBar: AppBar(title: const Text('Settings'), centerTitle: false),
      body: ContentColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            SettingsGroup(
              title: 'CONNECTION',
              children: [
                if (onScanPairing != null)
                  ListTile(
                    leading: const Icon(Icons.qr_code_scanner_rounded),
                    title: const Text('Connect a machine'),
                    subtitle: const Text('Configure a private connection'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onScanPairing,
                  ),
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
            SettingsGroup(
              title: 'PREFERENCES',
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeViewModel,
                  builder: (context, mode, _) => ListTile(
                    leading: const Icon(Icons.contrast_rounded),
                    title: const Text('Appearance'),
                    subtitle: Text(appearanceLabel(mode)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AppearanceScreen(themeViewModel: themeViewModel),
                      ),
                    ),
                  ),
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
            SettingsGroup(
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
                  subtitle: const Text(
                    'Disconnects this device. Tasks already running on the server continue.',
                  ),
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
      ),
    );
  }
}
