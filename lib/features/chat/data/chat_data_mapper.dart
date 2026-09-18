import '../domain/chat_message.dart';
import '../domain/session_artifacts.dart';
import 'opencode_chat_api.dart';

ChatMessage mapChatMessage(OpenCodeMessageRecord record) => ChatMessage(
  id: record.id,
  role: record.role == 'user'
      ? ChatMessageRole.user
      : ChatMessageRole.assistant,
  createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAtMillis),
  text: record.text,
  details: record.details.map(mapChatMessageDetail).toList(growable: false),
  error: record.error,
);

ChatMessageDetail mapChatMessageDetail(OpenCodeMessageDetailRecord record) {
  return switch (record) {
    OpenCodeReasoningRecord(:final id, :final text) => ChatReasoningDetail(
      id: id,
      text: text,
    ),
    OpenCodeToolRecord(
      :final id,
      :final tool,
      :final status,
      :final input,
      :final output,
      :final error,
      :final presentation,
      :final filePath,
    ) =>
      ChatToolDetail(
        id: id,
        tool: tool,
        status: status,
        input: input,
        output: output,
        error: error,
        presentation: mapToolPresentation(presentation),
        filePath: filePath,
      ),
  };
}

ChatToolPresentation? mapToolPresentation(
  OpenCodeToolPresentationRecord? record,
) => switch (record) {
  OpenCodeTodoPresentationRecord(:final items) => ChatTodoPresentation(
    items
        .map(
          (item) => ChatTodoItem(
            content: item.content,
            status: _todoStatus(item.status),
            priority: _todoPriority(item.priority),
          ),
        )
        .toList(growable: false),
  ),
  OpenCodeTaskPresentationRecord(
    :final status,
    :final description,
    :final subagentType,
    :final prompt,
    :final result,
    :final error,
    :final background,
    :final summary,
  ) =>
    ChatTaskPresentation(
      status: switch (status) {
        'running' => ChatTaskStatus.running,
        'completed' => ChatTaskStatus.completed,
        'error' => ChatTaskStatus.error,
        _ => ChatTaskStatus.pending,
      },
      description: description,
      subagentType: subagentType,
      prompt: prompt,
      result: result,
      error: error,
      background: background,
      summary: summary,
    ),
  OpenCodeGenericToolPresentationRecord(
    :final title,
    :final subtitle,
    :final blocks,
  ) =>
    ChatGenericToolPresentation(
      title: title,
      subtitle: subtitle,
      blocks: blocks
          .map(
            (block) => ChatToolBlock(
              kind: switch (block.kind) {
                OpenCodeToolBlockKindRecord.markdown =>
                  ChatToolBlockKind.markdown,
                OpenCodeToolBlockKindRecord.plain => ChatToolBlockKind.plain,
                OpenCodeToolBlockKindRecord.code => ChatToolBlockKind.code,
                OpenCodeToolBlockKindRecord.diff => ChatToolBlockKind.diff,
              },
              text: block.text,
              label: block.label,
            ),
          )
          .toList(growable: false),
    ),
  null => null,
};

SessionTodo mapSessionTodo(OpenCodeTodoRecord record) => SessionTodo(
  id: record.id,
  content: record.content,
  status: _sessionTodoStatus(record.status),
  priority: _sessionTodoPriority(record.priority),
);

SessionFileDiff mapSessionDiff(OpenCodeFileDiffRecord record) =>
    SessionFileDiff(
      file: record.file,
      patch: record.patch,
      additions: record.additions,
      deletions: record.deletions,
      status: record.status,
    );

ChatTodoStatus _todoStatus(String value) => switch (value) {
  'in_progress' => ChatTodoStatus.inProgress,
  'completed' => ChatTodoStatus.completed,
  'cancelled' => ChatTodoStatus.cancelled,
  _ => ChatTodoStatus.pending,
};

ChatTodoPriority _todoPriority(String value) => switch (value) {
  'high' => ChatTodoPriority.high,
  'low' => ChatTodoPriority.low,
  _ => ChatTodoPriority.medium,
};

SessionTodoStatus _sessionTodoStatus(String value) => switch (value) {
  'in_progress' => SessionTodoStatus.inProgress,
  'completed' => SessionTodoStatus.completed,
  'cancelled' => SessionTodoStatus.cancelled,
  _ => SessionTodoStatus.pending,
};

SessionTodoPriority _sessionTodoPriority(String value) => switch (value) {
  'high' => SessionTodoPriority.high,
  'low' => SessionTodoPriority.low,
  _ => SessionTodoPriority.medium,
};
