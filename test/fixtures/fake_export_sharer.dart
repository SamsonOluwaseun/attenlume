import 'dart:ui' show Rect;

import 'package:attenlume/platform/share/export_sharer.dart';

/// An [ExportSharer] that records what it was asked to share (ADR-042).
class FakeExportSharer implements ExportSharer {
  FakeExportSharer({
    this.canShare = true,
    this.outcome = ExportShareOutcome.shared,
  });

  @override
  final bool canShare;

  ExportShareOutcome outcome;

  /// When set, [shareFile] throws it, as if the share sheet failed to open.
  Object? error;

  final shared = <({String path, String? subject, Rect? origin})>[];

  @override
  Future<ExportShareOutcome> shareFile(
    String filePath, {
    String? subject,
    Rect? origin,
  }) async {
    shared.add((path: filePath, subject: subject, origin: origin));
    if (error case final e?) throw e;
    return outcome;
  }
}
