import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:attenlume/features/conferences/conference_delete_dialog.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/conference_wizard_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDeviceTimezoneService extends DeviceTimezoneService {
  const _FakeDeviceTimezoneService();

  @override
  Future<String> detectTimezone() async => 'Europe/London';

  @override
  List<String> getAvailableTimezones() => const [
    'America/New_York',
    'Europe/London',
    'UTC',
  ];
}

void main() {
  late AppDatabase db;
  late ConferenceRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ConferenceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject({String? conferenceId}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceTimezoneServiceProvider.overrideWithValue(
          const _FakeDeviceTimezoneService(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ConferenceWizardScreen(conferenceId: conferenceId),
      ),
    );
  }

  testWidgets(
    'FR-CONF-02 to 07 full wizard sets up conference with details, role, goals, outputs and profile',
    (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // FR-CONF-02 details
      await tester.enterText(
        find.byKey(const Key('conference-name-input')),
        'Data Architecture Summit 2026',
      );
      await tester.enterText(
        find.byKey(const Key('conference-venue-input')),
        'ExCeL London',
      );
      await tester.enterText(
        find.byKey(const Key('conference-description-input')),
        'Annual enterprise data architecture summit',
      );

      // FR-CONF-03 role
      final speakerChip = find.byKey(const Key('role-chip-speaker'));
      await tester.ensureVisible(speakerChip);
      await tester.pumpAndSettle();
      await tester.tap(speakerChip);

      final roleInput = find.byKey(const Key('role-text-input'));
      await tester.ensureVisible(roleInput);
      await tester.pumpAndSettle();
      await tester.enterText(roleInput, 'Senior enterprise data architect');

      // FR-CONF-04 goals: tap example chip to populate priority goal 1
      final exampleChip = find.widgetWithText(
        ActionChip,
        'Where could enterprise data architecture improve reproducibility?',
      );
      expect(exampleChip, findsOneWidget);
      await tester.ensureVisible(exampleChip);
      await tester.pumpAndSettle();
      await tester.tap(exampleChip);

      // Enter priority goal 2
      final goal2Input = find.byKey(const Key('priority-goal-input-1'));
      await tester.ensureVisible(goal2Input);
      await tester.pumpAndSettle();
      await tester.enterText(
        goal2Input,
        'How is AI applied in public health response?',
      );

      // Add optional goal
      final addGoalBtn = find.byKey(const Key('add-goal-button'));
      await tester.ensureVisible(addGoalBtn);
      await tester.pumpAndSettle();
      await tester.tap(addGoalBtn);
      await tester.pumpAndSettle();

      final optGoalInput = find.byKey(const Key('optional-goal-input-0'));
      await tester.ensureVisible(optGoalInput);
      await tester.pumpAndSettle();
      await tester.enterText(
        optGoalInput,
        'Connect with reproducible data colleagues',
      );

      // FR-CONF-05 outputs
      final briefingChip = find.byKey(const Key('output-chip-briefing'));
      await tester.ensureVisible(briefingChip);
      await tester.pumpAndSettle();
      await tester.tap(briefingChip);

      final presentationChip = find.byKey(
        const Key('output-chip-presentation'),
      );
      await tester.ensureVisible(presentationChip);
      await tester.pumpAndSettle();
      await tester.tap(presentationChip);

      final blogChip = find.byKey(const Key('output-chip-blog'));
      await tester.ensureVisible(blogChip);
      await tester.pumpAndSettle();
      await tester.tap(blogChip);

      // FR-CONF-07 recording profile: pick Enhanced
      final enhancedTile = find.byKey(const Key('profile-tile-enhanced'));
      await tester.ensureVisible(enhancedTile);
      await tester.pumpAndSettle();
      await tester.tap(enhancedTile);

      // FR-CONF-06 policy notice & acknowledgement
      expect(
        find.text(
          'Some events and speakers do not allow recording. Record only when permitted.',
        ),
        findsOneWidget,
      );
      final policyCheckbox = find.byKey(
        const Key('policy-acknowledge-checkbox'),
      );
      await tester.ensureVisible(policyCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(policyCheckbox);

      // Save
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('save-conference-button'));
      await tester.tap(saveBtn);

      // Advance frames
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Land on ConferenceHomeScreen
      expect(find.byType(ConferenceHomeScreen), findsOneWidget);
      expect(find.text('Data Architecture Summit 2026'), findsWidgets);

      // Verify database
      final conferences = await repo.getRecent();
      expect(conferences.length, equals(1));
      final conf = conferences.first;

      expect(conf.name, 'Data Architecture Summit 2026');
      expect(conf.venue, 'ExCeL London');
      expect(conf.description, 'Annual enterprise data architecture summit');
      expect(conf.roleType, RoleType.speaker);
      expect(conf.roleText, 'Senior enterprise data architect');
      expect(conf.defaultRecordingProfile, RecordingProfile.enhanced);
      expect(conf.policyAcknowledgedAt, isNotNull);
      expect(
        conf.requestedOutputs,
        unorderedEquals([
          RequestedOutput.briefing,
          RequestedOutput.presentation,
          RequestedOutput.blog,
        ]),
      );

      // Verify goals in DB
      final goals = await repo.goalsFor(conf.id);
      expect(goals.length, equals(3));
      expect(goals[0].priority, equals(1));
      expect(
        goals[0].goalText,
        'Where could enterprise data architecture improve reproducibility?',
      );
      expect(goals[1].priority, equals(2));
      expect(goals[1].goalText, 'How is AI applied in public health response?');
      expect(goals[2].priority, isNull);
      expect(goals[2].goalText, 'Connect with reproducible data colleagues');
    },
  );

  testWidgets(
    'FR-CONF-08 edit existing conference updates fields and syncs goals',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Create initial conference in DB
      final initial = await repo.create(
        name: 'Initial Conference',
        timezone: 'Europe/London',
        defaultRecordingProfile: RecordingProfile.balanced,
      );
      await repo.addGoal(initial.id, 'Initial goal', priority: 1);

      await tester.pumpWidget(createSubject(conferenceId: initial.id));
      await tester.pumpAndSettle();

      // Verify prefilled
      expect(find.text('Edit conference'), findsOneWidget);
      expect(find.text('Initial Conference'), findsOneWidget);
      expect(find.text('Initial goal'), findsOneWidget);

      // Edit name
      await tester.enterText(
        find.byKey(const Key('conference-name-input')),
        'Updated Conference Name',
      );

      // Update goal
      await tester.enterText(
        find.byKey(const Key('priority-goal-input-0')),
        'Updated goal text',
      );

      // Save
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('save-conference-button'));
      await tester.tap(saveBtn);

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify DB update
      final updated = await repo.get(initial.id);
      expect(updated!.name, 'Updated Conference Name');

      final updatedGoals = await repo.goalsFor(initial.id);
      expect(updatedGoals.single.goalText, 'Updated goal text');
    },
  );

  testWidgets('FR-CONF-08 archive and unarchive conference from wizard', (
    tester,
  ) async {
    final initial = await repo.create(
      name: 'Conference To Archive',
      timezone: 'Europe/London',
    );

    await tester.pumpWidget(createSubject(conferenceId: initial.id));
    await tester.pumpAndSettle();

    // Tap archive icon in AppBar
    final archiveButton = find.byTooltip('Archive conference');
    expect(archiveButton, findsOneWidget);
    await tester.tap(archiveButton);
    await tester.pumpAndSettle();

    // Confirmation dialog
    expect(find.text('Archive Conference To Archive?'), findsOneWidget);
    await tester.tap(find.text('Archive conference'));

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final conf = await repo.get(initial.id);
    expect(conf!.isArchived, isTrue);
  });

  testWidgets(
    'FR-CONF-08 delete conference shows confirmation dialog with deletion summary',
    (tester) async {
      final initial = await repo.create(
        name: 'Conference To Delete',
        timezone: 'Europe/London',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    ConferenceDeleteDialog.show(context, conference: initial),
                child: const Text('Open Delete Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Delete Dialog'));
      await tester.pumpAndSettle();

      // Verify deletion summary contents
      expect(find.text('Delete Conference To Delete?'), findsOneWidget);
      expect(find.text('Activities'), findsOneWidget);
      expect(find.text('Recording segments'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('Delete conference'));
      await tester.pumpAndSettle();

      final conf = await repo.get(initial.id);
      expect(conf, isNull);
    },
  );

  group('FR-QUAL-03 bulk change confirmation [P1-09]', () {
    Future<(String, String, String)> seed() async {
      final conf = await repo.create(
        name: 'Profile Conference',
        timezone: 'Europe/London',
        defaultRecordingProfile: RecordingProfile.balanced,
      );
      final acts = ActivityRepository(db);
      final types = await acts.types();
      final typeId = types.first.id;
      final unrecorded = await acts.create(
        conferenceId: conf.id,
        typeId: typeId,
        title: 'Not yet recorded',
      );
      final later = await acts.create(
        conferenceId: conf.id,
        typeId: typeId,
        title: 'Also not recorded',
      );
      return (conf.id, unrecorded.id, later.id);
    }

    Future<void> changeToEnhancedAndSave(
      WidgetTester tester,
      String confId,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createSubject(conferenceId: confId));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('profile-tile-enhanced'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('save-conference-button'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('FR-QUAL-03 asks before moving unrecorded activities, and '
        '"New activities only" keeps them', (tester) async {
      final (confId, a, b) = (await tester.runAsync(seed))!;
      await changeToEnhancedAndSave(tester, confId);

      expect(
        find.byKey(const Key('profile-bulk-change-dialog')),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 activities that have not been recorded yet'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('profile-bulk-new-only')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final acts = ActivityRepository(db);
      final conf = (await tester.runAsync(() => repo.get(confId)))!;
      expect(conf.defaultRecordingProfile, RecordingProfile.enhanced);
      for (final id in [a, b]) {
        expect(
          await tester.runAsync(() => acts.effectiveProfile(id)),
          RecordingProfile.balanced,
        );
      }
    });

    testWidgets('FR-QUAL-03 "Change them too" moves unrecorded activities', (
      tester,
    ) async {
      final (confId, a, _) = (await tester.runAsync(seed))!;
      await changeToEnhancedAndSave(tester, confId);
      await tester.tap(find.byKey(const Key('profile-bulk-include')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        await tester.runAsync(() => ActivityRepository(db).effectiveProfile(a)),
        RecordingProfile.enhanced,
      );
    });

    testWidgets('FR-QUAL-03 Cancel saves nothing', (tester) async {
      final (confId, a, _) = (await tester.runAsync(seed))!;
      await changeToEnhancedAndSave(tester, confId);
      await tester.tap(find.byKey(const Key('profile-bulk-cancel')));
      await tester.pumpAndSettle();
      final conf = (await tester.runAsync(() => repo.get(confId)))!;
      expect(conf.defaultRecordingProfile, RecordingProfile.balanced);
      expect(
        await tester.runAsync(() => ActivityRepository(db).effectiveProfile(a)),
        RecordingProfile.balanced,
      );
    });
  });
}
