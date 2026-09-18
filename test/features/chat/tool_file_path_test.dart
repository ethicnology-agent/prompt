import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/features/chat/data/chat_data_mapper.dart';
import 'package:prompt/features/chat/data/conversation_sync.dart';
import 'package:prompt/features/chat/data/opencode_chat_api.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';

Map<String, dynamic> _part(String tool, Object? input) => {
  'id': 'part',
  'messageID': 'message',
  'sessionID': 'session',
  'type': 'tool',
  'tool': tool,
  'state': {'status': 'completed', 'input': input},
};

ChatToolDetail _rest(String tool, Object? input) =>
    mapChatMessage(
          OpenCodeMessageRecord.fromJson({
            'info': {
              'id': 'message',
              'role': 'assistant',
              'time': {'created': 1},
            },
            'parts': [_part(tool, input)],
          }),
        ).details.single
        as ChatToolDetail;

ChatToolDetail _live(String tool, Object? input, {ChatToolDetail? prior}) {
  final event =
      mapConversationEvent(
            OpenCodeEventEnvelope(
              directory: null,
              payload: {
                'type': 'message.part.updated',
                'properties': {'part': _part(tool, input)},
              },
            ),
            sessionId: 'session',
          )
          as MessagePartUpdatedEvent;
  return mergeConversationMessages(
        [
          if (prior != null)
            ChatMessage(
              id: 'message',
              role: ChatMessageRole.assistant,
              createdAt: DateTime(2026),
              text: '',
              details: [prior],
            ),
        ],
        {
          'message': ConversationMessage(
            id: 'message',
            sessionId: 'session',
            role: ConversationRole.assistant,
            parts: [event.part],
          ),
        },
      ).single.details.single
      as ChatToolDetail;
}

void main() {
  for (final tool in [
    'read',
    'edit',
    'write',
    'multiedit',
    'Read',
    'Edit',
    'Write',
    'MultiEdit',
  ]) {
    for (final key in ['filePath', 'file_path', 'path']) {
      test(
        '$tool $key maps the same exact structured path from REST and SSE',
        () {
          for (final path in [
            '/tmp/été file.dart',
            'lib/main.dart',
            r'C:\My Files\é.dart',
            'C:/My Files/file.dart',
            'notes:today.txt',
            ' leading and trailing ',
          ]) {
            expect(_rest(tool, {key: path}).filePath, path);
            expect(_live(tool, {key: path}).filePath, path);
          }
        },
      );
    }
  }
  test(
    'untrusted tool names, display strings and invalid paths never navigate',
    () {
      for (final input in [
        null,
        '/tmp/file',
        '{"filePath":"/tmp/file"}',
        {'command': 'cat /tmp/file'},
        {'filePath': 123},
        {'filePath': []},
        {'filePath': ''},
        {'filePath': '   '},
        {'filePath': '/tmp/a\nb'},
        {'filePath': '/tmp/a\u0000b'},
        {'filePath': '/tmp/a\u007fb'},
        {'filePath': 'https://example.com/a'},
        {'filePath': 'file:///tmp/a'},
        {'filePath': 'SSH://host/a'},
        {'filePath': ' //example.com/a'},
        {'filePath': '/tmp/a\u0085b'},
        {'filePath': true},
        {
          'filePath': {'path': '/tmp/a'},
        },
        {'filePath': null, 'path': '/tmp/a'},
      ]) {
        expect(_rest('read', input).filePath, isNull, reason: '$input');
        expect(_live('read', input).filePath, isNull, reason: '$input');
      }
      for (final tool in [
        'bash',
        'shell',
        'grep',
        'task',
        'read_file',
        ' read',
      ]) {
        expect(_rest(tool, {'filePath': '/tmp/file'}).filePath, isNull);
        expect(_live(tool, {'filePath': '/tmp/file'}).filePath, isNull);
      }
    },
  );
  test(
    'authoritative SSE path changes and removal replace prior navigation',
    () {
      const prior = ChatToolDetail(
        id: 'part',
        tool: 'read',
        status: 'completed',
        filePath: '/old',
      );
      expect(
        _live('read', {'file_path': '/new'}, prior: prior).filePath,
        '/new',
      );
      expect(_live('read', {'file_path': 3}, prior: prior).filePath, isNull);
      expect(_live('read', null, prior: prior).filePath, isNull);
    },
  );
}
