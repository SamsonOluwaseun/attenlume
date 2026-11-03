import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/local_database/builtin_activity_types.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/planned_session.dart';
import '../../domain/services/agenda_import.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/attenlume_button.dart';
import '../activities/activity_editor_screen.dart';
import '../activities/consent_check_dialog.dart';
import '../activities/custom_type_dialog.dart';
import '../agenda/agenda_providers.dart';
import '../agenda/agenda_section.dart';

/// Modal bottom sheet allowing users to start an activity of any type (FR-ACT-01, FR-ACT-02, FR-ACT-06, FR-ACT-07).
///
/// When the conference has an imported agenda, "From the agenda" lists the
/// planned sessions near now first; picking one fills in the title,
/// speakers, room, type and planned start (ADR-082) [P2-07].
class StartActivitySheet extends ConsumerStatefulWidget {
  const StartActivitySheet({
    super.key,
    required this.conferenceId,
    this.initialSession,
  });

  final String conferenceId;

  /// A planned session picked before the sheet opened (the conference
  /// page's agenda).
  final PlannedSession? initialSession;

  /// Agenda sessions shown before "Show all".
  static const agendaPreviewCount = 3;

  /// Shows the start activity bottom sheet.
  static Future<Activity?> show(
    BuildContext context, {
    required String conferenceId,
    PlannedSession? initialSession,
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
      builder: (context) => StartActivitySheet(
        conferenceId: conferenceId,
        initialSession: initialSession,
      ),
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

  /// The agenda, sessions near now first.
  List<PlannedSession> _agenda = [];
  String _timezone = 'UTC';
  DateTime _now = DateTime.now().toUtc();
  bool _showWholeAgenda = false;
  PlannedSession? _picked;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSession;
    if (initial != null) {
      _picked = initial;
      _titleController.text = initial.title;
    }
    _loadTypes();
    _loadAgenda();
  }

  Future<void> _loadAgenda() async {
    final sessions = await ref
        .read(plannedSessionRepositoryProvider)
        .listFor(widget.conferenceId);
    if (sessions.isEmpty) return;
    final conference = await ref
        .read(conferenceRepositoryProvider)
        .get(widget.conferenceId);
    final now = ref.read(agendaClockProvider)();
    if (!mounted) return;
    setState(() {
      _now = now;
      _timezone = conference?.timezone ?? 'UTC';
      _agenda = orderByNearNow(sessions, now);
    });
  }

  void _pick(PlannedSession session) {
    setState(() {
      if (_picked?.id == session.id) {
        _picked = null;
        _titleController.clear();
      } else {
        _picked = session;
        _titleController.text = session.title;
      }
    });
  }

  /// The type the picked session asks for (matched by label or a known
  /// word such as "Talk"), else Session.
  ActivityType? get _pickedType {
    final picked = _picked;
    if (picked == null || _types.isEmpty) return null;
    return matchActivityType(_types, picked.typeText);
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
      final picked = _picked;
      final activity = await repo.create(
        conferenceId: widget.conferenceId,
        typeId: type.id,
        title: customTitle.isNotEmpty ? customTitle : null,
        recordingPermissionStatus: permissionStatus,
        speakerNames: picked?.speakerNames ?? const [],
        room: picked?.room,
        plannedStart: picked?.startUtc,
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

  Widget _buildAgenda(ThemeData theme) {
    final picked = _picked;
    final pickedType = _pickedType;
    // A session picked on the conference page may not be in the loaded
    // list yet; show it anyway.
    final base = _agenda.isEmpty && picked != null ? [picked] : _agenda;
    final shown = _showWholeAgenda
        ? [...base]
        : base.take(StartActivitySheet.agendaPreviewCount).toList();
    if (picked != null && !shown.any((s) => s.id == picked.id)) {
      shown.insert(0, picked);
    }
    final details = picked == null
        ? ''
        : agendaDetailsLine(picked.speakerNames, picked.room);
    return Column(
      key: const Key('start-from-agenda'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'From the agenda',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: TokenSpace.space1),
        for (final s in shown)
          PlannedSessionTile(
            session: s,
            timezone: _timezone,
            nowUtc: _now,
            selected: picked?.id == s.id,
            actionHint: picked?.id == s.id
                ? 'Picked. Tap to clear'
                : 'Fill in the details from this session',
            onTap: _isCreating ? null : () => _pick(s),
          ),
        if (base.length > StartActivitySheet.agendaPreviewCount)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('start-agenda-show-all'),
              onPressed: () =>
                  setState(() => _showWholeAgenda = !_showWholeAgenda),
              child: Text(
                _showWholeAgenda
                    ? 'Show fewer sessions'
                    : 'Show all ${base.length} sessions',
              ),
            ),
          ),
        if (picked != null && pickedType != null) ...[
          const SizedBox(height: TokenSpace.space2),
          Semantics(
            liveRegion: true,
            child: Text(
              [
                'Picked: ${picked.title}.',
                'Type: ${pickedType.label}.',
                if (details.isNotEmpty) '$details.',
              ].join(' '),
              key: const Key('start-agenda-picked-summary'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: TokenSpace.space2),
          AttenlumeButton(
            key: const Key('start-from-agenda-button'),
            label: 'Start ${pickedType.label.toLowerCase()}',
            leading: Icon(activityTypeIconData(pickedType.icon)),
            onPressed: _isCreating ? null : () => _createActivity(pickedType),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: theme.colorScheme.surface,
      child: SingleChildScrollView(
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Start activity',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

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
              if (_agenda.isNotEmpty || _picked != null) ...[
                const SizedBox(height: TokenSpace.space4),
                _buildAgenda(theme),
              ],
              const SizedBox(height: TokenSpace.space4),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Select type',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

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
                Wrap(
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
      ),
    );
  }
}
