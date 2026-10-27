import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/services/crash_recovery_service.dart';
import 'package:attenlume/features/capture/crash_recovery_dialog.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keynote = RecoveredActivity(
    activityId: 'a',
    conferenceId: 'c',
    title: 'Data Mesh Keynote',
    wasRecording: true,
    recovered: 1,
  );
  const panel = RecoveredActivity(
    activityId: 'b',
    conferenceId: 'c',
    title: 'Panel',
    wasRecording: true,
    damaged: 1,
  );

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onPressed,
  ) async {
    phoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => onPressed(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('FR-REC-08 crash recovery prompt', () {
    testWidgets('FR-REC-08 one recording: shows what was saved and offers to '
        'carry on', (tester) async {
      String? chosen = 'unset';
      await pumpHost(tester, (context) async {
        chosen = await CrashRecoveryDialog.show(
          context,
          const RecoveryReport(activities: [keynote]),
        );
      });

      expect(find.text('Your recording was recovered'), findsOneWidget);
      expect(find.text(keynote.message), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crash-recovery-carry-on')));
      await tester.pumpAndSettle();

      expect(chosen, 'a');
    });

    testWidgets('FR-REC-08 Not now returns nothing to start', (tester) async {
      String? chosen = 'unset';
      await pumpHost(tester, (context) async {
        chosen = await CrashRecoveryDialog.show(
          context,
          const RecoveryReport(activities: [keynote]),
        );
      });

      await tester.tap(find.byKey(const Key('crash-recovery-ok')));
      await tester.pumpAndSettle();

      expect(chosen, isNull);
      expect(find.byKey(const Key('crash-recovery-dialog')), findsNothing);
    });

    testWidgets('FR-REC-08 several activities: each is listed and none is '
        'restarted', (tester) async {
      await pumpHost(
        tester,
        (context) => CrashRecoveryDialog.show(
          context,
          const RecoveryReport(
            activities: [keynote, panel],
            unlinkedFiles: ['x.m4a', 'y.m4a'],
          ),
        ),
      );

      expect(find.text(keynote.message), findsOneWidget);
      expect(find.text(panel.message), findsOneWidget);
      expect(
        find.text(
          '2 audio files are not linked to any activity. They are kept in '
          'the app folder.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('crash-recovery-carry-on')), findsNothing);
      expect(find.text('OK'), findsOneWidget);
    });
  });

  group('FR-REC-08 crash recovery gate', () {
    Future<void> pumpGate(WidgetTester tester, RecoveryReport report) async {
      phoneSize(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            crashRecoveryReportProvider.overrideWith((ref) async => report),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const CrashRecoveryGate(child: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('FR-REC-08 shows the prompt on start when something was '
        'recovered', (tester) async {
      await pumpGate(tester, const RecoveryReport(activities: [keynote]));

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const Key('crash-recovery-dialog')), findsOneWidget);
    });

    testWidgets('FR-REC-08 shows nothing after a clean exit', (tester) async {
      await pumpGate(tester, RecoveryReport.empty);

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const Key('crash-recovery-dialog')), findsNothing);
    });
  });
}
