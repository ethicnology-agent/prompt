import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/app/prompt_theme.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/chat_load_result.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';
import 'package:prompt/features/chat/presentation/conversation_screen.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/chat/presentation/widgets/approval_dock.dart';
import 'package:prompt/features/chat/presentation/widgets/composer.dart';
import 'package:prompt/features/chat/presentation/widgets/session_artifacts_panel.dart';
import 'package:prompt/features/capabilities/data/capabilities_repository.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/capabilities/domain/open_code_capabilities.dart';
import 'package:prompt/features/capabilities/domain/open_code_agent.dart';
import 'package:prompt/features/capabilities/domain/open_code_model.dart';
import 'package:prompt/features/capabilities/domain/open_code_slash_command.dart';
import 'package:prompt/features/capabilities/presentation/capabilities_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/domain/voice_language.dart';
import 'package:prompt/features/voice/domain/voice_model.dart';
import 'package:prompt/features/voice/presentation/voice_view_model.dart';
import 'package:url_launcher/link.dart';

class _StaticPasswordStore implements CredentialsStore {
  const _StaticPasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => null;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

double _contrastRatio(Color first, Color second) {
  final lighter = math.max(first.computeLuminance(), second.computeLuminance());
  final darker = math.min(first.computeLuminance(), second.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}

TextSpan? _findStyledSpan(
  InlineSpan span, {
  required String text,
  required FontWeight weight,
}) {
  if (span case final TextSpan textSpan) {
    if (textSpan.text == text && textSpan.style?.fontWeight == weight) {
      return textSpan;
    }
    for (final child in textSpan.children ?? const <InlineSpan>[]) {
      final match = _findStyledSpan(child, text: text, weight: weight);
      if (match != null) return match;
    }
  }
  return null;
}

class _CancelledAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

class _VoiceModelPicker implements VoiceModelPicker {
  @override
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language) async =>
      VoiceModel(
        language: language,
        encoderPath: '/encoder.int8.onnx',
        decoderPath: '/decoder.onnx',
        joinerPath: '/joiner.int8.onnx',
        tokensPath: '/tokens.txt',
        modelType: language == VoiceLanguage.french
            ? 'zipformer'
            : 'zipformer2',
      );
}

class _VoiceEngine implements VoiceEngine {
  _VoiceEngine(this.capture);

  final _VoiceCapture capture;

  @override
  Future<Result<void, VoiceEngineFailure>>
  requestMicrophonePermission() async => const Ok(null);

  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async => const Ok(null);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async {
    return Ok(capture);
  }

  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async =>
      Ok(capture.transcript);

  @override
  Future<void> releaseModel() async {}
}

class _VoiceCapture implements VoiceCapture {
  _VoiceCapture(this.transcript);

  final String transcript;
  final partials = StreamController<String>();

  @override
  Stream<String> get partialTranscripts => partials.stream;

  @override
  Future<void> release() async {
    unawaited(partials.close());
  }

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async {
    if (!partials.isClosed) {
      await partials.close();
    }
    return Ok(transcript);
  }
}

/// A [ConversationViewModel] test double that never touches the real
/// queue database, coordinator, or network: it seeds [messages] and
/// [queue] directly, and records every command the screen issues instead
/// of acting on it. The real queue/coordinator wiring (durable enqueue,
/// dispatch, abort-then-send-now, deactivation) is covered end-to-end by
/// `conversation_view_model_test.dart`; this double exists solely to test
/// the screen's rendering and command wiring in isolation.
class _FakeConversationViewModel extends ConversationViewModel {
  _FakeConversationViewModel()
    : super(
        chatRepository: ChatRepository(
          OpenCodeChatService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _StaticPasswordStore(),
        ),
        sessionsRepository: SessionsRepository(
          OpenCodeSessionsService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _StaticPasswordStore(),
        ),
        queueRepositoryProvider: () =>
            throw UnsupportedError('not used by the fake'),
        queueCoordinatorProvider: () =>
            throw UnsupportedError('not used by the fake'),
        attachmentPicker: _CancelledAttachmentPicker(),
      );

  int enqueueCallCount = 0;
  int removeCallCount = 0;
  int sendNowCallCount = 0;
  final List<String> enqueuedTexts = <String>[];
  PromptExecutionOptions? lastPromptOptions;
  int enqueueCommandCallCount = 0;
  String? lastCommandName;
  String? lastCommandArguments;
  PromptExecutionOptions? lastCommandOptions;
  String? lastRemovedId;
  String? lastSendNowId;
  bool openCalled = false;
  bool leaveCalled = false;
  int refreshCallCount = 0;
  int loadOlderCallCount = 0;

  int respondToPermissionCallCount = 0;
  String? lastPermissionId;
  PermissionResponse? lastPermissionResponse;

  int replyToQuestionCallCount = 0;
  String? lastQuestionRequestId;
  List<List<String>>? lastQuestionAnswers;

  int rejectQuestionCallCount = 0;
  String? lastRejectedRequestId;
  bool approvalSubmissionSucceeds = true;
  String? lastRevertedMessageId;

  int _nextId = 0;

  @override
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    openCalled = true;
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> refreshFromUserAction() async {
    refreshCallCount++;
  }

  @override
  Future<void> loadOlderFromUserAction() async {
    loadOlderCallCount++;
  }

  @override
  Future<void> leave() async {
    leaveCalled = true;
  }

  @override
  Future<void> leaveSession(OpenCodeSession session) async {
    leaveCalled = true;
  }

  @override
  Future<bool> enqueuePrompt(
    String text, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    enqueueCallCount++;
    enqueuedTexts.add(text);
    lastPromptOptions = executionOptions;
    queue.value = [
      ...queue.value,
      _prompt('prompt-${_nextId++}', text, QueuedPromptState.queued),
    ];
    return true;
  }

  @override
  Future<bool> enqueueCommand(
    String commandName,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    enqueueCommandCallCount++;
    lastCommandName = commandName;
    lastCommandArguments = arguments;
    lastCommandOptions = executionOptions;
    return true;
  }

  @override
  Future<void> removeFromQueue(String promptId) async {
    removeCallCount++;
    lastRemovedId = promptId;
    queue.value = queue.value
        .where((prompt) => prompt.id != promptId)
        .toList(growable: false);
  }

  @override
  Future<void> sendNow(String promptId) async {
    sendNowCallCount++;
    lastSendNowId = promptId;
  }

  @override
  Future<bool> respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    respondToPermissionCallCount++;
    lastPermissionId = permissionId;
    lastPermissionResponse = response;
    if (approvalSubmissionSucceeds) pendingApproval.value = null;
    return approvalSubmissionSucceeds;
  }

  @override
  Future<bool> replyToQuestion(
    String requestId,
    List<List<String>> answers,
  ) async {
    replyToQuestionCallCount++;
    lastQuestionRequestId = requestId;
    lastQuestionAnswers = answers;
    if (approvalSubmissionSucceeds) pendingApproval.value = null;
    return approvalSubmissionSucceeds;
  }

  @override
  Future<bool> rejectQuestion(String requestId) async {
    rejectQuestionCallCount++;
    lastRejectedRequestId = requestId;
    if (approvalSubmissionSucceeds) pendingApproval.value = null;
    return approvalSubmissionSucceeds;
  }

  @override
  Future<SessionsFailure?> revert(String messageId) async {
    lastRevertedMessageId = messageId;
    return null;
  }

  QueuedPrompt _prompt(String id, String text, QueuedPromptState state) {
    final now = DateTime.now();
    return QueuedPrompt(
      id: id,
      serverProfileId: 'profile-1',
      sessionId: 'session-1',
      directory: '/workspace/project',
      position: 0,
      promptText: text,
      state: state,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _ReviewRepositoryForScreen implements ReviewRepository {
  final _progress = StreamController<ReviewRun>.broadcast();
  @override
  Stream<ReviewRun> get progress => _progress.stream;
  @override
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) async => ReviewSnapshot(
    target: target,
    files: const [ReviewFile(path: 'a', status: 'M', patch: 'x')],
  );
  @override
  Future<ReviewRun> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations, {
    Duration timeout = const Duration(seconds: 120),
    Duration globalTimeout = const Duration(seconds: 240),
  }) async => const ReviewRun(state: ReviewRunState.completed);
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() => _progress.close();
}

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session-1',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  late _FakeConversationViewModel viewModel;

  setUp(() {
    viewModel = _FakeConversationViewModel();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    CapabilitiesViewModel? capabilitiesViewModel,
    ReviewViewModel Function()? reviewViewModelFactory,
    VoiceViewModel? voiceViewModel,
    ThemeData? theme,
    double textScale = 1.0,
    double viewInsetsBottom = 0,
    bool disableAnimations = false,
    OpenCodeSession? activeSession,
  }) async {
    // Default to a settled, empty transcript unless a test seeds its own:
    // the loading state renders an indeterminate `CircularProgressIndicator`,
    // whose animation never lets `pumpAndSettle` return.
    if (viewModel.messages.value is ConversationLoading) {
      viewModel.messages.value = const ConversationReady(<ChatMessage>[]);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: tester.binding.renderViews.first.constraints.biggest,
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: ConversationScreen(
          key: ValueKey('conversation:${(activeSession ?? session).id}'),
          profile: profile,
          session: activeSession ?? session,
          viewModel: viewModel,
          capabilitiesViewModel: capabilitiesViewModel,
          reviewViewModelFactory: reviewViewModelFactory,
          voiceViewModel: voiceViewModel,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('activates the view model for the given session on open', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(viewModel.openCalled, isTrue);
  });

  testWidgets('Review diff action opens ReviewScreen through its factory', (
    tester,
  ) async {
    final capabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    capabilities.value = const CapabilitiesReady(
      OpenCodeCapabilities(models: [], agents: [], commands: []),
    );
    await pumpScreen(
      tester,
      capabilitiesViewModel: capabilities,
      reviewViewModelFactory: () =>
          ReviewViewModel(_ReviewRepositoryForScreen()),
    );
    await tester.tap(find.byTooltip('Review diff'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('Review diff'), findsOneWidget);
  });

  testWidgets(
    'desktop conversation remains readable across widths and scaling',
    (tester) async {
      viewModel.messages.value = ConversationReady([
        ChatMessage(
          id: 'wide-message',
          role: ChatMessageRole.assistant,
          createdAt: DateTime(2024),
          text: 'Transcript remains readable at every supported width.',
        ),
      ]);
      viewModel.artifacts.value = const SessionArtifactsReady(
        todos: [
          SessionTodo(
            content: 'Contextual detail',
            status: SessionTodoStatus.inProgress,
            priority: SessionTodoPriority.medium,
          ),
        ],
        diffs: [],
      );
      for (final width in [900.0, 920.0, 1024.0, 1100.0, 1600.0]) {
        for (final scale in [1.3, 2.0]) {
          await tester.binding.setSurfaceSize(Size(width, 900));
          await pumpScreen(tester, textScale: scale);
          expect(
            find.text('Transcript remains readable at every supported width.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          final rail = find.byKey(
            const ValueKey('desktop-composer-action-rail'),
          );
          if (width >= 900) {
            expect(rail, findsOneWidget);
            expect(find.text('Contextual detail'), findsOneWidget);
            expect(find.byTooltip('Hide session details'), findsOneWidget);
          }
        }
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('desktop assistant transcript grows with the available width', (
    tester,
  ) async {
    final text = 'Transcript width probe ${'content ' * 200}';
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'resizable-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime(2024),
        text: text,
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Hide session details'));
    await tester.pump();

    final renderedText = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText && widget.textSpan?.toPlainText() == text,
    );
    final narrowWidth = tester.getSize(renderedText).width;

    await tester.binding.setSurfaceSize(const Size(1600, 900));
    await tester.pump();
    final wideWidth = tester.getSize(renderedText).width;

    expect(narrowWidth, greaterThan(900));
    expect(wideWidth, greaterThan(narrowWidth + 400));
  });

  testWidgets('short height keeps approval, queue, and composer reachable', (
    tester,
  ) async {
    await viewModel.enqueuePrompt('Queued prompt');
    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'question-short',
      questions: const [
        QuestionPrompt(
          question: 'Choose an option',
          header: 'Approval',
          options: [QuestionOption(label: 'Allow', description: 'Proceed')],
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(480, 450));
    await pumpScreen(tester, textScale: 1.3, viewInsetsBottom: 180);
    expect(tester.takeException(), isNull);
    // On a phone the questionnaire lives in a sheet, so the dock only has to
    // keep the way into it reachable. Refusing happens inside, once read.
    await tester.ensureVisible(find.text('Answer'));
    expect(find.text('Reject'), findsNothing);
    await tester.ensureVisible(find.text('Queued prompt'));
    // The request stands where the input stands: generation is blocked until
    // it is answered, so there is no field inviting a message meanwhile.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Message this session…',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('keeps the composer adjacent to the software keyboard', (
    tester,
  ) async {
    const surfaceSize = Size(393, 851);
    const keyboardHeight = 320.0;
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester, viewInsetsBottom: keyboardHeight);

    final composerPanel = find.byKey(
      const ValueKey('conversation-composer-panel'),
    );
    expect(
      tester.getBottomRight(composerPanel).dy,
      closeTo(surfaceSize.height - keyboardHeight, 1),
    );
  });

  testWidgets(
    'loads earlier history from the visible edge and preserves errors',
    (tester) async {
      viewModel.messages.value = ConversationReady([
        ChatMessage(
          id: 'visible',
          role: ChatMessageRole.assistant,
          createdAt: DateTime(2024),
          text: 'Readable transcript',
        ),
      ]);
      viewModel.history.value = const ConversationHistoryUiState(
        hasMore: true,
        loadingOlder: false,
        limitedByServer: false,
      );
      await pumpScreen(tester);
      final control = find.text('Load earlier messages');
      await tester.ensureVisible(control);
      await tester.tap(control);
      expect(viewModel.loadOlderCallCount, 1);

      viewModel.history.value = const ConversationHistoryUiState(
        hasMore: false,
        loadingOlder: false,
        limitedByServer: true,
        failure: ChatFailure.unavailable,
      );
      await tester.pump();
      expect(find.text('Readable transcript'), findsOneWidget);
      expect(
        find.text('History may be limited by this server'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Earlier messages unavailable'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hides an empty queue and shows a multi-line composer by default',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Queue: empty'), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, greaterThan(1));
      expect(find.byTooltip('Queue this prompt'), findsOneWidget);
    },
  );

  testWidgets('keeps the desktop footer intrinsic and caps active activity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Hide session details'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('conversation-activity-scroll')),
      findsNothing,
    );
    final composer = find.byKey(
      const ValueKey('conversation-composer-content'),
    );
    final transcript = find.byKey(
      const ValueKey('conversation-transcript-scroll'),
    );
    final oneLineHeight = tester.getSize(composer).height;
    expect(tester.getSize(composer).width, lessThanOrEqualTo(960));
    expect(oneLineHeight, lessThan(160));
    expect(tester.getSize(transcript).height, greaterThan(400));

    await tester.enterText(
      find.byType(TextField),
      'one\ntwo\nthree\nfour\nfive\nsix',
    );
    await tester.pump();
    final sixLineHeight = tester.getSize(composer).height;
    expect(sixLineHeight, greaterThan(oneLineHeight));
    expect(sixLineHeight, lessThan(320));

    await viewModel.enqueuePrompt('Queued prompt');
    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'question-wide',
      questions: const [
        QuestionPrompt(
          question: 'Choose an option',
          header: 'Approval',
          options: [QuestionOption(label: 'Allow', description: 'Proceed')],
        ),
      ],
    );
    await tester.pump();

    final activity = find.byKey(const ValueKey('conversation-activity-scroll'));
    expect(activity, findsOneWidget);
    expect(tester.getSize(activity).height, lessThanOrEqualTo(320));
    await tester.ensureVisible(find.text('Submit answers'));
    await tester.ensureVisible(find.text('Queued prompt'));
    await tester.ensureVisible(composer);
  });

  testWidgets('a phone answers the questionnaire in a sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'question-sheet',
      questions: const [
        QuestionPrompt(
          question: 'Which branch should the fix target?',
          header: 'Target',
          options: [
            QuestionOption(label: 'main', description: 'Default branch'),
            QuestionOption(label: 'develop', description: 'Integration'),
          ],
        ),
      ],
    );
    await pumpScreen(tester);

    // The dock keeps only the way in; the form itself is not crammed into it.
    expect(find.text('Submit answers'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('approval-open-questions')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Which branch should the fix target?'),
      ),
      findsOneWidget,
    );
    expect(find.text('Submit answers'), findsOneWidget);

    await tester.tap(find.text('main'));
    await tester.pump();
    await tester.tap(find.text('Submit answers'));
    await tester.pumpAndSettle();

    // Answering closes the sheet rather than leaving it open over the chat.
    expect(find.byType(BottomSheet), findsNothing);
    expect(viewModel.lastQuestionRequestId, 'question-sheet');
    expect(viewModel.lastQuestionAnswers, [
      ['main'],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the request stands in for the composer, and gives it back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);

    final composerField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Message this session…',
    );
    expect(composerField, findsOneWidget);

    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'stand-in',
      questions: const [
        QuestionPrompt(
          question: 'Which branch?',
          header: 'Target',
          options: [QuestionOption(label: 'main', description: 'Default')],
        ),
      ],
    );
    await tester.pump();

    // In the composer's place, not stacked above it as a second bar.
    expect(composerField, findsNothing);
    expect(
      find.byKey(const ValueKey('approval-open-questions')),
      findsOneWidget,
    );
    expect(find.byType(ApprovalDock), findsOneWidget);
    // One way in and nothing else: refusing belongs with the questions, so it
    // is read before it is refused.
    expect(find.text('Reject'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('approval-open-questions')));
    await tester.pumpAndSettle();
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Submit answers'), findsOneWidget);
    Navigator.of(tester.element(find.text('Reject'))).pop();
    await tester.pumpAndSettle();

    viewModel.pendingApproval.value = null;
    await tester.pump();

    expect(find.byType(ApprovalDock), findsNothing);
    expect(composerField, findsOneWidget);
  });

  testWidgets('the open sheet survives the stream rebuilding the request', (
    tester,
  ) async {
    PendingQuestionApproval sameRequest() => PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'question-live',
      questions: const [
        QuestionPrompt(
          question: 'Which branch should the fix target?',
          header: 'Target',
          options: [QuestionOption(label: 'main', description: 'Default')],
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.pendingApproval.value = sameRequest();
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('approval-open-questions')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // Live conversation state is rebuilt on every SSE event, so the very same
    // pending question arrives as a fresh object. That must not disturb a form
    // the user is in the middle of filling in.
    await tester.tap(find.text('main'));
    await tester.pump();
    viewModel.pendingApproval.value = sameRequest();
    await tester.pump();

    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('Submit answers'));
    await tester.pumpAndSettle();
    expect(viewModel.lastQuestionAnswers, [
      ['main'],
    ]);
  });

  testWidgets('a different request replaces the form and its answers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'first',
      questions: const [
        QuestionPrompt(
          question: 'First question',
          header: 'First',
          options: [QuestionOption(label: 'one', description: '')],
        ),
      ],
    );
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('approval-open-questions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('one'));
    await tester.pump();

    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'second',
      questions: const [
        QuestionPrompt(
          question: 'Second question',
          header: 'Second',
          options: [
            QuestionOption(label: 'a', description: ''),
            QuestionOption(label: 'b', description: ''),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();

    // The sheet was asking about a request nobody waits on any more.
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('approval-open-questions')));
    await tester.pumpAndSettle();
    // Two options means the controllers were rebuilt for the new question.
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long option is shown whole, description included', (
    tester,
  ) async {
    const label =
        'Rewrite the migration so it can be replayed on a shared database';
    const description =
        'Keeps the published revision untouched and adds a new one, which is '
        'the only safe order once another branch has consumed it.';
    await tester.binding.setSurfaceSize(const Size(400, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'question-long',
      questions: const [
        QuestionPrompt(
          question: 'How should the migration be handled?',
          header: 'Migration',
          options: [QuestionOption(label: label, description: description)],
          allowsCustomAnswer: true,
        ),
      ],
    );
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('approval-open-questions')));
    await tester.pumpAndSettle();

    // Nothing about an option is hidden: neither a long label, nor the
    // description that used to reach screen readers only.
    final labelFinder = find.text(label);
    expect(labelFinder, findsOneWidget);
    expect(find.text(description), findsOneWidget);
    expect(
      tester.widget<Text>(labelFinder).overflow,
      isNot(TextOverflow.ellipsis),
    );
    expect(tester.widget<Text>(labelFinder).maxLines, isNull);

    // A free answer gets room to grow instead of scrolling out of sight.
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Or type your own answer'),
    );
    expect(field.maxLines, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide layout keeps the questionnaire in the dock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.pendingApproval.value = PendingQuestionApproval(
      sessionId: 'session-1',
      requestId: 'question-wide-inline',
      questions: const [
        QuestionPrompt(
          question: 'Choose an option',
          header: 'Approval',
          options: [QuestionOption(label: 'Allow', description: 'Proceed')],
        ),
      ],
    );
    await pumpScreen(tester);

    expect(find.text('Submit answers'), findsOneWidget);
    expect(find.byKey(const ValueKey('approval-open-questions')), findsNothing);
  });

  testWidgets('pulling up from the transcript bottom refreshes the session', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        24,
        (index) => ChatMessage(
          id: 'message-$index',
          role: ChatMessageRole.assistant,
          text: 'Transcript item $index ' * 8,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await pumpScreen(tester);

    // The transcript opens anchored to the newest message, so a pull up from
    // there drags the standard refresh indicator rather than scrolling.
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(viewModel.refreshCallCount, 1);
  });

  testWidgets('opens anchored to the newest message without scrolling', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        24,
        (index) => ChatMessage(
          id: 'message-$index',
          role: ChatMessageRole.assistant,
          text: 'Transcript item $index ' * 8,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await pumpScreen(tester);

    expect(find.textContaining('Transcript item 23'), findsOneWidget);
    expect(find.byTooltip('Scroll to latest message'), findsNothing);
  });

  testWidgets('centers the latest-message action above the composer', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        24,
        (index) => ChatMessage(
          id: 'message-$index',
          role: ChatMessageRole.assistant,
          text: 'Transcript item $index ' * 8,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await pumpScreen(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pump();

    final jump = find.byTooltip('Scroll to latest message');
    expect(jump, findsOneWidget);
    expect(tester.getCenter(jump).dx, closeTo(400, 2));
    expect(
      tester.getCenter(jump).dx,
      lessThan(tester.getCenter(find.byTooltip('Add attachment')).dx),
    );
  });

  testWidgets('streams voice transcription into the composer', (tester) async {
    final capture = _VoiceCapture('Bonjour le monde');
    final voiceEngine = _VoiceEngine(capture);
    final voiceViewModel = VoiceViewModel(
      VoiceRepository(voiceEngine, _VoiceModelPicker()),
    );
    await voiceViewModel.selectModelFromUserAction(VoiceLanguage.french);
    final darkTheme = promptDarkTheme();
    final inputColors = darkTheme.extension<PromptTokens>()!;
    await pumpScreen(tester, voiceViewModel: voiceViewModel, theme: darkTheme);

    expect(find.byTooltip('Start voice mode'), findsOneWidget);
    final voiceRect = tester.getRect(find.byTooltip('Start voice mode'));
    final attachmentRect = tester.getRect(find.byTooltip('Add attachment'));
    expect(voiceRect.center.dx, closeTo(attachmentRect.center.dx, 1));
    expect(voiceRect.top, lessThan(attachmentRect.top));
    expect(
      attachmentRect.bottom,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
    final inputRect = tester.getRect(find.byType(TextField));
    final sendRect = tester.getRect(find.byTooltip('Queue this prompt'));
    expect(inputRect.right, closeTo(784, 2));
    expect(sendRect.top, lessThan(inputRect.top));

    await tester.enterText(find.byType(TextField), 'Existing draft');
    await tester.tap(find.byTooltip('Start voice mode'));
    await tester.pump();
    expect(find.text('Hold to talk'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    expect(find.byTooltip('Stop voice mode'), findsOneWidget);

    final hold = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_off_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Listening'), findsOneWidget);
    expect(
      _contrastRatio(
        inputColors.userMessageForeground,
        inputColors.userMessageBackground,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      tester.widget<Text>(find.text('Listening')).style?.color,
      inputColors.userMessageForeground,
    );
    expect(
      tester.widget<Text>(find.text('Release to mute')).style?.color,
      inputColors.userMessageForeground,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.mic_rounded)).color,
      inputColors.userMessageBackground,
    );
    expect(
      tester.widget<Text>(find.text('Stop')).style?.color,
      inputColors.userMessageForeground,
    );
    capture.partials.add('Bonjour');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Existing draft\nbonjour',
    );

    await hold.up();
    await tester.runAsync(() async {
      while (voiceViewModel.state.value is VoiceTranscribing) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Existing draft\nbonjour le monde',
    );
    expect(find.text('Hold to talk'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop voice mode'));
    await tester.pump();
    expect(find.text('Hold to talk'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('honors the reduced-motion preference in voice mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TextEditingController();
    final attachments = ValueNotifier<List<PromptAttachment>>([]);
    final voiceState = ValueNotifier<VoiceUiState>(const VoiceReady());
    addTearDown(() {
      controller.dispose();
      attachments.dispose();
      voiceState.dispose();
    });

    Future<void> pumpComposer({required bool disableAnimations}) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Scaffold(
            body: Composer(
              controller: controller,
              command: null,
              attachments: attachments,
              onRemoveAttachment: (_) {},
              onSubmit: () async {},
              voiceState: voiceState,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    List<Duration> voiceAnimationDurations() {
      final animations = find.descendant(
        of: find.byType(Composer),
        matching: find.byType(AnimatedContainer),
      );
      return [
        for (final animation in tester.widgetList<AnimatedContainer>(
          animations,
        ))
          animation.duration,
      ];
    }

    await pumpComposer(disableAnimations: false);
    expect(
      voiceAnimationDurations(),
      unorderedEquals(<Duration>[
        const Duration(milliseconds: 180),
        const Duration(milliseconds: 140),
      ]),
    );

    await pumpComposer(disableAnimations: true);
    expect(
      voiceAnimationDurations(),
      unorderedEquals(<Duration>[Duration.zero, Duration.zero]),
    );
  });

  testWidgets('push to talk supports a held keyboard key and ignores repeats', (
    tester,
  ) async {
    final capture = _VoiceCapture('done');
    final voiceViewModel = VoiceViewModel(
      VoiceRepository(_VoiceEngine(capture), _VoiceModelPicker()),
    );
    await voiceViewModel.selectModelFromUserAction(VoiceLanguage.french);
    await pumpScreen(tester, voiceViewModel: voiceViewModel);
    await tester.tap(find.byTooltip('Start voice mode'));
    await tester.pump();

    final pushToTalkFocus = tester.widget<Focus>(
      find
          .ancestor(
            of: find.byIcon(Icons.mic_off_rounded),
            matching: find.byType(Focus),
          )
          .first,
    );
    pushToTalkFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Listening'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.runAsync(() async {
      while (voiceViewModel.state.value is VoiceTranscribing) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    expect(capture.partials.isClosed, isTrue);
    await tester.pump();
  });

  testWidgets(
    'submitting the composer enqueues the prompt instead of sending it '
    'directly, and clears the field',
    (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Hello session');
      await tester.pump();
      await tester.tap(find.byTooltip('Queue this prompt'));
      await tester.pump();

      expect(viewModel.enqueueCallCount, 1);
      expect(viewModel.enqueuedTexts.single, 'Hello session');
      expect(find.text('Queue: 1 prompt'), findsOneWidget);
      expect(find.text('Hello session'), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);
    },
  );

  testWidgets('desktop plain Enter queues once and clears the composer', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Hello from Enter');
      await tester.tap(find.byType(TextField));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(viewModel.enqueueCallCount, 1);
      expect(viewModel.enqueuedTexts.single, 'Hello from Enter');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('desktop Shift+Enter inserts a newline without queueing', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'First');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(viewModel.enqueueCallCount, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'First\n',
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('desktop Ctrl+Enter queues once', (tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Hello from Ctrl+Enter');
      await tester.tap(find.byType(TextField));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(viewModel.enqueueCallCount, 1);
      expect(viewModel.enqueuedTexts.single, 'Hello from Ctrl+Enter');
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('mobile plain Enter remains multiline at desktop width', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    try {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'First');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(viewModel.enqueueCallCount, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'First\n',
      );
      expect(
        find.text(
          'Enter to send · Shift+Enter for newline · Ctrl+Enter to queue',
        ),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('mobile Ctrl+Enter does not trigger the desktop queue shortcut', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Mobile draft');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(viewModel.enqueueCallCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('never enqueues blank composer text', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(viewModel.enqueueCallCount, 0);
    expect(find.text('Queue: empty'), findsNothing);
  });

  testWidgets('shows removable attachment chips and queues their prompt', (
    tester,
  ) async {
    viewModel.attachments.value = [
      PromptAttachment(name: 'notes.txt', bytes: Uint8List.fromList([1])),
    ];
    await pumpScreen(tester);

    expect(find.textContaining('notes.txt'), findsOneWidget);
    expect(find.byTooltip('Remove attachment'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Read this');
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(viewModel.enqueueCallCount, 1);
  });

  testWidgets('removing an attachment chip releases it from the composer', (
    tester,
  ) async {
    final attachment = PromptAttachment(
      name: 'notes.txt',
      bytes: Uint8List.fromList([1]),
    );
    viewModel.attachments.value = [attachment];
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pump();

    expect(viewModel.attachments.value, isEmpty);
    expect(attachment.isReleased, isTrue);
  });

  testWidgets('selects a discovered slash command and queues its arguments '
      'with advertised agent and model defaults', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final capabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    await pumpScreen(tester, capabilitiesViewModel: capabilities);
    capabilities.value = CapabilitiesReady(
      OpenCodeCapabilities(
        models: const [],
        agents: const [],
        commands: const [
          OpenCodeSlashCommand(
            name: 'review',
            description: 'Review the selected files',
            agentName: 'build',
            model: OpenCodeModelReference(
              providerId: 'anthropic',
              modelId: 'claude-sonnet',
            ),
            isSubtask: false,
          ),
        ],
      ),
    );
    await tester.pump();

    final attachmentRect = tester.getRect(find.byTooltip('Add attachment'));
    final commandRect = tester.getRect(find.byTooltip('Choose slash command'));
    expect(attachmentRect.center.dx, closeTo(commandRect.center.dx, 1));
    expect(attachmentRect.top, lessThan(commandRect.top));
    expect(
      attachmentRect.bottom,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );

    await tester.tap(find.byTooltip('Choose slash command'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('/review'), findsOneWidget);
    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lib/');
    await tester.tap(find.byTooltip('Queue command'));
    await tester.pump();

    expect(viewModel.enqueueCommandCallCount, 1);
    expect(viewModel.lastCommandName, 'review');
    expect(viewModel.lastCommandArguments, 'lib/');
    expect(viewModel.lastCommandOptions!.agentName, 'build');
    expect(viewModel.lastCommandOptions!.modelProviderId, 'anthropic');
    capabilities.dispose();
  });

  testWidgets(
    'shows a send-now control only for a prompt that is still queued',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'Queued prompt');
      await tester.pump();
      await tester.tap(find.byTooltip('Queue this prompt'));
      await tester.pump();

      expect(
        find.byTooltip('Send now (aborts current generation)'),
        findsOneWidget,
      );

      // Simulate the coordinator advancing the prompt past `queued`.
      viewModel.queue.value = [
        viewModel.queue.value.single.copyWith(
          state: QueuedPromptState.acknowledged,
        ),
      ];
      await tester.pump();

      expect(
        find.byTooltip('Send now (aborts current generation)'),
        findsNothing,
      );
    },
  );

  testWidgets('offers merging only for queued prompts below the queue head', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'First');
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(find.byTooltip('Merge into the prompt above'), findsNothing);

    final queued = viewModel.queue.value.single;
    viewModel.queue.value = [queued, queued];
    await tester.pump();

    expect(find.byTooltip('Merge into the prompt above'), findsOneWidget);
  });

  testWidgets(
    'send now shows a clearly labeled abort confirmation, and only calls '
    'sendNow once confirmed',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'First');
      await tester.pump();
      await tester.tap(find.byTooltip('Queue this prompt'));
      await tester.pump();
      final promptId = viewModel.queue.value.single.id;

      await tester.tap(find.byTooltip('Send now (aborts current generation)'));
      await tester.pumpAndSettle();

      expect(
        find.text('Abort current generation and send now?'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'cancels whatever the session is currently '
          'generating',
        ),
        findsOneWidget,
      );
      expect(viewModel.sendNowCallCount, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(viewModel.sendNowCallCount, 0);

      await tester.tap(find.byTooltip('Send now (aborts current generation)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abort & send now'));
      await tester.pumpAndSettle();

      expect(viewModel.sendNowCallCount, 1);
      expect(viewModel.lastSendNowId, promptId);
    },
  );

  testWidgets('remove takes a prompt out of the queue', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'Removable');
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();
    final promptId = viewModel.queue.value.single.id;

    await tester.tap(find.byTooltip('Remove from queue'));
    await tester.pump();

    expect(viewModel.removeCallCount, 1);
    expect(viewModel.lastRemovedId, promptId);
    expect(find.text('Queue: empty'), findsNothing);
  });

  testWidgets('renders the loaded transcript', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.user,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Hi there',
      ),
    ]);

    await pumpScreen(tester);

    expect(find.text('Hi there'), findsOneWidget);
  });

  testWidgets('shows execution state as an AppBar icon', (tester) async {
    await pumpScreen(tester);

    viewModel.executionState.value = const SessionBusy();
    await tester.pump();
    expect(find.bySemanticsLabel('Execution status: Working'), findsOneWidget);
    expect(find.text('Working'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.sync_rounded),
      ),
      findsOneWidget,
    );

    viewModel.executionState.value = const SessionIdle();
    await tester.pump();
    expect(find.bySemanticsLabel('Execution status: Idle'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.check_circle_outline_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('animates the execution icon while busy and stops when idle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);

    viewModel.executionState.value = const SessionBusy();
    await tester.pump();
    final rotation = tester.widget<RotationTransition>(_spin());
    final initialTurns = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    final spinningTurns = tester
        .widget<RotationTransition>(_spin())
        .turns
        .value;
    expect(spinningTurns, isNot(closeTo(initialTurns, 0.001)));
    // Anticlockwise, the way the arrows of the sync and replay glyphs point.
    expect(spinningTurns, lessThan(initialTurns));

    viewModel.executionState.value = const SessionIdle();
    await tester.pump();
    final stoppedTurns = tester.widget<RotationTransition>(_spin()).turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.widget<RotationTransition>(_spin()).turns.value,
      closeTo(stoppedTurns, 0.001),
    );
  });

  testWidgets(
    'does not animate the execution icon when animations are disabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpScreen(tester, disableAnimations: true);

      viewModel.executionState.value = const SessionBusy();
      await tester.pump();
      final initialTurns = tester
          .widget<RotationTransition>(_spin())
          .turns
          .value;
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        tester.widget<RotationTransition>(_spin()).turns.value,
        closeTo(initialTurns, 0.001),
      );
    },
  );

  testWidgets('keeps a compact selectable user message legible in dark theme', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.user,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Hi there',
      ),
    ]);
    final theme = promptDarkTheme();
    final tokens = theme.extension<PromptTokens>()!;

    await pumpScreen(tester, theme: theme);

    expect(
      _contrastRatio(
        tokens.userMessageForeground,
        tokens.userMessageBackground,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(find.text('You'), findsNothing);
    expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.content_copy_outlined), findsNothing);
    final messageText = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'Hi there',
      ),
    );
    expect(messageText.textSpan?.style?.color, tokens.userMessageForeground);
    expect(messageText.onTap, isNotNull);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('Hi there'));
    await tester.pump();
    expect(find.text('Text copied'), findsOneWidget);
    expect(copiedText, 'Hi there');
    final revertButton = tester.widget<TextButton>(
      find.ancestor(
        of: find.byIcon(Icons.undo_rounded),
        matching: find.byType(TextButton),
      ),
    );
    expect(
      revertButton.style?.foregroundColor?.resolve({}),
      tokens.userMessageForeground,
    );
  });

  testWidgets('renders a live subagent tool before assistant prose', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'task-1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(id: 'tool-1', tool: 'task', status: 'running'),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('Subagent task'), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('offers expansion only when a task has details', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'task-1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'tool-1',
            tool: 'task',
            status: 'completed',
            output: '**Detailed result**\n\n```text\n**copy literally**\n```',
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.tap(find.text('Subagent task'));
    await tester.pumpAndSettle();

    final renderedResult = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().trim() == 'Detailed result',
      ),
    );
    expect(
      _findStyledSpan(
        renderedResult.textSpan!,
        text: 'Detailed result',
        weight: FontWeight.bold,
      ),
      isNotNull,
    );
    expect(find.text('**Detailed result**'), findsNothing);
    expect(find.text('**copy literally**'), findsOneWidget);
    expect(find.bySemanticsLabel('Code block'), findsOneWidget);
  });

  testWidgets('renders TodoWrite as a structured list without raw JSON', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'todo-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'todo-tool',
            tool: 'todowrite',
            status: 'completed',
            input:
                '{"todos":[{"content":"**Ship** it","status":"completed","priority":"high"}]}',
            output:
                '[{"content":"**Ship** it","status":"completed","priority":"high"}]',
            presentation: ChatTodoPresentation([
              ChatTodoItem(
                content: '**Ship** it',
                status: ChatTodoStatus.completed,
                priority: ChatTodoPriority.high,
              ),
              ChatTodoItem(
                content: 'Check tests',
                status: ChatTodoStatus.inProgress,
                priority: ChatTodoPriority.medium,
              ),
            ]),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('Todos'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.timelapse_rounded), findsOneWidget);
    expect(
      find.textContaining('High · Ship it', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('{"todos"'), findsNothing);
    expect(find.textContaining('[{"content"'), findsNothing);
    expect(find.byType(ExpansionTile), findsOneWidget);
  });

  testWidgets('renders one TodoWrite line directly without a chevron', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'todo-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'todo-tool',
            tool: 'todowrite',
            status: 'running',
            presentation: ChatTodoPresentation([
              ChatTodoItem(
                content: '**Review** changes',
                status: ChatTodoStatus.inProgress,
                priority: ChatTodoPriority.high,
              ),
            ]),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('Todos'), findsOneWidget);
    expect(
      find.textContaining('High · Review changes', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('collapses one TodoWrite item when its content is multiline', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'todo-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'todo-tool',
            tool: 'todowrite',
            status: 'running',
            presentation: ChatTodoPresentation([
              ChatTodoItem(
                content: 'First line\nSecond line',
                status: ChatTodoStatus.inProgress,
                priority: ChatTodoPriority.medium,
              ),
            ]),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.byType(ExpansionTile), findsOneWidget);
  });

  testWidgets('renders one generic tool line directly', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'tool',
            tool: 'shell',
            status: 'completed',
            presentation: ChatGenericToolPresentation(
              title: r'$ pwd',
              blocks: [
                ChatToolBlock(
                  kind: ChatToolBlockKind.plain,
                  text: '/workspace',
                  label: 'Output',
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('/workspace'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('renders Markdown in unfenced code and diff tool output', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'tool',
            tool: 'execute',
            status: 'completed',
            presentation: ChatGenericToolPresentation(
              title: 'Execute',
              blocks: [
                ChatToolBlock(
                  kind: ChatToolBlockKind.code,
                  text: '**Rendered output**',
                ),
                ChatToolBlock(
                  kind: ChatToolBlockKind.diff,
                  text: '[Rendered link](https://example.com)',
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);
    await tester.tap(find.text('Execute'));
    await tester.pumpAndSettle();

    final renderedOutput = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'Rendered output',
      ),
    );
    expect(
      _findStyledSpan(
        renderedOutput.textSpan!,
        text: 'Rendered output',
        weight: FontWeight.bold,
      ),
      isNotNull,
    );
    expect(find.text('**Rendered output**'), findsNothing);
    expect(find.byType(Link), findsOneWidget);
  });

  testWidgets('counts a one-line fenced code block as one direct line', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'tool',
            tool: 'execute',
            status: 'completed',
            presentation: ChatGenericToolPresentation(
              title: 'Execute',
              blocks: [
                ChatToolBlock(
                  kind: ChatToolBlockKind.code,
                  text: '```sh\necho ok\n```',
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('echo ok'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Code block',
      ),
      findsOneWidget,
    );
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('collapses a generic tool result with multiple logical lines', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'tool',
            tool: 'glob',
            status: 'completed',
            presentation: ChatGenericToolPresentation(
              title: 'Glob *.dart',
              blocks: [
                ChatToolBlock(
                  kind: ChatToolBlockKind.plain,
                  text: 'lib/a.dart\nlib/b.dart',
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(find.text('lib/a.dart\nlib/b.dart'), findsNothing);
    await tester.tap(find.text('Glob *.dart'));
    await tester.pumpAndSettle();
    expect(find.text('lib/a.dart\nlib/b.dart'), findsOneWidget);
  });

  testWidgets('keeps a generic header static when it has no useful line', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'tool',
            tool: 'plan_exit',
            status: 'completed',
            presentation: ChatGenericToolPresentation(title: 'Plan'),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('Plan'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets(
    'renders a structured subagent task without JSON, XML, or status labels',
    (tester) async {
      viewModel.messages.value = ConversationReady([
        ChatMessage(
          id: 'task-message',
          role: ChatMessageRole.assistant,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          text: '',
          details: const [
            ChatToolDetail(
              id: 'task-tool',
              tool: 'task',
              status: 'completed',
              input: '{"description":"Review changes"}',
              output:
                  '<task state="completed"><task_result>done</task_result></task>',
              presentation: ChatTaskPresentation(
                status: ChatTaskStatus.completed,
                description: 'Review changes',
                subagentType: 'reviewer',
                background: true,
                prompt: '**Check** this\n\n```text\n**copy literally**\n```',
                result: '**Looks good**',
                summary: 'Background task completed',
              ),
            ),
          ],
        ),
      ]);
      await pumpScreen(tester);

      expect(find.text('Review changes'), findsOneWidget);
      expect(find.text('reviewer · Background'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Running'), findsNothing);
      expect(find.textContaining('{"description"'), findsNothing);
      expect(find.textContaining('<task'), findsNothing);
      expect(find.text('Background task completed'), findsNothing);
      expect(find.byType(ExpansionTile), findsOneWidget);

      await tester.tap(find.text('Review changes'));
      await tester.pumpAndSettle();

      expect(find.text('Prompt'), findsOneWidget);
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('**copy literally**'), findsOneWidget);
      expect(find.bySemanticsLabel('Code block'), findsOneWidget);
      expect(
        find.textContaining('Looks good', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('does not expand a subagent task with no prompt or result', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'task-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'task-tool',
            tool: 'task',
            status: 'running',
            presentation: ChatTaskPresentation(
              status: ChatTaskStatus.running,
              description: 'Inspect code',
              subagentType: 'reviewer',
              summary: 'Background task started',
            ),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('Inspect code'), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(find.text('Background task started'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('renders a one-line subagent result directly', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'task-message',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(
            id: 'task-tool',
            tool: 'task',
            status: 'completed',
            presentation: ChatTaskPresentation(
              status: ChatTaskStatus.completed,
              description: 'Review changes',
              result: '**Looks good**',
            ),
          ),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(
      find.textContaining('Looks good', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('revert requires confirmation for its specific message ID', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'message-1',
        role: ChatMessageRole.user,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Hi there',
      ),
    ]);
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Revert to this message'));
    await tester.pumpAndSettle();
    expect(find.text('Revert this message?'), findsOneWidget);
    expect(viewModel.lastRevertedMessageId, isNull);

    await tester.tap(find.text('Revert message'));
    await tester.pumpAndSettle();
    expect(viewModel.lastRevertedMessageId, 'message-1');
  });

  testWidgets('never offers revert on an assistant message', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'assistant-1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Here is the answer',
      ),
    ]);
    await pumpScreen(tester);

    expect(find.byTooltip('Revert to this message'), findsNothing);
  });

  testWidgets('hides revert after a user message has been processed', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'user-1',
        role: ChatMessageRole.user,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Do the work',
      ),
      ChatMessage(
        id: 'assistant-1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        text: 'Done',
      ),
    ]);
    await pumpScreen(tester);

    expect(find.byTooltip('Revert to this message'), findsNothing);
  });

  testWidgets('renders basic Markdown without interpreting HTML', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text:
            '# Heading\n\nUse **bold** and `code`.\n\n```dart\nmain();\n```\n\n[Prompt](https://example.com) <b>not HTML</b>',
      ),
    ]);

    await pumpScreen(tester);

    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('main();'), findsOneWidget);
    expect(find.textContaining('Prompt', findRichText: true), findsOneWidget);
    expect(find.byType(Link), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.link == true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('<b>not HTML</b>', findRichText: true),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Code block'), findsOneWidget);
  });

  testWidgets(
    'launches bare and Markdown HTTP links from selectable messages',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launchedUrls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          final arguments = call.arguments as Map<Object?, Object?>;
          launchedUrls.add(arguments['url']! as String);
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      viewModel.messages.value = ConversationReady([
        ChatMessage(
          id: 'links',
          role: ChatMessageRole.assistant,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          text:
              'Bare HTTP: http://example.com\n\n[Secure](https://example.com)',
        ),
      ]);

      await pumpScreen(tester);

      await tester.tap(find.text('http://example.com'));
      await tester.tap(find.text('Secure'));
      await tester.pump();

      expect(launchedUrls, ['http://example.com', 'https://example.com']);
    },
  );

  testWidgets('renders GFM tables with Markdown and desktop scrolling', (
    tester,
  ) async {
    final wideCell = 'wide table cell ${'content ' * 40}';
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'table',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text:
            '| **Name** | Count | Note |\n'
            '| :--- | ---: | :---: |\n'
            '| [Alice](https://example.com) | `12` | $wideCell |\n'
            '| Bob | 345 | a \\| b |',
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('345'), findsOneWidget);
    expect(find.text('a | b'), findsOneWidget);
    expect(find.text('**Name**'), findsNothing);
    expect(find.byType(Link), findsOneWidget);
    final renderedHeader = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'Name',
      ),
    );
    expect(
      _findStyledSpan(
        renderedHeader.textSpan!,
        text: 'Name',
        weight: FontWeight.bold,
      ),
      isNotNull,
    );
    final table = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Markdown table',
    );
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.byType(Scrollbar)),
      findsOneWidget,
    );
    final horizontalScroll = find.descendant(
      of: table,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    final scrollView = tester.widget<SingleChildScrollView>(horizontalScroll);
    expect(scrollView.controller, isNotNull);
    expect(scrollView.controller!.position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      horizontalScroll,
      const Offset(-240, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(scrollView.controller!.offset, greaterThan(0));
  });

  testWidgets('uses a card for one-line reasoning and an expansion for prose', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'reasoning',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatReasoningDetail(id: 'short', text: '**One thought**\n'),
          ChatReasoningDetail(id: 'long', text: 'Line one\nLine two'),
        ],
      ),
    ]);
    await pumpScreen(tester);

    final renderedReasoning = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'One thought',
      ),
    );
    expect(
      _findStyledSpan(
        renderedReasoning.textSpan!,
        text: 'One thought',
        weight: FontWeight.bold,
      ),
      isNotNull,
    );
    expect(find.text('**One thought**'), findsNothing);
    expect(find.byType(ExpansionTile), findsOneWidget);
  });

  testWidgets('lifecycle pause removes composer focus without layout errors', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps malformed Markdown and unsafe link schemes as plain text',
    (tester) async {
      viewModel.messages.value = ConversationReady([
        ChatMessage(
          id: 'm1',
          role: ChatMessageRole.assistant,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          text: '[unsafe](javascript:alert(1)) and **unfinished',
        ),
      ]);

      await pumpScreen(tester);

      expect(
        find.text('[unsafe](javascript:alert(1)) and **unfinished'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders selectable session todos and file diffs', (
    tester,
  ) async {
    viewModel.artifacts.value = const SessionArtifactsReady(
      todos: [
        SessionTodo(
          id: 'todo-1',
          content: 'Review diff',
          status: SessionTodoStatus.inProgress,
          priority: SessionTodoPriority.high,
        ),
      ],
      diffs: [
        SessionFileDiff(
          file: 'lib/example.dart',
          patch: '@@ -1 +1 @@\n-old line\n+new line',
          additions: 1,
          deletions: 1,
        ),
      ],
    );
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Session artifacts'));
    await tester.pumpAndSettle();

    expect(find.text('Review diff'), findsOneWidget);
    expect(find.text('lib/example.dart'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('shows and changes model and agent in session artifacts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.artifacts.value = const SessionArtifactsReady(
      todos: [],
      diffs: [],
    );
    final capabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    capabilities.value = CapabilitiesReady(
      const OpenCodeCapabilities(
        models: [
          OpenCodeModel(
            providerId: 'anthropic',
            id: 'claude-sonnet',
            name: 'Claude Sonnet',
            isProviderConnected: true,
          ),
        ],
        agents: [
          OpenCodeAgent(
            name: 'build',
            mode: OpenCodeAgentMode.primary,
            isBuiltIn: true,
          ),
        ],
        commands: [],
      ),
    );
    await pumpScreen(tester, capabilitiesViewModel: capabilities);
    const capabilityState = CapabilitiesReady(
      OpenCodeCapabilities(
        models: [
          OpenCodeModel(
            providerId: 'anthropic',
            id: 'claude-sonnet',
            name: 'Claude Sonnet',
            isProviderConnected: true,
          ),
        ],
        agents: [
          OpenCodeAgent(
            name: 'build',
            mode: OpenCodeAgentMode.primary,
            isBuiltIn: true,
          ),
        ],
        commands: [],
      ),
    );
    capabilities.value = capabilityState;
    await tester.pump();

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('OpenCode default'), findsNWidgets(2));

    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Default').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Sonnet').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('build').last);
    await tester.ensureVisible(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Claude Sonnet'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    capabilities.dispose();
  });

  testWidgets('compact execution choices use a sheet and keep long labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    viewModel.artifacts.value = const SessionArtifactsReady(
      todos: [],
      diffs: [],
    );
    final longModelName =
        'A model name that remains completely readable on a phone';
    final capabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    final capabilityState = CapabilitiesReady(
      OpenCodeCapabilities(
        models: [
          OpenCodeModel(
            providerId: 'anthropic',
            id: 'long-model',
            name: longModelName,
            isProviderConnected: true,
          ),
        ],
        agents: const [
          OpenCodeAgent(
            name: 'build',
            mode: OpenCodeAgentMode.primary,
            isBuiltIn: true,
          ),
        ],
        commands: const [],
      ),
    );
    capabilities.value = capabilityState;
    await pumpScreen(tester, capabilitiesViewModel: capabilities);
    capabilities.value = capabilityState;
    await tester.pump();

    await tester.tap(find.byTooltip('Session artifacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model').last);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNWidgets(2));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Model').last);
    await tester.pumpAndSettle();
    expect(find.text(longModelName), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(longModelName));
    await tester.pumpAndSettle();
    expect(find.text(longModelName), findsOneWidget);
    expect(tester.takeException(), isNull);
    capabilities.dispose();
  });

  testWidgets('restores the model and unsent draft for each session', (
    tester,
  ) async {
    viewModel.artifacts.value = const SessionArtifactsReady(
      todos: [],
      diffs: [],
    );
    final firstSession = OpenCodeSession(
      id: 'session-first',
      projectId: 'project-1',
      directory: '/workspace/project',
      title: 'First session',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      modelProviderId: 'anthropic',
      modelId: 'claude-fable-5',
      agentName: 'codex',
    );
    final secondSession = OpenCodeSession(
      id: 'session-second',
      projectId: 'project-1',
      directory: '/workspace/project',
      title: 'Second session',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      modelProviderId: 'anthropic',
      modelId: 'claude-fable-5',
      agentName: 'codex',
    );
    final capabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    const capabilityState = CapabilitiesReady(
      OpenCodeCapabilities(
        models: [
          OpenCodeModel(
            providerId: 'anthropic',
            id: 'claude-fable-5',
            name: 'Fable',
            isProviderConnected: true,
          ),
          OpenCodeModel(
            providerId: 'openai',
            id: 'gpt-5.6-sol',
            name: 'GPT-5.6 Sol',
            isProviderConnected: true,
          ),
        ],
        agents: [
          OpenCodeAgent(
            name: 'codex',
            mode: OpenCodeAgentMode.primary,
            isBuiltIn: true,
          ),
        ],
        commands: [],
      ),
    );
    capabilities.value = capabilityState;

    await pumpScreen(
      tester,
      activeSession: firstSession,
      capabilitiesViewModel: capabilities,
    );
    capabilities.value = capabilityState;
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Unsent first draft');
    await tester.tap(find.byTooltip('Session artifacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fable').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-5.6 Sol').last);
    await tester.ensureVisible(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await pumpScreen(tester, activeSession: secondSession);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField), 'Unsent second draft');

    final restoredCapabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    restoredCapabilities.value = capabilityState;
    await pumpScreen(
      tester,
      activeSession: firstSession,
      capabilitiesViewModel: restoredCapabilities,
    );
    restoredCapabilities.value = capabilityState;
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Unsent first draft',
    );
    await tester.tap(find.byTooltip('Session artifacts'));
    await tester.pumpAndSettle();
    expect(find.text('GPT-5.6 Sol'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();
    expect(viewModel.enqueuedTexts.last, 'Unsent first draft');
    expect(viewModel.lastPromptOptions?.modelProviderId, 'openai');
    expect(viewModel.lastPromptOptions?.modelId, 'gpt-5.6-sol');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await pumpScreen(tester, activeSession: secondSession);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Unsent second draft',
    );
    capabilities.dispose();
    restoredCapabilities.dispose();
  });

  testWidgets('opens artifacts in a scrollable sheet on a narrow layout', (
    tester,
  ) async {
    viewModel.artifacts.value = SessionArtifactsReady(
      todos: List.generate(
        20,
        (index) => SessionTodo(
          content: 'Todo $index',
          status: SessionTodoStatus.pending,
          priority: SessionTodoPriority.medium,
        ),
      ),
      diffs: const [],
    );
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Session artifacts'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
    await tester.drag(find.text('Todo 0'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps desktop queue shortcut guidance out of the field layout', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpScreen(tester);

      expect(
        find.text(
          'Enter to send · Shift+Enter for newline · Ctrl+Enter to queue',
        ),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('shows artifacts and keeps composer actions beside wide panel', (
    tester,
  ) async {
    viewModel.artifacts.value = const SessionArtifactsReady(
      todos: [
        SessionTodo(
          content: 'Desktop todo',
          status: SessionTodoStatus.inProgress,
          priority: SessionTodoPriority.medium,
        ),
      ],
      diffs: [
        SessionFileDiff(
          file: 'lib/desktop.dart',
          patch: '@@ -1 +1 @@\n-old\n+new',
          additions: 1,
          deletions: 1,
        ),
      ],
    );
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'desktop-transcript',
        role: ChatMessageRole.assistant,
        createdAt: DateTime(2024),
        text: 'Desktop transcript remains present',
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('Desktop todo'), findsOneWidget);
    expect(find.text('lib/desktop.dart'), findsOneWidget);
    expect(find.text('Desktop transcript remains present'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final divider = tester.getRect(find.byType(VerticalDivider));
    final actionRail = tester.getRect(
      find.byKey(const ValueKey('desktop-composer-action-rail')),
    );
    final attachment = tester.getRect(find.byTooltip('Add attachment'));
    expect(attachment.right, lessThanOrEqualTo(divider.left));
    expect(actionRail.right, lessThanOrEqualTo(divider.left));
    expect(attachment.left, lessThan(actionRail.right));
    expect(attachment.left - divider.right, lessThanOrEqualTo(20));

    final detailsBefore = tester
        .getRect(find.byType(SessionArtifactsPanel))
        .width;
    expect(detailsBefore, greaterThan(450));
    await tester.drag(
      find.byKey(const ValueKey('desktop-session-details-divider')),
      const Offset(-80, 0),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byType(SessionArtifactsPanel)).width,
      greaterThan(detailsBefore),
    );
    expect(
      tester.getRect(find.byType(TextField)).right,
      lessThan(
        tester
            .getRect(
              find.byKey(const ValueKey('desktop-session-details-divider')),
            )
            .left,
      ),
    );
  });

  testWidgets('toggles the persistent artifacts panel on wide layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    final artifactsButton = find.widgetWithIcon(
      IconButton,
      Icons.assignment_outlined,
    );
    expect(
      tester.widget<IconButton>(artifactsButton).tooltip,
      'Hide session details',
    );
    expect(find.text('Session artifacts'), findsOneWidget);

    await tester.tap(artifactsButton);
    await tester.pump();
    expect(
      tester.widget<IconButton>(artifactsButton).tooltip,
      'Show session details',
    );
    expect(find.byType(SessionArtifactsPanel), findsNothing);

    await tester.tap(artifactsButton);
    await tester.pump();
    expect(
      tester.widget<IconButton>(artifactsButton).tooltip,
      'Hide session details',
    );
    expect(find.byType(SessionArtifactsPanel), findsOneWidget);
  });

  testWidgets('offers transcript refresh on wide layouts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    expect(find.byTooltip('Refresh transcript'), findsOneWidget);
    expect(viewModel.refreshCallCount, 0);
    await tester.tap(find.byTooltip('Refresh transcript'));
    await tester.pump();
    expect(viewModel.refreshCallCount, 1);
  });

  testWidgets('desktop bottom pull-to-refresh triggers without inversion', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        20,
        (index) => ChatMessage(
          id: 'refresh-$index',
          role: ChatMessageRole.assistant,
          text: 'Refreshable message $index ' * 8,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);
    final scroll = find.byKey(const ValueKey('conversation-transcript-scroll'));
    await tester.drag(
      find.byKey(const ValueKey('conversation-transcript-scroll')),
      const Offset(0, 380),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(viewModel.refreshCallCount, 1);
    expect(tester.takeException(), isNull);
    expect(scroll, findsOneWidget);
  });

  testWidgets(
    'desktop pull-to-refresh does not trigger from older transcript history',
    (tester) async {
      viewModel.messages.value = ConversationReady(
        List.generate(
          30,
          (index) => ChatMessage(
            id: 'older-refresh-$index',
            role: ChatMessageRole.assistant,
            text: 'Older refresh message $index ' * 12,
            createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpScreen(tester);

      final scrollView = find.byKey(
        const ValueKey('conversation-transcript-scroll'),
      );
      final scrollable = find.descendant(
        of: scrollView,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable.first).position;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(scrollView),
          scrollDelta: const Offset(0, -500),
        ),
      );
      await tester.pump();
      expect(position.pixels, greaterThan(80));

      await tester.drag(scrollView, const Offset(0, 380));
      await tester.pump(const Duration(milliseconds: 500));

      expect(viewModel.refreshCallCount, 0);
    },
  );

  testWidgets('desktop pointer scrolling moves toward older messages', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        30,
        (index) => ChatMessage(
          id: 'desktop-message-$index',
          role: ChatMessageRole.assistant,
          text: 'Desktop transcript item $index ' * 12,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    final scrollView = find.byKey(
      const ValueKey('conversation-transcript-scroll'),
    );
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.pixels, 0);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scrollView),
        scrollDelta: const Offset(0, -300),
      ),
    );
    await tester.pump();

    expect(position.pixels, greaterThan(0));
  });

  testWidgets('hides messages without displayable text', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-only',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '   ',
      ),
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        text: 'Visible response',
      ),
    ]);

    await pumpScreen(tester);

    expect(find.text('No text output.'), findsNothing);
    expect(find.text('Visible response'), findsOneWidget);
  });

  testWidgets('deactivates the view model when the screen is left', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(viewModel.leaveCalled, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(viewModel.leaveCalled, isTrue);
  });

  group('approval dock', () {
    testWidgets('shows nothing when there is no pending approval', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Allow once'), findsNothing);
      expect(find.text('Submit answers'), findsNothing);
    });

    testWidgets('renders a pending permission with allow once/always/deny, and '
        'submitting once calls respondToPermission', (tester) async {
      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-1',
        toolType: 'bash',
        title: 'Run rm -rf /tmp/build',
      );

      await pumpScreen(tester);

      expect(find.textContaining('bash'), findsOneWidget);
      expect(find.text('Run rm -rf /tmp/build'), findsOneWidget);
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.text('Always allow'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);

      await tester.tap(find.text('Allow once'));
      await tester.pump();

      expect(viewModel.respondToPermissionCallCount, 1);
      expect(viewModel.lastPermissionId, 'perm-1');
      expect(viewModel.lastPermissionResponse, PermissionResponse.once);
    });

    testWidgets('re-enables permission controls after a failed submission', (
      tester,
    ) async {
      viewModel.approvalSubmissionSucceeds = false;
      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-failed',
        toolType: 'bash',
        title: 'Run a command',
      );

      await pumpScreen(tester);
      await tester.tap(find.text('Allow once'));
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Allow once'),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('always allow and deny call respondToPermission with the '
        'matching response', (tester) async {
      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-1',
        toolType: 'edit',
        title: 'Edit a file',
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Always allow'));
      await tester.pump();
      expect(viewModel.lastPermissionResponse, PermissionResponse.always);

      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-2',
        toolType: 'edit',
        title: 'Edit another file',
      );
      await tester.pump();

      await tester.tap(find.text('Deny'));
      await tester.pump();
      expect(viewModel.lastPermissionResponse, PermissionResponse.reject);
      expect(viewModel.lastPermissionId, 'perm-2');
    });

    testWidgets(
      'renders a pending question with selectable options, and submitting '
      'calls replyToQuestion with the selected label',
      (tester) async {
        viewModel.pendingApproval.value = PendingQuestionApproval(
          sessionId: 'session-1',
          requestId: 'que-1',
          questions: const [
            QuestionPrompt(
              question: 'Which database should I use?',
              header: 'Database choice',
              options: [
                QuestionOption(label: 'Postgres', description: 'Relational'),
                QuestionOption(label: 'SQLite', description: 'Embedded'),
              ],
            ),
          ],
        );

        await pumpScreen(tester);

        expect(find.text('Which database should I use?'), findsOneWidget);
        expect(find.text('Postgres'), findsOneWidget);
        expect(find.text('SQLite'), findsOneWidget);

        // Submit is disabled until an answer is chosen.
        final submitButtonFinder = find.widgetWithText(
          FilledButton,
          'Submit answers',
        );
        expect(
          tester.widget<FilledButton>(submitButtonFinder).onPressed,
          isNull,
        );

        await tester.tap(find.text('Postgres'));
        await tester.pump();

        expect(
          tester.widget<FilledButton>(submitButtonFinder).onPressed,
          isNotNull,
        );

        await tester.ensureVisible(submitButtonFinder);
        await tester.tap(submitButtonFinder);
        await tester.pump();

        expect(viewModel.replyToQuestionCallCount, 1);
        expect(viewModel.lastQuestionRequestId, 'que-1');
        expect(viewModel.lastQuestionAnswers, [
          ['Postgres'],
        ]);
      },
    );

    testWidgets('a typed custom answer also enables submit', (tester) async {
      viewModel.pendingApproval.value = PendingQuestionApproval(
        sessionId: 'session-1',
        requestId: 'que-1',
        questions: const [
          QuestionPrompt(
            question: 'Anything else you want me to know?',
            header: 'Other',
            options: [],
          ),
        ],
      );

      await pumpScreen(tester);

      final submitButtonFinder = find.widgetWithText(
        FilledButton,
        'Submit answers',
      );
      expect(tester.widget<FilledButton>(submitButtonFinder).onPressed, isNull);

      // The dock's custom-answer field renders before the composer's
      // `TextField` in the tree.
      await tester.enterText(find.byType(TextField).first, 'Keep it concise');
      await tester.pump();

      expect(
        tester.widget<FilledButton>(submitButtonFinder).onPressed,
        isNotNull,
      );

      await tester.ensureVisible(submitButtonFinder);
      await tester.tap(submitButtonFinder);
      await tester.pump();

      expect(viewModel.lastQuestionAnswers, [
        ['Keep it concise'],
      ]);
    });

    testWidgets('reject calls rejectQuestion with the request id', (
      tester,
    ) async {
      viewModel.pendingApproval.value = PendingQuestionApproval(
        sessionId: 'session-1',
        requestId: 'que-1',
        questions: const [
          QuestionPrompt(
            question: 'Which database should I use?',
            header: 'Database choice',
            options: [
              QuestionOption(label: 'Postgres', description: 'Relational'),
            ],
          ),
        ],
      );

      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Reject'));
      await tester.tap(find.text('Reject'));
      await tester.pump();

      expect(viewModel.rejectQuestionCallCount, 1);
      expect(viewModel.lastRejectedRequestId, 'que-1');
    });
  });
}

/// The rotating layer inside the app bar's execution indicator.
Finder _spin() => find.descendant(
  of: find.byKey(const ValueKey('conversation-execution-spin')),
  matching: find.byType(RotationTransition),
);
