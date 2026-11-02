import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// The published Attenlume privacy policy (FR-PRI-07, P1-57). Its source is
/// `docs/legal/attenlume-privacy.html`; Google Play and the App Store use the
/// same address.
const privacyPolicyUrl =
    'https://www.samlytics.co.uk/attenlume-policy/attenlume-privacy.html';

/// Opens the privacy policy in the system browser. Returns false when this
/// platform cannot open it; the screen then offers Copy link instead.
typedef PrivacyPolicyOpener = Future<bool> Function();

final privacyPolicyOpenerProvider = Provider<PrivacyPolicyOpener>(
  (ref) => openPrivacyPolicy,
);

/// Whether this platform has an opener. iOS has none until the Mac adds a
/// native handler, so only Copy link is shown there.
bool get canOpenPrivacyPolicy => Platform.isAndroid || Platform.isWindows;

/// Opens exactly [privacyPolicyUrl], never any other address. Separate from
/// the PayPal support link so Play builds, which disable support, can still
/// open the policy.
Future<bool> openPrivacyPolicy() async {
  try {
    if (Platform.isWindows) {
      final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final result = await Process.run(
        p.join(system, 'System32', 'rundll32.exe'),
        ['url.dll,FileProtocolHandler', privacyPolicyUrl],
        runInShell: false,
      ).timeout(const Duration(seconds: 10));
      return result.exitCode == 0;
    }
    if (Platform.isAndroid) {
      return await const MethodChannel('com.samlytics.attenlume/policy_link')
              .invokeMethod<bool>('open', privacyPolicyUrl) ??
          false;
    }
  } on Object {
    return false;
  }
  return false;
}
