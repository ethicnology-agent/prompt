import '../domain/chat_message.dart';
import '../domain/conversation_message.dart';
import '../domain/conversation_state.dart';

/// The repository-owned, already consolidated conversation projection.
class ConversationRepositoryState {
  const ConversationRepositoryState({
    required this.messages,
    required this.conversation,
  });

  final List<ChatMessage> messages;
  final ConversationState conversation;
}

List<ChatMessage> mergeConversationMessages(
  List<ChatMessage> restMessages,
  Map<String, ConversationMessage> liveMessages,
) {
  if (liveMessages.isEmpty) return restMessages;
  final byId = <String, ChatMessage>{
    for (final message in restMessages) message.id: message,
  };
  final order = restMessages.map((message) => message.id).toList();
  var changed = false;
  for (final live in liveMessages.values) {
    final role = switch (live.role) {
      ConversationRole.user => ChatMessageRole.user,
      ConversationRole.assistant => ChatMessageRole.assistant,
      ConversationRole.unknown => null,
    };
    if (role == null) continue;
    final text = _text(live.parts) ?? '';
    final prior = byId[live.id];
    final details = _details(live.parts, prior?.details ?? const []);
    if (text.isEmpty && details.isEmpty) continue;
    final nextText = prior != null && prior.text.startsWith(text)
        ? prior.text
        : text;
    final nextDetails = details.isEmpty ? prior?.details ?? const [] : details;
    if (prior != null &&
        prior.role == role &&
        prior.text == nextText &&
        _sameDetails(prior.details, nextDetails)) {
      continue;
    }
    if (prior == null) order.add(live.id);
    byId[live.id] = ChatMessage(
      id: live.id,
      role: role,
      createdAt: prior?.createdAt ?? DateTime.now(),
      text: nextText,
      details: nextDetails,
      error: prior?.error,
    );
    changed = true;
  }
  return changed ? [for (final id in order) byId[id]!] : restMessages;
}

String? _text(List<MessagePart> parts) {
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is TextMessagePart) buffer.write(part.text);
  }
  return buffer.isEmpty ? null : buffer.toString();
}

List<ChatMessageDetail> _details(
  List<MessagePart> parts,
  List<ChatMessageDetail> loaded,
) {
  final prior = {for (final detail in loaded) detail.id: detail};
  return [
    for (final part in parts)
      switch (part) {
        ReasoningMessagePart(:final id, :final text) =>
          text.isEmpty && prior[id] is ChatReasoningDetail
              ? prior[id]!
              : ChatReasoningDetail(id: id, text: text),
        ToolMessagePart(
          :final id,
          :final tool,
          :final status,
          :final summary,
          :final error,
          :final filePath,
        ) =>
          _toolDetail(id, tool, status, summary, error, filePath, prior[id]),
        _ => null,
      },
  ].whereType<ChatMessageDetail>().toList(growable: false);
}

ChatToolDetail _toolDetail(
  String id,
  String tool,
  ToolPartStatus status,
  String? input,
  String? error,
  String? filePath,
  ChatMessageDetail? old,
) {
  final prior = old is ChatToolDetail ? old : null;
  return ChatToolDetail(
    id: id,
    tool: tool,
    status: status.name,
    input: input ?? prior?.input,
    output: prior?.output,
    error: error ?? prior?.error,
    presentation: prior?.presentation,
    filePath: filePath,
  );
}

bool _sameDetails(List<ChatMessageDetail> a, List<ChatMessageDetail> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].runtimeType != b[i].runtimeType || a[i].id != b[i].id) {
      return false;
    }
    if (a[i] is ChatReasoningDetail &&
        b[i] is ChatReasoningDetail &&
        (a[i] as ChatReasoningDetail).text !=
            (b[i] as ChatReasoningDetail).text) {
      return false;
    }
    if (a[i] is ChatToolDetail && b[i] is ChatToolDetail) {
      final left = a[i] as ChatToolDetail;
      final right = b[i] as ChatToolDetail;
      if (left.tool != right.tool ||
          left.status != right.status ||
          left.input != right.input ||
          left.output != right.output ||
          left.error != right.error ||
          left.filePath != right.filePath ||
          left.presentation != right.presentation) {
        return false;
      }
    }
  }
  return true;
}
