import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import 'status_pill.dart';

/// Maps an activity type icon string to rounded Material [IconData].
IconData activityTypeIconData(String? iconKey) {
  switch (iconKey) {
    case 'presentation':
      return Icons.slideshow_rounded;
    case 'mic':
      return Icons.mic_rounded;
    case 'users':
      return Icons.groups_rounded;
    case 'messages-square':
      return Icons.forum_rounded;
    case 'hammer':
      return Icons.build_rounded;
    case 'store':
      return Icons.store_rounded;
    case 'handshake':
      return Icons.handshake_rounded;
    case 'contact':
      return Icons.people_rounded;
    case 'lightbulb':
      return Icons.lightbulb_rounded;
    case 'tag':
      return Icons.label_rounded;
    case 'sparkles':
      return Icons.auto_awesome_rounded;
    case 'coffee':
      return Icons.coffee_rounded;
    case 'camera':
      return Icons.camera_alt_rounded;
    case 'school':
      return Icons.school_rounded;
    case 'folder':
      return Icons.folder_rounded;
    case 'book':
      return Icons.menu_book_rounded;
    case 'chat':
      return Icons.chat_bubble_outline_rounded;
    case 'help':
      return Icons.help_outline_rounded;
    default:
      return Icons.label_rounded;
  }
}

/// One activity in a conference timeline (DESIGN_GUIDE ActivityCard, FR-ACT-03).
///
/// Displays type, title, time, location, recording state, duration, asset counts
/// and effective recording profile.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.typeLabel,
    required this.typeIcon,
    required this.title,
    required this.startTime,
    this.location,
    required this.status,
    required this.duration,
    required this.photoCount,
    required this.bookmarkCount,
    required this.profile,
    this.isPrivate = false,
    this.onOpen,
  });

  /// Factory creating an [ActivityCard] from an [ActivitySummary].
  factory ActivityCard.fromSummary({
    Key? key,
    required ActivitySummary summary,
    required String formattedStartTime,
    required String formattedDuration,
    VoidCallback? onOpen,
  }) {
    return ActivityCard(
      key: key,
      typeLabel: summary.type.label,
      typeIcon: summary.type.icon,
      title: summary.activity.title,
      startTime: formattedStartTime,
      location: summary.activity.room,
      status: summary.statusPillStatus,
      duration: formattedDuration,
      photoCount: summary.photoCount,
      bookmarkCount: summary.bookmarkCount,
      profile: summary.effectiveProfile,
      isPrivate: summary.activity.isPrivate,
      onOpen: onOpen,
    );
  }

  final String typeLabel;
  final String typeIcon;
  final String title;
  final String startTime;
  final String? location;
  final StatusPillStatus status;
  final String duration;
  final int photoCount;
  final int bookmarkCount;
  final RecordingProfile profile;
  final bool isPrivate;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inkMuted = theme.colorScheme.onSurfaceVariant;

    // Row 3 metadata: "09:30 · Hall A · 47 min"
    final metadataParts = <String>[
      startTime,
      if (location != null && location!.trim().isNotEmpty) location!.trim(),
      duration,
    ];
    final metadataText = metadataParts.join(' · ');

    // Everything the card shows, in reading order (NFR-09).
    final semanticLabel = [
      title,
      typeLabel,
      if (isPrivate) 'Private',
      status.label,
      metadataText,
      if (photoCount > 0) '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
      if (bookmarkCount > 0)
        '$bookmarkCount ${bookmarkCount == 1 ? 'bookmark' : 'bookmarks'}',
      profile.label,
    ].join(', ');

    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: semanticLabel,
      onTap: onOpen,
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.all(
          Radius.circular(TokenRadius.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusMd),
          ),
          child: Container(
            padding: const EdgeInsets.all(TokenSpace.space4),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              borderRadius: const BorderRadius.all(
                Radius.circular(TokenRadius.radiusMd),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Type label + optional Private lock + StatusPill.
                // Wraps instead of overflowing at large text (NFR-09).
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: TokenSpace.space2,
                  runSpacing: TokenSpace.space1,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: TokenSpace.space2,
                      runSpacing: TokenSpace.space1,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              activityTypeIconData(typeIcon),
                              size: 16,
                              color: inkMuted,
                            ),
                            const SizedBox(width: TokenSpace.space1),
                            Flexible(
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isPrivate)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 13,
                                color: inkMuted,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  'Private',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: inkMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    StatusPill(status: status),
                  ],
                ),

                const SizedBox(height: TokenSpace.space2),

                // Row 2: Title in heading (Montserrat Semibold 20px, max 2 lines, then truncate)
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: TokenSpace.space2),

                // Row 3: Metadata in body-small ink-muted ("09:30 · Hall A · 47 min")
                Text(
                  metadataText,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: inkMuted,
                  ),
                ),

                const SizedBox(height: TokenSpace.space3),

                // Row 4: Counts (camera 12, bookmark 4) and recording profile.
                // Wraps instead of overflowing at large text (NFR-09).
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: TokenSpace.space3,
                  runSpacing: TokenSpace.space1,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: TokenSpace.space3,
                      runSpacing: TokenSpace.space1,
                      children: [
                        if (photoCount > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 15,
                                color: inkMuted,
                              ),
                              const SizedBox(width: TokenSpace.space1),
                              Text(
                                '$photoCount',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: inkMuted,
                                ),
                              ),
                            ],
                          ),
                        if (bookmarkCount > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bookmark_outline_rounded,
                                size: 15,
                                color: inkMuted,
                              ),
                              const SizedBox(width: TokenSpace.space1),
                              Text(
                                '$bookmarkCount',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: inkMuted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(TokenRadius.radiusPill),
                        ),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        profile.label,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
