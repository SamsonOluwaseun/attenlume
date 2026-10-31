import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../presentation/components/attenlume_button.dart';
import 'support_prompt_policy.dart';

/// Shows the optional post-export voluntary support prompt dialog (FR-SUP-01, FR-SUP-02).
///
/// Returns a [SupportPromptDecision] reflecting user choice, or `null` if dismissed.
Future<SupportPromptDecision?> showSupportPrompt(
  BuildContext context,
  SupportPromptKind kind,
) {
  return SupportPromptDialog.show(context, kind: kind);
}

/// Accessible voluntary support dialog (FR-SUP-01, FR-SUP-02, ADR-065).
///
/// Features:
/// - UK English phrasing with zero guilt or pressure.
/// - Clarifies that user files are completely theirs whether they give or not.
/// - Declarative suggested amounts (£2, £5, £10) without fake checkout enforcement.
/// - Safe at 200% text scale in both light and dark themes.
class SupportPromptDialog extends StatefulWidget {
  const SupportPromptDialog({
    super.key,
    required this.kind,
  });

  final SupportPromptKind kind;

  /// Shows the dialog. Returns the chosen [SupportPromptDecision], or null if dismissed.
  static Future<SupportPromptDecision?> show(
    BuildContext context, {
    required SupportPromptKind kind,
  }) {
    return showDialog<SupportPromptDecision>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SupportPromptDialog(kind: kind),
    );
  }

  @override
  State<SupportPromptDialog> createState() => _SupportPromptDialogState();
}

class _SupportPromptDialogState extends State<SupportPromptDialog> {
  SupportGiftAmount? _selectedAmount;

  static const String initialMessage =
      'Your export is ready. Enjoying Attenlume? An optional gift helps us '
      'improve it and cover app-store costs. Your files are yours whether you give or not.';

  static const String reminderMessage =
      'Enjoying Attenlume? You can support its development with an optional gift.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInitial = widget.kind == SupportPromptKind.initial;
    final message = isInitial ? initialMessage : reminderMessage;

    return AlertDialog(
      key: const Key('support-prompt-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      icon: Icon(
        Icons.favorite_outline_rounded,
        size: 36,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'Support Attenlume',
        key: const Key('support-prompt-title'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                key: const Key('support-prompt-message'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TokenSpace.space3),
              Semantics(
                label: 'Suggested gift amount',
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: TokenSpace.space2,
                  runSpacing: TokenSpace.space2,
                  children: [
                    for (final amount in SupportGiftAmount.values)
                      ChoiceChip(
                        key: Key('support-amount-${amount.pounds}'),
                        label: Text(amount.label),
                        selected: _selectedAmount == amount,
                        onSelected: (selected) {
                          setState(() {
                            _selectedAmount = selected ? amount : null;
                          });
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: TokenSpace.space4),
              AttenlumeButton(
                key: const Key('support-prompt-gift-now'),
                label: 'Gift now',
                leading: const Icon(Icons.open_in_new_rounded),
                onPressed: () => Navigator.of(context).pop(
                  SupportPromptDecision.giftNow(_selectedAmount),
                ),
              ),
              const SizedBox(height: TokenSpace.space2),
              AttenlumeButton(
                key: const Key('support-prompt-maybe-later'),
                label: 'Maybe later',
                variant: AttenlumeButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(
                  const SupportPromptDecision.maybeLater(),
                ),
              ),
              const SizedBox(height: TokenSpace.space2),
              AttenlumeButton(
                key: const Key('support-prompt-dont-ask-again'),
                label: 'Don’t ask again',
                variant: AttenlumeButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(
                  const SupportPromptDecision.dontAskAgain(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
