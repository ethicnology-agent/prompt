enum ChatMessageRole { user, assistant }

sealed class ChatMessageDetail {
  const ChatMessageDetail({required this.id});

  final String id;
}

class ChatReasoningDetail extends ChatMessageDetail {
  const ChatReasoningDetail({required super.id, required this.text});

  final String text;
}

class ChatToolDetail extends ChatMessageDetail {
  const ChatToolDetail({
    required super.id,
    required this.tool,
    required this.status,
    this.input,
    this.output,
    this.error,
    this.presentation,
    this.filePath,
  });

  final String tool;
  final String status;
  final String? input;
  final String? output;
  final String? error;
  final ChatToolPresentation? presentation;

  /// Validated structured tool input; never inferred from display text.
  final String? filePath;
}

sealed class ChatToolPresentation {
  const ChatToolPresentation();
}

enum ChatToolBlockKind { markdown, plain, code, diff }

class ChatToolBlock {
  const ChatToolBlock({required this.kind, required this.text, this.label});

  final ChatToolBlockKind kind;
  final String text;
  final String? label;

  int get logicalLineCount => _logicalLineCount(text);
}

class ChatGenericToolPresentation extends ChatToolPresentation {
  const ChatGenericToolPresentation({
    required this.title,
    this.subtitle,
    this.blocks = const [],
  });

  final String title;
  final String? subtitle;
  final List<ChatToolBlock> blocks;

  int get logicalLineCount =>
      blocks.fold(0, (total, block) => total + block.logicalLineCount);
}

int _logicalLineCount(String text) => text
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((line) => line.trim().isNotEmpty && !_isFence(line))
    .length;

bool _isFence(String line) => line.trim().startsWith('```');

enum ChatTodoStatus { pending, inProgress, completed, cancelled }

enum ChatTodoPriority { high, medium, low }

class ChatTodoItem {
  const ChatTodoItem({
    required this.content,
    required this.status,
    required this.priority,
  });

  final String content;
  final ChatTodoStatus status;
  final ChatTodoPriority priority;
}

class ChatTodoPresentation extends ChatToolPresentation {
  const ChatTodoPresentation(this.items);

  final List<ChatTodoItem> items;

  int get logicalLineCount => items.fold(
    0,
    (total, item) => total + _todoLogicalLineCount(item.content),
  );
}

int _todoLogicalLineCount(String text) {
  final count = _logicalLineCount(text);
  return count == 0 ? 1 : count;
}

enum ChatTaskStatus { pending, running, completed, error }

class ChatTaskPresentation extends ChatToolPresentation {
  const ChatTaskPresentation({
    required this.status,
    this.description,
    this.subagentType,
    this.prompt,
    this.result,
    this.error,
    this.background = false,
    this.summary,
  });

  final ChatTaskStatus status;
  final String? description;
  final String? subagentType;
  final String? prompt;
  final String? result;
  final String? error;
  final bool background;
  final String? summary;

  int get logicalLineCount => [prompt, result, error].whereType<String>().fold(
    0,
    (total, text) => total + _logicalLineCount(text),
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.text,
    this.details = const [],
    this.error,
  });

  final String id;
  final ChatMessageRole role;
  final DateTime createdAt;
  final String text;
  final List<ChatMessageDetail> details;
  final String? error;
}
