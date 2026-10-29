import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/media.dart';
import '../capture/recording_providers.dart';
import 'gallery_import_sheet.dart';

/// Lets the user pick image files to import. Tests replace it.
final photoFilePickerProvider = Provider<Future<List<String>> Function()>(
  (ref) => () async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Photos',
          extensions: ['jpg', 'jpeg', 'png'],
          mimeTypes: ['image/jpeg', 'image/png'],
          uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
        ),
      ],
    );
    return [for (final f in files) f.path];
  },
);

/// The activity's photos as thumbnails, with import and per-photo caption
/// and label (FR-PHO-03, FR-PHO-06) [P1-14].
///
/// Thumbnails are decoded at display size only (FR-PHO-03).
class ActivityPhotosSection extends ConsumerStatefulWidget {
  const ActivityPhotosSection({
    super.key,
    required this.activityId,
    this.timezone = 'UTC',
    this.onChanged,
  });

  final String activityId;

  /// Conference timezone for the gallery import window (FR-PHO-05).
  final String timezone;

  /// Called after photos are imported or edited.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ActivityPhotosSection> createState() =>
      _ActivityPhotosSectionState();
}

class _ActivityPhotosSectionState extends ConsumerState<ActivityPhotosSection> {
  List<Photo> _photos = const [];
  Directory? _root;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final root = await ref.read(mediaRootProvider)();
    final photos = await ref
        .read(mediaAssetRepositoryProvider)
        .photosFor(widget.activityId);
    if (mounted) {
      setState(() {
        _root = root;
        _photos = photos;
      });
    }
  }

  Future<void> _import() async {
    final paths = await ref.read(photoFilePickerProvider)();
    if (paths.isEmpty || !mounted) return;
    final label = await _askLabel(paths.length);
    if (label == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final saved = await ref
          .read(photoCaptureServiceProvider)
          .importFiles(widget.activityId, paths, label: label);
      if (!mounted) return;
      final skipped = paths.length - saved.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${saved.length == 1 ? '1 photo' : '${saved.length} photos'} '
            'imported${skipped > 0 ? ', $skipped could not be read' : ''}.',
          ),
        ),
      );
      await _load();
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importTaken() async {
    setState(() => _importing = true);
    try {
      final result = await GalleryImportSheet.show(
        context,
        activityId: widget.activityId,
        timezone: widget.timezone,
      );
      if (result == null || !mounted) return;
      final n = result.saved.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${n == 1 ? '1 photo' : '$n photos'} imported'
            '${result.skipped > 0 ? ', ${result.skipped} could not be read' : ''}.',
          ),
        ),
      );
      await _load();
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Returns the label ('' for none), or null if the user cancelled.
  Future<String?> _askLabel(int count) => showDialog<String>(
    context: context,
    builder: (context) => _ImportLabelDialog(count: count),
  );

  Future<void> _open(Photo photo) async {
    final root = _root;
    if (root == null) return;
    final updated = await PhotoDetailSheet.show(context, photo, root);
    if (updated != null && mounted) {
      await _load();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = _root;
    return Column(
      key: const Key('activity-photos-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                _photos.isEmpty ? 'Photos' : 'Photos (${_photos.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            TextButton.icon(
              key: const Key('activity-photos-import-button'),
              onPressed: _importing ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Import photos'),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('activity-photos-import-taken-button'),
            onPressed: _importing ? null : _importTaken,
            icon: const Icon(Icons.schedule_outlined),
            label: const Text('Import photos taken during this activity'),
          ),
        ),
        if (_photos.isEmpty)
          Text(
            'No photos yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else if (root != null)
          Wrap(
            spacing: TokenSpace.space2,
            runSpacing: TokenSpace.space2,
            children: [
              for (final photo in _photos)
                _Thumbnail(
                  key: Key('activity-photo-${photo.id}'),
                  photo: photo,
                  root: root,
                  onTap: () => _open(photo),
                ),
            ],
          ),
      ],
    );
  }
}

/// Asks for an optional label for a batch of imported photos. Owns its
/// text controller so it lives until the dialog has closed.
class _ImportLabelDialog extends StatefulWidget {
  const _ImportLabelDialog({required this.count});

  final int count;

  @override
  State<_ImportLabelDialog> createState() => _ImportLabelDialogState();
}

class _ImportLabelDialogState extends State<_ImportLabelDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.count == 1 ? 'Import 1 photo' : 'Import ${widget.count} photos',
    ),
    content: TextField(
      key: const Key('photo-import-label-input'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Label (optional)',
        hintText: 'For example: Slides',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('photo-import-confirm-button'),
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Import'),
      ),
    ],
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    super.key,
    required this.photo,
    required this.root,
    required this.onTap,
  });

  final Photo photo;
  final Directory root;
  final VoidCallback onTap;

  static const size = 72.0;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final caption = photo.caption ?? photo.label;
    return Semantics(
      button: true,
      label: caption == null ? 'Photo' : 'Photo: $caption',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
          child: SizedBox.square(
            dimension: size,
            child: Image.file(
              MediaPaths.resolve(root, photo.thumbnailPath ?? photo.filePath),
              fit: BoxFit.cover,
              cacheWidth: (size * dpr).round(),
              errorBuilder: (context, _, _) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One photo at display size with its caption and label (FR-PHO-06).
class PhotoDetailSheet extends ConsumerStatefulWidget {
  const PhotoDetailSheet({super.key, required this.photo, required this.root});

  final Photo photo;
  final Directory root;

  /// Returns the updated photo when the user saved changes.
  static Future<Photo?> show(
    BuildContext context,
    Photo photo,
    Directory root,
  ) => showModalBottomSheet<Photo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PhotoDetailSheet(photo: photo, root: root),
  );

  @override
  ConsumerState<PhotoDetailSheet> createState() => _PhotoDetailSheetState();
}

class _PhotoDetailSheetState extends ConsumerState<PhotoDetailSheet> {
  late final _caption = TextEditingController(text: widget.photo.caption);
  late final _label = TextEditingController(text: widget.photo.label);
  bool _saving = false;

  @override
  void dispose() {
    _caption.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = await ref
        .read(mediaAssetRepositoryProvider)
        .updatePhotoText(
          widget.photo.id,
          caption: _caption.text,
          label: _label.text,
        );
    if (mounted) Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final offset = widget.photo.offsetMs;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: Column(
          key: const Key('photo-detail-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
              child: Image.file(
                MediaPaths.resolve(widget.root, widget.photo.filePath),
                fit: BoxFit.contain,
                // Decode at display size only (FR-PHO-03).
                cacheWidth: (media.size.width * media.devicePixelRatio).round(),
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            if (offset != null) ...[
              const SizedBox(height: TokenSpace.space2),
              Text(
                '${_mmss(offset)} into the recording',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: TokenSpace.space4),
            TextField(
              key: const Key('photo-caption-input'),
              controller: _caption,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Caption'),
            ),
            const SizedBox(height: TokenSpace.space3),
            TextField(
              key: const Key('photo-label-input'),
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'For example: Slides',
              ),
            ),
            const SizedBox(height: TokenSpace.space4),
            FilledButton(
              key: const Key('photo-save-button'),
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static String _mmss(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
