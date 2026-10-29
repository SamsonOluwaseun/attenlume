import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/presentation/components/activity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget testHarness(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('ActivityCard [DESIGN_GUIDE ActivityCard, FR-ACT-03]', () {
    testWidgets('renders all 4 rows correctly with metadata and status', (
      tester,
    ) async {
      var opened = false;
      await tester.pumpWidget(
        testHarness(
          ActivityCard(
            typeLabel: 'Keynote',
            typeIcon: 'mic',
            title: 'Data Mesh in Practice',
            startTime: '09:30',
            location: 'Hall A',
            status: StatusPillStatus.saved,
            duration: '47 min',
            photoCount: 12,
            bookmarkCount: 4,
            profile: RecordingProfile.balanced,
            onOpen: () => opened = true,
          ),
        ),
      );

      // Row 1: Type label, mic icon, status pill
      expect(find.text('Keynote'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      // Row 2: Title in heading
      expect(find.text('Data Mesh in Practice'), findsOneWidget);
      final titleWidget = tester.widget<Text>(
        find.text('Data Mesh in Practice'),
      );
      expect(titleWidget.style?.fontSize, 20.0);
      expect(titleWidget.maxLines, 2);
      expect(titleWidget.overflow, TextOverflow.ellipsis);

      // Row 3: Metadata formatted as "09:30 · Hall A · 47 min"
      expect(find.text('09:30 · Hall A · 47 min'), findsOneWidget);

      // Row 4: Asset counts and quality profile
      expect(find.text('12'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);

      // Tap action
      await tester.tap(find.text('Data Mesh in Practice'));
      expect(opened, isTrue);

      // Semantics
      expect(
        tester.getSemantics(find.byType(ActivityCard)),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          // NFR-09: the label reads everything the card shows.
          label:
              'Data Mesh in Practice, Keynote, Saved, '
              '09:30 · Hall A · 47 min, 12 photos, 4 bookmarks, Balanced',
        ),
      );
    });

    testWidgets('renders private activity with lock icon and Private badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(
          const ActivityCard(
            typeLabel: 'Reflection',
            typeIcon: 'lightbulb',
            title: 'Daily thoughts',
            startTime: '17:00',
            status: StatusPillStatus.private,
            duration: '0 min',
            photoCount: 0,
            bookmarkCount: 0,
            profile: RecordingProfile.balanced,
            isPrivate: true,
          ),
        ),
      );

      expect(find.text('Reflection'), findsOneWidget);
      expect(
        find.text('Private'),
        findsNWidgets(2),
      ); // in row 1 badge and in status pill
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
    });

    testWidgets('omits location cleanly if not provided in row 3 metadata', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(
          const ActivityCard(
            typeLabel: 'Session',
            typeIcon: 'presentation',
            title: 'Flutter Desktop Deep Dive',
            startTime: '14:00',
            status: StatusPillStatus.saved,
            duration: '30 min',
            photoCount: 0,
            bookmarkCount: 0,
            profile: RecordingProfile.economy,
          ),
        ),
      );

      expect(find.text('14:00 · 30 min'), findsOneWidget);
    });
  });
}
