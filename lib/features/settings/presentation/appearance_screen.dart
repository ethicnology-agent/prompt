import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import 'theme_view_model.dart';

String appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

/// Local appearance preferences, using the application's existing theme state.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({required this.themeViewModel, super.key});

  final ThemeViewModel themeViewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: SettingsGroup.pageColor(theme),
      appBar: AppBar(title: const Text('Appearance'), centerTitle: false),
      body: ContentColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeViewModel,
              builder: (context, mode, _) => SettingsGroup(
                title: 'THEME',
                children: [
                  for (final option in ThemeMode.values)
                    Semantics(
                      checked: mode == option,
                      inMutuallyExclusiveGroup: true,
                      child: ListTile(
                        leading: Icon(switch (option) {
                          ThemeMode.system => Icons.contrast_rounded,
                          ThemeMode.light => Icons.light_mode_outlined,
                          ThemeMode.dark => Icons.dark_mode_outlined,
                        }),
                        title: Text(appearanceLabel(option)),
                        subtitle: option == ThemeMode.system
                            ? const Text('Match system settings')
                            : null,
                        selected: mode == option,
                        trailing: mode == option
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => themeViewModel.select(option),
                      ),
                    ),
                ],
              ),
            ),
            ValueListenableBuilder<ThemeSaveState>(
              valueListenable: themeViewModel.saveState,
              builder: (context, state, _) => switch (state) {
                ThemeSaveState.idle ||
                ThemeSaveState.saved => const SizedBox.shrink(),
                ThemeSaveState.saving => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Semantics(
                    liveRegion: true,
                    child: const Text('Saving appearance…'),
                  ),
                ),
                ThemeSaveState.failed => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Appearance changed for this session, but could not be saved.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppButton(
                        label: 'Retry',
                        variant: AppButtonVariant.secondary,
                        onPressed: themeViewModel.retrySave,
                      ),
                    ],
                  ),
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                'Choose your preferred color scheme. This preference stays on '
                'this device.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
