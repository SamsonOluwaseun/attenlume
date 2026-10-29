import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../../shared/utilities/date_formatters.dart';
import '../capture/recording_providers.dart';

/// Counts and cover photo for every conference card, keyed by conference ID
/// (FR-UI-10, ADR-052) [P1-39]. Invalidated with the conference list.
final conferenceCardInfoProvider =
    FutureProvider<Map<String, ConferenceCardInfo>>(
      (ref) => ref.watch(conferenceRepositoryProvider).cardInfo(),
    );

/// The media root used to show cover photos, or null when it cannot be
/// found. Only read when a card has a cover, so a list with no photos does
/// no file work.
final conferenceCoverRootProvider = FutureProvider<Directory?>((ref) async {
  try {
    return await ref.watch(mediaRootProvider)();
  } on Object {
    return null;
  }
});

/// Text for the counts line: "3 activities · 12 photos".
String conferenceCountsLabel(ConferenceCardInfo info) {
  String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  return '${plural(info.activityCount, 'activity', 'activities')} · '
      '${plural(info.photoCount, 'photo', 'photos')}';
}

/// One conference on My conferences, as on the screens board: cover photo,
/// name, place, dates, counts and a chevron (FR-UI-10, ADR-052) [P1-39].
///
/// The whole card is one button for screen readers, read as one label
/// (NFR-09, ADR-050).
class ConferenceCard extends StatelessWidget {
  const ConferenceCard({
    super.key,
    required this.conference,
    required this.info,
    required this.onTap,
  });

  final Conference conference;
  final ConferenceCardInfo info;
  final VoidCallback onTap;

  static const coverSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final venue = conference.venue?.trim() ?? '';
    final dates = formatDateRange(conference.startDate, conference.endDate);
    final counts = conferenceCountsLabel(info);

    Widget meta(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: TokenSpace.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: muted),
          ),
          const SizedBox(width: TokenSpace.space1),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: [
        conference.name,
        if (venue.isNotEmpty) venue,
        dates,
        counts,
      ].join(', '),
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: TokenSpace.space3),
        child: InkWell(
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusMd),
          ),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TokenSize.tapMin),
            child: Padding(
              padding: const EdgeInsets.all(TokenSpace.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ConferenceCover(
                    key: Key('conference-cover-${conference.id}'),
                    relativePath: info.coverPhotoPath,
                  ),
                  const SizedBox(width: TokenSpace.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conference.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (venue.isNotEmpty)
                          meta(Icons.location_on_outlined, venue),
                        meta(Icons.calendar_today_outlined, dates),
                        meta(Icons.photo_library_outlined, counts),
                      ],
                    ),
                  ),
                  const SizedBox(width: TokenSpace.space1),
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's cover: the conference's first photo, or a branded placeholder
/// when there is none or it cannot be read. Never a network image.
class ConferenceCover extends ConsumerWidget {
  const ConferenceCover({super.key, required this.relativePath});

  final String? relativePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = relativePath;
    final root = path == null
        ? null
        : ref.watch(conferenceCoverRootProvider).asData?.value;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const size = ConferenceCard.coverSize;

    return ClipRRect(
      borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
      child: SizedBox.square(
        dimension: size,
        child: path == null || root == null
            ? const _CoverPlaceholder()
            : Image.file(
                MediaPaths.resolve(root, path),
                key: const Key('conference-cover-photo'),
                fit: BoxFit.cover,
                cacheWidth: (size * dpr).round(),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const _CoverPlaceholder(),
              ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // brand-tint with an ink icon (3:1 or more in both themes).
    return ColoredBox(
      key: const Key('conference-cover-placeholder'),
      color: scheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.event_outlined,
          size: TokenSize.iconMd,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
