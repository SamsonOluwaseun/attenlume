import 'dart:io';
import 'dart:ui' as ui;

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/settings/settings_screen.dart';
import 'package:attenlume/features/support/support_after_export.dart';
import 'package:attenlume/features/support/support_prompt_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData data;
  var reads = 0;
  var writes = 0;
  var opens = 0;
  var opensSuccessfully = true;
  setUp(() {
    data = TestData();
    reads = writes = opens = 0;
    opensSuccessfully = true;
  });
  tearDown(() => data.close());
  SupportAfterExport service({
    SupportDistributionChannel channel =
        SupportDistributionChannel.androidDirect,
  }) => SupportAfterExport(
    channel: channel,
    url: 'https://www.paypal.com/donate/?hosted_button_id=EMQCVQHTPDR2U',
    readState: () async {
      reads++;
      return '{"dontAskAgain":true}';
    },
    writeState: (_) async {
      writes++;
    },
    openLink: (_) async {
      opens++;
      return opensSuccessfully;
    },
  );

  Future<void> pump(
    WidgetTester tester,
    SupportAfterExport support, {
    bool large = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(data.db),
          recordingStatusProvider.overrideWith(
            (ref) => Stream.value(RecordingStatus.idle),
          ),
          supportAfterExportProvider.overrideWithValue(support),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: Key('support-settings-capture'),
            child: SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('FR-SUP-02/03 manual support ignores automatic suppression without changing it', () async {
    final result = await service().requestSupport(
      show: () async =>
          const SupportPromptDecision.giftNow(SupportGiftAmount.ten),
    );
    expect(result, isTrue);
    expect(opens, 1);
    expect(reads, 0);
    expect(writes, 0);
  });
  test('FR-SUP-03 manual support unavailable on store channels', () async {
    for (final channel in [
      SupportDistributionChannel.appStore,
      SupportDistributionChannel.googlePlay,
    ]) {
      await service(channel: channel)
          .requestSupport(show: () async => throw StateError('must not show'));
    }
    expect(opens, 0);
    expect(reads, 0);
    expect(writes, 0);
  });
  testWidgets(
    'FR-SUP-01/02 Settings manual page opens PayPal without export claims or preferences',
    (tester) async {
      tester.view.physicalSize = const Size(540, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_SUPPORT_SETTINGS')) {
        await tester.runAsync(() async {
          await (FontLoader('Montserrat')
                ..addFont(
                  rootBundle.load('assets/fonts/Montserrat-Regular.ttf'),
                )
                ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      await pump(tester, service());
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-support')),
        200,
      );
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('CAPTURE_SUPPORT_SETTINGS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('support-settings-capture')),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tool/logs/support-settings.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('settings-support')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-support')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('settings-support')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Thank you for considering'), findsOneWidget);
      expect(find.textContaining('Your export is ready'), findsNothing);
      expect(find.text('Maybe later'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
      expect(
        find.byKey(const Key('support-prompt-dont-ask-again')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('support-prompt-gift-now')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(reads, 0);
      expect(writes, 0);
    },
  );
  testWidgets('FR-SUP-03 Settings hides support on unreviewed builds', (
    tester,
  ) async {
    await pump(tester, service(channel: SupportDistributionChannel.other));
    expect(find.byKey(const Key('settings-support')), findsNothing);
  });
  testWidgets('FR-SUP-01 failed browser shows retry guidance at 200 percent', (
    tester,
  ) async {
    opensSuccessfully = false;
    await pump(tester, service(), large: true);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-support')),
      200,
    );
    await tester.ensureVisible(find.byKey(const Key('settings-support')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-support')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('settings-support')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('support-prompt-gift-now')),
    );
    await tester.tap(find.byKey(const Key('support-prompt-gift-now')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PayPal could not be opened'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(writes, 0);
  });
}
