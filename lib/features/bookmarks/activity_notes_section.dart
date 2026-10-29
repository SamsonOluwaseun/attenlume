import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_database/app_database.dart';
import '../../data/repositories/repository_providers.dart';

/// Short plain-Markdown notes for one activity, with a quick editor
/// (FR-BMK-02) [P1-16].
///
/// The Markdown is stored and exported as written. Here only `**bold**` is
/// rendered, so the app's own labels such as `**[Quick thought]**` read as
/// a bold "Quick thought" rather than as symbols.
class ActivityNotesSection extends ConsumerWidget {
  const ActivityNotesSection({
    super.key,
    required this.activityId,
    required this.notesMd,
    this.onChanged,
  });

  final String activityId;
  final String? notesMd;

  /// Called after the notes are saved.
  final VoidCallback? onChanged;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => NotesEditDialog(initial: notesMd ?? ''),
    );
    if (text == null) return;
    final trimmed = text.trim();
    await ref
        .read(activityRepositoryProvider)
        .update(
          activityId,
          ActivitiesCompanion(notesMd: Value(trimmed.isEmpty ? null : trimmed)),
        );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notes = notesMd;
    final hasNotes = notes != null && notes.isNotEmpty;
    return Column(
      key: const Key('activity-notes-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Notes',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            TextButton.icon(
              key: const Key('activity-notes-edit-button'),
              onPressed: () => _edit(context, ref),
              icon: Icon(hasNotes ? Icons.edit_note_rounded : Icons.add),
              label: Text(hasNotes ? 'Edit notes' : 'Add notes'),
            ),
          ],
        ),
        if (hasNotes)
          SelectableText.rich(
            TextSpan(children: notesSpans(notes)),
            key: const Key('detail-notes'),
            style: theme.textTheme.bodyMedium,
          )
        else
          Text(
            'No notes yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

final _bold = RegExp(r'\*\*(.+?)\*\*');
final _label = RegExp(r'^\[(.+)\]$');

/// [notes] as spans with `**bold**` in bold. A bold label in square
/// brackets, as the app writes, loses its brackets.
List<TextSpan> notesSpans(String notes) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in _bold.allMatches(notes)) {
    if (m.start > at) spans.add(TextSpan(text: notes.substring(at, m.start)));
    final inner = m.group(1)!;
    spans.add(
      TextSpan(
        text: _label.firstMatch(inner)?.group(1) ?? inner,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    at = m.end;
  }
  if (at < notes.length) spans.add(TextSpan(text: notes.substring(at)));
  return spans;
}

/// Multi-line editor for activity notes. Pops the text, or null on cancel.
class NotesEditDialog extends StatefulWidget {
  const NotesEditDialog({super.key, required this.initial});

  final String initial;

  @override
  State<NotesEditDialog> createState() => _NotesEditDialogState();
}

class _NotesEditDialogState extends State<NotesEditDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notes'),
      content: SizedBox(
        width: 480,
        child: TextField(
          key: const Key('activity-notes-input'),
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Plain Markdown, for example "- Key point"',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('activity-notes-save-button'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
