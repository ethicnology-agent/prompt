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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<List<PromptAttachment>>(
              valueListenable: attachments,
              builder: (context, selected, _) {
                if (selected.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final attachment in selected)
                          InputChip(
                            label: Text(
                              '${attachment.name} · '
                              '${_formatBytes(attachment.byteCount)}',
                            ),
                            onDeleted: () => onRemoveAttachment(attachment),
                            deleteButtonTooltipMessage: 'Remove attachment',
                          ),
                      ],
                    ),
                  ),
                );
              },
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
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 6,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            labelText: command == null
                                ? null
                                : '/${command!.name}',
                            hintText: command == null
                                ? 'Message this session…'
                                : command!.description ?? 'Command arguments…',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
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
                  IconButton.filledTonal(
                    onPressed: widget.onStop == null
                        ? null
                        : () => unawaited(_stopVoiceMode()),
                    style: recording
                        ? IconButton.styleFrom(
                            backgroundColor: recordingForeground,
                            foregroundColor: recordingBackground,
                          )
                        : null,
                    icon: const Icon(Icons.stop_rounded),
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
