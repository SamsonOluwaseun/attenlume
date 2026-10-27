import '../models/enums.dart';

/// Recording states per activity (BUILD_GUIDE 5.4, ARCHITECTURE 3) [P1-04].
enum RecordingState {
  idle,
  starting,
  recording,
  paused,
  switchingSegment,
  interrupted,
  recovering,
  userResumeRequired,
  stopping,
  saved,
  storageStop,
  errorRecoverable;

  /// True while the state holds an activity, so no other recording may
  /// start (NFR-04). Only idle and saved leave the recorder free.
  bool get holdsActivity => this != idle && this != saved;

  /// True while an audio file is open for writing.
  bool get isCapturing => this == recording;
}

/// Allowed transitions, from the build guide 5.4 diagram (FR-REC-09)
/// [P1-04]. Any state may also go to [RecordingState.errorRecoverable].
///
/// Additions to the diagram, recorded in ADR-012:
/// - `saved` and `errorRecoverable` may go to `starting`, for the next
///   recording or a retry.
/// - `recovering` may go to `userResumeRequired` when the OS refuses resume.
/// - `userResumeRequired` and `errorRecoverable` may go to `stopping`, so
///   the user can always save what was written.
/// - `switchingSegment` may go to `userResumeRequired` when the input is
///   lost and no other microphone can start (ADR-016, FR-REC-07).
const Map<RecordingState, Set<RecordingState>> recordingTransitions = {
  RecordingState.idle: {RecordingState.starting},
  RecordingState.starting: {RecordingState.recording},
  RecordingState.recording: {
    RecordingState.paused,
    RecordingState.switchingSegment,
    RecordingState.interrupted,
    RecordingState.stopping,
    RecordingState.storageStop,
  },
  RecordingState.paused: {RecordingState.recording, RecordingState.stopping},
  RecordingState.switchingSegment: {
    RecordingState.recording,
    RecordingState.userResumeRequired,
  },
  RecordingState.interrupted: {
    RecordingState.recovering,
    RecordingState.userResumeRequired,
    RecordingState.stopping,
  },
  RecordingState.recovering: {
    RecordingState.recording,
    RecordingState.userResumeRequired,
  },
  RecordingState.userResumeRequired: {
    RecordingState.recording,
    RecordingState.stopping,
  },
  RecordingState.stopping: {RecordingState.saved},
  RecordingState.storageStop: {RecordingState.saved},
  RecordingState.saved: {RecordingState.starting},
  RecordingState.errorRecoverable: {
    RecordingState.starting,
    RecordingState.stopping,
  },
};

bool canTransition(RecordingState from, RecordingState to) =>
    to == RecordingState.errorRecoverable ||
    (recordingTransitions[from]?.contains(to) ?? false);

/// What the recorder is doing now. Immutable, emitted on every change.
class RecordingStatus {
  const RecordingStatus({
    required this.state,
    this.activityId,
    this.profile,
    this.segmentId,
    this.segmentSequence,
    this.segmentStartUtc,
    this.inputRoute,
    this.errorMessage,
  });

  static const idle = RecordingStatus(state: RecordingState.idle);

  final RecordingState state;

  /// The activity this recording belongs to, kept after saving so the UI
  /// can show what was saved.
  final String? activityId;

  /// The profile requested for the open segment (FR-QUAL-02).
  final RecordingProfile? profile;

  /// The segment being written, only while [RecordingState.recording].
  final String? segmentId;
  final int? segmentSequence;
  final DateTime? segmentStartUtc;

  /// The input the open segment records from (FR-REC-07), as stored in
  /// `input_route`. Null when the platform does not say.
  final String? inputRoute;

  /// Plain description of the last failure, in
  /// [RecordingState.errorRecoverable].
  final String? errorMessage;

  @override
  String toString() =>
      'RecordingStatus(${state.name}, activity: $activityId, '
      'segment: $segmentSequence)';
}
