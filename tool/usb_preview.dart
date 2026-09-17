import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/app/prompt_app.dart';

void main() {
  if (!kDebugMode ||
      kIsWeb ||
      !const bool.fromEnvironment('PROMPT_USB_PREVIEW')) {
    throw StateError(
      'USB preview requires an explicitly enabled native debug build.',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: 'USB PREVIEW',
        location: BannerLocation.topEnd,
        color: const Color(0xff985500),
        child: PromptApp(dependencies: AppDependencies.create()),
      ),
    ),
  );
}
