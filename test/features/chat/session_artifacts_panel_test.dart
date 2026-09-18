import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
import 'package:prompt/features/chat/presentation/widgets/session_artifacts_panel.dart';

void main() {
  for (final todoCount in [0, 1, 2]) {
    for (final diffCount in [0, 1, 2]) {
      testWidgets(
        'lazy artifacts preserve every row: $todoCount todos, $diffCount diffs',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(393, 850));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final todos = [
            for (var index = 0; index < todoCount; index++)
              SessionTodo(
                content: 'Task $index',
                status: SessionTodoStatus.pending,
                priority: SessionTodoPriority.medium,
              ),
          ];
          final diffs = [
            for (var index = 0; index < diffCount; index++)
              SessionFileDiff(
                file: 'file-$index.dart',
                patch: '-before\n+after',
                additions: 1,
                deletions: 1,
              ),
          ];
          var refreshes = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SessionArtifactsPanel(
                  lazy: true,
                  state: SessionArtifactsReady(todos: todos, diffs: diffs),
                  onRefresh: ({String? messageId}) async => refreshes++,
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            find.text('Todos ($todoCount) · Changed files ($diffCount)'),
            findsOneWidget,
          );
          expect(
            find.text('No todos reported for this session.'),
            todoCount == 0 ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('No changed files reported for this session.'),
            diffCount == 0 ? findsOneWidget : findsNothing,
          );
          for (final todo in todos) {
            expect(find.text(todo.content), findsOneWidget);
          }
          for (final diff in diffs) {
            expect(find.text(diff.file), findsOneWidget);
          }
          final labels = [
            for (final todo in todos) todo.content,
            for (final diff in diffs) diff.file,
          ];
          for (var index = 1; index < labels.length; index++) {
            expect(
              tester.getTopLeft(find.text(labels[index])).dy,
              greaterThan(tester.getTopLeft(find.text(labels[index - 1])).dy),
            );
          }
          await tester.tap(find.byTooltip('Refresh session artifacts'));
          await tester.pump();
          expect(refreshes, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
