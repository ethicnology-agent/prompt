/// Domain model for a single live conversation, reduced from OpenCode SSE
/// events. These types intentionally hold no OpenCode JSON, HTTP, or Drift
/// shapes; see `conversation_event.dart` for the pure mapping layer and
/// `conversation_state.dart` for the pure reducer.
library;

import 'dart:typed_data';

final class FileMessagePart extends MessagePart {
  const FileMessagePart({
    required super.id,
    required super.messageId,
    required this.name,
    required this.mediaType,
    this.bytes,
  });
  final String name;
  final String mediaType;
  final Uint8List? bytes;
}

/// The role of a [ConversationMessage].
///
/// [ConversationRole.unknown] exists only for the transitional case where a
/// `message.part.updated` event is reduced before the corresponding
/// `message.updated` event has been observed. It is replaced once the
/// message's own event arrives.
enum ConversationRole { user, assistant, unknown }

/// A single part of a message. Parts arrive and are updated independently of
/// their owning message; each `message.part.updated` event carries a full,
/// authoritative snapshot of one part, never a delta to apply on top of a
/// prior snapshot.
sealed class MessagePart {
  const MessagePart({required this.id, required this.messageId});

  /// Stable identifier for this part, unique within its message.
  final String id;

  /// Identifier of the [ConversationMessage] this part belongs to.
  final String messageId;
}

/// A rendered text part of a message.
final class TextMessagePart extends MessagePart {
  const TextMessagePart({
    required super.id,
    required super.messageId,
    required this.text,
  });

  final String text;
}

/// A reasoning ("thinking") part of a message.
final class ReasoningMessagePart extends MessagePart {
  const ReasoningMessagePart({
    required super.id,
    required super.messageId,
    required this.text,
  });

  final String text;
}

/// Lifecycle status of a [ToolMessagePart].
enum ToolPartStatus { pending, running, completed, error }

/// A placeholder for a tool call. Only the tool name and its lifecycle
/// status are preserved; large tool input/output is never held by this pure
/// domain layer.
final class ToolMessagePart extends MessagePart {
  const ToolMessagePart({
    required super.id,
    required super.messageId,
    required this.tool,
    required this.status,
    this.summary,
    this.error,
    this.filePath,
  });

  final String tool;
  final ToolPartStatus status;

  /// A short user-visible description, such as a subagent task description.
  /// It is kept in memory only and is never logged or persisted.
  final String? summary;
  final String? error;
  final String? filePath;
}

/// Any other OpenCode part type (file, agent, step markers, snapshots,
/// patches, retries, compaction, subtasks, ...). Only its identity and raw
/// type name are preserved so the part can still be tracked and removed.
final class OtherMessagePart extends MessagePart {
  const OtherMessagePart({
    required super.id,
    required super.messageId,
    required this.partType,
  });

  final String partType;
}

/// A single message within a conversation, reduced from `message.updated`
/// and `message.part.updated`/`message.part.removed` events. Message parts
/// preserve the order in which they were first observed; a later snapshot of
/// an existing part replaces it in place without moving its position.
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    this.parts = const <MessagePart>[],
  });

  final String id;
  final String sessionId;
  final ConversationRole role;
  final List<MessagePart> parts;

  ConversationMessage copyWith({
    ConversationRole? role,
    List<MessagePart>? parts,
  }) {
    return ConversationMessage(
      id: id,
      sessionId: sessionId,
      role: role ?? this.role,
      parts: parts ?? this.parts,
    );
  }
}
