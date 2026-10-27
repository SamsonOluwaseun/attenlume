/// The offset rule (BUILD_GUIDE 9.4) [P0-09].
///
/// `offset_ms` is measured from the `start_utc` of the activity's first
/// segment, counting gaps as real time, so photos and bookmarks line up with
/// wall-clock time across pauses and interruptions.
///
/// Returns null when the activity has no segment yet. The result is negative
/// for an event before the first segment started (for example a photo taken
/// just before pressing Record), which keeps its place on the timeline.
int? timelineOffsetMs({
  required DateTime eventUtc,
  required DateTime? firstSegmentStartUtc,
}) {
  if (firstSegmentStartUtc == null) return null;
  return eventUtc
      .toUtc()
      .difference(firstSegmentStartUtc.toUtc())
      .inMilliseconds;
}
