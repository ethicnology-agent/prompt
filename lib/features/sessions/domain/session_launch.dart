import '../../connection/connection.dart';
import '../../queue/queue.dart';
import '../../chat/chat.dart';
import 'open_code_session.dart';

class SessionLaunch {
  const SessionLaunch({
    required this.profile,
    required this.session,
    required this.draft,
    required this.options,
    this.submitDraft = false,
    this.attachments = const [],
  });
  final ServerProfile profile;
  final OpenCodeSession session;
  final String draft;
  final PromptExecutionOptions options;
  final bool submitDraft;
  final List<PromptAttachment> attachments;
}
