import 'package:attenlume/features/support/support_prompt_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validPayPalUrl = 'https://paypal.me/Samlytics';
  const defaultPolicy = SupportPromptPolicy();

  group('SupportPromptPolicy eligibility & conditions (FR-SUP-01, FR-SUP-02, FR-SUP-03)', () {
    test('FR-SUP-01: failed or cancelled export never prompts', () {
      const state = SupportPromptState();

      final failedResult = defaultPolicy.shouldPrompt(
        state: state,
        exportSucceeded: false,
        isChannelEligible: true,
        supportUrl: validPayPalUrl,
      );
      expect(failedResult, isNull);

      final failedChannelResult = defaultPolicy.shouldPromptForChannel(
        state: state,
        exportSucceeded: false,
        channel: SupportDistributionChannel.windowsDirect,
        supportUrl: validPayPalUrl,
      );
      expect(failedChannelResult, isNull);
    });

    test('FR-SUP-03: missing, empty or invalid link never prompts', () {
      const state = SupportPromptState();

      // Null link
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: null,
        ),
        isNull,
      );

      // Empty link
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: '',
        ),
        isNull,
      );

      // Non-HTTPS link
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: 'http://paypal.me/Samlytics',
        ),
        isNull,
      );

      // Non-PayPal host
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: 'https://bank.example.com/donate',
        ),
        isNull,
      );
    });

    test('FR-SUP-03: disallowed distribution channels never prompt', () {
      const state = SupportPromptState();

      // Disallowed via boolean flag
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: false,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );

      // Disallowed channels: App Store, Google Play, other
      for (final channel in [
        SupportDistributionChannel.appStore,
        SupportDistributionChannel.googlePlay,
        SupportDistributionChannel.other,
      ]) {
        expect(
          defaultPolicy.shouldPromptForChannel(
            state: state,
            exportSucceeded: true,
            channel: channel,
            supportUrl: validPayPalUrl,
          ),
          isNull,
          reason: 'Channel ${channel.name} must not show unreviewed payment prompt',
        );
      }
    });

    test('FR-SUP-03: reviewed direct channels prompt when link is valid', () {
      const state = SupportPromptState();

      for (final channel in [
        SupportDistributionChannel.windowsDirect,
        SupportDistributionChannel.androidDirect,
      ]) {
        final result = defaultPolicy.shouldPromptForChannel(
          state: state,
          exportSucceeded: true,
          channel: channel,
          supportUrl: validPayPalUrl,
        );
        expect(
          result,
          equals(SupportPromptKind.initial),
          reason: 'Channel ${channel.name} should be eligible for initial prompt',
        );
      }
    });

    test('FR-SUP-02: first eligible successful export prompts initial', () {
      const state = SupportPromptState();
      final result = defaultPolicy.shouldPrompt(
        state: state,
        exportSucceeded: true,
        isChannelEligible: true,
        supportUrl: validPayPalUrl,
      );
      expect(result, equals(SupportPromptKind.initial));
    });

    test('FR-SUP-02: Maybe later permits exactly one neutral reminder on second eligible export', () {
      // 1. Initial prompt shown, user picks Maybe later
      var state = const SupportPromptState();
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        equals(SupportPromptKind.initial),
      );

      state = state.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.maybeLater(),
      );
      expect(state.initialPromptShown, isTrue);
      expect(state.reminderEligible, isTrue);
      expect(state.reminderShown, isFalse);
      expect(state.promptCount, equals(1));

      // 2. Second eligible successful export shows reminder
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        equals(SupportPromptKind.reminder),
      );

      // User responds to reminder (even with Maybe later or dismissed)
      state = state.withDecision(
        SupportPromptKind.reminder,
        const SupportPromptDecision.maybeLater(),
      );
      expect(state.reminderShown, isTrue);
      expect(state.reminderEligible, isFalse);
      expect(state.promptCount, equals(2));

      // 3. No repeat after reminder (FR-SUP-02)
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );
      expect(state.canPromptAgain, isFalse);
    });

    test('FR-SUP-02: Don\'t ask again permanently dismisses prompt', () {
      var state = const SupportPromptState();
      state = state.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.dontAskAgain(),
      );

      expect(state.dismissedPermanently, isTrue);
      expect(state.reminderEligible, isFalse);
      expect(state.canPromptAgain, isFalse);

      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );
    });

    test('FR-SUP-01: Gift click never implies payment occurred', () {
      const decision = SupportPromptDecision.giftNow(SupportGiftAmount.five);
      expect(decision.isGiftNow, isTrue);
      expect(decision.paymentCompleted, isFalse);

      var state = const SupportPromptState();
      state = state.withDecision(SupportPromptKind.initial, decision);

      expect(state.giftClicked, isTrue);
      expect(state.paymentCompleted, isFalse);
      expect(state.canPromptAgain, isFalse);

      // No more prompts after user chose gift
      expect(
        defaultPolicy.shouldPrompt(
          state: state,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );
    });

    test('FR-SUP-02: Initial, reminder, decline and don\'t ask transitions survive JSON serialization', () {
      // 1. Initial fresh state roundtrip
      const initial = SupportPromptState();
      expect(SupportPromptState.fromJson(initial.toJson()), equals(initial));

      // 2. Decline transition roundtrip
      final declined = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.declined(),
      );
      expect(SupportPromptState.fromJson(declined.toJson()), equals(declined));
      expect(declined.lastDecision?.isDeclined, isTrue);

      // 3. Maybe later -> reminder eligible roundtrip
      final maybeLater = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.maybeLater(),
      );
      expect(SupportPromptState.fromJson(maybeLater.toJson()), equals(maybeLater));
      expect(maybeLater.reminderEligible, isTrue);

      // 4. Reminder shown roundtrip
      final reminderShown = maybeLater.withDecision(
        SupportPromptKind.reminder,
        const SupportPromptDecision.maybeLater(),
      );
      expect(SupportPromptState.fromJson(reminderShown.toJson()), equals(reminderShown));
      expect(reminderShown.reminderShown, isTrue);

      // 5. Don't ask again roundtrip
      final dontAsk = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.dontAskAgain(),
      );
      expect(SupportPromptState.fromJson(dontAsk.toJson()), equals(dontAsk));
      expect(dontAsk.dismissedPermanently, isTrue);

      // 6. Gift now with amount roundtrip
      final giftWithAmount = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.giftNow(SupportGiftAmount.ten),
      );
      final restoredGift = SupportPromptState.fromJson(giftWithAmount.toJson());
      expect(restoredGift, equals(giftWithAmount));
      expect(restoredGift.lastDecision?.selectedAmount, equals(SupportGiftAmount.ten));
      expect(restoredGift.paymentCompleted, isFalse);
    });
  });

  group('PayPalUrlValidator (FR-SUP-03, ADR-065)', () {
    test('accepts valid public PayPal HTTPS hosts', () {
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics'), isTrue);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.me/Samlytics'), isTrue);
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/donate/?hosted_button_id=ABC123XYZ'),
        isTrue,
      );
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/ncp/payment/XYZ'), isTrue);
    });

    test('rejects HTTP, userinfo, non-PayPal hosts, malformed URIs, and bare domains', () {
      expect(PayPalUrlValidator.isValidPayPalUrl(null), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl(''), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('   '), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('not-a-url'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('http://paypal.me/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://admin:pass@paypal.me/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://evil-paypal.com/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me.attacker.com/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://bank.example.co.uk/account/12345678'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me:8080/Samlytics'), isFalse);
    });
  });
}
