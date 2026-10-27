import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/profile_estimates.dart';
import '../../domain/services/storage_thresholds.dart';

/// Shows free space and recording time left at the current quality,
/// with staged warnings so the user is never surprised by a full device
/// (DESIGN_GUIDE StorageMeter, FR-UI-07, FR-STO-01, FR-STO-02).
class StorageMeter extends StatelessWidget {
  const StorageMeter({
    super.key,
    required this.freeBytes,
    required this.minutesLeft,
    required this.profile,
    required this.level,
    this.totalBytes,
    this.conferenceBytes,
    this.compact = false,
    this.onManage,
  });

  /// Bytes free on the storage volume (null when unknown).
  final int? freeBytes;

  /// Total capacity of the storage volume in bytes (null when unknown).
  final int? totalBytes;

  /// Whole minutes of recording left before hitting the hard reserve.
  /// Computed from measured file growth where available (FR-STO-01).
  final int? minutesLeft;

  /// The quality profile in use.
  final RecordingProfile profile;

  /// Storage status level (ok, warning, urgent, hardStop).
  final StorageLevel level;

  /// Bytes used by the current conference (FR-UI-07).
  final int? conferenceBytes;

  /// On the recording screen, shrinks to one muted line under the timer
  /// and only grows into a banner at low or critical (DESIGN_GUIDE StorageMeter).
  final bool compact;

  /// Optional callback to open storage management / cleanup.
  final VoidCallback? onManage;

  /// Formats byte counts into human-readable strings (e.g. "14.2 GB", "350 MB").
  static String formatBytes(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  /// Builds the primary sentence leading with time (DESIGN_GUIDE StorageMeter).
  static String leadSentence(int? minutes, RecordingProfile profile) {
    if (minutes == null) return 'Space left unknown';
    if (minutes <= 0) return 'No space left at ${profile.label}';
    final formatted = formatTimeLeft(minutes).replaceAll(' left', '');
    return '$formatted left at ${profile.label}';
  }

  @override
  Widget build(BuildContext context) {
    final attenlume = Theme.of(context).extension<AttenlumeColors>();

    if (compact) {
      return _buildCompact(context, attenlume);
    }
    return _buildExpanded(context, attenlume);
  }

  /// Compact presentation for the recording screen: one muted line when OK,
  /// growing into a banner at warning or critical.
  Widget _buildCompact(BuildContext context, AttenlumeColors? attenlume) {
    if (level == StorageLevel.ok) {
      final timeText = leadSentence(minutesLeft, profile);
      final freeText = '${formatBytes(freeBytes)} free';
      final label = '$timeText • $freeText';

      return Semantics(
        label: 'Storage budget: $label',
        child: Text(
          label,
          key: const Key('storage-meter-compact-ok'),
          style: TextStyle(
            fontFamily: TokenType.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8),
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // At low or critical, it grows into a staged banner.
    return _buildBanner(context, attenlume);
  }

  /// Full presentation for storage manager cards and detailed sheets.
  Widget _buildExpanded(BuildContext context, AttenlumeColors? attenlume) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final leadText = leadSentence(minutesLeft, profile);
    final freeText = '${formatBytes(freeBytes)} free';
    final totalText = totalBytes != null
        ? ' of ${formatBytes(totalBytes)}'
        : '';
    final confText = conferenceBytes != null && conferenceBytes! > 0
        ? ' • ${formatBytes(conferenceBytes)} in this conference'
        : '';

    final usedRatio =
        (totalBytes != null && freeBytes != null && totalBytes! > 0)
        ? ((totalBytes! - freeBytes!) / totalBytes!).clamp(0.0, 1.0)
        : null;

    final barColor = switch (level) {
      StorageLevel.ok => colorScheme.primary,
      StorageLevel.warning => attenlume?.warningFill ?? const Color(0xFFFFF4C2),
      StorageLevel.urgent || StorageLevel.hardStop => colorScheme.error,
    };

    return Semantics(
      container: true,
      label: 'Storage budget: $leadText, $freeText$totalText$confText',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  leadText,
                  key: const Key('storage-meter-lead-text'),
                  style: TextStyle(
                    fontFamily: TokenType.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (onManage != null)
                TextButton(
                  key: const Key('storage-meter-manage-button'),
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TokenSpace.space2,
                      vertical: TokenSpace.space1,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Manage',
                    style: TextStyle(
                      fontFamily: TokenType.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TokenSpace.space2),
          // Progress bar track
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: const BorderRadius.all(
                Radius.circular(TokenRadius.radiusSm),
              ),
            ),
            child: usedRatio != null
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: constraints.maxWidth * usedRatio,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(TokenRadius.radiusSm),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : null,
          ),
          const SizedBox(height: TokenSpace.space1),
          Text(
            '$freeText$totalText$confText',
            key: const Key('storage-meter-subtext'),
            style: TextStyle(
              fontFamily: TokenType.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (level != StorageLevel.ok) ...[
            const SizedBox(height: TokenSpace.space3),
            _buildBanner(context, attenlume),
          ],
        ],
      ),
    );
  }

  /// Warning / Critical banner with explicit sentences (never colour alone).
  Widget _buildBanner(BuildContext context, AttenlumeColors? attenlume) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (bgColor, textColor, icon, mainText, subText, key) = switch (level) {
      StorageLevel.warning => (
        attenlume?.warningFill ?? const Color(0xFFFFF4C2),
        const Color(0xFF00212B),
        Icons.warning_amber_rounded,
        'Running low. Export or free space soon.',
        '${formatTimeLeft(minutesLeft)} (${formatBytes(freeBytes)} free)',
        const Key('storage-meter-banner-warning'),
      ),
      StorageLevel.urgent => (
        colorScheme.error,
        colorScheme.onError,
        Icons.error_outline_rounded,
        'Storage nearly full. Recording will stop safely.',
        '${formatTimeLeft(minutesLeft)} (${formatBytes(freeBytes)} free)',
        const Key('storage-meter-banner-urgent'),
      ),
      StorageLevel.hardStop => (
        colorScheme.error,
        colorScheme.onError,
        Icons.report_problem_rounded,
        'Storage nearly full. Recording stopped and saved.',
        '${formatBytes(freeBytes)} free (hard reserve reached)',
        const Key('storage-meter-banner-hard-stop'),
      ),
      StorageLevel.ok => (
        Colors.transparent,
        Colors.transparent,
        Icons.check_circle_outline,
        '',
        '',
        const Key('storage-meter-banner-ok'),
      ),
    };

    return Semantics(
      container: true,
      label: '$mainText $subText',
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpace.space3,
          vertical: TokenSpace.space2,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusMd),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: textColor),
            const SizedBox(width: TokenSpace.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mainText,
                    style: TextStyle(
                      fontFamily: TokenType.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  if (subText.isNotEmpty)
                    Text(
                      subText,
                      style: TextStyle(
                        fontFamily: TokenType.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textColor.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
