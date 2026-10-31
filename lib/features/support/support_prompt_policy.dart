import 'package:flutter/foundation.dart';

/// The prompt phase to show to the user (FR-SUP-02).
enum SupportPromptKind {
  /// First prompt after the first eligible successful export.
  initial,

  /// One-time neutral follow-up prompt if user previously chose "Maybe later".
  reminder,
}

/// Declarative suggested gift amounts for the support prompt.
///
/// Purely declarative: no checkout or fixed-amount enforcement (FR-SUP-01).
enum SupportGiftAmount {
  five(5, '£5'),
  ten(10, '£10'),
  twenty(20, '£20');

  const SupportGiftAmount(this.pounds, this.label);

  final int pounds;
  final String label;

  static SupportGiftAmount? fromPounds(int? value) {
    if (value == null) return null;
    for (final amount in values) {
      if (amount.pounds == value) return amount;
    }
    return null;
  }
}

/// The decision made by the user in the support prompt dialog.
enum SupportPromptDecisionType {
  giftNow,
  maybeLater,
  dontAskAgain,
  declined,
  dismissed,
}

/// Represents the user's response to an optional support prompt (FR-SUP-01, FR-SUP-02).
@immutable
class SupportPromptDecision {
  const SupportPromptDecision({required this.type, this.selectedAmount});

  const SupportPromptDecision.giftNow([SupportGiftAmount? amount])
    : type = SupportPromptDecisionType.giftNow,
      selectedAmount = amount;

  const SupportPromptDecision.maybeLater()
    : type = SupportPromptDecisionType.maybeLater,
      selectedAmount = null;

  const SupportPromptDecision.dontAskAgain()
    : type = SupportPromptDecisionType.dontAskAgain,
      selectedAmount = null;

  const SupportPromptDecision.declined()
    : type = SupportPromptDecisionType.declined,
      selectedAmount = null;

  const SupportPromptDecision.dismissed()
    : type = SupportPromptDecisionType.dismissed,
      selectedAmount = null;

  final SupportPromptDecisionType type;
  final SupportGiftAmount? selectedAmount;

  bool get isGiftNow => type == SupportPromptDecisionType.giftNow;
  bool get isMaybeLater => type == SupportPromptDecisionType.maybeLater;
  bool get isDontAskAgain => type == SupportPromptDecisionType.dontAskAgain;
  bool get isDeclined => type == SupportPromptDecisionType.declined;
  bool get isDismissed => type == SupportPromptDecisionType.dismissed;

  /// Crucial rule (FR-SUP-01, ADR-065): Clicking "Gift now" or opening a link
  /// never implies or records that payment occurred.
  bool get paymentCompleted => false;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    if (selectedAmount != null) 'selectedAmount': selectedAmount!.pounds,
  };

  factory SupportPromptDecision.fromJson(dynamic rawJson) {
    if (rawJson is! Map) {
      return const SupportPromptDecision.dismissed();
    }
    final json = Map<String, dynamic>.from(rawJson);
    final typeName = json['type'];
    if (typeName is! String) {
      return const SupportPromptDecision.dismissed();
    }
    final type = SupportPromptDecisionType.values
        .cast<SupportPromptDecisionType?>()
        .firstWhere((v) => v?.name == typeName, orElse: () => null);
    if (type == null) {
      return const SupportPromptDecision.dismissed();
    }

    final amountRaw = json['selectedAmount'];
    SupportGiftAmount? amount;
    if (amountRaw is int) {
      amount = SupportGiftAmount.fromPounds(amountRaw);
    }
    return SupportPromptDecision(type: type, selectedAmount: amount);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupportPromptDecision &&
          other.type == type &&
          other.selectedAmount == selectedAmount;

  @override
  int get hashCode => Object.hash(type, selectedAmount);

  @override
  String toString() =>
      'SupportPromptDecision(type: ${type.name}, selectedAmount: ${selectedAmount?.label})';
}

/// Distribution channels for Attenlume (FR-SUP-03, ADR-065).
///
/// External payment links are only permitted on reviewed, eligible channels
/// (such as direct Windows installer or direct Android APK). App Store and
/// Play Store distributions must remain disabled unless reviewed separately.
enum SupportDistributionChannel {
  windowsDirect,
  androidDirect,
  googlePlay,
  appStore,
  other;

  /// Whether external donation/gift links may be shown for this channel.
  bool get isExternalLinkAllowed {
    switch (this) {
      case SupportDistributionChannel.windowsDirect:
      case SupportDistributionChannel.androidDirect:
        return true;
      case SupportDistributionChannel.googlePlay:
      case SupportDistributionChannel.appStore:
      case SupportDistributionChannel.other:
        return false;
    }
  }
}

/// Validates public HTTPS PayPal support links (FR-SUP-03, ADR-065).
///
/// Enforces:
/// - HTTPS scheme only.
/// - Exact public PayPal hosts only (paypal.me, paypal.com).
/// - Exact allowed public routes:
///   1. `paypal.me/<recipient>` (optionally with verified amount in path, e.g. `/5` or `/5GBP`).
///   2. `paypal.com/donate` with public hosted button query `hosted_button_id=<id>`.
///   3. `paypal.com/ncp/payment/<id>`.
/// - Reject private/auth/account routes (signin, login, myaccount, webscr, cgi-bin, etc.).
/// - Reject userinfo (passwords/usernames).
/// - Reject non-443 ports.
/// - Reject credential-like query string names (password, token, access_token, auth, secret, etc.).
abstract final class PayPalUrlValidator {
  static const Set<String> allowedHosts = {
    'paypal.me',
    'www.paypal.me',
    'paypal.com',
    'www.paypal.com',
  };

  static const Set<String> _forbiddenPathSegments = {
    'signin',
    'login',
    'auth',
    'authenticate',
    'myaccount',
    'account',
    'accounts',
    'private',
    'webscr',
    'cgi-bin',
    'connect',
    'security',
    'wallet',
    'settings',
    'oauth',
    'session',
    'logout',
    'checkout',
  };

  static const List<String> _credentialQueryKeywords = [
    'password',
    'pass',
    'token',
    'auth',
    'secret',
    'credential',
    'session',
    'cookie',
    'key',
    'code',
    'pin',
  ];

  static final RegExp _handleRegExp = RegExp(r'^[a-zA-Z0-9_\-]+$');
  static final RegExp _amountRegExp = RegExp(
    r'^[0-9]+(\.[0-9]{1,2})?([a-zA-Z]{3})?$',
  );
  static final RegExp _buttonIdRegExp = RegExp(r'^[a-zA-Z0-9_\-]+$');

  /// Validates whether [rawUrl] is a safe, public PayPal HTTPS URL matching
  /// approved public donation/payment patterns.
  static bool isValidPayPalUrl(String? rawUrl) {
    if (rawUrl == null) return false;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;

    // Must be https
    if (uri.scheme.toLowerCase() != 'https') return false;

    // Reject userinfo/credentials
    if (uri.userInfo.isNotEmpty) return false;

    // Host must match allowed PayPal hosts exactly
    final host = uri.host.toLowerCase();
    if (!allowedHosts.contains(host)) return false;

    // If port specified, must be default 443
    if (uri.hasPort && uri.port != 443) return false;

    // Reject any credential-like query parameter keys
    for (final paramKey in uri.queryParameters.keys) {
      final lowerKey = paramKey.toLowerCase();
      for (final keyword in _credentialQueryKeywords) {
        if (lowerKey.contains(keyword)) {
          return false;
        }
      }
    }

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;

    // Check for private / auth segments anywhere in path
    for (final seg in segments) {
      final lowerSeg = seg.toLowerCase();
      if (_forbiddenPathSegments.contains(lowerSeg)) {
        return false;
      }
    }

    final isMeHost = host == 'paypal.me' || host == 'www.paypal.me';
    if (isMeHost) {
      // Allowed: paypal.me/<recipient> or paypal.me/<recipient>/<amount>
      if (segments.length != 1 && segments.length != 2) return false;

      final recipient = segments[0];
      if (!_handleRegExp.hasMatch(recipient)) return false;

      if (segments.length == 2) {
        final amountPart = segments[1];
        if (!_amountRegExp.hasMatch(amountPart)) return false;
      }
      return true;
    }

    // Host is paypal.com / www.paypal.com
    // Only two public routes permitted:
    // 1) /donate with public hosted button configuration: ?hosted_button_id=<id>
    // 2) /ncp/payment/<id>
    if (segments.length == 1 && segments[0].toLowerCase() == 'donate') {
      final buttonId = uri.queryParameters['hosted_button_id'];
      if (buttonId == null || buttonId.isEmpty) return false;
      if (!_buttonIdRegExp.hasMatch(buttonId)) return false;
      return true;
    }

    if (segments.length == 3 &&
        segments[0].toLowerCase() == 'ncp' &&
        segments[1].toLowerCase() == 'payment') {
      final paymentId = segments[2];
      if (paymentId.isEmpty || !_buttonIdRegExp.hasMatch(paymentId)) {
        return false;
      }
      return true;
    }

    // All other paths on paypal.com are rejected
    return false;
  }
}

/// State of support prompts persisted across sessions (FR-SUP-02).
///
/// Completely offline, dependency-free, and contains no analytics or payment
/// account/bank details.
@immutable
class SupportPromptState {
  const SupportPromptState({
    this.initialPromptShown = false,
    this.reminderEligible = false,
    this.reminderShown = false,
    this.dismissedPermanently = false,
    this.giftClicked = false,
    this.promptCount = 0,
    this.lastDecision,
  });

  /// Suppressed fail-closed state used for corrupt, malformed or inconsistent inputs.
  static const suppressed = SupportPromptState(
    initialPromptShown: true,
    reminderEligible: false,
    reminderShown: true,
    dismissedPermanently: true,
    giftClicked: false,
    promptCount: 2,
    lastDecision: SupportPromptDecision.dismissed(),
  );

  /// Whether the initial support prompt has been shown.
  final bool initialPromptShown;

  /// Whether user chose "Maybe later" on the initial prompt, permitting exactly
  /// one reminder on a future successful export.
  final bool reminderEligible;

  /// Whether the single reminder prompt has been shown.
  final bool reminderShown;

  /// Whether the user chose "Don't ask again", permanently dismissing prompts.
  final bool dismissedPermanently;

  /// Whether user clicked "Gift now". Note: clicking gift never implies payment!
  final bool giftClicked;

  /// Total number of support prompts shown (enforced 0..2: initial + reminder).
  final int promptCount;

  /// The most recent decision made by the user, if any.
  final SupportPromptDecision? lastDecision;

  /// Rule (FR-SUP-01): Payment is never inferred from clicking a link.
  bool get paymentCompleted => false;

  /// Validates internal consistency across all state flags and lastDecision.
  bool get isConsistent {
    // 1. Prompt count bounds: 0..2
    if (promptCount < 0 || promptCount > 2) return false;

    // 2. Fresh state: promptCount == 0, initialPromptShown == false
    if (!initialPromptShown) {
      if (reminderEligible ||
          reminderShown ||
          promptCount != 0 ||
          giftClicked) {
        return false;
      }
      // A fresh state before first prompt must not have a recorded decision
      if (lastDecision != null) return false;
      return true;
    }

    // 3. Persisted shown state (initialPromptShown == true):
    // Must have promptCount >= 1 and a valid recorded lastDecision
    if (promptCount < 1 || lastDecision == null) return false;

    // 4. Invariants for reminderEligible:
    // User must have chosen maybeLater on the initial prompt.
    // Missing, malformed, or contradictory decision forbids reminder eligibility.
    if (reminderEligible) {
      if (lastDecision?.type != SupportPromptDecisionType.maybeLater) {
        return false;
      }
      if (reminderShown ||
          dismissedPermanently ||
          giftClicked ||
          promptCount != 1) {
        return false;
      }
    }

    // 5. Contradictory decision validations:
    switch (lastDecision!.type) {
      case SupportPromptDecisionType.dontAskAgain:
        if (!dismissedPermanently || reminderEligible) return false;
        break;
      case SupportPromptDecisionType.giftNow:
        if (!giftClicked || reminderEligible) return false;
        break;
      case SupportPromptDecisionType.maybeLater:
        if (promptCount == 1 && !reminderEligible) return false;
        if (reminderShown && reminderEligible) return false;
        break;
      case SupportPromptDecisionType.declined:
      case SupportPromptDecisionType.dismissed:
        if (reminderEligible) return false;
        break;
    }

    // 6. Invariants for reminderShown:
    if (reminderShown) {
      if (!initialPromptShown || reminderEligible || promptCount != 2) {
        return false;
      }
    }

    // 7. Dismissed or giftClicked cannot be reminderEligible
    if (dismissedPermanently && reminderEligible) return false;
    if (giftClicked && reminderEligible) return false;

    return true;
  }

  /// Whether any further prompt could ever be shown under this state.
  /// Enforces promptCount < 2, no prompt after reminder, and no prompt if dismissed/gifted.
  bool get canPromptAgain {
    if (!isConsistent) return false;
    if (dismissedPermanently || giftClicked) return false;
    if (promptCount >= 2) return false;
    if (reminderShown) return false;
    if (!initialPromptShown) return promptCount == 0;
    return reminderEligible &&
        promptCount == 1 &&
        lastDecision?.type == SupportPromptDecisionType.maybeLater;
  }

  /// Returns a new [SupportPromptState] reflecting the decision on [kind].
  SupportPromptState withDecision(
    SupportPromptKind kind,
    SupportPromptDecision? decision,
  ) {
    final effectiveDecision =
        decision ?? const SupportPromptDecision.dismissed();
    final newPromptCount = (promptCount + 1).clamp(0, 2);

    switch (effectiveDecision.type) {
      case SupportPromptDecisionType.dontAskAgain:
        return copyWith(
          initialPromptShown: true,
          dismissedPermanently: true,
          reminderEligible: false,
          promptCount: newPromptCount,
          lastDecision: effectiveDecision,
        );

      case SupportPromptDecisionType.giftNow:
        return copyWith(
          initialPromptShown: true,
          giftClicked: true,
          reminderEligible: false,
          promptCount: newPromptCount,
          lastDecision: effectiveDecision,
        );

      case SupportPromptDecisionType.maybeLater:
        if (kind == SupportPromptKind.initial) {
          return copyWith(
            initialPromptShown: true,
            reminderEligible: true,
            promptCount: newPromptCount,
            lastDecision: effectiveDecision,
          );
        } else {
          // On reminder: choosing maybe later does not permit further reminders.
          return copyWith(
            initialPromptShown: true,
            reminderShown: true,
            reminderEligible: false,
            promptCount: 2,
            lastDecision: effectiveDecision,
          );
        }

      case SupportPromptDecisionType.declined:
      case SupportPromptDecisionType.dismissed:
        if (kind == SupportPromptKind.initial) {
          return copyWith(
            initialPromptShown: true,
            reminderEligible: false,
            promptCount: newPromptCount,
            lastDecision: effectiveDecision,
          );
        } else {
          return copyWith(
            initialPromptShown: true,
            reminderShown: true,
            reminderEligible: false,
            promptCount: 2,
            lastDecision: effectiveDecision,
          );
        }
    }
  }

  SupportPromptState copyWith({
    bool? initialPromptShown,
    bool? reminderEligible,
    bool? reminderShown,
    bool? dismissedPermanently,
    bool? giftClicked,
    int? promptCount,
    SupportPromptDecision? lastDecision,
  }) {
    return SupportPromptState(
      initialPromptShown: initialPromptShown ?? this.initialPromptShown,
      reminderEligible: reminderEligible ?? this.reminderEligible,
      reminderShown: reminderShown ?? this.reminderShown,
      dismissedPermanently: dismissedPermanently ?? this.dismissedPermanently,
      giftClicked: giftClicked ?? this.giftClicked,
      promptCount: (promptCount ?? this.promptCount).clamp(0, 2),
      lastDecision: lastDecision ?? this.lastDecision,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'initialPromptShown': initialPromptShown,
    'reminderEligible': reminderEligible,
    'reminderShown': reminderShown,
    'dismissedPermanently': dismissedPermanently,
    'giftClicked': giftClicked,
    'promptCount': promptCount,
    if (lastDecision != null) 'lastDecision': lastDecision!.toJson(),
  };

  /// Parses state from JSON.
  ///
  /// Fails CLOSED to [SupportPromptState.suppressed] if required fields are missing,
  /// malformed, or if inconsistent invariants are detected.
  factory SupportPromptState.fromJson(dynamic rawJson) {
    if (rawJson is! Map) {
      return SupportPromptState.suppressed;
    }
    final json = Map<String, dynamic>.from(rawJson);

    // 1. Verify all required state fields exist with exact expected types
    const requiredKeys = [
      'initialPromptShown',
      'reminderEligible',
      'reminderShown',
      'dismissedPermanently',
      'giftClicked',
      'promptCount',
    ];
    for (final key in requiredKeys) {
      if (!json.containsKey(key)) {
        return SupportPromptState.suppressed;
      }
    }

    final initialPromptShownRaw = json['initialPromptShown'];
    final reminderEligibleRaw = json['reminderEligible'];
    final reminderShownRaw = json['reminderShown'];
    final dismissedPermanentlyRaw = json['dismissedPermanently'];
    final giftClickedRaw = json['giftClicked'];
    final promptCountRaw = json['promptCount'];

    if (initialPromptShownRaw is! bool ||
        reminderEligibleRaw is! bool ||
        reminderShownRaw is! bool ||
        dismissedPermanentlyRaw is! bool ||
        giftClickedRaw is! bool ||
        promptCountRaw is! int) {
      return SupportPromptState.suppressed;
    }

    final initialPromptShown = initialPromptShownRaw;
    final reminderEligible = reminderEligibleRaw;
    final reminderShown = reminderShownRaw;
    final dismissedPermanently = dismissedPermanentlyRaw;
    final giftClicked = giftClickedRaw;
    final promptCount = promptCountRaw;

    // 2. Decode lastDecision safely if present
    SupportPromptDecision? lastDecision;
    if (json.containsKey('lastDecision') && json['lastDecision'] != null) {
      lastDecision = SupportPromptDecision.fromJson(json['lastDecision']);
    }

    final parsedState = SupportPromptState(
      initialPromptShown: initialPromptShown,
      reminderEligible: reminderEligible,
      reminderShown: reminderShown,
      dismissedPermanently: dismissedPermanently,
      giftClicked: giftClicked,
      promptCount: promptCount,
      lastDecision: lastDecision,
    );

    // 3. Fail closed if state violates internal consistency
    if (!parsedState.isConsistent) {
      return SupportPromptState.suppressed;
    }

    return parsedState;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupportPromptState &&
          other.initialPromptShown == initialPromptShown &&
          other.reminderEligible == reminderEligible &&
          other.reminderShown == reminderShown &&
          other.dismissedPermanently == dismissedPermanently &&
          other.giftClicked == giftClicked &&
          other.promptCount == promptCount &&
          other.lastDecision == lastDecision;

  @override
  int get hashCode => Object.hash(
    initialPromptShown,
    reminderEligible,
    reminderShown,
    dismissedPermanently,
    giftClicked,
    promptCount,
    lastDecision,
  );

  @override
  String toString() =>
      'SupportPromptState(initialPromptShown: $initialPromptShown, reminderEligible: $reminderEligible, reminderShown: $reminderShown, dismissedPermanently: $dismissedPermanently, giftClicked: $giftClicked, promptCount: $promptCount, lastDecision: $lastDecision)';
}

/// Evaluates whether a post-export support prompt should be presented (FR-SUP-01, FR-SUP-02, FR-SUP-03).
class SupportPromptPolicy {
  const SupportPromptPolicy({
    this.validator = PayPalUrlValidator.isValidPayPalUrl,
  });

  /// The HTTPS URL validator. Defaults to [PayPalUrlValidator.isValidPayPalUrl].
  final bool Function(String? url) validator;

  /// Evaluates whether to show a support prompt after an export.
  ///
  /// Returns [SupportPromptKind.initial] or [SupportPromptKind.reminder] if
  /// eligible, or `null` if no prompt should be displayed.
  SupportPromptKind? shouldPrompt({
    required SupportPromptState state,
    required bool exportSucceeded,
    required bool isChannelEligible,
    required String? supportUrl,
  }) {
    // Fail closed for any inconsistent state (whether manually constructed or deserialized)
    if (!state.isConsistent) return null;

    // 0. Hard prompt count cap: promptCount 0..2
    if (state.promptCount >= 2) return null;

    // 1. Never prompt if reminder was already shown (FR-SUP-02)
    if (state.reminderShown) return null;

    // 2. Export check: Never show on failed or cancelled export (FR-SUP-01).
    if (!exportSucceeded) return null;

    // 3. Channel check: Only reviewed eligible channels (FR-SUP-03).
    if (!isChannelEligible) return null;

    // 4. Link check: No valid public HTTPS link means no active prompt (FR-SUP-03).
    if (!validator(supportUrl)) return null;

    // 5. Persistence check: Dismissed permanently or already clicked gift.
    if (state.dismissedPermanently || state.giftClicked) return null;

    // 6. Initial prompt: First eligible successful export (FR-SUP-02).
    // Prompt count must be 0 and initialPromptShown must be false.
    if (!state.initialPromptShown && state.promptCount == 0) {
      return SupportPromptKind.initial;
    }

    // 7. Reminder prompt: Exactly one neutral reminder if user chose "Maybe later" (FR-SUP-02).
    // Prompt count must be 1, reminderEligible must be true, reminderShown must be false,
    // and lastDecision must strictly be maybeLater.
    if (state.reminderEligible &&
        !state.reminderShown &&
        state.promptCount == 1 &&
        state.lastDecision?.type == SupportPromptDecisionType.maybeLater) {
      return SupportPromptKind.reminder;
    }

    // 8. No repeat after reminder or already 2.
    return null;
  }

  /// Convenience wrapper using [SupportDistributionChannel].
  SupportPromptKind? shouldPromptForChannel({
    required SupportPromptState state,
    required bool exportSucceeded,
    required SupportDistributionChannel channel,
    required String? supportUrl,
  }) {
    return shouldPrompt(
      state: state,
      exportSucceeded: exportSucceeded,
      isChannelEligible: channel.isExternalLinkAllowed,
      supportUrl: supportUrl,
    );
  }
}
