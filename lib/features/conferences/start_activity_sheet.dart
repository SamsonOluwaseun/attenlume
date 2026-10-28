import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/local_database/builtin_activity_types.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/attenlume_button.dart';
import '../activities/activity_editor_screen.dart';
import '../activities/consent_check_dialog.dart';
import '../activities/custom_type_dialog.dart';

/// Modal bottom sheet allowing users to start an activity of any type (FR-ACT-01, FR-ACT-02, FR-ACT-06, FR-ACT-07).
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
      useSafeArea: true,
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

    // Consent awareness check for conversations & networking (FR-ACT-07, FR-PRI-01)
    RecordingPermissionStatus permissionStatus =
        RecordingPermissionStatus.unknown;
    if (consentCheckTypeKeys.contains(type.key)) {
      final consent = await ConsentCheckDialog.show(context);
      if (consent == null) {
        if (mounted) setState(() => _isCreating = false);
        return;
      }
      permissionStatus = consent;
    }

    try {
      final repo = ref.read(activityRepositoryProvider);
      final customTitle = _titleController.text.trim();
      final activity = await repo.create(
        conferenceId: widget.conferenceId,
        typeId: type.id,
        title: customTitle.isNotEmpty ? customTitle : null,
        recordingPermissionStatus: permissionStatus,
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

  Future<void> _openCustomTypeDialog() async {
    final created = await CustomTypeDialog.show(context);
    if (created != null && mounted) {
      await _loadTypes();
      await _createActivity(created);
    }
  }

  Future<void> _openFullEditor() async {
    final created = await Navigator.of(context).push<Activity>(
      MaterialPageRoute(
        builder: (context) =>
            ActivityEditorScreen(conferenceId: widget.conferenceId),
      ),
    );

    if (created != null && mounted) {
      Navigator.of(context).pop(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
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
            Row(
              children: [
                Text(
                  'Select type',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  key: const Key('add-custom-type-chip'),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Custom type'),
                  onPressed: _openCustomTypeDialog,
                ),
              ],
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
                          avatar: Icon(
                            activityTypeIconData(type.icon),
                            size: 18,
                          ),
                          label: Text(type.label),
                          onPressed: _isCreating
                              ? null
                              : () => _createActivity(type),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: TokenSpace.space4),
            AttenlumeButton(
              key: const Key('open-activity-editor-button'),
              label: 'Create with full details',
              variant: AttenlumeButtonVariant.secondary,
              leading: const Icon(Icons.tune_rounded),
              onPressed: _openFullEditor,
            ),
          ],
        ),
      ),
    );
  }
}
