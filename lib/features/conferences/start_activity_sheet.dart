import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../presentation/components/activity_card.dart';

/// Modal bottom sheet allowing users to start an activity of any type (FR-ACT-01, FR-ACT-02).
class StartActivitySheet extends ConsumerStatefulWidget {
  const StartActivitySheet({super.key, required this.conferenceId});

  final String conferenceId;

  /// Shows the start activity bottom sheet.
  static Future<Activity?> show(
    BuildContext context, {
    required String conferenceId,
  }) {
    return showModalBottomSheet<Activity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TokenRadius.radiusLg),
        ),
      ),
      builder: (context) => StartActivitySheet(conferenceId: conferenceId),
    );
  }

  @override
  ConsumerState<StartActivitySheet> createState() => _StartActivitySheetState();
}

class _StartActivitySheetState extends ConsumerState<StartActivitySheet> {
  final TextEditingController _titleController = TextEditingController();
  List<ActivityType> _types = [];
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final repo = ref.read(activityRepositoryProvider);
    final types = await repo.types();
    if (mounted) {
      setState(() {
        _types = types;
        _isLoading = false;
      });
    }
  }

  Future<void> _createActivity(ActivityType type) async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    try {
      final repo = ref.read(activityRepositoryProvider);
      final customTitle = _titleController.text.trim();
      final activity = await repo.create(
        conferenceId: widget.conferenceId,
        typeId: type.id,
        title: customTitle.isNotEmpty ? customTitle : null,
      );

      if (mounted) {
        Navigator.of(context).pop(activity);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create activity: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: TokenSpace.space4,
        right: TokenSpace.space4,
        top: TokenSpace.space4,
        bottom: TokenSpace.space4 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Start activity',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: TokenSpace.space3),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              hintText: 'Leave blank for default: {Type} {n}, {HH:mm}',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title_rounded),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: TokenSpace.space4),
          Text(
            'Select type',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: TokenSpace.space2),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(TokenSpace.space4),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: TokenSpace.space2,
                  runSpacing: TokenSpace.space2,
                  children: [
                    for (final type in _types)
                      ActionChip(
                        key: Key('activity-type-chip-${type.key}'),
                        avatar: Icon(activityTypeIconData(type.icon), size: 18),
                        label: Text(type.label),
                        onPressed: _isCreating
                            ? null
                            : () => _createActivity(type),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
