import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/presentation/widgets/approval_dock.dart';
import 'package:prompt/features/chat/presentation/widgets/composer.dart';
import 'package:prompt/features/voice/voice.dart';

void main() {
  testWidgets('semantic voice toggle records a second segment', (tester) async {
    final voice = ValueNotifier<VoiceUiState>(const VoiceReady(transcript: ''));
    final text = TextEditingController();
    final attachments = ValueNotifier<List<PromptAttachment>>([]);
    addTearDown(voice.dispose);
    addTearDown(text.dispose);
    addTearDown(attachments.dispose);
    var starts = 0;
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            controller: text,
            command: null,
            attachments: attachments,
            onRemoveAttachment: (_) {},
            onSubmit: () async {},
            voiceState: voice,
            onVoiceHoldStart: () async {
              starts++;
              voice.value = const VoiceRecording('');
            },
            onVoiceHoldEnd: () async {
              stops++;
              voice.value = const VoiceReady(transcript: '');
            },
          ),
        ),
      ),
    );
    VoidCallback semanticTap() => tester
        .widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.hint ==
                    'Press and hold while speaking, then release',
          ),
        )
        .properties
        .onTap!;
    semanticTap()();
    await tester.pump();
    semanticTap()();
    await tester.pump();
    semanticTap()();
    await tester.pump();
    expect(starts, 2);
    expect(stops, 1);
  });

  for (final reject in [false, true]) {
    testWidgets(
      'question ${reject ? 'reject' : 'submit'} prevents duplicates and busy edits',
      (tester) async {
        final completion = Completer<bool>();
        var submissions = 0;
        const approval = PendingQuestionApproval(
          sessionId: 's',
          requestId: 'q',
          questions: [
            QuestionPrompt(
              question: 'Choose',
              header: 'Choice',
              options: [
                QuestionOption(label: 'One', description: 'First'),
                QuestionOption(label: 'Two', description: 'Second'),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ApprovalDock(
                approval: approval,
                onRespondToPermission: (_, _) async => false,
                onReplyToQuestion: (_, _) {
                  submissions++;
                  return completion.future;
                },
                onRejectQuestion: (_) {
                  submissions++;
                  return completion.future;
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('One'));
        await tester.pump();
        final action = tester
            .widget<AppButton>(
              find.widgetWithText(
                AppButton,
                reject ? 'Reject' : 'Submit answers',
              ),
            )
            .onPressed!;
        action();
        action();
        expect(submissions, 1);
        await tester.pump();
        expect(
          tester
              .widget<ChoiceOptionTile>(
                find.widgetWithText(ChoiceOptionTile, 'Two'),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        completion.complete(false);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceOptionTile>(
                find.widgetWithText(ChoiceOptionTile, 'Two'),
              )
              .enabled,
          isTrue,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
      },
    );
  }
}
