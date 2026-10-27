import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../domain/models/activity.dart';

/// A short status pill indicating an activity's recording or export state
/// (DESIGN_GUIDE StatusPill).
///
/// Ensures status never relies solely on colour: every state has dedicated text
/// and an explicit icon/dot indicator.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.isOnNavy = false});

  final StatusPillStatus status;

  /// Whether this pill sits on a navy surface (such as the live recording screen).
  ///
  /// On cream or light surfaces, `recording` uses a navy pill with a lime dot
  /// and cream text to ensure high contrast and comply with the brand rule:
  /// "Never a lime mark on cream."
  final bool isOnNavy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();

    Color fill;
    Color textColor;
    Border? border;
    Widget? leadingIcon;

    switch (status) {
      case StatusPillStatus.recording:
        if (isOnNavy) {
          fill = attenlume?.live ?? const Color(0xFFDCFF38);
          textColor = attenlume?.onLive ?? const Color(0xFF00212B);
          leadingIcon = Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: textColor, shape: BoxShape.circle),
          );
        } else {
          fill = const Color(0xFF00212B);
          textColor = attenlume?.onBrandLarge ?? const Color(0xFFFEFFF8);
          leadingIcon = Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: attenlume?.live ?? const Color(0xFFDCFF38),
              shape: BoxShape.circle,
            ),
          );
        }
        break;

      case StatusPillStatus.paused:
        fill = Colors.transparent;
        textColor = theme.colorScheme.onSurface;
        border = Border.all(color: theme.colorScheme.outline, width: 1.5);
        leadingIcon = Icon(Icons.pause_rounded, size: 12, color: textColor);
        break;

      case StatusPillStatus.interrupted:
        fill = Colors.transparent;
        textColor = theme.colorScheme.onSurface;
        border = Border.all(color: theme.colorScheme.outline, width: 1.5);
        leadingIcon = Icon(
          Icons.phone_disabled_rounded,
          size: 12,
          color: textColor,
        );
        break;

      case StatusPillStatus.saved:
      case StatusPillStatus.exported:
      case StatusPillStatus.verified:
        fill = attenlume?.success ?? const Color(0xFF1B8755);
        textColor = attenlume?.onSuccess ?? Colors.white;
        leadingIcon = Icon(Icons.check_rounded, size: 12, color: textColor);
        break;

      case StatusPillStatus.private:
        fill = Colors.transparent;
        textColor = theme.colorScheme.onSurface;
        border = Border.all(color: theme.colorScheme.outline, width: 1.5);
        leadingIcon = Icon(
          Icons.lock_outline_rounded,
          size: 12,
          color: textColor,
        );
        break;

      case StatusPillStatus.draft:
        fill = Colors.transparent;
        textColor = theme.colorScheme.onSurfaceVariant;
        border = Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 1.0,
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(
          Radius.circular(TokenRadius.radiusPill),
        ),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leadingIcon != null) ...[
            leadingIcon,
            const SizedBox(width: TokenSpace.space1),
          ],
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
