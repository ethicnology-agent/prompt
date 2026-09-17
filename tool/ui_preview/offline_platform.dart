import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/platform/local_notification_types.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/voice/voice.dart';

/// No secrets are accepted, read, or persisted in the fixture.
class OfflineCredentials implements CredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

class OfflineAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

class OfflineNotifications implements LocalNotificationPlatform {
  @override
  Future<LocalNotificationPermission> requestPermission() async =>
      LocalNotificationPermission.unavailable;
  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {}
}

class OfflineVoiceModelPicker implements VoiceModelPicker {
  @override
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language) async =>
      null;
}

class OfflineVoiceModelInstaller implements VoiceModelInstaller {
  @override
  Future<VoiceModel?> installedModel(VoiceLanguage language) async => null;
  @override
  Future<VoiceModel> install(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  }) async => throw const VoiceModelUnavailableException();
  @override
  Future<void> remove(VoiceLanguage language) async {}
}

class OfflineVoiceEngine implements VoiceEngine {
  @override
  Future<Result<void, VoiceEngineFailure>>
  requestMicrophonePermission() async =>
      const Err(VoiceEngineFailure.permissionUnavailable);
  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async => const Err(VoiceEngineFailure.modelUnavailable);
  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async => const Err(VoiceEngineFailure.modelUnavailable);
  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async =>
      const Err(VoiceEngineFailure.modelUnavailable);
  @override
  Future<void> releaseModel() async {}
}
