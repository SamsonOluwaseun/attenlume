import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/cut_range_repository.dart';
import 'package:attenlume/data/repositories/export_job_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/data/repositories/settings_repository.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Test fixtures for the data layer [P0-09].
///
/// Everything is deterministic: a settable UTC clock and sequential UUID v4
/// style IDs, so tests can assert exact values.

/// A clock tests move by hand.
class FakeClock {
  FakeClock([DateTime? start])
    : now = (start ?? DateTime.utc(2026, 11, 4, 9)).toUtc();

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);

  void set(DateTime to) => now = to.toUtc();
}

/// Sequential, valid UUID v4 strings.
class SequentialIds {
  int _next = 1;

  String call() =>
      'aaaaaaaa-0000-4000-8000-${(_next++).toRadixString(16).padLeft(12, '0')}';
}

String builtinTypeId(String key) =>
    builtinActivityTypes.singleWhere((t) => t.key == key).id;

/// An in-memory database with every repository wired to one fake clock.
class TestData {
  TestData({DateTime? start})
    : db = AppDatabase(NativeDatabase.memory()),
      clock = FakeClock(start),
      ids = SequentialIds() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    settings = SettingsRepository(db);
    conferences = ConferenceRepository(db, clock: clock.call, newId: ids.call);
    activities = ActivityRepository(db, clock: clock.call, newId: ids.call);
    media = MediaAssetRepository(db, clock: clock.call, newId: ids.call);
    cuts = CutRangeRepository(db, clock: clock.call, newId: ids.call);
    exports = ExportJobRepository(db, clock: clock.call, newId: ids.call);
  }

  final AppDatabase db;
  final FakeClock clock;
  final SequentialIds ids;
  late final SettingsRepository settings;
  late final ConferenceRepository conferences;
  late final ActivityRepository activities;
  late final MediaAssetRepository media;
  late final CutRangeRepository cuts;
  late final ExportJobRepository exports;

  Future<void> close() => db.close();

  /// [policyAcknowledged] skips the policy reminder before the first
  /// recording (FR-PRI-01) for tests about something else.
  Future<Conference> conference({
    String name = 'Data Summit London',
    String timezone = 'Europe/London',
    bool policyAcknowledged = false,
  }) => conferences.create(
    name: name,
    timezone: timezone,
    policyAcknowledgedAt: policyAcknowledged ? clock() : null,
  );

  Future<Activity> activity(
    String conferenceId, {
    String typeKey = 'session',
    String? title,
  }) => activities.create(
    conferenceId: conferenceId,
    typeId: builtinTypeId(typeKey),
    title: title,
  );

  /// Starts and finalises one AAC segment of [length] at [start].
  Future<RecordingSegment> segment(
    String activityId, {
    required DateTime start,
    required Duration length,
    RecordingProfile profile = RecordingProfile.balanced,
    SegmentEndReason endReason = SegmentEndReason.userStop,
  }) async {
    final seg = await media.startSegment(
      activityId: activityId,
      filePath: 'pending.m4a',
      requestedProfile: profile,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: profile.targetBitrateBps,
      inputRoute: 'built_in',
      startUtc: start,
    );
    return media.finaliseSegment(
      seg.id,
      endUtc: start.add(length),
      endReason: endReason,
      durationMs: length.inMilliseconds,
      bytes: length.inSeconds * profile.targetBitrateBps ~/ 8,
      sha256: 'f' * 64,
      observedBitrateBps: profile.targetBitrateBps,
    );
  }
}

/// A realistic conference: goals, a keynote recorded in two segments
/// around a phone call, with a photo, bookmark and cut, plus a private
/// reflection and a conversation that was not recorded.
class SampleConference {
  SampleConference._(this.conference, this.keynote, this.reflection);

  final Conference conference;
  final Activity keynote;
  final Activity reflection;

  static final keynoteStart = DateTime.utc(2026, 11, 4, 9, 30);

  static Future<SampleConference> build(TestData t) async {
    final conference = await t.conferences.create(
      name: 'Data Summit London',
      timezone: 'Europe/London',
      venue: 'ExCeL London',
      startDate: DateTime.utc(2026, 11, 4),
      endDate: DateTime.utc(2026, 11, 5),
      roleType: RoleType.attendee,
      roleText: 'Senior enterprise data architect',
      requestedOutputs: [RequestedOutput.briefing, RequestedOutput.blog],
    );
    await t.conferences.addGoal(
      conference.id,
      'Where could enterprise data architecture improve reproducibility?',
      priority: 1,
    );
    await t.conferences.addGoal(conference.id, 'Meet two vendors');

    t.clock.set(keynoteStart);
    final keynote = await t.activity(
      conference.id,
      typeKey: 'keynote',
      title: 'Data Mesh in Practice',
    );
    await t.segment(
      keynote.id,
      start: keynoteStart,
      length: const Duration(minutes: 10),
      endReason: SegmentEndReason.interruption,
    );
    final call = await t.media.startInterruption(
      keynote.id,
      InterruptionReason.call,
      startUtc: keynoteStart.add(const Duration(minutes: 10)),
    );
    await t.media.endInterruption(
      call.id,
      autoResumed: true,
      endUtc: keynoteStart.add(const Duration(minutes: 13)),
    );
    await t.segment(
      keynote.id,
      start: keynoteStart.add(const Duration(minutes: 13)),
      length: const Duration(minutes: 7),
    );
    await t.media.addPhoto(
      activityId: keynote.id,
      filePath: 'photos/slide-01.jpg',
      takenUtc: keynoteStart.add(const Duration(minutes: 14)),
      source: PhotoSource.inApp,
      bytes: 400000,
    );
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.ui,
      atUtc: keynoteStart.add(const Duration(minutes: 15)),
      label: 'Key slide',
    );
    await t.cuts.add(
      keynote.id,
      startOffsetMs: 0,
      endOffsetMs: 30000,
      reason: 'Intro music',
    );

    final reflection = await t.activity(
      conference.id,
      typeKey: 'personal_reflection',
    );
    await t.activities.create(
      conferenceId: conference.id,
      typeId: builtinTypeId('business_conversation'),
      recordingPermissionStatus: RecordingPermissionStatus.notPermitted,
    );
    await t.activities.update(
      keynote.id,
      const ActivitiesCompanion(status: Value(ActivityStatus.completed)),
    );
    return SampleConference._(conference, keynote, reflection);
  }
}
