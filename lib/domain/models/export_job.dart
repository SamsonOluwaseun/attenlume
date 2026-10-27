import 'enums.dart';

/// One local or cloud export run (BUILD_GUIDE 9.4 `export_jobs`) [P0-09].
class ExportJob {
  const ExportJob({
    required this.id,
    required this.conferenceId,
    required this.scope,
    required this.destination,
    required this.format,
    required this.audioMode,
    required this.state,
    this.bytesTotal,
    required this.bytesDone,
    this.startedAt,
    this.completedAt,
    required this.verificationLevel,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String conferenceId;

  /// Export scope (FR-EXP-01) as a JSON object. Its shape is set in P1-21.
  final Map<String, Object?> scope;
  final ExportDestination destination;
  final ExportFormat format;
  final ExportAudioMode audioMode;
  final ExportJobState state;
  final int? bytesTotal;
  final int bytesDone;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final VerificationLevel verificationLevel;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}
