// Explicit offline target only: flutter run -t tool/ui_preview.dart.
// Never imported by lib/main.dart or shipped as the production entrypoint.
import 'package:flutter/material.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/app/prompt_app.dart';
import 'package:prompt/core/platform/local_notification_service.dart';
import 'package:prompt/data/local/prompt_local_storage_handle.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/settings/settings.dart';

import 'ui_preview/offline_client.dart';
import 'ui_preview/offline_platform.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(OfflinePreview());
}

/// The real application and repositories, with in-memory external boundaries.
class OfflinePreview extends StatelessWidget {
  OfflinePreview({OfflinePreviewClient? client, super.key})
    : client = client ?? OfflinePreviewClient();

  final OfflinePreviewClient client;
  late final AppDependencies dependencies = AppDependencies.create(
    httpClient: client,
    credentialsStore: OfflineCredentials(),
    themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.light),
    attachmentPicker: OfflineAttachmentPicker(),
    voiceEngine: OfflineVoiceEngine(),
    voiceModelPicker: OfflineVoiceModelPicker(),
    voiceModelInstaller: OfflineVoiceModelInstaller(),
    localNotificationService: LocalNotificationService(OfflineNotifications()),
    openStorage: () async => PromptLocalStorageHandle(
      serverProfiles: InMemoryServerProfileStore(),
      queuedPrompts: InMemoryQueuePromptsDao(),
      reviewHistory: InMemoryReviewHistoryStore(),
      closeHandle: () async {},
    ),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Banner(
      message: 'OFFLINE FIXTURE',
      location: BannerLocation.topEnd,
      color: const Color(0xff985500),
      child: PromptApp(
        dependencies: dependencies,
        lastProfileLoader: () async =>
            ServerProfile(origin: Uri.parse(OfflinePreviewClient.origin)),
      ),
    ),
  );
}
