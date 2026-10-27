import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/storage_thresholds.dart';
import 'package:attenlume/presentation/components/storage_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp(Widget child, {bool liveTheme = false}) {
    return MaterialApp(
      theme: liveTheme ? AppTheme.live() : AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('FR-UI-07 StorageMeter formatting [P1-12]', () {
    test('FR-UI-07 formatBytes formats across magnitude ranges', () {
      expect(StorageMeter.formatBytes(null), 'Unknown');
      expect(StorageMeter.formatBytes(0), '0 B');
      expect(StorageMeter.formatBytes(512), '512 B');
      expect(StorageMeter.formatBytes(2048), '2 KB');
      expect(StorageMeter.formatBytes(50 * 1024 * 1024), '50.0 MB');
      expect(StorageMeter.formatBytes(15 * 1024 * 1024 * 1024), '15.0 GB');
    });

    test('FR-UI-07 leadSentence leads with time, not bytes', () {
      expect(
        StorageMeter.leadSentence(null, RecordingProfile.balanced),
        'Space left unknown',
      );
      expect(
        StorageMeter.leadSentence(0, RecordingProfile.balanced),
        'No space left at Balanced',
      );
      expect(
        StorageMeter.leadSentence(45, RecordingProfile.balanced),
        'About 45 minutes left at Balanced',
      );
      expect(
        StorageMeter.leadSentence(580, RecordingProfile.balanced),
        'About 9 h 40 min left at Balanced',
      );
    });
  });

  group('FR-UI-07 StorageMeter compact mode (recording screen) [P1-12]', () {
    testWidgets(
      'FR-UI-07 compact mode shows single muted line when level is ok',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            const StorageMeter(
              freeBytes: 15 * 1024 * 1024 * 1024, // 15 GB
              minutesLeft: 580,
              profile: RecordingProfile.balanced,
              level: StorageLevel.ok,
              compact: true,
            ),
            liveTheme: true,
          ),
        );

        expect(
          find.byKey(const Key('storage-meter-compact-ok')),
          findsOneWidget,
        );
        expect(
          find.text('About 9 h 40 min left at Balanced • 15.0 GB free'),
          findsOneWidget,
        );
        // No warning banner when ok
        expect(
          find.byKey(const Key('storage-meter-banner-warning')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('storage-meter-banner-urgent')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'FR-UI-07 compact mode grows into warning banner when level is warning',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            const StorageMeter(
              freeBytes: 850 * 1024 * 1024,
              minutesLeft: 45,
              profile: RecordingProfile.balanced,
              level: StorageLevel.warning,
              compact: true,
            ),
            liveTheme: true,
          ),
        );

        expect(find.byKey(const Key('storage-meter-compact-ok')), findsNothing);
        expect(
          find.byKey(const Key('storage-meter-banner-warning')),
          findsOneWidget,
        );
        expect(
          find.text('Running low. Export or free space soon.'),
          findsOneWidget,
        );
        expect(
          find.text('About 45 minutes left (850.0 MB free)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FR-UI-07 compact mode grows into danger banner when level is urgent',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            const StorageMeter(
              freeBytes: 250 * 1024 * 1024,
              minutesLeft: 12,
              profile: RecordingProfile.balanced,
              level: StorageLevel.urgent,
              compact: true,
            ),
            liveTheme: true,
          ),
        );

        expect(find.byKey(const Key('storage-meter-compact-ok')), findsNothing);
        expect(
          find.byKey(const Key('storage-meter-banner-urgent')),
          findsOneWidget,
        );
        expect(
          find.text('Storage nearly full. Recording will stop safely.'),
          findsOneWidget,
        );
        expect(
          find.text('About 12 minutes left (250.0 MB free)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FR-UI-07 compact mode displays hard-stop banner when level is hardStop',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            const StorageMeter(
              freeBytes: 90 * 1024 * 1024,
              minutesLeft: 0,
              profile: RecordingProfile.balanced,
              level: StorageLevel.hardStop,
              compact: true,
            ),
            liveTheme: true,
          ),
        );

        expect(find.byKey(const Key('storage-meter-compact-ok')), findsNothing);
        expect(
          find.byKey(const Key('storage-meter-banner-hard-stop')),
          findsOneWidget,
        );
        expect(
          find.text('Storage nearly full. Recording stopped and saved.'),
          findsOneWidget,
        );
        expect(
          find.text('90.0 MB free (hard reserve reached)'),
          findsOneWidget,
        );
      },
    );
  });

  group('FR-UI-07 StorageMeter expanded mode [P1-12]', () {
    testWidgets(
      'FR-UI-07 expanded mode displays progress, free/total bytes and onManage',
      (tester) async {
        var managed = false;

        await tester.pumpWidget(
          buildApp(
            StorageMeter(
              freeBytes: 20 * 1024 * 1024 * 1024,
              totalBytes: 128 * 1024 * 1024 * 1024,
              minutesLeft: 720,
              profile: RecordingProfile.balanced,
              level: StorageLevel.ok,
              conferenceBytes: 120 * 1024 * 1024,
              onManage: () => managed = true,
            ),
          ),
        );

        expect(
          find.byKey(const Key('storage-meter-lead-text')),
          findsOneWidget,
        );
        expect(find.text('About 12 h left at Balanced'), findsOneWidget);
        expect(find.byKey(const Key('storage-meter-subtext')), findsOneWidget);
        expect(
          find.text('20.0 GB free of 128.0 GB • 120.0 MB in this conference'),
          findsOneWidget,
        );

        final manageBtn = find.byKey(const Key('storage-meter-manage-button'));
        expect(manageBtn, findsOneWidget);
        await tester.tap(manageBtn);
        expect(managed, isTrue);
      },
    );
  });
}
