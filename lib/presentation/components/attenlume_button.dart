import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';

/// Emphasis levels for Attenlume buttons (DESIGN_GUIDE Button).
enum AttenlumeButtonVariant {
  /// Brand fill with cream 19px Semibold label. One per screen, full width on phones.
  primary,

  /// Transparent with 1.5px border and ink label.
  secondary,

  /// Text only in ink, for low-emphasis actions.
  ghost,

  /// Danger fill with on-danger label. For destructive actions.
  danger,
}

/// Standard button for actions outside recording controls (DESIGN_GUIDE Button).
class AttenlumeButton extends StatelessWidget {
  const AttenlumeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AttenlumeButtonVariant.primary,
    this.leading,
    this.disabled = false,
    this.disabledReason,
    this.isFullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AttenlumeButtonVariant variant;
  final Widget? leading;
  final bool disabled;
  final String? disabledReason;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();
    final isEnabled = !disabled && onPressed != null;

    final Widget buttonWidget;

    final cream = attenlume?.onBrandLarge ?? const Color(0xFFFEFFF8);

    switch (variant) {
      case AttenlumeButtonVariant.primary:
        buttonWidget = ElevatedButton(
          onPressed: isEnabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: cream,
            disabledBackgroundColor: theme.colorScheme.primary.withValues(
              alpha: 0.38,
            ),
            disabledForegroundColor: cream.withValues(alpha: 0.38),
            minimumSize: Size(isFullWidth ? double.infinity : 0, 52),
            padding: const EdgeInsets.symmetric(
              vertical: TokenSpace.space3,
              horizontal: TokenSpace.space5,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(TokenRadius.radiusMd),
              ),
            ),
            elevation: 0,
          ),
          child: _buildContent(
            context,
            TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: isEnabled ? cream : cream.withValues(alpha: 0.38),
            ),
          ),
        );
        break;

      case AttenlumeButtonVariant.secondary:
        buttonWidget = OutlinedButton(
          onPressed: isEnabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(
              color: isEnabled
                  ? theme.colorScheme.outline
                  : theme.colorScheme.outlineVariant,
              width: 1.5,
            ),
            minimumSize: Size(isFullWidth ? double.infinity : 0, 52),
            padding: const EdgeInsets.symmetric(
              vertical: TokenSpace.space3,
              horizontal: TokenSpace.space5,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(TokenRadius.radiusMd),
              ),
            ),
          ),
          child: _buildContent(
            context,
            TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isEnabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        );
        break;

      case AttenlumeButtonVariant.ghost:
        buttonWidget = TextButton(
          onPressed: isEnabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            minimumSize: const Size(0, TokenSize.tapMin),
            padding: const EdgeInsets.symmetric(
              vertical: TokenSpace.space2,
              horizontal: TokenSpace.space3,
            ),
          ),
          child: _buildContent(
            context,
            TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isEnabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        );
        break;

      case AttenlumeButtonVariant.danger:
        buttonWidget = ElevatedButton(
          onPressed: isEnabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            minimumSize: Size(isFullWidth ? double.infinity : 0, 52),
            padding: const EdgeInsets.symmetric(
              vertical: TokenSpace.space3,
              horizontal: TokenSpace.space5,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(TokenRadius.radiusMd),
              ),
            ),
            elevation: 0,
          ),
          child: _buildContent(
            context,
            TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onError,
            ),
          ),
        );
        break;
    }

    if (disabled && disabledReason != null) {
      return Column(
        crossAxisAlignment: isFullWidth
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          buttonWidget,
          const SizedBox(height: TokenSpace.space1),
          Text(
            disabledReason!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: isFullWidth ? TextAlign.start : TextAlign.center,
          ),
        ],
      );
    }

    return buttonWidget;
  }

  Widget _buildContent(BuildContext context, TextStyle textStyle) {
    if (leading == null) {
      return Text(label, style: textStyle);
    }
    return Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        leading!,
        const SizedBox(width: TokenSpace.space2),
        Text(label, style: textStyle),
      ],
    );
  }
}
