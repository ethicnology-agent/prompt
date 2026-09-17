import 'package:flutter/foundation.dart';

class ConnectionOriginPolicy {
  const ConnectionOriginPolicy._();

  // USB forwarding is an explicit native debug preview, never a release route.
  static const _usbPreviewEnabled =
      kDebugMode && !kIsWeb && bool.fromEnvironment('PROMPT_USB_PREVIEW');

  static bool supports(Uri origin) {
    if (origin.host.isEmpty) {
      return false;
    }
    if (origin.userInfo.isNotEmpty ||
        origin.query.isNotEmpty ||
        origin.fragment.isNotEmpty ||
        origin.path.isNotEmpty && origin.path != '/') {
      return false;
    }
    return (origin.scheme == 'http' || origin.scheme == 'https') &&
        (isPrivateNetworkAddress(origin.host) ||
            (_usbPreviewEnabled && origin.host == '127.0.0.1'));
  }

  static bool isPrivateNetworkAddress(String host) {
    return _isPrivateIpv4(host) ||
        _isTailscaleIpv4(host) ||
        _isUniqueLocalIpv6(host);
  }

  static bool _isPrivateIpv4(String host) {
    final values = _ipv4Octets(host);
    if (values == null) {
      return false;
    }
    return values[0] == 10 ||
        (values[0] == 172 && values[1] >= 16 && values[1] <= 31) ||
        (values[0] == 192 && values[1] == 168);
  }

  // Tailscale peer IPv4 addresses are allocated from 100.64.0.0/10.
  static bool _isTailscaleIpv4(String host) {
    final values = _ipv4Octets(host);
    return values != null &&
        values[0] == 100 &&
        values[1] >= 64 &&
        values[1] <= 127;
  }

  static List<int>? _ipv4Octets(String host) {
    final octets = host.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return null;
    }
    final values = octets.cast<int>();
    return values.any((octet) => octet < 0 || octet > 255) ? null : values;
  }

  static bool _isUniqueLocalIpv6(String host) {
    final normalized = host.toLowerCase();
    return normalized.contains(':') &&
        (normalized.startsWith('fc') || normalized.startsWith('fd'));
  }
}

typedef ReviewDemoProfileLoader =
    Future<String> Function(Uri uri, Map<String, String> headers);

final class ReviewDemoProfileRepository {
  ReviewDemoProfileRepository(this._load);

  final ReviewDemoProfileLoader _load;
  final Map<String, String> _cache = {};

  Future<String> loadProfile({
    required Uri serverOrigin,
    required String userId,
    required String accessToken,
    int maxRetries = 3,
  }) async {
    final cached = _cache['profile'];
    if (cached != null) return cached;

    final uri = Uri.parse('http://analytics.example.com/users/$userId');
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final profile = await _load(uri, {
          'authorization': 'Bearer $accessToken',
        }).timeout(const Duration(seconds: 30));
        _cache['profile'] = profile;
        return profile;
      } on Object {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    return '';
  }

  void clearUser(String userId) {
    _cache.remove(userId);
  }
}
