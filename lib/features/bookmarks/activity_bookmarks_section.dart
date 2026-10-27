import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/media.dart';
import '../../shared/utilities/date_formatters.dart';

/// The activity's bookmarks in time order, each with its recording offset,
/// label and note, and an editor to change or remove one (FR-BMK-01)
/// [P1-16].
class ActivityBookmarksSection extends ConsumerStatefulWidget {
  const ActivityBookmarksSection({
    super.key,
    required this.activityId,
    required this.timezone,
    this.onChanged,
  });

  final String activityId;

  /// Conference timezone for the time of day.
  final String timezone;

  /// Called after a bookmark is edited or removed.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ActivityBookmarksSection> createState() =>
      _ActivityBookmarksSectionState();
}

class _ActivityBookmarksSectionState
    extends ConsumerState<ActivityBookmarksSection> {
  List<Bookmark> _bookmarks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bookmarks = await ref
        .read(mediaAssetRepositoryProvider)
        .bookmarksFor(widget.activityId);
    if (mounted) setState(() => _bookmarks = bookmarks);
  }

  Future<void> _open(Bookmark bookmark) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => BookmarkEditDialog(bookmark: bookmark),
    );
    if (changed == true && mounted) {
      await _load();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('activity-bookmarks-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _bookmarks.isEmpty ? 'Bookmarks' : 'Bookmarks (${_bookmarks.length})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TokenSpace.space1),
        if (_bookmarks.isEmpty)
          Text(
            'No bookmarks yet. Tap Bookmark while recording to mark a moment.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final b in _bookmarks)
            ListTile(
              key: Key('activity-bookmark-${b.id}'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(b.label ?? 'Bookmark'),
              subtitle: b.note == null
                  ? null
                  : Text(b.note!, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(
                _when(b),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              onTap: () => _open(b),
            ),
      ],
    );
  }

  /// Offset into the recording where there is one, plus the time of day.
  String _when(Bookmark b) {
    final time = formatTimeOfDayInTimezone(b.atUtc, widget.timezone);
    final offset = b.offsetMs;
    return offset == null ? time : '${formatOffset(offset)} · $time';
  }
}

/// Edits a bookmark's label and note, or deletes it (FR-BMK-01) [P1-16].
/// Pops `true` when something changed.
class BookmarkEditDialog extends ConsumerStatefulWidget {
  const BookmarkEditDialog({super.key, required this.bookmark});

  final Bookmark bookmark;

  @override
  ConsumerState<BookmarkEditDialog> createState() => _BookmarkEditDialogState();
}

class _BookmarkEditDialogState extends ConsumerState<BookmarkEditDialog> {
  late final _label = TextEditingController(text: widget.bookmark.label);
  late final _note = TextEditingController(text: widget.bookmark.note);
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref
        .read(mediaAssetRepositoryProvider)
        .updateBookmarkText(
          widget.bookmark.id,
          label: _label.text,
          note: _note.text,
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this bookmark?'),
        content: const Text('The recording and photos stay as they are.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('bookmark-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await ref
        .read(mediaAssetRepositoryProvider)
        .deleteBookmark(widget.bookmark.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bookmark'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('bookmark-label-input'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: TokenSpace.space3),
            TextField(
              key: const Key('bookmark-note-input'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('bookmark-delete-button'),
          onPressed: _busy ? null : _delete,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Remove'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('bookmark-save-button'),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
