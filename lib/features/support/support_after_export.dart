import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/local_database/database_provider.dart';
import 'support_prompt_dialog.dart';
import 'support_prompt_policy.dart';

/// Optional side effect after export success. Payment is never inferred.
class SupportAfterExport {
  SupportAfterExport({
    required this.channel,
    required this.url,
    required this.readState,
    required this.writeState,
    required this.openLink,
  });
  final SupportDistributionChannel channel;
  final String url;
  final Future<String?> Function() readState;
  final Future<void> Function(String) writeState;
  final Future<bool> Function(Uri) openLink;
  bool _showing = false;

  bool get available =>
      channel.isExternalLinkAllowed && PayPalUrlValidator.isValidPayPalUrl(url);

  Future<void> run({
    required bool exportSucceeded,
    required Future<SupportPromptDecision?> Function(SupportPromptKind) show,
  }) async {
    if (!exportSucceeded || !available || _showing) return;
    _showing = true;
    try {
      final raw = await readState();
      final SupportPromptState state;
      if (raw == null) {
        state = const SupportPromptState();
      } else {
        final json = jsonDecode(raw);
        state = json is Map<String, dynamic>
            ? SupportPromptState.fromJson(json)
            : SupportPromptState.suppressed;
      }
      final kind = const SupportPromptPolicy().shouldPromptForChannel(
        state: state,
        exportSucceeded: true,
        channel: channel,
        supportUrl: url,
      );
      if (kind == null) return;
      // Reserve before showing: closing the app must not cause repeated nags.
      await writeState(jsonEncode(state.withDecision(kind, null).toJson()));
      final decision = await show(kind);
      await writeState(jsonEncode(state.withDecision(kind, decision).toJson()));
      if (decision?.isGiftNow == true) {
        var target = Uri.parse(url);
        final amount = decision!.selectedAmount;
        if (amount != null &&
            (target.host == 'paypal.me' || target.host == 'www.paypal.me')) {
          target = target.replace(
            pathSegments: [target.pathSegments.first, '${amount.pounds}GBP'],
          );
        }
        if (PayPalUrlValidator.isValidPayPalUrl(target.toString())) {
          await openLink(target);
        }
      }
    } on Object {
      // Missing configuration, preferences or browser must never undo or block
      // the export which already completed, or its copy/share actions.
    } finally {
      _showing = false;
    }
  }
}

const _supportUrl = String.fromEnvironment(
  'ATTENLUME_SUPPORT_URL',
  defaultValue: 'https://www.paypal.com/donate/?hosted_button_id=EMQCVQHTPDR2U',
);
const _distribution = String.fromEnvironment('ATTENLUME_SUPPORT_DISTRIBUTION');

final supportAfterExportProvider = Provider<SupportAfterExport>((ref) {
  final channel = _distribution == 'windows-direct' && Platform.isWindows
      ? SupportDistributionChannel.windowsDirect
      : _distribution == 'android-direct' && Platform.isAndroid
      ? SupportDistributionChannel.androidDirect
      : SupportDistributionChannel.other;
  return SupportAfterExport(
    channel: channel,
    url: _supportUrl,
    readState: () => ref
        .read(appDatabaseProvider)
        .readSetting('voluntary_support_prompt_v1'),
    writeState: (value) => ref
        .read(appDatabaseProvider)
        .writeSetting('voluntary_support_prompt_v1', value),
    openLink: _openPublicSupportLink,
  );
});

Future<void> offerSupportAfterExport(
  WidgetRef ref,
  BuildContext context,
) async {
  try {
    await ref
        .read(supportAfterExportProvider)
        .run(
          exportSucceeded: true,
          show: (kind) => context.mounted
              ? showSupportPrompt(context, kind)
              : Future.value(),
        );
  } on Object {
    // Provider construction/lifetime errors cannot affect the export result.
  }
}

Future<bool> _openPublicSupportLink(Uri uri) async {
  if (!PayPalUrlValidator.isValidPayPalUrl(uri.toString())) return false;
  if (Platform.isWindows) {
    final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final result = await Process.run(
      p.join(system, 'System32', 'rundll32.exe'),
      ['url.dll,FileProtocolHandler', uri.toString()],
      runInShell: false,
    ).timeout(const Duration(seconds: 10));
    return result.exitCode == 0;
  }
  if (Platform.isAndroid) {
    return await const MethodChannel('com.samlytics.attenlume/support_link')
            .invokeMethod<bool>('open', uri.toString()) ??
        false;
  }
  return false;
}
