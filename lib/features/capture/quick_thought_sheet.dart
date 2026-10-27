import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/enums.dart';

/// Modal bottom sheet for quick thoughts and reflections during recording (FR-UI-05).
///
/// Keeps private reflections distinct and marked so they are never mixed into
/// speaker audio or unintentionally shared.
class QuickThoughtSheet extends ConsumerStatefulWidget {
  const QuickThoughtSheet({
    super.key,
    required this.activityId,
    this.initialPrivate = false,
  });

  final String activityId;
  final bool initialPrivate;

  static Future<void> show(
    BuildContext context, {
    required String activityId,
    bool initialPrivate = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuickThoughtSheet(
        activityId: activityId,
        initialPrivate: initialPrivate,
      ),
    );
  }

  @override
  ConsumerState<QuickThoughtSheet> createState() => _QuickThoughtSheetState();
}

class _QuickThoughtSheetState extends ConsumerState<QuickThoughtSheet> {
  final _controller = TextEditingController();
  late bool _isPrivate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _isPrivate = widget.initialPrivate;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSaving = true);
    await HapticFeedback.lightImpact();

    try {
      final mediaRepo = ref.read(mediaAssetRepositoryProvider);
      await mediaRepo.addBookmark(
        activityId: widget.activityId,
        source: BookmarkSource.ui,
        label: _isPrivate ? 'Private thought' : 'Quick thought',
        note: text,
      );

      // Also append to activity notes
      final actRepo = ref.read(activityRepositoryProvider);
      final act = await actRepo.get(widget.activityId);
      if (act != null) {
        final existing = act.notesMd ?? '';
        final prefix = _isPrivate
            ? '**[Private reflection]**'
            : '**[Quick thought]**';
        final updatedNotes = existing.isEmpty
            ? '$prefix $text'
            : '$existing\n\n$prefix $text';
        await actRepo.update(
          widget.activityId,
          ActivitiesCompanion(notesMd: Value(updatedNotes)),
        );
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.pop(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              _isPrivate ? 'Private reflection saved' : 'Thought saved',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save note: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();

    final liveSurface = attenlume?.liveSurface ?? const Color(0xFF00212B);
    final liveRaised = attenlume?.liveRaised ?? const Color(0xFF0E3542);
    final onLiveSurface = attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8);
    final onLiveSurfaceMuted =
        attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8);

    final viewInsets = MediaQuery.of(context).viewInsets;

    return Theme(
      data: AppTheme.live(),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(TokenSpace.space4),
            decoration: BoxDecoration(
              color: liveSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(TokenRadius.radiusLg),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 24,
                      color: onLiveSurface,
                    ),
                    const SizedBox(width: TokenSpace.space2),
                    Text(
                      'Quick Thought',
                      style: TextStyle(
                        fontFamily: TokenType.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: onLiveSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: onLiveSurfaceMuted,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: TokenSpace.space3),

                TextField(
                  key: const Key('quick-thought-input'),
                  controller: _controller,
                  autofocus: true,
                  maxLines: 3,
                  style: TextStyle(
                    fontFamily: TokenType.fontFamily,
                    color: onLiveSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type your observation or takeaway...',
                    hintStyle: TextStyle(
                      fontFamily: TokenType.fontFamily,
                      color: onLiveSurfaceMuted,
                    ),
                    filled: true,
                    fillColor: liveRaised,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(TokenRadius.radiusMd),
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: TokenSpace.space2),

                // Private reflection toggle
                Row(
                  children: [
                    Checkbox(
                      key: const Key('quick-thought-private-checkbox'),
                      value: _isPrivate,
                      onChanged: (val) {
                        setState(() => _isPrivate = val ?? false);
                      },
                      activeColor:
                          attenlume?.surfaceBrand ?? const Color(0xFF4392F1),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isPrivate = !_isPrivate),
                        child: Text(
                          'Mark as private reflection (excluded from export)',
                          style: TextStyle(
                            fontFamily: TokenType.fontFamily,
                            fontSize: 13,
                            color: onLiveSurfaceMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: TokenSpace.space3),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: onLiveSurface,
                          side: BorderSide(color: onLiveSurfaceMuted),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: TokenSpace.space3),
                    Expanded(
                      child: FilledButton(
                        key: const Key('quick-thought-save-button'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              attenlume?.surfaceBrand ??
                              const Color(0xFF4392F1),
                          foregroundColor:
                              attenlume?.onBrandLarge ??
                              const Color(0xFFFEFFF8),
                        ),
                        onPressed: _isSaving ? null : _handleSave,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save thought'),
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
