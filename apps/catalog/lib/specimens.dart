import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

class Specimen {
  const Specimen(this.name, this.builder);

  final String name;
  final WidgetBuilder builder;
}

final specimens = <Specimen>[
  Specimen('Draft composer panel', (_) => const _DraftComposerSpecimen()),
  Specimen(
    'Draft composer collapsed',
    (_) => const _DraftComposerSpecimen(expanded: false),
  ),
  Specimen(
    'Draft composer disabled submit',
    (_) => const _DraftComposerSpecimen(expanded: false, canSubmit: false),
  ),
  Specimen('Attachment thumbnail', (_) => const _AttachmentSpecimen()),
  Specimen(
    'Code lines',
    (_) => const SizedBox(
      height: 320,
      child: CodeLineViewer(
        lines: [
          '// Read-only local specimen',
          'final greeting = "Hello";',
          '',
          'https://example.invalid is literal text',
        ],
      ),
    ),
  ),
  Specimen(
    'Selection picker',
    (_) => SizedBox(
      height: 360,
      child: SelectionPicker<String>(
        title: 'Model',
        selected: 'provider-a/model-a',
        options: const [
          SelectionOption(
            value: 'provider-a/model-a',
            label: 'Reasoning model',
            description: 'Provider A · model-a',
          ),
          SelectionOption(
            value: 'provider-b/model-b',
            label: 'Fast model',
            description: 'Provider B · model-b',
          ),
        ],
        onApply: (_) {},
        onCancel: () {},
      ),
    ),
  ),
  Specimen(
    'Composer actions',
    (_) => ComposerActionBar(
      leading: [
        AppIconButton(
          icon: Icons.attach_file,
          tooltip: 'Attach files',
          onPressed: () {},
        ),
      ],
      controls: AppButton(
        label: 'Model and agent',
        variant: AppButtonVariant.tertiary,
        onPressed: () {},
      ),
      trailing: AppIconButton(
        icon: Icons.arrow_upward,
        tooltip: 'Send message',
        variant: AppIconButtonVariant.filled,
        onPressed: () {},
      ),
    ),
  ),
  Specimen(
    'Settings group',
    (context) => ColoredBox(
      color: SettingsGroup.pageColor(Theme.of(context)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SettingsGroup(
          title: 'PREFERENCES',
          children: [
            ListTile(
              leading: const Icon(Icons.contrast_rounded),
              title: const Text('Appearance'),
              subtitle: const Text('Follow the system theme'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Private connection'),
              subtitle: Text('Your infrastructure, without a public relay'),
            ),
          ],
        ),
      ),
    ),
  ),
  Specimen(
    'Session list',
    (_) => Column(
      children: [
        SessionListTile(
          identifier: 'example-idle',
          title: 'Build a private coding companion',
          project: 'example-project',
          status: 'Idle',
          timestamp: '12m',
          onTap: () {},
          onLongPress: () {},
        ),
        SessionListTile(
          identifier: 'example-active',
          title: 'A long title that must remain readable at larger text scales',
          project: 'workspace / feature-branch',
          status: 'Working',
          timestamp: 'Now',
          selected: true,
          inProgress: true,
          statusIcon: Icons.sync,
          onTap: () {},
        ),
        const SessionListTile(
          identifier: 'example-offline',
          title: 'Unavailable session',
          project: 'another-project',
          status: 'Offline',
          timestamp: '2h',
          onTap: null,
        ),
      ],
    ),
  ),
  for (final variant in AppButtonVariant.values)
    Specimen(
      'Button - ${variant.name}',
      (_) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          AppButton(label: 'Continue', variant: variant, onPressed: () {}),
          AppButton(
            label: 'With icon',
            variant: variant,
            icon: Icons.add,
            onPressed: () {},
          ),
          AppButton(label: 'Disabled', variant: variant, onPressed: null),
          AppButton(
            label: 'Working',
            variant: variant,
            busy: true,
            onPressed: () {},
          ),
          AppButton(
            label: 'A longer action label that wraps on a narrow screen',
            variant: variant,
            onPressed: () {},
          ),
        ],
      ),
    ),
  for (final variant in AppIconButtonVariant.values)
    Specimen(
      'Icon button - ${variant.name}',
      (_) => Wrap(
        spacing: 12,
        children: [
          AppIconButton(
            variant: variant,
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: () {},
          ),
          AppIconButton(
            variant: variant,
            icon: Icons.refresh,
            tooltip: 'Unavailable',
            onPressed: null,
          ),
          AppIconButton(
            variant: variant,
            icon: Icons.refresh,
            tooltip: 'Refreshing',
            busy: true,
            onPressed: () {},
          ),
        ],
      ),
    ),
  Specimen(
    'Contextual actions',
    (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        AppButton(
          label: 'What would you like to do?',
          variant: AppButtonVariant.tertiary,
          tone: AppButtonTone.subtle,
          leftAligned: true,
          onPressed: () {},
        ),
        AppButton(
          label: 'Reconnect',
          variant: AppButtonVariant.secondary,
          loading: true,
          onPressed: () {},
        ),
        Wrap(
          spacing: 12,
          children: [
            AppIconButton(
              icon: Icons.filter_list,
              tooltip: 'Selected filter',
              isSelected: true,
              onPressed: () {},
            ),
            AppIconButton(
              icon: Icons.stop,
              tooltip: 'Stop recording',
              variant: AppIconButtonVariant.tonal,
              tone: AppIconButtonTone.recording,
              onPressed: () {},
            ),
          ],
        ),
      ],
    ),
  ),
  for (final variant in AppTextFieldVariant.values)
    Specimen(
      'Field appearance - ${variant.name}',
      (_) => AppTextField(
        label: 'Input',
        hint: 'Enter a value',
        variant: variant,
        minLines: 1,
        maxLines: 4,
      ),
    ),
  Specimen(
    'Dialog',
    (context) => AppButton(
      label: 'Open dialog',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: const Text('Confirm action'),
          scrollable: true,
          content: const Text(
            'This example does not change any application data.',
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              label: 'Confirm',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  ),
  Specimen(
    'Text field',
    (_) => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        AppTextField(
          label: 'Search',
          hint: 'Search sessions',
          prefixIcon: Icons.search,
        ),
        AppTextField(label: 'Unavailable', enabled: false),
        AppTextField(
          label: 'Required value',
          errorText: 'Enter a value to continue',
        ),
        AppTextField(
          label: 'Access key',
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
        ),
        AppTextField(label: 'Message', minLines: 3, maxLines: 6),
      ],
    ),
  ),
  Specimen(
    'Form field',
    (_) => const AppTextFormField(
      label: 'Display name',
      initialValue: 'Example session',
      helperText: 'Only synthetic data is used here.',
    ),
  ),
  Specimen(
    'Panel',
    (_) => const PromptPanel(
      padding: EdgeInsets.all(16),
      child: Text('A shared surface for feature content.'),
    ),
  ),
  Specimen(
    'Identity avatar',
    (_) => Wrap(
      spacing: 16,
      children: [
        const IdentityAvatar(identifier: 'sample-one', size: 40),
        const IdentityAvatar(identifier: 'sample-two'),
        const IdentityAvatar(identifier: 'sample-three', size: 80),
        IdentityAvatarButton(
          identifier: 'sample-action',
          tooltip: 'Session details',
          onPressed: () {},
        ),
      ],
    ),
  ),
];

class _DraftComposerSpecimen extends StatefulWidget {
  const _DraftComposerSpecimen({this.expanded = true, this.canSubmit = true});
  final bool expanded;
  final bool canSubmit;
  @override
  State<_DraftComposerSpecimen> createState() => _DraftComposerSpecimenState();
}

class _DraftComposerSpecimenState extends State<_DraftComposerSpecimen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _engine = 'Local engine';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 400,
    child: DraftComposerPanel(
      controller: _controller,
      focusNode: _focus,
      expanded: widget.expanded,
      configuration: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CreationConfigurationRow(
            icon: Icons.computer_outlined,
            label: 'Machine',
            value: 'Local specimen',
          ),
          const CreationConfigurationRow(
            icon: Icons.folder_outlined,
            label: 'Directory',
            value: '/workspace/example',
          ),
          const CreationConfigurationRow(
            icon: Icons.account_tree_outlined,
            label: 'Worktree',
            value: 'Unavailable',
          ),
          CreationConfigurationRow(
            icon: Icons.memory_outlined,
            label: 'Engine',
            value: _engine,
            onTap: () => setState(
              () => _engine = _engine == 'Local engine'
                  ? 'Alternate local engine'
                  : 'Local engine',
            ),
          ),
        ],
      ),
      onSubmit: widget.canSubmit ? () => _controller.clear() : null,
      onClose: _focus.unfocus,
    ),
  );
}

class SpecimenPage extends StatelessWidget {
  const SpecimenPage({required this.specimen, super.key});

  final Specimen specimen;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: specimen.builder(context),
      ),
    ),
  );
}

class _AttachmentSpecimen extends StatefulWidget {
  const _AttachmentSpecimen();

  @override
  State<_AttachmentSpecimen> createState() => _AttachmentSpecimenState();
}

class _AttachmentSpecimenState extends State<_AttachmentSpecimen> {
  AttachmentThumbnailController? _controller;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 64, 64),
      Paint()..color = const Color(0xff56d6b2),
    );
    canvas.drawCircle(const Offset(24, 24), 12, Paint()..color = Colors.white);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(64, 64);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      setState(
        () => _controller = AttachmentThumbnailController(
          data.buffer.asUint8List(),
        ),
      );
    } finally {
      image.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_removed) return const Text('Attachment removed');
    if (controller == null) return const SizedBox(width: 88, height: 80);
    return AttachmentThumbnail(
      controller: controller,
      label: 'Synthetic color tile',
      onRemove: () => setState(() => _removed = true),
    );
  }
}
