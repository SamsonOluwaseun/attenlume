import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/local_database/app_database.dart';
import '../../data/local_database/builtin_activity_types.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';
import 'custom_type_dialog.dart';

/// Full Activity CRUD editor screen (FR-ACT-04, FR-ACT-05, FR-ACT-06, FR-ACT-07, FR-ACT-08).
///
/// Supports creating a new activity or editing an existing one, including:
/// - Title with blank default formula (FR-ACT-05)
/// - Type selection and custom type creation (FR-ACT-06)
/// - Awareness / consent check for conversations and networking (FR-ACT-07)
/// - Manual contact details and follow-up action (FR-ACT-08)
/// - Speakers, organisation, room, notes, tags, planned start, profile override, privacy (FR-ACT-04).
class ActivityEditorScreen extends ConsumerStatefulWidget {
  const ActivityEditorScreen({
    super.key,
    this.conferenceId,
    this.activityId,
    this.initialTypeId,
  }) : assert(
         conferenceId != null || activityId != null,
         'Either conferenceId or activityId must be provided',
       );

  final String? conferenceId;
  final String? activityId;
  final String? initialTypeId;

  @override
  ConsumerState<ActivityEditorScreen> createState() =>
      _ActivityEditorScreenState();
}

class _ActivityEditorScreenState extends ConsumerState<ActivityEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _speakersController = TextEditingController();
  final _organisationController = TextEditingController();
  final _roomController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactDetailsController = TextEditingController();
  final _followUpController = TextEditingController();

  List<ActivityType> _types = [];
  String? _selectedTypeId;
  Conference? _conference;
  Activity? _existingActivity;
  bool _isLoading = true;
  bool _isSaving = false;

  DateTime? _plannedStart;
  RecordingPermissionStatus _permissionStatus =
      RecordingPermissionStatus.unknown;
  RecordingProfile? _profileOverride;
  bool _isPrivate = false;

  bool get _isEditing => widget.activityId != null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _speakersController.dispose();
    _organisationController.dispose();
    _roomController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _contactNameController.dispose();
    _contactDetailsController.dispose();
    _followUpController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final actRepo = ref.read(activityRepositoryProvider);
    final confRepo = ref.read(conferenceRepositoryProvider);

    final types = await actRepo.types();

    Activity? existing;
    String resolvedConferenceId = widget.conferenceId ?? '';

    if (_isEditing) {
      existing = await actRepo.get(widget.activityId!);
      if (existing != null) {
        resolvedConferenceId = existing.conferenceId;
        _existingActivity = existing;
        _titleController.text = existing.title;
        _selectedTypeId = existing.typeId;
        _speakersController.text = existing.speakerNames.join(', ');
        _organisationController.text = existing.organisation ?? '';
        _roomController.text = existing.room ?? '';
        _notesController.text = existing.notesMd ?? '';
        _tagsController.text = existing.tags.join(', ');
        _plannedStart = existing.plannedStart;
        _permissionStatus = existing.recordingPermissionStatus;
        _profileOverride = existing.recordingProfileOverride;
        _isPrivate = existing.isPrivate;
        _contactNameController.text = existing.contactName ?? '';
        _contactDetailsController.text = existing.contactDetails ?? '';
        _followUpController.text = existing.followUpText ?? '';
      }
    } else {
      _selectedTypeId =
          widget.initialTypeId ?? (types.isNotEmpty ? types.first.id : null);
      if (_selectedTypeId != null) {
        final t = types.cast<ActivityType?>().firstWhere(
          (x) => x?.id == _selectedTypeId,
          orElse: () => null,
        );
        if (t != null && t.key == ActivityRepository.reflectionTypeKey) {
          _isPrivate = true;
        }
      }
    }

    final conf = await confRepo.get(resolvedConferenceId);

    if (mounted) {
      setState(() {
        _types = types;
        _conference = conf;
        _isLoading = false;
      });
    }
  }

  ActivityType? get _currentType {
    if (_selectedTypeId == null) return null;
    return _types.cast<ActivityType?>().firstWhere(
      (t) => t?.id == _selectedTypeId,
      orElse: () => null,
    );
  }

  bool get _isConversationOrNetworking {
    final type = _currentType;
    if (type == null) return false;
    return consentCheckTypeKeys.contains(type.key);
  }

  Future<void> _openCustomTypeDialog() async {
    final created = await CustomTypeDialog.show(context);
    if (created != null && mounted) {
      final actRepo = ref.read(activityRepositoryProvider);
      final types = await actRepo.types();
      setState(() {
        _types = types;
        _selectedTypeId = created.id;
      });
    }
  }

  Future<void> _deleteCustomType(ActivityType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete type ${type.label}?'),
        content: const Text(
          'Custom types that are not used by any activities can be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final actRepo = ref.read(activityRepositoryProvider);
    try {
      await actRepo.deleteCustomType(type.id);
      final types = await actRepo.types();
      if (!mounted) return;
      setState(() {
        _types = types;
        if (_selectedTypeId == type.id) {
          _selectedTypeId = types.isNotEmpty ? types.first.id : null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Custom type "${type.label}" deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete type: ${e is StateError ? e.message : e}',
          ),
        ),
      );
    }
  }

  Future<void> _pickPlannedStart() async {
    final initialDate = _plannedStart ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _plannedStart = DateTime.utc(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final actRepo = ref.read(activityRepositoryProvider);
      final confId = _conference?.id ?? widget.conferenceId!;
      final typeId = _selectedTypeId!;

      final rawTitle = _titleController.text.trim();
      final speakers = _speakersController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final tags = _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      final org = _organisationController.text.trim();
      final room = _roomController.text.trim();
      final notes = _notesController.text.trim();
      final contactName = _contactNameController.text.trim();
      final contactDetails = _contactDetailsController.text.trim();
      final followUp = _followUpController.text.trim();

      Activity saved;
      if (_isEditing) {
        final existing = _existingActivity!;
        var updatedTitle = rawTitle;
        if (updatedTitle.isEmpty) {
          updatedTitle = existing.title;
        }

        await actRepo.update(
          existing.id,
          ActivitiesCompanion(
            title: Value(updatedTitle),
            typeId: Value(typeId),
            speakerNames: Value(speakers),
            organisation: Value(org.isEmpty ? null : org),
            room: Value(room.isEmpty ? null : room),
            notesMd: Value(notes.isEmpty ? null : notes),
            tags: Value(tags),
            plannedStart: Value(_plannedStart),
            recordingPermissionStatus: Value(_permissionStatus),
            recordingProfileOverride: Value(_profileOverride),
            isPrivate: Value(_isPrivate),
            contactName: Value(contactName.isEmpty ? null : contactName),
            contactDetails: Value(
              contactDetails.isEmpty ? null : contactDetails,
            ),
            followUpText: Value(followUp.isEmpty ? null : followUp),
          ),
        );
        saved = (await actRepo.get(existing.id))!;
      } else {
        saved = await actRepo.create(
          conferenceId: confId,
          typeId: typeId,
          title: rawTitle.isEmpty ? null : rawTitle,
          speakerNames: speakers,
          organisation: org.isEmpty ? null : org,
          room: room.isEmpty ? null : room,
          notesMd: notes.isEmpty ? null : notes,
          tags: tags,
          plannedStart: _plannedStart,
          recordingPermissionStatus: _permissionStatus,
          recordingProfileOverride: _profileOverride,
          isPrivate: _isPrivate,
          contactName: contactName.isEmpty ? null : contactName,
          contactDetails: contactDetails.isEmpty ? null : contactDetails,
          followUpText: followUp.isEmpty ? null : followUp,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save activity: $e')));
      }
    }
  }

  Future<void> _handleDelete() async {
    final existing = _existingActivity;
    if (existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${existing.title}"?'),
        content: const Text(
          'This will permanently delete this activity and all its recordings, '
          'photos and bookmarks. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final actRepo = ref.read(activityRepositoryProvider);
    await actRepo.delete(existing.id);

    if (mounted) {
      Navigator.of(context).pop({'deleted': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inkMuted = theme.colorScheme.onSurfaceVariant;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final confDefaultProfile =
        _conference?.defaultRecordingProfile ?? RecordingProfile.globalDefault;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit activity' : 'New activity'),
        actions: [
          TextButton(
            key: const Key('save-activity-appbar-button'),
            onPressed: _isSaving ? null : _handleSave,
            child: Text(
              _isSaving ? 'Saving...' : 'Save',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section 1: Type Selection (FR-ACT-06)
                    Row(
                      children: [
                        Text(
                          'Activity type',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          key: const Key('activity-add-custom-type-button'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Custom type'),
                          onPressed: _openCustomTypeDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: TokenSpace.space2),
                    Wrap(
                      spacing: TokenSpace.space2,
                      runSpacing: TokenSpace.space2,
                      children: [
                        for (final type in _types)
                          InputChip(
                            key: Key('activity-type-choice-${type.key}'),
                            avatar: Icon(
                              activityTypeIconData(type.icon),
                              size: 18,
                            ),
                            label: Text(type.label),
                            selected: _selectedTypeId == type.id,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedTypeId = type.id;
                                  if (type.key ==
                                      ActivityRepository.reflectionTypeKey) {
                                    _isPrivate = true;
                                  }
                                  if (consentCheckTypeKeys.contains(type.key) &&
                                      _permissionStatus ==
                                          RecordingPermissionStatus.unknown) {
                                    // Default prompt or reminder
                                    _permissionStatus =
                                        RecordingPermissionStatus.unknown;
                                  }
                                });
                              }
                            },
                            onDeleted: !type.isBuiltin
                                ? () => _deleteCustomType(type)
                                : null,
                            deleteIcon: !type.isBuiltin
                                ? const Icon(Icons.close, size: 16)
                                : null,
                            deleteButtonTooltipMessage: 'Delete custom type',
                          ),
                      ],
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Section 2: Title (FR-ACT-05)
                    TextFormField(
                      key: const Key('activity-title-field'),
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        hintText: _isEditing
                            ? 'Title'
                            : 'Default: {Type} {n}, {HH:mm}',
                        helperText: 'Leave blank for default: {Type} {n}, {HH:mm} (rename any time)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.title_rounded),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Section 3: Consent Check for Conversations & Networking (FR-ACT-07)
                    if (_isConversationOrNetworking) ...[
                      Card(
                        key: const Key('consent-check-card'),
                        color: theme.colorScheme.surfaceContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(TokenSpace.space3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.privacy_tip_outlined,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: TokenSpace.space2),
                                  Expanded(
                                    child: Text(
                                      'Consent check (FR-ACT-07)',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: TokenSpace.space2),
                              Text(
                                'Does the other person know you are recording?',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: TokenSpace.space2),
                              Wrap(
                                spacing: TokenSpace.space2,
                                runSpacing: TokenSpace.space2,
                                children: [
                                  ChoiceChip(
                                    key: const Key('consent-chip-yes'),
                                    label: const Text(
                                      'Yes (Participant aware)',
                                    ),
                                    selected:
                                        _permissionStatus ==
                                        RecordingPermissionStatus
                                            .participantAware,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _permissionStatus =
                                              RecordingPermissionStatus
                                                  .participantAware;
                                        });
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    key: const Key('consent-chip-no-audio'),
                                    label: const Text('Not recording audio'),
                                    selected:
                                        _permissionStatus ==
                                        RecordingPermissionStatus.notPermitted,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _permissionStatus =
                                              RecordingPermissionStatus
                                                  .notPermitted;
                                        });
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    key: const Key('consent-chip-unknown'),
                                    label: const Text('Not specified'),
                                    selected:
                                        _permissionStatus ==
                                        RecordingPermissionStatus.unknown,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _permissionStatus =
                                              RecordingPermissionStatus.unknown;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: TokenSpace.space4),
                    ],

                    // Section 4: Contact details & follow-up (FR-ACT-08)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(TokenSpace.space3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.badge_outlined, size: 20),
                                const SizedBox(width: TokenSpace.space2),
                                Text(
                                  'Contact details & follow-up',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: TokenSpace.space1),
                            Text(
                              'Manual entry only. No facial recognition or automatic identity extraction.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: inkMuted,
                              ),
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            TextFormField(
                              key: const Key('activity-contact-name-field'),
                              controller: _contactNameController,
                              decoration: const InputDecoration(
                                labelText: 'Contact name',
                                hintText: 'e.g. Sam Sample',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            TextFormField(
                              key: const Key('activity-contact-details-field'),
                              controller: _contactDetailsController,
                              decoration: const InputDecoration(
                                labelText: 'Contact details',
                                hintText: 'Email, telephone or social handle',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.contact_mail_outlined),
                              ),
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            TextFormField(
                              key: const Key('activity-follow-up-field'),
                              controller: _followUpController,
                              decoration: const InputDecoration(
                                labelText: 'Follow-up action',
                                hintText: 'e.g. Email slides by Friday',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.task_alt_rounded),
                              ),
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Section 5: Session Details (FR-ACT-04)
                    Text(
                      'Session details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: TokenSpace.space2),
                    TextFormField(
                      key: const Key('activity-speakers-field'),
                      controller: _speakersController,
                      decoration: const InputDecoration(
                        labelText: 'Speakers',
                        hintText: 'Comma separated: Dr Ada Example, Sam Sample',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.record_voice_over_outlined),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('activity-organisation-field'),
                            controller: _organisationController,
                            decoration: const InputDecoration(
                              labelText: 'Organisation',
                              hintText: 'e.g. Samlytics Data Services',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: TokenSpace.space3),
                        Expanded(
                          child: TextFormField(
                            key: const Key('activity-room-field'),
                            controller: _roomController,
                            decoration: const InputDecoration(
                              labelText: 'Room',
                              hintText: 'e.g. Hall A',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.meeting_room_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: TokenSpace.space3),

                    // Planned Start Picker
                    ListTile(
                      key: const Key('activity-planned-start-tile'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_rounded),
                      title: const Text('Planned start time'),
                      subtitle: Text(
                        _plannedStart != null
                            ? '${formatTimeOfDayInTimezone(_plannedStart!, _conference?.timezone ?? "Europe/London")} (${_conference?.timezone ?? "Europe/London"})'
                            : 'Not set (tap to specify schedule)',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_plannedStart != null)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              tooltip: 'Clear planned time',
                              onPressed: () =>
                                  setState(() => _plannedStart = null),
                            ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      onTap: _pickPlannedStart,
                    ),

                    const Divider(height: TokenSpace.space4),

                    // Section 6: Recording & Privacy settings (FR-ACT-04, FR-QUAL-02, FR-EXP-10)
                    Text(
                      'Recording & privacy',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: TokenSpace.space2),

                    // Profile Override Dropdown
                    DropdownButtonFormField<RecordingProfile?>(
                      key: const Key('activity-profile-override-dropdown'),
                      initialValue: _profileOverride,
                      decoration: const InputDecoration(
                        labelText: 'Recording profile override',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.graphic_eq_rounded),
                      ),
                      items: [
                        DropdownMenuItem<RecordingProfile?>(
                          value: null,
                          child: Text(
                            'Conference default (${confDefaultProfile.label})',
                          ),
                        ),
                        for (final p in RecordingProfile.values)
                          DropdownMenuItem<RecordingProfile?>(
                            value: p,
                            child: Text('${p.label} (${p.mbPerHourLabel})'),
                          ),
                      ],
                      onChanged: (val) =>
                          setState(() => _profileOverride = val),
                    ),

                    const SizedBox(height: TokenSpace.space3),

                    // Permission Status Dropdown (for non-conversation or manual control)
                    if (!_isConversationOrNetworking) ...[
                      DropdownButtonFormField<RecordingPermissionStatus>(
                        key: const Key('activity-permission-status-dropdown'),
                        initialValue: _permissionStatus,
                        decoration: const InputDecoration(
                          labelText: 'Recording permission status',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.rule_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: RecordingPermissionStatus.unknown,
                            child: Text('Unknown / Not specified'),
                          ),
                          DropdownMenuItem(
                            value: RecordingPermissionStatus.permitted,
                            child: Text('Permitted'),
                          ),
                          DropdownMenuItem(
                            value: RecordingPermissionStatus.participantAware,
                            child: Text('Participant aware (Yes)'),
                          ),
                          DropdownMenuItem(
                            value: RecordingPermissionStatus.notPermitted,
                            child: Text('Not permitted / Audio off'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _permissionStatus = val);
                          }
                        },
                      ),
                      const SizedBox(height: TokenSpace.space3),
                    ],

                    // Private activity switch
                    SwitchListTile(
                      key: const Key('activity-privacy-switch'),
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.lock_outline_rounded),
                      title: const Text('Mark as private'),
                      subtitle: const Text(
                        'Excluded from exports by default. Reflections are private by default.',
                      ),
                      value: _isPrivate,
                      onChanged: (val) => setState(() => _isPrivate = val),
                    ),

                    const Divider(height: TokenSpace.space4),

                    // Section 7: Notes & Tags (FR-ACT-04)
                    Text(
                      'Notes & tags',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: TokenSpace.space2),
                    TextFormField(
                      key: const Key('activity-notes-field'),
                      controller: _notesController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Markdown)',
                        hintText: 'Add session notes, bullet points or observations...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    TextFormField(
                      key: const Key('activity-tags-field'),
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags',
                        hintText: 'Comma separated: ai, data-mesh, keynote',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_offer_outlined),
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space6),

                    // Save Button
                    AttenlumeButton(
                      key: const Key('save-activity-button'),
                      label: _isSaving
                          ? 'Saving...'
                          : (_isEditing ? 'Save changes' : 'Create activity'),
                      leading: const Icon(Icons.check_circle_outline_rounded),
                      onPressed: _isSaving ? null : _handleSave,
                    ),

                    // Delete Button (if editing)
                    if (_isEditing) ...[
                      const SizedBox(height: TokenSpace.space3),
                      AttenlumeButton(
                        key: const Key('delete-activity-button'),
                        label: 'Delete activity',
                        variant: AttenlumeButtonVariant.danger,
                        leading: const Icon(Icons.delete_outline_rounded),
                        onPressed: _isSaving ? null : _handleDelete,
                      ),
                    ],

                    const SizedBox(height: TokenSpace.space6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
