import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/attenlume_button.dart';

/// Modal dialog allowing the user to create a custom activity type (FR-ACT-06).
class CustomTypeDialog extends ConsumerStatefulWidget {
  const CustomTypeDialog({super.key});

  /// Shows the custom type creation dialog. Returns the created [ActivityType],
  /// or null if cancelled.
  static Future<ActivityType?> show(BuildContext context) {
    return showDialog<ActivityType>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const CustomTypeDialog(),
    );
  }

  @override
  ConsumerState<CustomTypeDialog> createState() => _CustomTypeDialogState();
}

class _CustomTypeDialogState extends ConsumerState<CustomTypeDialog> {
  final TextEditingController _labelController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  static const List<String> _availableIcons = [
    'tag',
    'presentation',
    'mic',
    'users',
    'sparkles',
    'coffee',
    'school',
    'store',
    'camera',
    'folder',
    'book',
    'chat',
  ];

  String _selectedIcon = 'tag';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(activityRepositoryProvider);
      final created = await repo.createCustomType(
        _labelController.text.trim(),
        icon: _selectedIcon,
      );

      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to create type: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('custom-type-dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      title: const Text(
        'New activity type',
        key: Key('custom-type-dialog-title'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('custom-type-label-input'),
                  controller: _labelController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Type name',
                    hintText: 'e.g. Poster session, Lab tour',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a type name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: TokenSpace.space4),
                Text(
                  'Icon',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: TokenSpace.space2),
                Wrap(
                  spacing: TokenSpace.space2,
                  runSpacing: TokenSpace.space2,
                  children: [
                    for (final iconKey in _availableIcons)
                      ChoiceChip(
                        key: Key('custom-type-icon-$iconKey'),
                        avatar: Icon(activityTypeIconData(iconKey), size: 18),
                        label: Text(iconKey),
                        selected: _selectedIcon == iconKey,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedIcon = iconKey);
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: TokenSpace.space4),
                AttenlumeButton(
                  key: const Key('custom-type-create-button'),
                  label: _isSubmitting ? 'Creating...' : 'Create type',
                  leading: const Icon(Icons.add_rounded),
                  onPressed: _isSubmitting ? null : _handleCreate,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('custom-type-cancel-button'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
