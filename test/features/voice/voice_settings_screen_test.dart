import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_model_installer.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/domain/voice_language.dart';
import 'package:prompt/features/voice/domain/voice_model.dart';
import 'package:prompt/features/voice/presentation/voice_settings_screen.dart';
import 'package:prompt/features/voice/presentation/voice_view_model.dart';

void main() {
  testWidgets('installation failure remains readable with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = VoiceViewModel(
      VoiceRepository(
        _UnavailableVoiceEngine(),
        _UnavailableModelPicker(),
        _FakeModelInstaller(error: const VoiceModelChecksumException()),
      ),
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: VoiceSettingsScreen(viewModel: viewModel),
      ),
    );
    await tester.scrollUntilVisible(find.text('Install French model'), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Install French model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install French model'));
    await tester.pumpAndSettle();
    expect(
      find.text('The downloaded voice model failed its checksum.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'installs and selects a model without requesting microphone permission',
    (tester) async {
      final engine = _UnavailableVoiceEngine();
      final picker = _UnavailableModelPicker();
      final installer = _FakeModelInstaller();
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, picker, installer),
      );
      await tester.pumpWidget(
        MaterialApp(home: VoiceSettingsScreen(viewModel: viewModel)),
      );

      expect(engine.permissionRequests, 0);
      expect(find.text('Language: French'), findsOneWidget);
      expect(find.text('English INT8'), findsOneWidget);
      expect(find.text('Install French model'), findsOneWidget);
      await tester.tap(find.text('Install French model'));
      await tester.pumpAndSettle();
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('Remove French model'), findsOneWidget);
      expect(installer.installCalls, [VoiceLanguage.french]);
      expect(picker.calls, isEmpty);
      expect(viewModel.hasSelectedModel.value, isTrue);
      expect(viewModel.language.value, VoiceLanguage.french);
      await tester.tap(find.text('Language: French'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close Language choices'));
      await tester.pumpAndSettle();
      expect(viewModel.language.value, VoiceLanguage.french);
      await tester.tap(find.text('Language: French'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(viewModel.language.value, VoiceLanguage.english);
      expect(engine.permissionRequests, 0);
      expect(viewModel.hasSelectedModel.value, isFalse);
      await viewModel.dispose();
    },
  );

  testWidgets('shows the typed installation failure without an exception', (
    tester,
  ) async {
    final viewModel = VoiceViewModel(
      VoiceRepository(
        _UnavailableVoiceEngine(),
        _UnavailableModelPicker(),
        _FakeModelInstaller(error: const VoiceModelChecksumException()),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: VoiceSettingsScreen(viewModel: viewModel)),
    );

    await tester.tap(find.text('Install French model'));
    await tester.pumpAndSettle();

    expect(
      find.text('The downloaded voice model failed its checksum.'),
      findsOneWidget,
    );
    await viewModel.dispose();
  });
}

class _UnavailableVoiceEngine implements VoiceEngine {
  var permissionRequests = 0;

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    permissionRequests++;
    return const Err(VoiceEngineFailure.assetsNotBundled);
  }

  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async => const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async => const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async =>
      const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<void> releaseModel() async {}
}

class _UnavailableModelPicker implements VoiceModelPicker {
  final List<VoiceLanguage> calls = [];

  @override
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language) async {
    calls.add(language);
    return _model(language);
  }
}

class _FakeModelInstaller implements VoiceModelInstaller {
  _FakeModelInstaller({this.error});

  final VoiceModelInstallException? error;
  final Map<VoiceLanguage, VoiceModel> installed = {};
  final List<VoiceLanguage> installCalls = [];

  @override
  Future<VoiceModel?> installedModel(VoiceLanguage language) async =>
      installed[language];

  @override
  Future<VoiceModel> install(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  }) async {
    installCalls.add(language);
    final installError = error;
    if (installError != null) throw installError;
    onProgress(0.5);
    onProgress(1);
    return installed[language] = _model(language);
  }

  @override
  Future<void> remove(VoiceLanguage language) async {
    installed.remove(language);
  }
}

VoiceModel _model(VoiceLanguage language) => VoiceModel(
  language: language,
  encoderPath: '/encoder.int8.onnx',
  decoderPath: '/decoder.onnx',
  joinerPath: '/joiner.int8.onnx',
  tokensPath: '/tokens.txt',
  modelType: language == VoiceLanguage.french ? 'zipformer' : 'zipformer2',
);
