import 'dart:convert';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/spikes/profile_switch_spike.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService service;
  late Activity keynote;

  ProfileSwitchSpike spike({
    CapturePlatform platform = CapturePlatform.android,
    Duration switchCost = Duration.zero,
  }) {
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: platform,
      clock: t.clock.call,
      hashFile: (_) async {
        // Finalising takes time on a device. The gap shows in the report.
        t.clock.advance(switchCost);
        return 'hash';
      },
    );
    return ProfileSwitchSpike(
      service: service,
      activities: t.activities,
      media: t.media,
      mediaRoot: root,
      platform: platform,
      clock: t.clock.call,
      wait: (d) async => t.clock.advance(d),
    );
  }

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_p0_12_');
    engine = FakeCaptureEngine()..deliveredBitrateBps = ((r) => r.bitrateBps);
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  test('P0-12 one segment per profile, switched by stop then start '
      '(FR-QUAL-04)', () async {
    final report = await spike().run(activityId: keynote.id);

    expect(report.startOutcome, StartOutcome.started);
    expect(report.switches.map((s) => s.result.outcome), [
      ProfileChangeOutcome.changed,
      ProfileChangeOutcome.changed,
      ProfileChangeOutcome.changed,
    ]);
    expect(report.segments.map((s) => s.segment.requestedProfile), [
      RecordingProfile.economy,
      RecordingProfile.balanced,
      RecordingProfile.enhanced,
      RecordingProfile.economy,
    ]);
    expect(report.segments.map((s) => s.segment.endReason), [
      SegmentEndReason.qualityChange,
      SegmentEndReason.qualityChange,
      SegmentEndReason.qualityChange,
      SegmentEndReason.userStop,
    ]);
    expect(engine.requests.map((r) => r.bitrateBps), [
      32000,
      48000,
      64000,
      32000,
    ]);
  });

  test('P0-12 reports requested against observed bitrate from the file '
      '(FR-QUAL-01, FR-QUAL-06)', () async {
    // An encoder that rounds every request up to 64 kbps.
    engine.deliveredBitrateBps = (_) => 64000;

    final report = await spike().run(
      activityId: keynote.id,
      profiles: const [RecordingProfile.economy, RecordingProfile.enhanced],
    );

    final economy = report.segments.first;
    expect(economy.segment.requestedBitrateBps, 32000);
    expect(economy.info!.declaredAvgBitrateBps, 64000);
    expect(economy.info!.payloadBitrateBps, 64000);
    expect(economy.payloadDeviationPercent, closeTo(100, 0.01));
    expect(
      economy.segment.observedBitrateBps,
      economy.info!.observedBitrateBps,
    );
    expect(economy.observedMegabytesPerHour, greaterThan(28.8));
    expect(economy.requestedMegabytesPerHour, closeTo(14.4, 0.01));
    expect(report.segments.last.payloadDeviationPercent, closeTo(0, 0.01));
    expect(
      report.observations,
      contains(contains('Segment 1 (economy): payload 64.0 kbps against 32')),
    );
  });

  test('P0-12 measures the gap each switch leaves between '
      'segments', () async {
    final report = await spike(switchCost: const Duration(milliseconds: 180))
        .run(activityId: keynote.id);

    expect(report.segments.first.gapBefore, isNull);
    expect(report.segments.skip(1).map((s) => s.gapBefore!.inMilliseconds), [
      180,
      180,
      180,
    ]);
    expect(report.switches.every((s) => s.commandMs == 180), isTrue);
    expect(report.observations, contains(contains('180 to 180 ms')));
  });

  test('P0-12 a refused profile is reported as declined and recording '
      'carries on', () async {
    engine.refuse = (r) =>
        r.bitrateBps == 64000 ? StateError('not supported') : null;

    final report = await spike().run(activityId: keynote.id);

    expect(report.switches.map((s) => s.result.outcome), [
      ProfileChangeOutcome.changed,
      ProfileChangeOutcome.declined,
      ProfileChangeOutcome.changed,
    ]);
    expect(report.switches[1].result.reason, contains('not supported'));
    expect(report.segments.map((s) => s.error), [
      null,
      null,
      'damaged',
      null,
      null,
    ]);
    expect(report.observations, contains(contains('enhanced declined')));
    expect(report.toMarkdown(), contains('error: damaged'));
  });

  test('P0-12 Windows requests are raised to the encoder floor '
      '(ADR-002, FR-QUAL-05)', () async {
    final report = await spike(platform: CapturePlatform.windows)
        .run(activityId: keynote.id);

    expect(report.segments.map((s) => s.segment.requestedBitrateBps).toSet(), {
      96000,
    });
    expect(report.platform, CapturePlatform.windows);
  });

  test('P0-12 denied microphone records nothing and says so', () async {
    engine.permission = false;

    final report = await spike().run(activityId: keynote.id);

    expect(report.startOutcome, StartOutcome.microphoneDenied);
    expect(report.switches, isEmpty);
    expect(report.segments, isEmpty);
    expect(report.observations.take(2), [
      'Start: microphoneDenied.',
      'No switches ran.',
    ]);
  });

  test('P0-12 a failed start carries the encoder error into the '
      'report', () async {
    engine.startError = StateError('No audio recording device was found.');

    final report = await spike().run(activityId: keynote.id);

    expect(report.startOutcome, StartOutcome.failed);
    expect(report.startError, contains('No audio recording device'));
    expect(report.observations.first, contains('No audio recording device'));
    expect(report.toJson()['start_error'], report.startError);
    expect(report.segments.single.error, 'damaged');
  });

  test('P0-12 report JSON and Markdown carry every segment', () async {
    final report = await spike().run(activityId: keynote.id);

    final json = jsonDecode(report.toPrettyJson()) as Map<String, Object?>;
    expect(json['spike'], 'P0-12');
    expect(json['switches'], hasLength(3));
    expect(json['segments'], hasLength(4));
    final markdown = report.toMarkdown();
    expect(
      markdown.split('\n').where((l) => RegExp(r'^\| \d').hasMatch(l)),
      hasLength(4),
    );
    expect(markdown, contains('| 3 | enhanced | 64 | aac_lc | 1 | 48000 '));
  });
}
