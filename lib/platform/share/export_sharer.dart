import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// What the system share sheet reported (ADR-042).
enum ExportShareOutcome {
  /// The person picked a target. It does not prove the target finished.
  shared,

  /// The person closed the share sheet.
  dismissed,

  /// The platform cannot say what happened.
  unknown,
}

/// Hands a finished export to the system share sheet, so a phone user can
/// send it to Files, Google Drive or an AI app (FR-EXP-02, ADR-042).
///
/// The file stays where it is: sharing copies it, nothing is deleted.
abstract interface class ExportSharer {
  /// Whether this platform has a share sheet the export sheet should offer:
  /// Android and iOS. Windows keeps the chosen folder and "Copy location".
  bool get canShare;

  /// Opens the share sheet for [filePath]. [origin] anchors the popover on
  /// iPad. Throws if the share sheet could not be opened.
  Future<ExportShareOutcome> shareFile(
    String filePath, {
    String? subject,
    Rect? origin,
  });
}

/// [ExportSharer] over `share_plus` (ADR-042). On Android the plugin
/// copies the file into its own cache and serves it through its own
/// FileProvider, so the manifest needs nothing.
class SharePlusExportSharer implements ExportSharer {
  const SharePlusExportSharer();

  @override
  bool get canShare => Platform.isAndroid || Platform.isIOS;

  @override
  Future<ExportShareOutcome> shareFile(
    String filePath, {
    String? subject,
    Rect? origin,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeTypeFor(filePath))],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => ExportShareOutcome.shared,
      ShareResultStatus.dismissed => ExportShareOutcome.dismissed,
      ShareResultStatus.unavailable => ExportShareOutcome.unknown,
    };
  }

  /// The MIME type share targets see, so a ZIP is offered to apps that
  /// accept archives.
  static String mimeTypeFor(String filePath) =>
      switch (p.extension(filePath).toLowerCase()) {
        '.zip' => 'application/zip',
        _ => 'application/octet-stream',
      };
}
