import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';

import '../domain/voice_language.dart';
import '../domain/voice_failure.dart';
import 'voice_view_model.dart';

class VoiceSettingsScreen extends StatelessWidget {
  const VoiceSettingsScreen({required this.viewModel, super.key});

  final VoiceViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SettingsGroup.pageColor(Theme.of(context)),
    appBar: AppBar(title: const Text('Voice input'), centerTitle: false),
    // Every settings surface wears the same grouped chrome: a grey page,
    // white cards, an uppercase heading and a sentence underneath saying what
    // the group is for. This screen used to be a bare list on white.
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        SettingsGroup(
          title: 'Recognition language',
          footer:
              'Speech is matched against the language you choose here, not '
              'detected automatically.',
          children: [
            ValueListenableBuilder<VoiceLanguage>(
              valueListenable: viewModel.language,
              builder: (context, language, _) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ChoiceField<VoiceLanguage>(
                  label: 'Language',
                  scopeKey: viewModel,
                  selected: language,
                  options: [
                    for (final option in VoiceLanguage.values)
                      InlineSelectionOption(value: option, label: option.label),
                  ],
                  onSelected: viewModel.selectLanguage,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ModelsGroup(viewModel: viewModel),
      ],
    ),
  );
}

class _ModelsGroup extends StatelessWidget {
  const _ModelsGroup({required this.viewModel});

  final VoiceViewModel viewModel;

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: 'Local models',
    footer:
        'Install downloads, verifies, stores, and selects all four required '
        'files in one action. French needs about 123 MiB; English needs about '
        '69 MiB. Models remain installed across app updates. Installing '
        'explicitly contacts Hugging Face to download the selected model. '
        'Models and transcripts remain local: audio stays in memory and is '
        'released after each segment, cancellation, or lifecycle pause, and '
        'removing a model deletes its private files.',
    children: [
      ValueListenableBuilder<Set<VoiceLanguage>>(
        valueListenable: viewModel.selectedModelLanguages,
        builder: (context, selected, _) =>
            ValueListenableBuilder<Map<VoiceLanguage, double>>(
              valueListenable: viewModel.modelInstallProgress,
              builder: (context, progress, _) =>
                  ValueListenableBuilder<
                    Map<VoiceLanguage, VoiceModelInstallFailure>
                  >(
                    valueListenable: viewModel.modelInstallFailures,
                    builder: (context, failures, _) => Column(
                      children: [
                        _ModelCard(
                          language: VoiceLanguage.french,
                          selected: selected.contains(VoiceLanguage.french),
                          progress: progress[VoiceLanguage.french],
                          failure: failures[VoiceLanguage.french],
                          onInstall: () => viewModel.installModelFromUserAction(
                            VoiceLanguage.french,
                          ),
                          onRemove: () => viewModel.removeModelFromUserAction(
                            VoiceLanguage.french,
                          ),
                          onSelectExisting: () => viewModel
                              .selectModelFromUserAction(VoiceLanguage.french),
                        ),
                        const SizedBox(height: 12),
                        _ModelCard(
                          language: VoiceLanguage.english,
                          selected: selected.contains(VoiceLanguage.english),
                          progress: progress[VoiceLanguage.english],
                          failure: failures[VoiceLanguage.english],
                          onInstall: () => viewModel.installModelFromUserAction(
                            VoiceLanguage.english,
                          ),
                          onRemove: () => viewModel.removeModelFromUserAction(
                            VoiceLanguage.english,
                          ),
                          onSelectExisting: () => viewModel
                              .selectModelFromUserAction(VoiceLanguage.english),
                        ),
                      ],
                    ),
                  ),
            ),
      ),
    ],
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.language,
    required this.selected,
    required this.progress,
    required this.failure,
    required this.onInstall,
    required this.onRemove,
    required this.onSelectExisting,
  });

  final VoiceLanguage language;
  final bool selected;
  final double? progress;
  final VoiceModelInstallFailure? failure;
  final VoidCallback onInstall;
  final VoidCallback onRemove;
  final VoidCallback onSelectExisting;

  @override
  Widget build(BuildContext context) {
    final installing = progress != null;
    final status = installing
        ? 'Installing ${(progress! * 100).round()}%'
        : selected
        ? 'Installed'
        : failure != null
        ? failure!.message
        : 'Not installed';
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${language.label} INT8',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(status),
              ],
            ),
            if (installing) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
            const SizedBox(height: 8),
            AppButton(
              label:
                  '${selected ? 'Reinstall' : 'Install'} ${language.label} model',
              icon: Icons.download_outlined,
              onPressed: installing ? null : onInstall,
            ),
            if (selected) ...[
              const SizedBox(height: 8),
              AppButton(
                label: 'Remove ${language.label} model',
                variant: AppButtonVariant.secondary,
                icon: Icons.delete_outline,
                onPressed: installing ? null : onRemove,
              ),
            ],
            const SizedBox(height: 4),
            AppButton(
              label: 'Choose existing ${language.label} model files',
              variant: AppButtonVariant.tertiary,
              onPressed: installing ? null : onSelectExisting,
            ),
          ],
        ),
      ),
    );
  }
}
