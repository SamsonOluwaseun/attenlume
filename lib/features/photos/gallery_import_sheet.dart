import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/services/capture_settings.dart';
import '../../domain/services/gallery_import_service.dart';
import '../../platform/gallery/folder_gallery_source.dart';
import '../../platform/gallery/gallery_source.dart';
import '../../platform/gallery/photo_manager_gallery_source.dart';
import '../../shared/utilities/date_formatters.dart';
import '../capture/recording_providers.dart';

/// The camera roll on phones, a chosen folder on Windows (ADR-035).
final gallerySourceProvider = Provider<GallerySource>(
  (ref) => ref.watch(capturePlatformProvider) == CapturePlatform.windows
      ? FolderGallerySource()
      : PhotoManagerGallerySource(),
);

final galleryImportServiceProvider = Provider<GalleryImportService>(
  (ref) => GalleryImportService(
    gallery: ref.watch(gallerySourceProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    photos: ref.watch(photoCaptureServiceProvider),
  ),
);

/// "Import photos taken during this activity" (FR-PHO-05) [P1-15].
///
/// Lists the gallery's photos from the activity's window with a margin
/// the user can change, flags likely duplicates and large files, and
/// imports only the photos the user confirms.
class GalleryImportSheet extends ConsumerStatefulWidget {
  const GalleryImportSheet({
    super.key,
    required this.activityId,
    required this.timezone,
  });

  final String activityId;
  final String timezone;

  /// Returns the import result, or null when nothing was imported.
  static Future<GalleryImportResult?> show(
    BuildContext context, {
    required String activityId,
    required String timezone,
  }) => showModalBottomSheet<GalleryImportResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        GalleryImportSheet(activityId: activityId, timezone: timezone),
  );

  static const margins = [
    Duration.zero,
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  @override
  ConsumerState<GalleryImportSheet> createState() => _GalleryImportSheetState();
}

class _GalleryImportSheetState extends ConsumerState<GalleryImportSheet> {
  final _label = TextEditingController();
  Duration _margin = GalleryImportService.defaultMargin;
  GalleryScan? _scan;
  final _selected = <String>{};
  bool _loading = true;
  bool _importing = false;

  GalleryImportService get _service => ref.read(galleryImportServiceProvider);

  @override
  void initState() {
    super.initState();
    _load(reopen: true);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reopen}) async {
    setState(() => _loading = true);
    final scan = await _service.scan(
      widget.activityId,
      margin: _margin,
      reopen: reopen,
    );
    if (!mounted) return;
    if (scan.access == GalleryAccess.cancelled) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _scan = scan;
      _loading = false;
      _selected
        ..clear()
        ..addAll([
          for (final c in scan.candidates)
            if (c.selectedByDefault) c.item.id,
        ]);
    });
  }

  void _setMargin(Duration margin) {
    if (margin == _margin) return;
    _margin = margin;
    _load(reopen: false);
  }

  List<GalleryCandidate> get _chosen => [
    for (final c in _scan?.candidates ?? const <GalleryCandidate>[])
      if (_selected.contains(c.item.id)) c,
  ];

  Future<void> _import() async {
    final chosen = _chosen;
    if (chosen.isEmpty) return;
    final duplicates = chosen.where((c) => c.duplicate).length;
    final large = chosen.where((c) => c.large).length;
    if (duplicates > 0 || large > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import anyway?'),
          content: Text(
            [
              if (duplicates > 0)
                duplicates == 1
                    ? '1 photo looks already imported.'
                    : '$duplicates photos look already imported.',
              if (large > 0)
                large == 1
                    ? '1 photo is a large file. It is resized to save space.'
                    : '$large photos are large files. They are resized to '
                          'save space.',
            ].join(' '),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('gallery-import-anyway-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _importing = true);
    final result = await _service.importItems(widget.activityId, [
      for (final c in chosen) c.item,
    ], label: _label.text);
    if (mounted) Navigator.of(context).pop(result);
  }

  String _time(DateTime utc) => formatTimeOfDayInTimezone(utc, widget.timezone);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = _scan;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Padding(
          padding: const EdgeInsets.all(TokenSpace.space4),
          child: Column(
            key: const Key('gallery-import-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Photos taken during this activity',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: TokenSpace.space2),
              if (_loading && scan == null)
                const Padding(
                  padding: EdgeInsets.all(TokenSpace.space6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (scan != null)
                ..._body(theme, scan),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(ThemeData theme, GalleryScan scan) {
    final window = scan.window;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (window == null) {
      return [
        Text(
          "This activity hasn't started yet, so there is no time window to "
          'look in. Use Import photos to pick files instead.',
          key: const Key('gallery-import-not-started'),
          style: muted,
        ),
      ];
    }
    if (scan.access == GalleryAccess.denied) {
      return [
        Text(
          "Attenlume can't see your photos. Allow photo access in Settings, "
          'then try again.',
          key: const Key('gallery-import-denied'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: TokenSpace.space3),
        OutlinedButton(
          onPressed: _service.gallery.openSettings,
          child: const Text('Open settings'),
        ),
      ];
    }
    final chosen = _chosen.length;
    final source = _service.gallery;
    return [
      Text(
        '${_time(window.startUtc)} to ${_time(window.endUtc)}'
        '${window.margin == Duration.zero ? '' : ', with ${window.margin.inMinutes} min either side'}'
        '${source is FolderGallerySource && source.folder != null ? '\nFolder: ${source.folder}' : ''}',
        key: const Key('gallery-import-window'),
        style: muted,
      ),
      const SizedBox(height: TokenSpace.space2),
      Wrap(
        spacing: TokenSpace.space2,
        children: [
          for (final m in GalleryImportSheet.margins)
            ChoiceChip(
              key: Key('gallery-import-margin-${m.inMinutes}'),
              label: Text(
                m == Duration.zero ? 'No margin' : '${m.inMinutes} min',
              ),
              selected: m == _margin,
              onSelected: _loading ? null : (_) => _setMargin(m),
            ),
        ],
      ),
      if (scan.access == GalleryAccess.limited) ...[
        const SizedBox(height: TokenSpace.space2),
        Text(
          "You've let Attenlume see some of your photos only. Only those "
          'are listed.',
          key: const Key('gallery-import-limited'),
          style: theme.textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: TokenSpace.space3),
      if (scan.candidates.isEmpty)
        Text(
          'No photos found in this time.',
          key: const Key('gallery-import-empty'),
          style: muted,
        )
      else
        Flexible(
          child: GridView.extent(
            shrinkWrap: true,
            maxCrossAxisExtent: 120,
            mainAxisSpacing: TokenSpace.space2,
            crossAxisSpacing: TokenSpace.space2,
            childAspectRatio: 0.75,
            children: [
              for (final c in scan.candidates)
                _CandidateTile(
                  key: Key('gallery-candidate-${c.item.id}'),
                  candidate: c,
                  time: _time(c.item.takenUtc),
                  selected: _selected.contains(c.item.id),
                  gallery: source,
                  onChanged: (on) => setState(() {
                    on ? _selected.add(c.item.id) : _selected.remove(c.item.id);
                  }),
                ),
            ],
          ),
        ),
      if (scan.candidates.isNotEmpty) ...[
        const SizedBox(height: TokenSpace.space3),
        TextField(
          key: const Key('gallery-import-label-input'),
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Label (optional)',
            hintText: 'For example: Slides',
          ),
        ),
        const SizedBox(height: TokenSpace.space3),
        FilledButton(
          key: const Key('gallery-import-confirm-button'),
          onPressed: chosen == 0 || _importing || _loading ? null : _import,
          child: Text(
            _importing
                ? 'Importing...'
                : chosen == 1
                ? 'Import 1 photo'
                : 'Import $chosen photos',
          ),
        ),
      ],
    ];
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    super.key,
    required this.candidate,
    required this.time,
    required this.selected,
    required this.gallery,
    required this.onChanged,
  });

  final GalleryCandidate candidate;
  final String time;
  final bool selected;
  final GallerySource gallery;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = candidate.item;
    final notes = [
      if (candidate.duplicate) 'Already imported',
      if (candidate.large) 'Large file',
    ];
    return Semantics(
      checked: selected,
      label: ['Photo taken at $time', ...notes].join(', '),
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
                    child: _Preview(item: item, gallery: gallery),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Checkbox(
                      value: selected,
                      onChanged: (v) => onChanged(v ?? false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: TokenSpace.space1),
            Text(time, style: theme.textTheme.labelSmall),
            if (notes.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: TokenSpace.space1),
                  Expanded(
                    child: Text(
                      notes.join(', '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A preview at tile size only (FR-PHO-03). The thumbnail is fetched
/// once, not on every selection change.
class _Preview extends StatefulWidget {
  const _Preview({required this.item, required this.gallery});

  final GalleryItem item;
  final GallerySource gallery;

  static const size = 120.0;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  Future<Uint8List?>? _thumb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.item.path == null) {
      _thumb ??= widget.gallery.thumbnail(widget.item, size: _px);
    }
  }

  int get _px =>
      (_Preview.size * MediaQuery.devicePixelRatioOf(context)).round();

  Widget _fallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Icons.image_outlined),
  );

  @override
  Widget build(BuildContext context) {
    final path = widget.item.path;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: _px,
        errorBuilder: (context, _, _) => _fallback(context),
      );
    }
    return FutureBuilder(
      future: _thumb,
      builder: (context, snap) {
        final bytes = snap.data;
        return bytes == null
            ? _fallback(context)
            : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: _px);
      },
    );
  }
}
