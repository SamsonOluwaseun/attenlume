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
      expect(state.canPromptAgain, isTrue);

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

      // User responds to reminder
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

    test('FR-SUP-02: promptCount caps at 2 and prevents further prompts', () {
      const stateAtCap = SupportPromptState(
        initialPromptShown: true,
        reminderEligible: true,
        reminderShown: false,
        promptCount: 2,
      );
      expect(stateAtCap.canPromptAgain, isFalse);
      expect(
        defaultPolicy.shouldPrompt(
          state: stateAtCap,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );
    });

    test('FR-SUP-02: no initial prompt allowed if reminder was already shown', () {
      // Inconsistent state where initialPromptShown was false but reminderShown was true
      const stateWithPriorReminder = SupportPromptState(
        initialPromptShown: false,
        reminderShown: true,
        promptCount: 1,
      );
      expect(stateWithPriorReminder.canPromptAgain, isFalse);
      expect(
        defaultPolicy.shouldPrompt(
          state: stateWithPriorReminder,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );
    });
  });

  group('SupportPromptState & Decision serialization & fail-closed validation', () {
    test('survives clean JSON roundtrips for all valid states', () {
      // Initial state
      const initial = SupportPromptState();
      expect(SupportPromptState.fromJson(initial.toJson()), equals(initial));

      // Maybe later state
      final maybeLater = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.maybeLater(),
      );
      expect(SupportPromptState.fromJson(maybeLater.toJson()), equals(maybeLater));

      // Reminder state
      final reminder = maybeLater.withDecision(
        SupportPromptKind.reminder,
        const SupportPromptDecision.maybeLater(),
      );
      expect(SupportPromptState.fromJson(reminder.toJson()), equals(reminder));

      // Don't ask again state
      final dontAsk = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.dontAskAgain(),
      );
      expect(SupportPromptState.fromJson(dontAsk.toJson()), equals(dontAsk));

      // Gift now with amount
      final gift = initial.withDecision(
        SupportPromptKind.initial,
        const SupportPromptDecision.giftNow(SupportGiftAmount.ten),
      );
      final restoredGift = SupportPromptState.fromJson(gift.toJson());
      expect(restoredGift, equals(gift));
      expect(restoredGift.paymentCompleted, isFalse);
    });

    test('fails closed to suppressed state on missing or wrong-typed required fields', () {
      // Non-map input
      expect(SupportPromptState.fromJson(null), equals(SupportPromptState.suppressed));
      expect(SupportPromptState.fromJson('not-a-map'), equals(SupportPromptState.suppressed));
      expect(SupportPromptState.fromJson(123), equals(SupportPromptState.suppressed));

      // Empty map (missing required fields)
      expect(SupportPromptState.fromJson(<String, dynamic>{}), equals(SupportPromptState.suppressed));

      // Missing single required field
      final validMap = const SupportPromptState().toJson();
      for (final key in validMap.keys) {
        final incomplete = Map<String, dynamic>.from(validMap)..remove(key);
        expect(
          SupportPromptState.fromJson(incomplete),
          equals(SupportPromptState.suppressed),
          reason: 'Missing key "$key" must fail closed to suppressed',
        );
      }

      // Wrong field types
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          ...validMap,
          'promptCount': 'not-an-int',
        }),
        equals(SupportPromptState.suppressed),
      );

      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          ...validMap,
          'initialPromptShown': 'true', // string instead of bool
        }),
        equals(SupportPromptState.suppressed),
      );
    });

    test('fails closed to suppressed state on inconsistent invariants', () {
      final base = const SupportPromptState().toJson();

      // Invariant 1: promptCount out of bounds (< 0 or > 2)
      expect(
        SupportPromptState.fromJson(<String, dynamic>{...base, 'promptCount': -1}),
        equals(SupportPromptState.suppressed),
      );
      expect(
        SupportPromptState.fromJson(<String, dynamic>{...base, 'promptCount': 3}),
        equals(SupportPromptState.suppressed),
      );

      // Invariant 2: initialPromptShown == false but reminderEligible == true
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          ...base,
          'initialPromptShown': false,
          'reminderEligible': true,
        }),
        equals(SupportPromptState.suppressed),
      );

      // Invariant 3: reminderShown == true but promptCount != 2
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          ...base,
          'initialPromptShown': true,
          'reminderShown': true,
          'promptCount': 1,
        }),
        equals(SupportPromptState.suppressed),
      );

      // Invariant 4: reminderShown == true and reminderEligible == true
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          ...base,
          'initialPromptShown': true,
          'reminderShown': true,
          'reminderEligible': true,
          'promptCount': 2,
          'lastDecision': {'type': 'maybeLater'},
        }),
        equals(SupportPromptState.suppressed),
      );

      // Invariant 5 (Codex finding): contradictory lastDecision (e.g. dontAskAgain with reminderEligible: true)
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          'initialPromptShown': true,
          'reminderEligible': true,
          'reminderShown': false,
          'dismissedPermanently': false,
          'giftClicked': false,
          'promptCount': 1,
          'lastDecision': {'type': 'dontAskAgain'},
        }),
        equals(SupportPromptState.suppressed),
      );

      // Invariant 6: contradictory giftNow decision with reminderEligible: true
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          'initialPromptShown': true,
          'reminderEligible': true,
          'reminderShown': false,
          'dismissedPermanently': false,
          'giftClicked': false,
          'promptCount': 1,
          'lastDecision': {'type': 'giftNow'},
        }),
        equals(SupportPromptState.suppressed),
      );

      // Invariant 7: missing or malformed lastDecision with reminderEligible: true
      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          'initialPromptShown': true,
          'reminderEligible': true,
          'reminderShown': false,
          'dismissedPermanently': false,
          'giftClicked': false,
          'promptCount': 1,
        }),
        equals(SupportPromptState.suppressed),
      );

      expect(
        SupportPromptState.fromJson(<String, dynamic>{
          'initialPromptShown': true,
          'reminderEligible': true,
          'reminderShown': false,
          'dismissedPermanently': false,
          'giftClicked': false,
          'promptCount': 1,
          'lastDecision': {'type': 'malformedType'},
        }),
        equals(SupportPromptState.suppressed),
      );
    });

    test('direct construct inconsistent states fail closed in shouldPrompt and canPromptAgain', () {
      // 1. Contradictory dontAskAgain with reminderEligible: true
      const contradictoryDontAsk = SupportPromptState(
        initialPromptShown: true,
        reminderEligible: true,
        reminderShown: false,
        dismissedPermanently: false,
        giftClicked: false,
        promptCount: 1,
        lastDecision: SupportPromptDecision.dontAskAgain(),
      );
      expect(contradictoryDontAsk.isConsistent, isFalse);
      expect(contradictoryDontAsk.canPromptAgain, isFalse);
      expect(
        defaultPolicy.shouldPrompt(
          state: contradictoryDontAsk,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );

      // 2. Contradictory giftNow with reminderEligible: true
      const contradictoryGift = SupportPromptState(
        initialPromptShown: true,
        reminderEligible: true,
        reminderShown: false,
        dismissedPermanently: false,
        giftClicked: false,
        promptCount: 1,
        lastDecision: SupportPromptDecision.giftNow(),
      );
      expect(contradictoryGift.isConsistent, isFalse);
      expect(contradictoryGift.canPromptAgain, isFalse);
      expect(
        defaultPolicy.shouldPrompt(
          state: contradictoryGift,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );

      // 3. reminderEligible: true but missing lastDecision
      const missingDecision = SupportPromptState(
        initialPromptShown: true,
        reminderEligible: true,
        reminderShown: false,
        dismissedPermanently: false,
        giftClicked: false,
        promptCount: 1,
        lastDecision: null,
      );
      expect(missingDecision.isConsistent, isFalse);
      expect(missingDecision.canPromptAgain, isFalse);
      expect(
        defaultPolicy.shouldPrompt(
          state: missingDecision,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        isNull,
      );

      // 4. Fresh empty constructor state is consistent and permits initial prompt
      const fresh = SupportPromptState();
      expect(fresh.isConsistent, isTrue);
      expect(fresh.canPromptAgain, isTrue);
      expect(
        defaultPolicy.shouldPrompt(
          state: fresh,
          exportSucceeded: true,
          isChannelEligible: true,
          supportUrl: validPayPalUrl,
        ),
        equals(SupportPromptKind.initial),
      );
    });

    test('SupportPromptDecision.fromJson handles bad input safely and never claims payment', () {
      expect(SupportPromptDecision.fromJson(null).isDismissed, isTrue);
      expect(SupportPromptDecision.fromJson('string').isDismissed, isTrue);
      expect(SupportPromptDecision.fromJson(<String, dynamic>{}).isDismissed, isTrue);
      expect(
        SupportPromptDecision.fromJson(<String, dynamic>{'type': 'nonExistentType'}).isDismissed,
        isTrue,
      );
      expect(
        SupportPromptDecision.fromJson(<String, dynamic>{
          'type': 'giftNow',
          'selectedAmount': 'badAmount',
        }).selectedAmount,
        isNull,
      );

      // In all cases, paymentCompleted is strictly false
      final decoded = SupportPromptDecision.fromJson(<String, dynamic>{'type': 'giftNow'});
      expect(decoded.paymentCompleted, isFalse);
    });
  });

  group('PayPalUrlValidator public forms & security restrictions (FR-SUP-03, ADR-065)', () {
    test('accepts approved public donation & payment forms', () {
      // 1. paypal.me/<recipient>
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics'), isTrue);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.me/Samlytics'), isTrue);

      // 2. paypal.me/<recipient>/<amount>
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics/5'), isTrue);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics/5GBP'), isTrue);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics/10.50EUR'), isTrue);

      // 3. paypal.com/donate with public hosted_button_id
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/donate?hosted_button_id=ABC123XYZ'),
        isTrue,
      );
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/donate?hosted_button_id=BUTTON999'),
        isTrue,
      );

      // 4. paypal.com/ncp/payment/<id>
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/ncp/payment/PAY123'), isTrue);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/ncp/payment/PAY456'), isTrue);
    });

    test('rejects private, auth, account and webscr routes', () {
      // paypal.com private/auth routes
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/signin'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/login'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/auth'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/myaccount'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/myaccount/transfer'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/cgi-bin/webscr'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/webscr?cmd=_donations'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://www.paypal.com/checkout'), isFalse);

      // paypal.me forbidden handle names
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/signin'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/login'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/myaccount'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/auth'), isFalse);

      // Missing required params
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/donate'), isFalse); // no hosted_button_id
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/ncp/payment/'), isFalse); // empty id
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/ncp/other/123'), isFalse);
    });

    test('rejects credential-like query string parameters', () {
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics?token=secret123'),
        isFalse,
      );
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics?access_token=secret123'),
        isFalse,
      );
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics?password=mypassword'),
        isFalse,
      );
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/Samlytics?auth_key=abc'),
        isFalse,
      );
      expect(
        PayPalUrlValidator.isValidPayPalUrl('https://paypal.com/donate?hosted_button_id=ABC&session_token=xyz'),
        isFalse,
      );
    });

    test('rejects non-HTTPS, userinfo, non-443 ports, unknown hosts and malformed URLs', () {
      expect(PayPalUrlValidator.isValidPayPalUrl(null), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl(''), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('http://paypal.me/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://user:pass@paypal.me/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me:8080/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://evil-paypal.com/Samlytics'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://bank.example.co.uk/donate'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me/'), isFalse);
      expect(PayPalUrlValidator.isValidPayPalUrl('https://paypal.me'), isFalse);
    });
  });
}
