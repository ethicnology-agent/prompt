import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../../capabilities/capabilities.dart';
import '../../../voice/voice.dart';
import '../../domain/prompt_attachment.dart';

/// Whether the composer should use desktop keyboard shortcuts.
///
/// This is based on the target platform rather than the available width:
/// mobile platforms can render a wide layout without gaining desktop input
/// behavior, while the web client uses the desktop interaction model here.
bool composerSupportsDesktopShortcuts({TargetPlatform? platform}) {
  if (kIsWeb) return true;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => false,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.fuchsia => false,
  };
}

KeyEventResult _handleComposerKeyEvent(
  TextEditingController controller,
  bool desktopShortcuts,
  KeyEvent event,
) {
  if (event is! KeyDownEvent ||
      event.logicalKey != LogicalKeyboardKey.enter ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed) {
    return KeyEventResult.ignored;
  }
  if (!desktopShortcuts || HardwareKeyboard.instance.isShiftPressed) {
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : start;
    final text = value.text.replaceRange(start, end, '\n');
    controller.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

Duration _composerAnimationDuration(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.command,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onSubmit,
    this.voiceState,
    this.onVoiceHoldStart,
    this.onVoiceHoldEnd,
    this.onVoiceStop,
    super.key,
  });

  final TextEditingController controller;
  final OpenCodeSlashCommand? command;
  final ValueListenable<List<PromptAttachment>> attachments;
  final ValueChanged<PromptAttachment> onRemoveAttachment;
  final Future<void> Function() onSubmit;
  final ValueListenable<VoiceUiState>? voiceState;
  final Future<void> Function()? onVoiceHoldStart;
  final Future<void> Function()? onVoiceHoldEnd;
  final Future<void> Function()? onVoiceStop;

  @override
  Widget build(BuildContext context) {
    final desktopShortcuts = composerSupportsDesktopShortcuts();
    final keyboardHint = desktopShortcuts
        ? 'Enter sends; Shift+Enter inserts a newline; Ctrl+Enter queues'
        : 'Enter inserts a newline; use the queue button to submit';
    return PromptAdaptiveBuilder(
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AttachmentStrip(
              attachments: attachments,
              onRemove: onRemoveAttachment,
            ),
            if (voiceState case final voiceState?)
              ValueListenableBuilder<VoiceUiState>(
                valueListenable: voiceState,
                builder: (context, state, _) {
                  final status = switch (state) {
                    VoiceUnavailable(:final failure) => failure.message,
                    _ => null,
                  };
                  if (status == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Semantics(
                      liveRegion: true,
                      label: 'Voice input status: $status',
                      child: Text(status),
                    ),
                  );
                },
              ),
            if (voiceState case final voiceState?)
              ValueListenableBuilder<VoiceUiState>(
                valueListenable: voiceState,
                builder: (context, state, _) {
                  if (state is VoiceIdle || state is VoiceUnavailable) {
                    return const SizedBox.shrink();
                  }
                  return _VoiceModeBar(
                    state: state,
                    onHoldStart: onVoiceHoldStart,
                    onHoldEnd: onVoiceHoldEnd,
                    onStop: onVoiceStop,
                  );
                },
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Semantics(
                    label: command == null
                        ? 'Prompt composer'
                        : 'Arguments for /${command!.name}',
                    hint: command == null
                        ? keyboardHint
                        : desktopShortcuts
                        ? 'Enter sends these command arguments; Shift+Enter inserts a newline; Ctrl+Enter queues'
                        : 'Enter inserts a newline; use the queue button to submit',
                    child: CallbackShortcuts(
                      bindings: {
                        if (desktopShortcuts)
                          const SingleActivator(LogicalKeyboardKey.enter): () =>
                              unawaited(onSubmit()),
                        if (desktopShortcuts)
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): () =>
                              unawaited(onSubmit()),
                        if (desktopShortcuts)
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            meta: true,
                          ): () =>
                              unawaited(onSubmit()),
                      },
                      child: Focus(
                        onKeyEvent: (node, event) => _handleComposerKeyEvent(
                          controller,
                          desktopShortcuts,
                          event,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: AppTextField(
                            controller: controller,
                            dense: true,
                            minLines: 1,
                            maxLines: 6,
                            textInputAction: TextInputAction.newline,
                            label: command == null ? null : '/${command!.name}',
                            hint: command == null
                                ? 'Message this session…'
                                : command!.description ?? 'Command arguments…',
                            variant: AppTextFieldVariant.borderless,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({required this.attachments, this.onRemove, super.key});
  final ValueListenable<List<PromptAttachment>> attachments;
  final ValueChanged<PromptAttachment>? onRemove;

  @override
  State<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<AttachmentStrip>
    with WidgetsBindingObserver {
  final _previews =
      Map<PromptAttachment, AttachmentThumbnailController>.identity();
  List<PromptAttachment> _selected = const [];
  AttachmentThumbnailController? _viewer;
  PromptAttachment? _viewedAttachment;

  Future<void> _inspect(PromptAttachment attachment) async {
    if (_viewer != null || attachment.isReleased) return;
    final viewer = AttachmentThumbnailController.viewer(attachment.bytes);
    _viewer = viewer;
    _viewedAttachment = attachment;
    try {
      await showAttachmentImageViewer(
        context,
        controller: viewer,
        label: attachment.name,
      );
    } finally {
      viewer.dispose();
      if (identical(_viewer, viewer)) {
        _viewer = null;
        _viewedAttachment = null;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.attachments.addListener(_changed);
    _synchronize();
  }

  void _synchronize() {
    _selected = widget.attachments.value
        .where((attachment) => !attachment.isReleased)
        .toList(growable: false);
    if (_viewedAttachment != null && !_selected.contains(_viewedAttachment)) {
      _viewer?.clear();
    }
    for (final attachment in _previews.keys.toList()) {
      if (!_selected.any((current) => identical(current, attachment))) {
        _previews.remove(attachment)!.dispose();
      }
    }
    for (final attachment in _selected) {
      if (const {
        'image/png',
        'image/jpeg',
        'image/webp',
        'image/gif',
      }.contains(attachment.mediaType)) {
        _previews.putIfAbsent(
          attachment,
          () => AttachmentThumbnailController(attachment.bytes),
        );
      }
    }
  }

  void _changed() {
    // Release removed previews synchronously, even if no frame is scheduled.
    _synchronize();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // A platform picker can deliver its selection before resumed. Controllers
    // deliberately keep no encoded bytes while inactive, so ask the current
    // owner again instead of reviving a cached buffer or a released selection.
    for (final attachment in _previews.keys.toList()) {
      if (_previews[attachment]!.state == AttachmentThumbnailState.cleared) {
        _previews.remove(attachment)!.dispose();
      }
    }
    _changed();
  }

  @override
  void didUpdateWidget(AttachmentStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachments != widget.attachments) {
      oldWidget.attachments.removeListener(_changed);
      widget.attachments.addListener(_changed);
      _synchronize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.attachments.removeListener(_changed);
    _viewer?.clear();
    for (final controller in _previews.values) {
      controller.dispose();
    }
    _previews.clear();
    _selected = const [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selected.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        key: const ValueKey('composer-attachments'),
        height: _previews.isEmpty ? 64 : 80,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final attachment in _selected) ...[
                if (_previews[attachment] case final controller?)
                  AttachmentThumbnail(
                    key: ObjectKey(attachment),
                    controller: controller,
                    label: attachment.name,
                    onOpen: () => _inspect(attachment),
                    onRemove: widget.onRemove == null
                        ? null
                        : () => widget.onRemove!(attachment),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: InputChip(
                      key: ObjectKey(attachment),
                      label: Text(
                        '${attachment.name} · ${_formatBytes(attachment.byteCount)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: widget.onRemove == null
                          ? null
                          : () => widget.onRemove!(attachment),
                      deleteButtonTooltipMessage: 'Remove attachment',
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceModeBar extends StatefulWidget {
  const _VoiceModeBar({
    required this.state,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onStop,
  });

  final VoiceUiState state;
  final Future<void> Function()? onHoldStart;
  final Future<void> Function()? onHoldEnd;
  final Future<void> Function()? onStop;

  @override
  State<_VoiceModeBar> createState() => _VoiceModeBarState();
}

class _VoiceModeBarState extends State<_VoiceModeBar> {
  final _focusNode = FocusNode(debugLabel: 'push-to-talk');
  bool _captureHeld = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _beginCapture() async {
    if (_captureHeld || widget.onHoldStart == null) return;
    _focusNode.requestFocus();
    _captureHeld = true;
    await widget.onHoldStart!();
  }

  Future<void> _endCapture() async {
    if (!_captureHeld) return;
    _captureHeld = false;
    await widget.onHoldEnd?.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isPushToTalkKey =
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter;
    if (!isPushToTalkKey) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      unawaited(_beginCapture());
    } else if (event is KeyUpEvent) {
      unawaited(_endCapture());
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final recording = state is VoiceRecording;
    final processing = state is VoiceStarting || state is VoiceTranscribing;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = theme.extension<PromptTokens>();
    final recordingBackground =
        tokens?.userMessageBackground ?? colorScheme.primaryContainer;
    final recordingForeground =
        tokens?.userMessageForeground ?? colorScheme.onPrimaryContainer;
    final recordingBorder = tokens?.userMessageBorder ?? colorScheme.primary;
    final title = switch (state) {
      VoiceRecording() => 'Listening',
      VoiceTranscribing() => 'Finishing this phrase',
      VoiceStarting() => 'Opening a fresh phrase',
      _ => 'Microphone muted',
    };
    final instruction = switch (state) {
      VoiceRecording() => 'Release to mute',
      VoiceTranscribing() => 'Transcribing the bounded audio segment',
      VoiceStarting() => 'Wait for vibration before speaking',
      _ => 'Hold to talk',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: _composerAnimationDuration(
          context,
          const Duration(milliseconds: 180),
        ),
        width: double.infinity,
        decoration: BoxDecoration(
          color: recording
              ? recordingBackground
              : colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: recording ? recordingBorder : colorScheme.outlineVariant,
            width: recording ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '$title. $instruction.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: recording ? recordingForeground : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        instruction,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: recording
                              ? recordingForeground
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: recording
                    ? 'Recording. Release to mute microphone'
                    : processing
                    ? 'Opening microphone. Wait for vibration before speaking'
                    : 'Hold to talk. Microphone muted',
                hint: 'Press and hold while speaking, then release',
                onTap: processing
                    ? null
                    : recording
                    ? widget.onHoldEnd == null
                          ? null
                          : () => unawaited(widget.onHoldEnd!())
                    : widget.onHoldStart == null
                    ? null
                    : () => unawaited(_beginCapture()),
                child: Focus(
                  focusNode: _focusNode,
                  canRequestFocus: true,
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) unawaited(_endCapture());
                  },
                  onKeyEvent: _handleKeyEvent,
                  child: Listener(
                    onPointerDown: processing || widget.onHoldStart == null
                        ? null
                        : (_) => unawaited(_beginCapture()),
                    onPointerUp: widget.onHoldEnd == null
                        ? null
                        : (_) => unawaited(_endCapture()),
                    onPointerCancel: widget.onHoldEnd == null
                        ? null
                        : (_) => unawaited(_endCapture()),
                    child: AnimatedContainer(
                      duration: _composerAnimationDuration(
                        context,
                        const Duration(milliseconds: 140),
                      ),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: recording
                            ? recordingForeground
                            : colorScheme.primaryContainer,
                        border: Border.all(
                          color: recording
                              ? recordingForeground
                              : colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        recording ? Icons.mic_rounded : Icons.mic_off_rounded,
                        size: 34,
                        color: recording
                            ? recordingBackground
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    variant: AppIconButtonVariant.tonal,
                    tone: recording
                        ? AppIconButtonTone.recording
                        : AppIconButtonTone.standard,
                    onPressed: widget.onStop == null
                        ? null
                        : () => unawaited(_stopVoiceMode()),
                    icon: Icons.stop_rounded,
                    tooltip: 'Stop voice mode',
                  ),
                  Text(
                    'Stop',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: recording ? recordingForeground : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _stopVoiceMode() async {
    await _endCapture();
    await widget.onStop?.call();
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
