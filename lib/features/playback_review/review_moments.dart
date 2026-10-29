import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../data/filesystem/media_paths.dart';
import '../../domain/models/media.dart';
import '../../domain/services/review_timeline.dart';
import '../../shared/utilities/date_formatters.dart';

/// One row of the Key moments list.
class KeyMoment {
  const KeyMoment({
    required this.id,
    required this.kind,
    required this.offsetMs,
    required this.label,
    this.photo,
    this.thumbnail,
  });

  /// Marker id, or `start` for the session start row.
  final String id;

  /// Null for the session start row.
  final TimelineMarkerKind? kind;
  final int offsetMs;
  final String label;

  /// The photo itself, for photo moments.
  final Photo? photo;

  /// What the row shows as its picture: the photo, or for a bookmark the
  /// last photo taken at or before it (the slide on screen then).
  final Photo? thumbnail;

  String get kindName => switch (kind) {
    TimelineMarkerKind.photo => 'Photo',
    TimelineMarkerKind.bookmark => 'Bookmark',
    _ => 'Start',
  };
}

/// Bookmarks and photos in time order, after a "Session start" row when
/// there is audio (DESIGN_GUIDE "Key moments") [P1-39].
List<KeyMoment> keyMoments(ReviewTimeline timeline, List<Photo> photos) {
  final byId = {for (final p in photos) p.id: p};
  final moments = <KeyMoment>[
    if (timeline.hasAudio)
      KeyMoment(
        id: 'start',
        kind: null,
        offsetMs: timeline.segments.first.startMs,
        label: 'Session start',
      ),
  ];
  Photo? lastPhoto;
  for (final m in timeline.markers) {
    switch (m.kind) {
      case TimelineMarkerKind.interruption:
        continue;
      case TimelineMarkerKind.photo:
        final photo = byId[m.id];
        if (photo != null) lastPhoto = photo;
        // The current photo row wins over the marker, so a cleared caption
        // stays cleared without rebuilding the timeline.
        final text = photo == null ? m.label : photo.caption ?? photo.label;
        moments.add(
          KeyMoment(
            id: m.id,
            kind: m.kind,
            offsetMs: m.offsetMs,
            label: text == null || text.isEmpty ? 'Photo' : text,
            photo: photo,
            thumbnail: photo,
          ),
        );
      case TimelineMarkerKind.bookmark:
        final text = m.label;
        moments.add(
          KeyMoment(
            id: m.id,
            kind: m.kind,
            offsetMs: m.offsetMs,
            label: text == null || text.isEmpty ? 'Bookmark' : text,
            thumbnail: lastPhoto,
          ),
        );
    }
  }
  return moments;
}

/// A small local thumbnail, or an icon tile when there is no photo or it
/// cannot be read. Decorative: rows carry their own labels.
class MomentThumbnail extends StatelessWidget {
  const MomentThumbnail({
    super.key,
    required this.photo,
    required this.root,
    required this.icon,
    this.width = 72,
    this.height = 54,
  });

  final Photo? photo;
  final Directory? root;
  final IconData icon;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fallback = ColoredBox(
      color: scheme.surfaceContainer,
      child: Center(child: Icon(icon, color: scheme.onSurfaceVariant)),
    );
    final photo = this.photo;
    final root = this.root;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
        child: SizedBox(
          width: width,
          height: height,
          child: photo == null || root == null
              ? fallback
              : Image.file(
                  MediaPaths.resolve(
                    root,
                    photo.thumbnailPath ?? photo.filePath,
                  ),
                  fit: BoxFit.cover,
                  // Decode at display size only (FR-PHO-03).
                  cacheWidth: (width * dpr).round(),
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

enum _MomentAction { play, timeline, photo }

/// The Highlights tab: Key moments with time, label, picture and a menu.
/// Tapping a row plays from that moment (FR-REV-01, FR-BMK-01) [P1-39].
class ReviewHighlights extends StatelessWidget {
  const ReviewHighlights({
    super.key,
    required this.moments,
    required this.root,
    required this.canPlay,
    required this.onSeek,
    required this.onPlayFrom,
    required this.onShowOnTimeline,
    required this.onOpenPhoto,
  });

  final List<KeyMoment> moments;
  final Directory? root;
  final bool canPlay;

  /// Moves the playhead (a row tap).
  final ValueChanged<int> onSeek;

  /// Moves the playhead and starts playback ("Play from here").
  final ValueChanged<int> onPlayFrom;
  final ValueChanged<int> onShowOnTimeline;
  final ValueChanged<Photo> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final marked = moments.where((m) => m.kind != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          child: Text('Key moments', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: TokenSpace.space2),
        if (marked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: TokenSpace.space2),
            child: Text(
              'No bookmarks or photos in this activity.',
              key: const Key('review-no-moments'),
              style: muted,
            ),
          ),
        for (final m in moments) _row(context, m, muted),
      ],
    );
  }

  Widget _row(BuildContext context, KeyMoment m, TextStyle? muted) {
    final theme = Theme.of(context);
    final time = formatOffset(m.offsetMs);
    final photo = m.photo;
    return Padding(
      key: Key('review-moment-${m.id}'),
      padding: const EdgeInsets.symmetric(vertical: TokenSpace.space1),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              button: canPlay,
              label: '${m.kindName} at $time: ${m.label}',
              hint: canPlay ? 'Moves the playhead here' : null,
              // Keeps the tap for screen readers: excludeSemantics drops
              // the InkWell's own action.
              onTap: canPlay ? () => onSeek(m.offsetMs) : null,
              excludeSemantics: true,
              child: InkWell(
                onTap: canPlay ? () => onSeek(m.offsetMs) : null,
                borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: TokenSize.tapMin,
                  ),
                  child: Row(
                    children: [
                      MomentThumbnail(
                        photo: m.thumbnail,
                        root: root,
                        icon: switch (m.kind) {
                          TimelineMarkerKind.photo =>
                            Icons.photo_camera_outlined,
                          TimelineMarkerKind.bookmark => Icons.bookmark_rounded,
                          _ => Icons.play_circle_outline_rounded,
                        },
                      ),
                      const SizedBox(width: TokenSpace.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              time,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(m.label, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<_MomentAction>(
            key: Key('review-moment-menu-${m.id}'),
            tooltip: 'More for ${m.label}',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => switch (action) {
              _MomentAction.play => onPlayFrom(m.offsetMs),
              _MomentAction.timeline => onShowOnTimeline(m.offsetMs),
              _MomentAction.photo => onOpenPhoto(photo!),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _MomentAction.play,
                enabled: canPlay,
                child: const Text('Play from here'),
              ),
              const PopupMenuItem(
                value: _MomentAction.timeline,
                child: Text('Show on timeline'),
              ),
              if (photo != null)
                const PopupMenuItem(
                  value: _MomentAction.photo,
                  child: Text('View photo'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Photos tab: every photo of the activity, with its time. Tap a
/// photo to view it and edit its caption and label (FR-PHO-06); the play
/// button plays from the moment it was taken [P1-39].
class ReviewPhotos extends StatelessWidget {
  const ReviewPhotos({
    super.key,
    required this.photos,
    required this.offsets,
    required this.root,
    required this.canPlay,
    required this.onPlayFrom,
    required this.onOpenPhoto,
  });

  final List<Photo> photos;

  /// Timeline offset of each photo by id; missing when it has none.
  final Map<String, int> offsets;
  final Directory? root;
  final bool canPlay;
  final ValueChanged<int> onPlayFrom;
  final ValueChanged<Photo> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Semantics(
      container: true,
      header: true,
      child: Text(
        photos.isEmpty ? 'Photos' : 'Photos (${photos.length})',
        style: theme.textTheme.titleLarge,
      ),
    );
    if (photos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: TokenSpace.space2),
          Text(
            'No photos in this activity. Photos you take while recording, '
            'or import from the activity details, show here.',
            key: const Key('review-no-photos'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 600 ? 4 : 2;
        const gap = TokenSpace.space3;
        final tile = (width - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: TokenSpace.space2),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final p in photos)
                  SizedBox(
                    width: tile,
                    child: _PhotoTile(
                      key: Key('review-photo-${p.id}'),
                      photo: p,
                      offsetMs: offsets[p.id],
                      root: root,
                      width: tile,
                      canPlay: canPlay,
                      onPlayFrom: onPlayFrom,
                      onOpen: () => onOpenPhoto(p),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.photo,
    required this.offsetMs,
    required this.root,
    required this.width,
    required this.canPlay,
    required this.onPlayFrom,
    required this.onOpen,
  });

  final Photo photo;
  final int? offsetMs;
  final Directory? root;
  final double width;
  final bool canPlay;
  final ValueChanged<int> onPlayFrom;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = photo.caption ?? photo.label;
    final offset = offsetMs;
    final time = offset == null ? null : formatOffset(offset);
    final name = ['Photo', if (time != null) 'at $time'].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          label: caption == null ? name : '$name: $caption',
          hint: 'Opens the photo',
          onTap: onOpen,
          excludeSemantics: true,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
            child: MomentThumbnail(
              photo: photo,
              root: root,
              icon: Icons.photo_camera_outlined,
              width: width,
              height: width * 3 / 4,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                [?time, ?caption].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (offset != null)
              IconButton(
                key: Key('review-photo-play-${photo.id}'),
                tooltip: 'Play from $time',
                onPressed: canPlay ? () => onPlayFrom(offset) : null,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
          ],
        ),
      ],
    );
  }
}
