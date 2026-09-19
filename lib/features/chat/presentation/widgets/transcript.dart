import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../domain/chat_message.dart';
import '../basic_markdown_text.dart';

class Transcript extends StatelessWidget {
  const Transcript({
    required this.messages,
    required this.onRefresh,
    required this.controller,
    required this.onRevert,
    this.canRevert = true,
    this.onOpenFile,
    required this.onLoadOlder,
    required this.hasMore,
    required this.loadingOlder,
    required this.limitedByServer,
    this.desktop = false,
    super.key,
  });

  final List<ChatMessage> messages;
  final Future<void> Function() onRefresh;
  final ScrollController controller;
  final ValueChanged<ChatMessage> onRevert;
  final bool canRevert;
  final ValueChanged<String>? onOpenFile;
  final VoidCallback onLoadOlder;
  final bool hasMore;
  final bool loadingOlder;
  final bool limitedByServer;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    // The transcript is built bottom-up: index 0 is the newest message and
    // sits at the bottom, so the latest turn is visible without any
    // post-layout scrolling. On phone and tablet, `RefreshIndicator` only
    // attaches to a scrollable's leading edge, so that path rotates the whole
    // scrollable and turns each row back to provide bottom pull-to-refresh.
    // Desktop uses a normal reversed scrollable instead, because refresh is an
    // explicit AppBar action and pointer scrolling should keep its direction.
    final visibleMessages = messages
        .where(
          (message) =>
              message.text.trim().isNotEmpty || message.details.isNotEmpty,
        )
        .toList(growable: false)
        .reversed
        .toList(growable: false);

    final scrollView = CustomScrollView(
      key: const ValueKey('conversation-transcript-scroll'),
      controller: controller,
      reverse: desktop,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          sliver: SliverList.separated(
            itemCount: visibleMessages.length,
            itemBuilder: (context, index) {
              final message = visibleMessages[index];
              final bubble = _MessageBubble(
                key: ValueKey(message.id),
                message: message,
                showRevert: canRevert && index == 0,
                onRevert: () => onRevert(message),
                onOpenFile: onOpenFile,
                desktop: desktop,
              );
              return desktop
                  ? bubble
                  : Transform.rotate(angle: math.pi, child: bubble);
            },
            separatorBuilder: (_, _) => const SizedBox(height: 12),
          ),
        ),
        if (hasMore || loadingOlder || limitedByServer)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Center(
                child: limitedByServer
                    ? const Text('History may be limited by this server')
                    : loadingOlder
                    ? const _LoadingHistoryControl()
                    : Semantics(
                        button: true,
                        label: 'Load earlier messages',
                        child: AppButton(
                          label: 'Load earlier messages',
                          variant: AppButtonVariant.secondary,
                          icon: Icons.history,
                          onPressed: onLoadOlder,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
    if (desktop) {
      // `reverse` keeps the newest turn at the physical bottom while leaving
      // pointer-wheel and trackpad deltas in their normal direction. The
      // indicator therefore owns the ordinary, non-rotated scroll view.
      return _DesktopRefreshable(
        controller: controller,
        onRefresh: onRefresh,
        child: scrollView,
      );
    }
    return Transform.rotate(
      angle: math.pi,
      child: RefreshIndicator(onRefresh: onRefresh, child: scrollView),
    );
  }
}

class _DesktopRefreshable extends StatefulWidget {
  const _DesktopRefreshable({
    required this.controller,
    required this.onRefresh,
    required this.child,
  });

  final ScrollController controller;
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<_DesktopRefreshable> createState() => _DesktopRefreshableState();
}

class _DesktopRefreshableState extends State<_DesktopRefreshable> {
  static const _edgeTolerance = 0.5;

  bool _refreshing = false;
  double? _dragStart;
  double _dragDelta = 0;

  void _pointerDown(PointerDownEvent event) {
    _dragStart = _atNewestEdge ? event.position.dy : null;
    _dragDelta = 0;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_dragStart != null) _dragDelta += event.delta.dy;
  }

  void _pointerUp(PointerUpEvent event) {
    final shouldRefresh = _dragStart != null && _dragDelta > 80;
    _dragStart = null;
    _dragDelta = 0;
    if (shouldRefresh && !_refreshing) {
      _refreshing = true;
      widget.onRefresh().whenComplete(() {
        if (mounted) setState(() => _refreshing = false);
      });
    }
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is! OverscrollNotification ||
        notification.metrics.axis != Axis.vertical ||
        _refreshing) {
      return false;
    }
    final atNewestEdge =
        notification.metrics.pixels <=
        notification.metrics.minScrollExtent + _edgeTolerance;
    if (!atNewestEdge) return false;
    _refreshing = true;
    widget.onRefresh().whenComplete(() {
      if (mounted) setState(() => _refreshing = false);
    });
    return false;
  }

  bool get _atNewestEdge {
    if (!widget.controller.hasClients) return false;
    final position = widget.controller.position;
    return position.pixels <=
        position.minScrollExtent + _DesktopRefreshableState._edgeTolerance;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          child: widget.child,
        ),
      );
}

class _LoadingHistoryControl extends StatelessWidget {
  const _LoadingHistoryControl();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Loading earlier messages',
    child: const SizedBox(
      height: 40,
      width: 40,
      child: Padding(
        padding: EdgeInsets.all(10),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showRevert,
    required this.onRevert,
    required this.desktop,
    this.onOpenFile,
    super.key,
  });

  final ChatMessage message;
  final bool showRevert;
  final VoidCallback onRevert;
  final bool desktop;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final userMessage = message.role == ChatMessageRole.user;
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    final background = userMessage
        ? tokens.userMessageBackground
        : Colors.transparent;
    final foreground = userMessage
        ? tokens.userMessageForeground
        : theme.colorScheme.onSurface;

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(userMessage ? 18 : 0),
        border: userMessage
            ? Border.all(color: tokens.userMessageBorder)
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(userMessage ? 14 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.details.isNotEmpty) ...[
              for (final detail in message.details)
                _MessageDetailCard(detail: detail, onOpenFile: onOpenFile),
            ],
            if (message.text.trim().isNotEmpty) ...[
              if (message.details.isNotEmpty) const SizedBox(height: 10),
              BasicMarkdownText(
                text: message.text,
                style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              ),
              if (!userMessage) ...[
                const SizedBox(height: 4),
                AppIconButton(
                  icon: Icons.content_copy_outlined,
                  tooltip: 'Copy response',
                  onPressed: () => _copyResponse(context),
                ),
              ],
            ],
            // Once OpenCode has produced a visible response, the prompt is
            // treated and this transcript action no longer needs space.
            if (showRevert && userMessage && message.id.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: 'Revert to this message',
                  child: AppButton(
                    variant: AppButtonVariant.tertiary,
                    tone: AppButtonTone.userMessage,
                    onPressed: onRevert,
                    icon: Icons.undo_rounded,
                    label: 'Revert',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Align(
      alignment: userMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: !userMessage && desktop
          ? SizedBox(width: double.infinity, child: content)
          : ConstrainedBox(
              key: userMessage
                  ? ValueKey('user-message-bubble-${message.id}')
                  : null,
              constraints: BoxConstraints(
                maxWidth: userMessage && !desktop
                    ? (MediaQuery.sizeOf(context).width * 0.78)
                          .clamp(240.0, 760.0)
                          .toDouble()
                    : 760,
              ),
              child: content,
            ),
    );
  }

  Future<void> _copyResponse(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: message.text.trim()));
    } on PlatformException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not copy response')));
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Response copied')));
  }
}

class _MessageDetailCard extends StatelessWidget {
  const _MessageDetailCard({required this.detail, this.onOpenFile});

  final ChatMessageDetail detail;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    if (detail is ChatToolDetail) {
      final toolDetail = detail as ChatToolDetail;
      if (toolDetail.filePath case final path? when onOpenFile != null) {
        final theme = Theme.of(context);
        final generic = toolDetail.presentation;
        final status = _toolStatus(toolDetail.status);
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Card(
            margin: EdgeInsets.zero,
            color: _tokens(theme).panelRaised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: Icon(
                    status.icon,
                    color: status.color(_tokens(theme)),
                  ),
                  title: Text(
                    generic is ChatGenericToolPresentation
                        ? generic.title
                        : _toolLabel(toolDetail.tool),
                  ),
                  subtitle: Text(path),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpenFile!(path),
                ),
                ExpansionTile(
                  title: const Text('Tool output'),
                  children: [_MessageDetailCard(detail: detail)],
                ),
              ],
            ),
          ),
        );
      }
      if (toolDetail.presentation case final ChatTodoPresentation todos) {
        return _TodoDetailCard(items: todos.items);
      }
      if (toolDetail.presentation case final ChatTaskPresentation task) {
        return _TaskDetailCard(task: task);
      }
      if (toolDetail.presentation
          case final ChatGenericToolPresentation generic) {
        return _GenericToolDetailCard(
          presentation: generic,
          status: toolDetail.status,
        );
      }
      if (toolDetail.tool == 'task') {
        return _TaskDetailCard(
          task: ChatTaskPresentation(
            status: switch (toolDetail.status) {
              'running' => ChatTaskStatus.running,
              'completed' => ChatTaskStatus.completed,
              'error' => ChatTaskStatus.error,
              _ => ChatTaskStatus.pending,
            },
            description: toolDetail.input,
            result: toolDetail.output,
            error: toolDetail.error,
          ),
        );
      }
    }
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    return switch (detail) {
      ChatFileDetail() => _HistoryAttachment(detail: detail as ChatFileDetail),
      ChatReasoningDetail(:final text) when _isSingleLine(text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.panelRaised,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.psychology_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: BasicMarkdownText(
                    text: text.trim(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ChatReasoningDetail(:final text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          collapsedBackgroundColor: tokens.panelRaised,
          backgroundColor: tokens.panelRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: const Icon(Icons.psychology_outlined, size: 18),
          title: const Text('Reasoning'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: BasicMarkdownText(
                text: text,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      ChatToolDetail() => _ToolDetailCard(detail: detail as ChatToolDetail),
    };
  }
}

class _TodoDetailCard extends StatelessWidget {
  const _TodoDetailCard({required this.items});

  final List<ChatTodoItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    final logicalLines = ChatTodoPresentation(items).logicalLineCount;
    final rows = [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_todoIcon(item.status), size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: BasicMarkdownText(
                  text: '${_priorityLabel(item.priority)} · ${item.content}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
    ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Todos', style: theme.textTheme.titleSmall),
        ...rows,
      ],
    );
    if (logicalLines <= 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.panelRaised,
          child: Padding(padding: const EdgeInsets.all(10), child: content),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ExpansionTile(
        initiallyExpanded: false,
        collapsedBackgroundColor: tokens.panelRaised,
        backgroundColor: tokens.panelRaised,
        leading: const Icon(Icons.checklist_rounded),
        title: const Text('Todos'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskDetailCard extends StatelessWidget {
  const _TaskDetailCard({required this.task});

  final ChatTaskPresentation task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    final details = <({String title, String text})>[
      if (task.prompt case final value? when value.isNotEmpty)
        (title: 'Prompt', text: value),
      if (task.result case final value? when value.isNotEmpty)
        (title: 'Result', text: value),
      if (task.error case final value? when value.isNotEmpty)
        (title: 'Error', text: value),
    ];
    final title = task.description ?? task.subagentType ?? 'Subagent task';
    final subtitle = [
      if (task.subagentType case final type? when type.isNotEmpty) type,
      if (task.background) 'Background',
    ].join(' · ');
    final icon = switch (task.status) {
      ChatTaskStatus.pending => Icons.hourglass_top_rounded,
      ChatTaskStatus.running => Icons.sync_rounded,
      ChatTaskStatus.completed => Icons.check_circle_outline_rounded,
      ChatTaskStatus.error => Icons.error_outline_rounded,
    };
    final color = switch (task.status) {
      ChatTaskStatus.completed => tokens.success,
      ChatTaskStatus.error => tokens.danger,
      _ => tokens.warning,
    };
    final content = details;
    final logicalLines = task.logicalLineCount;
    final header = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(icon, size: 18, color: color),
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
    );
    if (logicalLines == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.panelRaised,
          child: header,
        ),
      );
    }
    if (logicalLines == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.panelRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              for (final section in content)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: BasicMarkdownText(
                    text: section.text,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        collapsedBackgroundColor: tokens.panelRaised,
        backgroundColor: tokens.panelRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        leading: Icon(icon, size: 18, color: color),
        title: Text(title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        children: [
          for (final section in content)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  BasicMarkdownText(
                    text: section.text,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

IconData _todoIcon(ChatTodoStatus status) => switch (status) {
  ChatTodoStatus.pending => Icons.radio_button_unchecked,
  ChatTodoStatus.inProgress => Icons.timelapse_rounded,
  ChatTodoStatus.completed => Icons.check_circle_outline_rounded,
  ChatTodoStatus.cancelled => Icons.cancel_outlined,
};

String _priorityLabel(ChatTodoPriority priority) => switch (priority) {
  ChatTodoPriority.high => 'High',
  ChatTodoPriority.medium => 'Medium',
  ChatTodoPriority.low => 'Low',
};

class _ToolDetailCard extends StatelessWidget {
  const _ToolDetailCard({required this.detail});

  final ChatToolDetail detail;

  @override
  Widget build(BuildContext context) {
    final isTask = detail.tool == 'task';
    final title = isTask ? 'Subagent task' : _toolLabel(detail.tool);
    final body = [
      detail.output,
      detail.error,
    ].whereType<String>().where((value) => value.isNotEmpty).join('\n\n');
    return _GenericToolDetailCard(
      status: detail.status,
      presentation: ChatGenericToolPresentation(
        title: title,
        blocks: body.isEmpty
            ? const []
            : [ChatToolBlock(kind: ChatToolBlockKind.markdown, text: body)],
      ),
    );
  }
}

class _GenericToolDetailCard extends StatelessWidget {
  const _GenericToolDetailCard({
    required this.presentation,
    required this.status,
  });

  final ChatGenericToolPresentation presentation;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    final body = presentation.blocks;
    final lines = presentation.logicalLineCount;
    final statusPresentation = _toolStatus(status);
    final header = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(
        statusPresentation.icon,
        size: 18,
        color: statusPresentation.color(tokens),
      ),
      title: Text(
        presentation.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: presentation.subtitle == null
          ? null
          : Text(presentation.subtitle!),
    );
    if (lines == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.panelRaised,
          child: header,
        ),
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in body)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.label case final label?) ...[
                  Text(label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                ],
                BasicMarkdownText(
                  text: block.text,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
    if (lines == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Card(
          margin: EdgeInsets.zero,
          color: tokens.panelRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, content],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        collapsedBackgroundColor: tokens.panelRaised,
        backgroundColor: tokens.panelRaised,
        leading: Icon(
          statusPresentation.icon,
          size: 18,
          color: statusPresentation.color(tokens),
        ),
        title: Text(
          presentation.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: presentation.subtitle == null
            ? null
            : Text(presentation.subtitle!),
        children: [content],
      ),
    );
  }
}

({IconData icon, String label, Color Function(PromptTokens) color}) _toolStatus(
  String status,
) => switch (status) {
  'pending' => (
    icon: Icons.hourglass_top_rounded,
    label: '',
    color: (tokens) => tokens.warning,
  ),
  'running' => (
    icon: Icons.sync_rounded,
    label: '',
    color: (tokens) => tokens.warning,
  ),
  'completed' => (
    icon: Icons.check_circle_outline_rounded,
    label: '',
    color: (tokens) => tokens.success,
  ),
  _ => (
    icon: Icons.error_outline_rounded,
    label: '',
    color: (tokens) => tokens.danger,
  ),
};

String _toolLabel(String tool) => tool
    .split(RegExp('[-_]'))
    .where((segment) => segment.isNotEmpty)
    .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
    .join(' ');

bool _isSingleLine(String text) =>
    text.trim().split('\n').where((line) => line.trim().isNotEmpty).length <= 1;

class _HistoryAttachment extends StatefulWidget {
  const _HistoryAttachment({required this.detail});
  final ChatFileDetail detail;
  @override
  State<_HistoryAttachment> createState() => _HistoryAttachmentState();
}

class _HistoryAttachmentState extends State<_HistoryAttachment>
    with WidgetsBindingObserver {
  AttachmentThumbnailController? _controller;
  AttachmentThumbnailController? _viewer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _inspect() async {
    final bytes = widget.detail.bytes;
    if (bytes == null || _viewer != null) return;
    final viewer = AttachmentThumbnailController.viewer(bytes);
    _viewer = viewer;
    try {
      await showAttachmentImageViewer(
        context,
        controller: viewer,
        label: widget.detail.name,
      );
    } finally {
      viewer.dispose();
      if (identical(_viewer, viewer)) _viewer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _controller?.state == AttachmentThumbnailState.cleared) {
      _controller?.dispose();
      _load();
      if (mounted) setState(() {});
    }
  }

  void _load() {
    final bytes = widget.detail.bytes;
    _controller = bytes == null ? null : AttachmentThumbnailController(bytes);
  }

  @override
  void didUpdateWidget(_HistoryAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.detail.bytes, widget.detail.bytes)) {
      _viewer?.clear();
      _controller?.dispose();
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewer?.clear();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_controller != null)
        AttachmentThumbnail(
          controller: _controller!,
          label: widget.detail.name,
          onOpen: _inspect,
        )
      else
        const Text('Preview unavailable'),
      Text(widget.detail.name),
    ],
  );
}

PromptTokens _tokens(ThemeData theme) =>
    theme.extension<PromptTokens>() ??
    const PromptTokens(
      panel: Color(0xfff5f7f6),
      panelRaised: Color(0xffecefed),
      subtle: Color(0xff59676c),
      success: Color(0xff13795b),
      warning: Color(0xff9a5600),
      danger: Color(0xffb42318),
      diffAdd: Color(0xffdcf8e9),
      diffDelete: Color(0xffffe5e4),
      userMessageBackground: Color(0xffd7f7ed),
      userMessageForeground: Color(0xff123a30),
      userMessageBorder: Color(0xff64bba2),
    );
