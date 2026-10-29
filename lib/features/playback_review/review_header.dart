import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../data/filesystem/media_paths.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media.dart';
import '../../domain/services/activity_title.dart';
import '../../shared/utilities/date_formatters.dart';

/// The photo at the top of the review screen: the first photo taken in the
/// app during the activity, else the first imported one, else none
/// (ADR-053) [P1-39].
Photo? reviewHeroPhoto(List<Photo> photos) {
  if (photos.isEmpty) return null;
  final sorted = [...photos]..sort((a, b) => a.takenUtc.compareTo(b.takenUtc));
  return sorted.firstWhere(
    (p) => p.source == PhotoSource.inApp,
    orElse: () => sorted.first,
  );
}

/// "4 Nov 2026" for [utc] on the conference's calendar.
String reviewDate(DateTime utc, String timezone) {
  final local = toConferenceTime(utc, timezone);
  return formatDateShort(DateTime.utc(local.year, local.month, local.day));
}

/// Hero photo of the session, or a branded panel when there is none. Only
/// local files: never a network image (NFR-01) [P1-39].
class ReviewHero extends StatelessWidget {
  const ReviewHero({super.key, required this.photo, required this.root});

  final Photo? photo;
  final Directory? root;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    final root = this.root;
    final caption = photo?.caption ?? photo?.label;
    return ClipRRect(
      borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: photo == null || root == null
            ? const _HeroPlaceholder(key: Key('review-hero-placeholder'))
            : Semantics(
                container: true,
                image: true,
                label: caption == null
                    ? 'First photo of this session'
                    : 'First photo of this session: $caption',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    return Image.file(
                      MediaPaths.resolve(root, photo.filePath),
                      key: const Key('review-hero-photo'),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      // Decode at display size only (FR-PHO-03).
                      cacheWidth: (constraints.maxWidth * dpr).round(),
                      errorBuilder: (_, _, _) => const _HeroPlaceholder(),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// Brand-blue panel with a sound-wave mark, for sessions without photos.
class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AttenlumeColors>()!;
    return ExcludeSemantics(
      child: ColoredBox(
        color: colors.surfaceBrand,
        child: Center(
          child: Icon(
            Icons.graphic_eq_rounded,
            size: TokenSpace.space7,
            // on-brand (navy) in both themes: surface-brand is blue in both.
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
      ),
    );
  }
}

/// Title, place and date with duration under the hero (DESIGN_GUIDE
/// "Session review") [P1-39].
class ReviewHeader extends StatelessWidget {
  const ReviewHeader({
    super.key,
    required this.title,
    required this.place,
    required this.date,
    required this.durationMs,
  });

  final String title;

  /// Room or stage and conference, already joined. Hidden when empty.
  final String place;

  /// Formatted date, or null when unknown.
  final String? date;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final when = [
      ?date,
      formatDuration(Duration(milliseconds: durationMs)),
    ].join(' · ');
    Widget line(IconData icon, String text, Key key) => Padding(
      padding: const EdgeInsets.only(top: TokenSpace.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: muted?.color),
          ),
          const SizedBox(width: TokenSpace.space2),
          Expanded(
            child: Text(text, key: key, style: muted),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          child: Text(
            title.isEmpty ? 'Untitled session' : title,
            key: const Key('review-title'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (place.isNotEmpty)
          line(Icons.place_outlined, place, const Key('review-place')),
        line(Icons.event_outlined, when, const Key('review-when')),
      ],
    );
  }
}
