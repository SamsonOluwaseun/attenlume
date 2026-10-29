import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/device_timezone.dart';
import '../../shared/utilities/date_formatters.dart';
import 'conference_delete_dialog.dart';
import 'conference_home_screen.dart';
import 'profile_bulk_change_dialog.dart';

/// Full conference set-up wizard and editor [FR-CONF-01 to 08].
///
/// Can create a new conference or edit an existing one (FR-CONF-08: edit all
/// fields at any time, archive and delete).
class ConferenceWizardScreen extends ConsumerStatefulWidget {
  const ConferenceWizardScreen({super.key, this.conferenceId});

  final String? conferenceId;

  bool get isEditing => conferenceId != null;

  @override
  ConsumerState<ConferenceWizardScreen> createState() =>
      _ConferenceWizardScreenState();
}

class _ConferenceWizardScreenState
    extends ConsumerState<ConferenceWizardScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _venueController;
  late final TextEditingController _roleTextController;

  DateTime? _startDate;
  DateTime? _endDate;
  String _timezone = DeviceTimezoneService.defaultFallbackTimezone;
  RoleType _roleType = RoleType.attendee;
  final Set<RequestedOutput> _requestedOutputs = {};
  RecordingProfile _defaultProfile = RecordingProfile.balanced;
  bool _policyAcknowledged = false;

  // Goals: priority 1, 2, 3 controllers, plus extra optional controllers.
  final List<TextEditingController> _priorityGoalControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final List<TextEditingController> _optionalGoalControllers = [];

  // Goal IDs for existing goals when editing.
  final Map<int, String> _priorityGoalIds = {};
  final List<String> _optionalGoalIds = [];

  bool _isLoading = true;
  Conference? _existingConference;

  static const List<String> goalExamples = [
    'Where could enterprise data architecture improve reproducibility?',
    'How is AI applied in public health response?',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _venueController = TextEditingController();
    _roleTextController = TextEditingController();

    _initializeData();
  }

  Future<void> _initializeData() async {
    final tzService = ref.read(deviceTimezoneServiceProvider);
    if (!widget.isEditing) {
      final detected = await tzService.detectTimezone();
      final settings = ref.read(settingsRepositoryProvider);
      final globalProfile = await settings.globalDefaultRecordingProfile();
      if (mounted) {
        setState(() {
          _timezone = detected;
          _defaultProfile = globalProfile;
          _isLoading = false;
        });
      }
      return;
    }

    final repo = ref.read(conferenceRepositoryProvider);
    final conf = await repo.get(widget.conferenceId!);
    if (conf == null) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final goals = await repo.goalsFor(conf.id);

    if (mounted) {
      _existingConference = conf;
      _nameController.text = conf.name;
      _descriptionController.text = conf.description ?? '';
      _venueController.text = conf.venue ?? '';
      _roleTextController.text = conf.roleText ?? '';
      _startDate = conf.startDate;
      _endDate = conf.endDate;
      _timezone = conf.timezone;
      _roleType = conf.roleType ?? RoleType.attendee;
      _requestedOutputs.addAll(conf.requestedOutputs);
      _defaultProfile = conf.defaultRecordingProfile;
      _policyAcknowledged = conf.policyAcknowledgedAt != null;

      // Populate goals.
      for (final goal in goals) {
        if (goal.priority != null &&
            goal.priority! >= 1 &&
            goal.priority! <= 3) {
          final idx = goal.priority! - 1;
          _priorityGoalControllers[idx].text = goal.goalText;
          _priorityGoalIds[idx] = goal.id;
        } else {
          final c = TextEditingController(text: goal.goalText);
          _optionalGoalControllers.add(c);
          _optionalGoalIds.add(goal.id);
        }
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _roleTextController.dispose();
    for (final c in _priorityGoalControllers) {
      c.dispose();
    }
    for (final c in _optionalGoalControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: isStart ? 'Select start date' : 'Select end date',
    );
    if (picked != null) {
      setState(() {
        final utcDate = DateTime.utc(picked.year, picked.month, picked.day);
        if (isStart) {
          _startDate = utcDate;
          if (_endDate != null && _endDate!.isBefore(utcDate)) {
            _endDate = utcDate;
          }
        } else {
          _endDate = utcDate;
        }
      });
    }
  }

  void _addOptionalGoal() {
    setState(() {
      _optionalGoalControllers.add(TextEditingController());
    });
  }

  void _removeOptionalGoal(int index) {
    setState(() {
      final controller = _optionalGoalControllers.removeAt(index);
      controller.dispose();
      if (index < _optionalGoalIds.length) {
        final goalId = _optionalGoalIds.removeAt(index);
        ref.read(conferenceRepositoryProvider).deleteGoal(goalId);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final repo = ref.read(conferenceRepositoryProvider);
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final venue = _venueController.text.trim().isEmpty
        ? null
        : _venueController.text.trim();
    final roleText = _roleTextController.text.trim().isEmpty
        ? null
        : _roleTextController.text.trim();
    final outputs = _requestedOutputs.toList();

    DateTime? policyTimestamp;
    if (_policyAcknowledged) {
      policyTimestamp =
          _existingConference?.policyAcknowledgedAt ?? DateTime.now().toUtc();
    }

    if (!widget.isEditing) {
      // Create new conference
      final created = await repo.create(
        name: name,
        timezone: _timezone,
        description: description,
        venue: venue,
        startDate: _startDate,
        endDate: _endDate,
        roleType: _roleType,
        roleText: roleText,
        requestedOutputs: outputs,
        defaultRecordingProfile: _defaultProfile,
        policyAcknowledgedAt: policyTimestamp,
      );

      // Save priority goals
      for (var i = 0; i < 3; i++) {
        final text = _priorityGoalControllers[i].text.trim();
        if (text.isNotEmpty) {
          await repo.addGoal(created.id, text, priority: i + 1);
        }
      }

      // Save optional goals
      for (final c in _optionalGoalControllers) {
        final text = c.text.trim();
        if (text.isNotEmpty) {
          await repo.addGoal(created.id, text);
        }
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) =>
                ConferenceHomeScreen(conferenceId: created.id),
          ),
        );
      }
    } else {
      // Update existing conference
      final confId = widget.conferenceId!;

      // FR-QUAL-03: new activities only, unless the user confirms moving
      // unrecorded ones too. Cancel saves nothing.
      var includeUnrecorded = false;
      if (_existingConference?.defaultRecordingProfile != _defaultProfile) {
        final unrecorded = await repo.countUnrecordedInheritingActivities(
          confId,
        );
        if (unrecorded > 0) {
          if (!mounted) return;
          final choice = await showProfileBulkChangeDialog(
            context,
            unrecordedCount: unrecorded,
            profile: _defaultProfile,
          );
          if (choice == null) return;
          includeUnrecorded = choice;
        }
      }

      await repo.update(
        confId,
        ConferencesCompanion(
          name: Value(name),
          description: Value(description),
          venue: Value(venue),
          startDate: Value(_startDate),
          endDate: Value(_endDate),
          timezone: Value(_timezone),
          roleType: Value(_roleType),
          roleText: Value(roleText),
          requestedOutputs: Value(outputs),
          policyAcknowledgedAt: Value(policyTimestamp),
        ),
      );

      // Handle profile change if different
      if (_existingConference?.defaultRecordingProfile != _defaultProfile) {
        await repo.changeDefaultRecordingProfile(
          confId,
          _defaultProfile,
          includeUnrecordedActivities: includeUnrecorded,
        );
      }

      // Sync priority goals
      for (var i = 0; i < 3; i++) {
        final text = _priorityGoalControllers[i].text.trim();
        final existingId = _priorityGoalIds[i];
        if (existingId != null) {
          if (text.isEmpty) {
            await repo.deleteGoal(existingId);
            _priorityGoalIds.remove(i);
          } else {
            await repo.updateGoal(existingId, text: text);
          }
        } else if (text.isNotEmpty) {
          final newGoal = await repo.addGoal(confId, text, priority: i + 1);
          _priorityGoalIds[i] = newGoal.id;
        }
      }

      // Sync optional goals
      for (var i = 0; i < _optionalGoalControllers.length; i++) {
        final text = _optionalGoalControllers[i].text.trim();
        if (i < _optionalGoalIds.length) {
          final existingId = _optionalGoalIds[i];
          if (text.isEmpty) {
            await repo.deleteGoal(existingId);
          } else {
            await repo.updateGoal(existingId, text: text);
          }
        } else if (text.isNotEmpty) {
          final newGoal = await repo.addGoal(confId, text);
          _optionalGoalIds.add(newGoal.id);
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleArchive() async {
    final conf = _existingConference;
    if (conf == null) return;
    final repo = ref.read(conferenceRepositoryProvider);

    if (conf.isArchived) {
      await repo.unarchive(conf.id);
      if (mounted) {
        setState(() {
          _existingConference = conf;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Conference unarchived')));
        Navigator.of(context).pop();
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Archive ${conf.name}?'),
          content: const Text(
            'Archived conferences are hidden from the active list but can be viewed and unarchived at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive conference'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await repo.archive(conf.id);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _handleDelete() async {
    final conf = _existingConference;
    if (conf == null) return;

    final deleted = await ConferenceDeleteDialog.show(
      context,
      conference: conf,
    );

    if (deleted && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tzService = ref.watch(deviceTimezoneServiceProvider);
    final availableTzs = tzService.getAvailableTimezones();

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.isEditing ? 'Edit conference' : 'New conference'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit conference' : 'New conference'),
        actions: [
          if (widget.isEditing) ...[
            IconButton(
              icon: Icon(
                _existingConference?.isArchived == true
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              tooltip: _existingConference?.isArchived == true
                  ? 'Unarchive conference'
                  : 'Archive conference',
              onPressed: _handleArchive,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete conference',
              onPressed: _handleDelete,
            ),
          ],
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
                    // Section 1: Details (FR-CONF-02)
                    _buildSectionHeader('Conference details'),
                    const SizedBox(height: TokenSpace.space3),
                    TextFormField(
                      key: const Key('conference-name-input'),
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Conference name *',
                        hintText: 'e.g. Health Security 2026',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'A conference needs a name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    TextFormField(
                      key: const Key('conference-venue-input'),
                      controller: _venueController,
                      decoration: const InputDecoration(
                        labelText: 'Location / Venue',
                        hintText: 'e.g. ExCeL London, Hall 3',
                      ),
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('start-date-button'),
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(
                              _startDate == null
                                  ? 'Start date'
                                  : formatDateShort(_startDate!),
                            ),
                            onPressed: () => _pickDate(isStart: true),
                          ),
                        ),
                        const SizedBox(width: TokenSpace.space3),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('end-date-button'),
                            icon: const Icon(Icons.event, size: 18),
                            label: Text(
                              _endDate == null
                                  ? 'End date'
                                  : formatDateShort(_endDate!),
                            ),
                            onPressed: () => _pickDate(isStart: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    DropdownButtonFormField<String>(
                      key: const Key('timezone-dropdown'),
                      // Long zone names shorten instead of overflowing.
                      isExpanded: true,
                      initialValue: availableTzs.contains(_timezone)
                          ? _timezone
                          : availableTzs.first,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        helperText:
                            'Default titles and calendar use this timezone',
                      ),
                      items: availableTzs.map((tz) {
                        return DropdownMenuItem(value: tz, child: Text(tz));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _timezone = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    TextFormField(
                      key: const Key('conference-description-input'),
                      controller: _descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Key topics, themes or attendee notes',
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space5),
                    const Divider(),
                    const SizedBox(height: TokenSpace.space4),

                    // Section 2: Participant Role (FR-CONF-03)
                    _buildSectionHeader('Your role'),
                    const SizedBox(height: TokenSpace.space2),
                    Text(
                      'Choose your role at this conference:',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    Wrap(
                      spacing: TokenSpace.space2,
                      runSpacing: TokenSpace.space2,
                      children: RoleType.values.map((role) {
                        final isSelected = _roleType == role;
                        return ChoiceChip(
                          key: Key('role-chip-${role.key}'),
                          label: Text(role.label),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _roleType = role;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    TextFormField(
                      key: const Key('role-text-input'),
                      controller: _roleTextController,
                      decoration: const InputDecoration(
                        labelText: 'Profession or organisational role',
                        hintText: 'e.g. Senior enterprise data architect',
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space5),
                    const Divider(),
                    const SizedBox(height: TokenSpace.space4),

                    // Section 3: Goals (FR-CONF-04)
                    _buildSectionHeader('Priority goals'),
                    const SizedBox(height: TokenSpace.space2),
                    Text(
                      'Set up to three priority goals to guide capture and export prompts:',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: TokenSpace.space2),
                    Wrap(
                      spacing: TokenSpace.space2,
                      children: goalExamples.map((ex) {
                        return ActionChip(
                          label: Text(
                            ex,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          tooltip: ex,
                          onPressed: () {
                            for (var i = 0; i < 3; i++) {
                              if (_priorityGoalControllers[i].text.isEmpty) {
                                setState(() {
                                  _priorityGoalControllers[i].text = ex;
                                });
                                break;
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    for (var i = 0; i < 3; i++) ...[
                      TextFormField(
                        key: Key('priority-goal-input-$i'),
                        controller: _priorityGoalControllers[i],
                        decoration: InputDecoration(
                          labelText: 'Priority goal ${i + 1}',
                          hintText: i < goalExamples.length
                              ? goalExamples[i]
                              : 'What do you want to learn or achieve?',
                        ),
                      ),
                      const SizedBox(height: TokenSpace.space2),
                    ],
                    if (_optionalGoalControllers.isNotEmpty) ...[
                      const SizedBox(height: TokenSpace.space2),
                      Text(
                        'Additional goals:',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: TokenSpace.space2),
                      for (
                        var i = 0;
                        i < _optionalGoalControllers.length;
                        i++
                      ) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: Key('optional-goal-input-$i'),
                                controller: _optionalGoalControllers[i],
                                decoration: InputDecoration(
                                  labelText: 'Goal ${i + 4}',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Remove goal',
                              onPressed: () => _removeOptionalGoal(i),
                            ),
                          ],
                        ),
                        const SizedBox(height: TokenSpace.space2),
                      ],
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('add-goal-button'),
                        icon: const Icon(Icons.add),
                        label: const Text('Add another goal'),
                        onPressed: _addOptionalGoal,
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space5),
                    const Divider(),
                    const SizedBox(height: TokenSpace.space4),

                    // Section 4: Expected Outputs (FR-CONF-05)
                    _buildSectionHeader('Expected outputs'),
                    const SizedBox(height: TokenSpace.space2),
                    Text(
                      'Select the outputs you plan to produce from this conference:',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    Wrap(
                      spacing: TokenSpace.space2,
                      runSpacing: TokenSpace.space2,
                      children: RequestedOutput.values.map((out) {
                        final isSelected = _requestedOutputs.contains(out);
                        return FilterChip(
                          key: Key('output-chip-${out.key}'),
                          label: Text(out.label),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _requestedOutputs.add(out);
                              } else {
                                _requestedOutputs.remove(out);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: TokenSpace.space5),
                    const Divider(),
                    const SizedBox(height: TokenSpace.space4),

                    // Section 5: Default Recording Profile (FR-CONF-07)
                    _buildSectionHeader('Default recording profile'),
                    const SizedBox(height: TokenSpace.space2),
                    Text(
                      'New activities will use this recording profile unless overridden:',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    RadioGroup<RecordingProfile>(
                      groupValue: _defaultProfile,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _defaultProfile = val;
                          });
                        }
                      },
                      child: Column(
                        children: RecordingProfile.values.map((profile) {
                          final isSelected = _defaultProfile == profile;
                          return Card(
                            margin: const EdgeInsets.only(
                              bottom: TokenSpace.space2,
                            ),
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(TokenRadius.radiusMd),
                              ),
                            ),
                            child: RadioListTile<RecordingProfile>(
                              key: Key('profile-tile-${profile.key}'),
                              value: profile,
                              // Wraps at large text (NFR-09).
                              title: Wrap(
                                spacing: TokenSpace.space2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    profile.label,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    profile.mbPerHourLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                profile.description,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space5),
                    const Divider(),
                    const SizedBox(height: TokenSpace.space4),

                    // Section 6: Recording policy notice (FR-CONF-06)
                    _buildSectionHeader('Recording policy'),
                    const SizedBox(height: TokenSpace.space3),
                    Card(
                      color: theme.colorScheme.surfaceContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(TokenSpace.space4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: TokenSpace.space3),
                                Expanded(
                                  child: Text(
                                    'Some events and speakers do not allow recording. Record only when permitted.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            CheckboxListTile(
                              key: const Key('policy-acknowledge-checkbox'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'I understand and will record only when permitted',
                              ),
                              value: _policyAcknowledged,
                              onChanged: (val) {
                                setState(() {
                                  _policyAcknowledged = val ?? false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space6),

                    // Save / Create button
                    FilledButton(
                      key: const Key('save-conference-button'),
                      onPressed: _save,
                      child: Text(
                        widget.isEditing ? 'Save changes' : 'Create conference',
                      ),
                    ),
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

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
