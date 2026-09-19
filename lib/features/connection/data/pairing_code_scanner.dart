import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class PairingScanResult {
  const PairingScanResult();
}

final class PairingScanCompleted extends PairingScanResult {
  const PairingScanCompleted(this.value);

  final String value;
}

final class PairingScanCancelled extends PairingScanResult {
  const PairingScanCancelled();
}

final class PairingScanUnavailable extends PairingScanResult {
  const PairingScanUnavailable();
}

final class PairingScanPermissionDenied extends PairingScanResult {
  const PairingScanPermissionDenied();
}

abstract interface class PairingCodeScanner {
  Future<PairingScanResult> scan();
}

PairingCodeScanner createPairingCodeScanner() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? const AndroidPairingCodeScanner()
    : const UnavailablePairingCodeScanner();

class AndroidPairingCodeScanner implements PairingCodeScanner {
  const AndroidPairingCodeScanner();

  static const _channel = MethodChannel('me.ethicnology.prompt/pairing');

  @override
  Future<PairingScanResult> scan() async {
    try {
      final value = await _channel.invokeMethod<String>('scan');
      if (value == null) return const PairingScanCancelled();
      if (value.isEmpty || value.length > 2048) {
        return const PairingScanUnavailable();
      }
      return PairingScanCompleted(value);
    } on PlatformException catch (error) {
      if (error.code == 'camera_permission_denied') {
        return const PairingScanPermissionDenied();
      }
      return const PairingScanUnavailable();
    } on MissingPluginException {
      return const PairingScanUnavailable();
    }
  }
}

class UnavailablePairingCodeScanner implements PairingCodeScanner {
  const UnavailablePairingCodeScanner();

  @override
  Future<PairingScanResult> scan() async => const PairingScanUnavailable();
}
