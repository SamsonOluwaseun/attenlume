import 'dart:convert';

import 'package:attenlume/features/support/support_after_export.dart';
import 'package:attenlume/features/support/support_prompt_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? stored;
  var reads = 0;
  late List<Uri> opened;
  setUp(() {
    stored = null;
    reads = 0;
    opened = [];
  });

  SupportAfterExport service({
    String url = 'https://paypal.me/SamlyticsDataServices',
    SupportDistributionChannel channel =
        SupportDistributionChannel.windowsDirect,
    Future<void> Function(String)? save,
    Future<bool> Function(Uri)? open,
  }) => SupportAfterExport(
    channel: channel,
    url: url,
    readState: () async {
      reads++;
      return stored;
    },
    writeState:
        save ??
        (value) async {
          stored = value;
        },
    openLink:
        open ??
        (uri) async {
          opened.add(uri);
          return true;
        },
  );

  test('FR-SUP-01 failed export, absent link and disallowed channel do not read preferences or prompt', () async {
    var prompts = 0;
    Future<SupportPromptDecision?> show(SupportPromptKind kind) async {
      prompts++;
      return null;
    }

    await service().run(exportSucceeded: false, show: show);
    await service(url: '').run(exportSucceeded: true, show: show);
    await service(channel: SupportDistributionChannel.appStore)
        .run(exportSucceeded: true, show: show);
    expect(reads, 0);
    expect(prompts, 0);
    expect(opened, isEmpty);
  });

  test(
    'FR-SUP-02 persisted Maybe later allows exactly one neutral later reminder',
    () async {
      final flow = service();
      final prompts = <SupportPromptKind>[];
      Future<SupportPromptDecision?> show(SupportPromptKind kind) async {
        prompts.add(kind);
        return const SupportPromptDecision.maybeLater();
      }

      await flow.run(exportSucceeded: true, show: show);
      await flow.run(exportSucceeded: true, show: show);
      await flow.run(exportSucceeded: true, show: show);
      expect(prompts, [SupportPromptKind.initial, SupportPromptKind.reminder]);
      expect(opened, isEmpty);
    },
  );

  test('FR-SUP-01 Gift now opens selected public amount but never records a payment', () async {
    await service().run(
      exportSucceeded: true,
      show: (_) async =>
          const SupportPromptDecision.giftNow(SupportGiftAmount.five),
    );
    expect(opened.single.path, '/SamlyticsDataServices/5GBP');
    final state = SupportPromptState.fromJson(
      jsonDecode(stored!) as Map<String, dynamic>,
    );
    expect(state.giftClicked, isTrue);
    expect(state.paymentCompleted, isFalse);
  });

  test('FR-SUP-01 failed persistence or browser cannot turn completed export into an exception', () async {
    var shown = false;
    await service(save: (_) async => throw StateError('disk')).run(
      exportSucceeded: true,
      show: (_) async {
        shown = true;
        return null;
      },
    );
    expect(shown, isFalse);
    await service(open: (_) async => throw StateError('browser')).run(
      exportSucceeded: true,
      show: (_) async => const SupportPromptDecision.giftNow(),
    );
    expect(
      SupportPromptState.fromJson(jsonDecode(stored!) as Map<String, dynamic>)
          .paymentCompleted,
      isFalse,
    );
  });

  test('FR-SUP-02 corrupt preferences and duplicate in-flight callbacks do not nag', () async {
    stored = '{invalid';
    var prompts = 0;
    await service().run(
      exportSucceeded: true,
      show: (_) async {
        prompts++;
        return null;
      },
    );
    expect(prompts, 0);
    stored = null;
    final flow = service();
    await flow.run(
      exportSucceeded: true,
      show: (_) async {
        prompts++;
        await flow.run(
          exportSucceeded: true,
          show: (_) async {
            prompts++;
            return null;
          },
        );
        return const SupportPromptDecision.dontAskAgain();
      },
    );
    await flow.run(
      exportSucceeded: true,
      show: (_) async {
        prompts++;
        return null;
      },
    );
    expect(prompts, 1);
  });
}
