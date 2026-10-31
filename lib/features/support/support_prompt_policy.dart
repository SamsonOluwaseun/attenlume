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
  two(2, '£2'),
  five(5, '£5'),
  ten(10, '£10');

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
  const SupportPromptDecision({
    required this.type,
    this.selectedAmount,
  });

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

  factory SupportPromptDecision.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final type = SupportPromptDecisionType.values.firstWhere(
      (v) => v.name == typeName,
      orElse: () => SupportPromptDecisionType.dismissed,
    );
    final pounds = json['selectedAmount'] as int?;
    return SupportPromptDecision(
      type: type,
      selectedAmount: SupportGiftAmount.fromPounds(pounds),
    );
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
/// - No userinfo (passwords/usernames).
/// - No bank details or credentials.
/// - Must include a recipient path.
abstract final class PayPalUrlValidator {
  static const Set<String> allowedHosts = {
    'paypal.me',
    'www.paypal.me',
    'paypal.com',
    'www.paypal.com',
  };

  /// Validates whether [rawUrl] is a safe, public PayPal HTTPS URL.
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

    // Must have a path specifying a recipient or donate action
    if (uri.path.isEmpty || uri.path == '/') return false;

    // If port specified, must be default 443
    if (uri.hasPort && uri.port != 443) return false;

    return true;
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

  /// Total number of support prompts shown (max 2: initial + reminder).
  final int promptCount;

  /// The most recent decision made by the user, if any.
  final SupportPromptDecision? lastDecision;

  /// Rule (FR-SUP-01): Payment is never inferred from clicking a link.
  bool get paymentCompleted => false;

  /// Whether any further prompt could ever be shown under this state.
  bool get canPromptAgain =>
      !dismissedPermanently &&
      !giftClicked &&
      (!initialPromptShown || (reminderEligible && !reminderShown));

  /// Returns a new [SupportPromptState] reflecting the decision on [kind].
  SupportPromptState withDecision(
    SupportPromptKind kind,
    SupportPromptDecision? decision,
  ) {
    final effectiveDecision =
        decision ?? const SupportPromptDecision.dismissed();
    final newPromptCount = promptCount + 1;

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
            reminderShown: true,
            reminderEligible: false,
            promptCount: newPromptCount,
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
            reminderShown: true,
            reminderEligible: false,
            promptCount: newPromptCount,
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
      dismissedPermanently:
          dismissedPermanently ?? this.dismissedPermanently,
      giftClicked: giftClicked ?? this.giftClicked,
      promptCount: promptCount ?? this.promptCount,
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

  factory SupportPromptState.fromJson(Map<String, dynamic> json) {
    final decisionMap = json['lastDecision'] as Map<String, dynamic>?;
    return SupportPromptState(
      initialPromptShown: json['initialPromptShown'] as bool? ?? false,
      reminderEligible: json['reminderEligible'] as bool? ?? false,
      reminderShown: json['reminderShown'] as bool? ?? false,
      dismissedPermanently: json['dismissedPermanently'] as bool? ?? false,
      giftClicked: json['giftClicked'] as bool? ?? false,
      promptCount: json['promptCount'] as int? ?? 0,
      lastDecision: decisionMap != null
          ? SupportPromptDecision.fromJson(decisionMap)
          : null,
    );
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
    // 1. Export check: Never show on failed or cancelled export (FR-SUP-01).
    if (!exportSucceeded) return null;

    // 2. Channel check: Only reviewed eligible channels (FR-SUP-03).
    if (!isChannelEligible) return null;

    // 3. Link check: No valid public HTTPS link means no active prompt (FR-SUP-03).
    if (!validator(supportUrl)) return null;

    // 4. Persistence check: Dismissed permanently or already clicked gift.
    if (state.dismissedPermanently || state.giftClicked) return null;

    // 5. Initial prompt: First eligible successful export (FR-SUP-02).
    if (!state.initialPromptShown) {
      return SupportPromptKind.initial;
    }

    // 6. Reminder prompt: Exactly one neutral reminder if user chose "Maybe later" (FR-SUP-02).
    if (state.reminderEligible && !state.reminderShown) {
      return SupportPromptKind.reminder;
    }

    // 7. No repeat after reminder (FR-SUP-02).
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
