import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/async/result.dart';
import '../core/platform/local_notification_service.dart';
import '../core/security/credentials_store.dart';
import '../core/security/secure_credentials_service.dart';
import '../data/local/prompt_local_storage.dart';
import '../data/remote/opencode_event_service.dart';
import '../data/remote/opencode_transport.dart';
import '../features/capabilities/capabilities.dart';
import '../features/chat/chat.dart';
import '../features/chat/data/opencode_chat_service.dart';
import '../features/connection/connection.dart';
import '../features/connection/data/opencode_health_service.dart';
import '../features/diagnostics/diagnostics.dart';
import '../features/diagnostics/data/opencode_diagnostics_service.dart';
import '../features/capabilities/data/opencode_capabilities_service.dart';
import '../features/queue/queue.dart';
import '../features/sessions/sessions.dart';
import '../features/settings/data/theme_preference_store.dart';
import '../features/settings/presentation/theme_view_model.dart';
import '../features/terminal/terminal.dart';
import '../features/terminal/data/opencode_terminal_service.dart';
import '../features/voice/voice.dart';
import '../features/workspace/workspace.dart';
import '../features/workspace/data/opencode_workspace_service.dart';
import '../features/review/review.dart';

/// Owns application-wide objects and their release order.
///
/// The optional factories are composition seams: tests can provide fake
/// transport, credentials, storage, and platform-facing services without a
/// service locator.
class AppDependencies {
  AppDependencies._({
    required this.connectionViewModel,
    required this.sessionsViewModel,
    required this.sessionCreationViewModel,
    required this.conversationViewModel,
    required this.capabilitiesViewModel,
    required this.workspaceViewModel,
    required this.terminalViewModel,
    required this.diagnosticsViewModel,
    required this.voiceViewModel,
    required this.themeViewModel,
    required this.localNotificationService,
    required this.credentialsStore,
    required this.transport,
    required this.httpClient,
    required this.openStorage,
    required this.chatRepository,
  });

  factory AppDependencies.create({
    ThemePreferenceStore? themePreferenceStore,
    CredentialsStore? credentialsStore,
    OpenCodeTransport? transport,
    http.Client? httpClient,
    Future<PromptLocalStorageHandle> Function()? openStorage,
    AttachmentPicker? attachmentPicker,
    VoiceEngine? voiceEngine,
    VoiceModelPicker? voiceModelPicker,
    VoiceModelInstaller? voiceModelInstaller,
    LocalNotificationService? localNotificationService,
  }) {
    final client = httpClient ?? http.Client();
    final resolvedTransport = transport ?? OpenCodeTransport(client);
    final credentials =
        credentialsStore ??
        SecureCredentialsService(const FlutterSecureStorage());
    final storage = openStorage ?? _openDefaultStorage;
    final notifications =
        localNotificationService ?? LocalNotificationService.platform();
    final chatRepository = ChatRepository(
      OpenCodeChatService(resolvedTransport),
      credentials,
    );
    late AppDependencies dependencies;
    final sessionsRepository = SessionsRepository(
      OpenCodeSessionsService(resolvedTransport),
      credentials,
      onSessionsDeleted: (profile, ids) async =>
          (await dependencies.ensureStorage()).reviewHistory.deleteForSessions(
            profile.id,
            ids,
          ),
    );

    final connectionRepository = ConnectionRepository(
      OpenCodeHealthService(resolvedTransport),
      credentials,
      LazyServerProfileStore(
        () async => (await dependencies.ensureStorage()).serverProfiles,
      ),
    );
    final capabilitiesRepository = CapabilitiesRepository(
      OpenCodeCapabilitiesService(resolvedTransport),
      credentials,
    );
    dependencies = AppDependencies._(
      connectionViewModel: ConnectionViewModel(connectionRepository),
      sessionCreationViewModel: SessionCreationViewModel(
        connections: connectionRepository,
        sessions: sessionsRepository,
        capabilities: capabilitiesRepository,
        attachmentPicker: attachmentPicker ?? createAttachmentPicker(),
        queueLaunch: (launch) => dependencies.queueLaunchDraft(launch),
        worktrees: WorktreeRepository(
          WorktreeService(resolvedTransport),
          credentials,
        ),
      ),
      sessionsViewModel: SessionsViewModel(
        sessionsRepository,
        catalogLoader: LoadSessionCatalog(
          connectionRepository,
          sessionsRepository,
        ),
      ),
      conversationViewModel: ConversationViewModel(
        chatRepository: chatRepository,
        sessionsRepository: sessionsRepository,
        queueRepositoryProvider: () async => QueuePromptsRepository(
          (await dependencies.ensureStorage()).queuedPrompts,
        ),
        queueCoordinatorProvider: () => dependencies.ensureQueueCoordinator(),
        attachmentPicker: attachmentPicker ?? createAttachmentPicker(),
      ),
      capabilitiesViewModel: CapabilitiesViewModel(capabilitiesRepository),
      workspaceViewModel: WorkspaceViewModel(
        OpenCodeWorkspaceRepository(
          OpenCodeWorkspaceService(resolvedTransport),
          credentials,
        ),
      ),
      terminalViewModel: TerminalViewModel(
        OpenCodeTerminalRepository(
          OpenCodeTerminalService(resolvedTransport),
          credentials,
        ),
      ),
      diagnosticsViewModel: DiagnosticsViewModel(
        DiagnosticsRepository(
          OpenCodeDiagnosticsService(resolvedTransport),
          credentials,
        ),
      ),
      voiceViewModel: VoiceViewModel(
        VoiceRepository(
          voiceEngine ?? createVoiceEngine(),
          voiceModelPicker ?? const FilePickerVoiceModelPicker(),
          voiceModelInstaller ?? createVoiceModelInstaller(),
        ),
      ),
      themeViewModel: ThemeViewModel(
        themePreferenceStore ?? SharedPreferencesThemePreferenceStore(),
      ),
      localNotificationService: notifications,
      credentialsStore: credentials,
      transport: resolvedTransport,
      httpClient: client,
      openStorage: storage,
      chatRepository: chatRepository,
    );
    return dependencies;
  }

  final ConnectionViewModel connectionViewModel;
  final SessionsViewModel sessionsViewModel;
  final SessionCreationViewModel sessionCreationViewModel;
  final ConversationViewModel conversationViewModel;
  final CapabilitiesViewModel capabilitiesViewModel;
  final WorkspaceViewModel workspaceViewModel;
  final TerminalViewModel terminalViewModel;
  final DiagnosticsViewModel diagnosticsViewModel;
  final VoiceViewModel voiceViewModel;
  final ThemeViewModel themeViewModel;
  final LocalNotificationService localNotificationService;
  final CredentialsStore credentialsStore;
  final OpenCodeTransport transport;
  final http.Client httpClient;
  final Future<PromptLocalStorageHandle> Function() openStorage;
  final ChatRepository chatRepository;

  /// Creates isolated state for one review route.
  ReviewViewModel createReviewViewModel() => ReviewViewModel(
    InMemoryReviewRepository(
      OpenCodeReviewService(transport, credentialsStore: credentialsStore),
    ),
    historyStoreProvider: () async => (await ensureStorage()).reviewHistory,
  );

  PromptLocalStorageHandle? _storage;
  Future<PromptLocalStorageHandle>? _storageFuture;
  QueueSendCoordinator? _queueCoordinator;
  Future<QueueSendCoordinator>? _queueCoordinatorFuture;
  bool _disposed = false;
  final Map<(String, String), Future<bool>> _queuedLaunches = {};
  final Set<(String, String)> _retryableLaunches = {};

  /// Explicit send from creation is stored once before activating the target.
  /// A rejected enqueue leaves the draft in presentation memory for recovery.
  Future<bool> queueLaunchDraft(SessionLaunch launch) async {
    if (!launch.submitDraft ||
        (launch.draft.trim().isEmpty && launch.attachments.isEmpty)) {
      return false;
    }
    final identity = (launch.profile.id, launch.session.id);
    final pending = _queuedLaunches[identity];
    if (pending != null) return pending;
    final operation = _enqueueLaunch(launch);
    _queuedLaunches[identity] = operation;
    final accepted = await operation;
    if (!accepted && _retryableLaunches.remove(identity)) {
      _queuedLaunches.remove(identity);
    }
    return accepted;
  }

  Future<bool> _enqueueLaunch(SessionLaunch launch) async {
    final identity = (launch.profile.id, launch.session.id);
    final id = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'creation-prompt-v1',
              launch.profile.id,
              launch.session.id,
            ]),
          ),
        )
        .toString();
    QueuePromptsRepository? repository;
    final copies = <QueuedAttachment>[];
    var attempted = false;
    try {
      if (launch.attachments.any((item) => item.isReleased)) return false;
      if (launch.attachments.isNotEmpty &&
          launch.profile.capabilities.supports(
            BackendFeature.imageAttachments,
          )) {
        final constraints = launch.profile.capabilities.attachmentConstraints;
        if (constraints == null ||
            attachmentConstraintError(launch.attachments, constraints) !=
                null) {
          return false;
        }
      }
      for (final item in launch.attachments) {
        copies.add(
          QueuedAttachment(
            name: item.name,
            mediaType: item.mediaType,
            bytes: Uint8List.fromList(item.bytes),
          ),
        );
      }
      repository = QueuePromptsRepository(
        (await ensureStorage()).queuedPrompts,
        idGenerator: () => id,
      );
      attempted = true;
      final result = await repository.enqueue(
        profile: launch.profile,
        session: launch.session,
        promptText: launch.draft,
        executionOptions: launch.options,
        attachments: copies,
      );
      if (result case Err()) {
        final stored = await repository
            .watchQueue(profile: launch.profile, session: launch.session)
            .first
            .timeout(const Duration(seconds: 5));
        if (!stored.any((item) => item.id == id)) {
          _retryableLaunches.add(identity);
          return false;
        }
      }
      for (final item in launch.attachments) {
        item.release();
      }
      return true;
    } on Exception {
      if (!attempted) _retryableLaunches.add(identity);
      return false;
    } finally {
      for (final item in copies) {
        item.bytes.fillRange(0, item.bytes.length, 0);
      }
    }
  }

  Future<PromptLocalStorageHandle> ensureStorage() async {
    if (_disposed) {
      throw StateError('AppDependencies was already disposed.');
    }
    final storage = _storage;
    if (storage != null) {
      return storage;
    }
    final pending = _storageFuture;
    if (pending != null) {
      return pending;
    }
    late Future<PromptLocalStorageHandle> current;
    current = () async {
      try {
        final opened = await openStorage();
        if (_disposed) {
          await opened.close();
          throw StateError(
            'AppDependencies was disposed while opening storage.',
          );
        }
        _storage = opened;
        return opened;
      } finally {
        if (identical(_storageFuture, current)) {
          _storageFuture = null;
        }
      }
    }();
    _storageFuture = current;
    return current;
  }

  Future<QueueSendCoordinator> ensureQueueCoordinator() async {
    if (_disposed) {
      throw StateError('AppDependencies was already disposed.');
    }
    final coordinator = _queueCoordinator;
    if (coordinator != null) {
      return coordinator;
    }
    final pending = _queueCoordinatorFuture;
    if (pending != null) {
      return pending;
    }
    late Future<QueueSendCoordinator> current;
    current = () async {
      try {
        final created = await _createCoordinator(
          storage: ensureStorage,
          chatRepository: chatRepository,
          transport: transport,
          credentials: credentialsStore,
          localNotificationService: localNotificationService,
        );
        if (_disposed) {
          await created.dispose();
          throw StateError(
            'AppDependencies was disposed while creating the queue coordinator.',
          );
        }
        _queueCoordinator = created;
        sessionsViewModel.bindLiveStatuses(created.liveStatuses);
        return created;
      } finally {
        if (identical(_queueCoordinatorFuture, current)) {
          _queueCoordinatorFuture = null;
        }
      }
    }();
    _queueCoordinatorFuture = current;
    return current;
  }

  QueueSendCoordinator? get queueCoordinator => _queueCoordinator;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // Consumers first, then lazy resources, and the transport last.
    connectionViewModel.dispose();
    sessionCreationViewModel.dispose();
    sessionsViewModel.dispose();
    await conversationViewModel.dispose();
    capabilitiesViewModel.dispose();
    workspaceViewModel.dispose();
    terminalViewModel.dispose();
    diagnosticsViewModel.dispose();
    await voiceViewModel.dispose();
    themeViewModel.dispose();
    final pendingCoordinator = _queueCoordinatorFuture;
    if (pendingCoordinator != null) {
      try {
        await pendingCoordinator;
      } on Object {
        // Preserve the original initialization failure during disposal.
      }
    }
    await _queueCoordinator?.dispose();
    final pendingStorage = _storageFuture;
    if (pendingStorage != null) {
      try {
        await pendingStorage;
      } on Object {
        // Preserve the original initialization failure during disposal.
      }
    }
    final storage = _storage;
    if (storage != null) {
      await storage.close();
    }
    httpClient.close();
  }

  static Future<PromptLocalStorageHandle> _openDefaultStorage() async {
    final result = await openPromptLocalStorage();
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw LocalStorageUnavailableException(failure),
    };
  }

  static Future<QueueSendCoordinator> _createCoordinator({
    required Future<PromptLocalStorageHandle> Function() storage,
    required ChatRepository? chatRepository,
    required OpenCodeTransport transport,
    required CredentialsStore credentials,
    required LocalNotificationService localNotificationService,
  }) async {
    final repository =
        chatRepository ??
        ChatRepository(OpenCodeChatService(transport), credentials);
    return QueueSendCoordinator(
      queueRepository: QueuePromptsRepository((await storage()).queuedPrompts),
      chatRepository: repository,
      eventService: OpenCodeEventService(transport),
      credentialsStore: credentials,
      onGenerationFinished: ({required bool failed}) {
        unawaited(
          failed
              ? localNotificationService.showSessionFailed()
              : localNotificationService.showSessionCompleted(),
        );
      },
    );
  }
}
