import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

void registerThirdPartyLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Prompt third-party notices',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
  });
}
