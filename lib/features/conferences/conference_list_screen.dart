import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../capture/recording_banner.dart';
import '../export/import_export_screen.dart';
import '../settings/settings_screen.dart';
import '../storage_manager/storage_manager_screen.dart';
import 'conference_card.dart';
import 'conference_home_screen.dart';
import 'conference_wizard_screen.dart';

/// List of all conferences with active / archived views (FR-CONF-08, NFR-02),
/// search and image-based cards as on the screens board (FR-UI-10, ADR-052)
/// [P1-39].
class ConferenceListScreen extends ConsumerStatefulWidget {
  const ConferenceListScreen({super.key, this.inShell = false});

  /// Shown as the Conferences destination of the navigation shell. The
  /// shell's bar already has Library (with the Storage Manager) and
  /// Settings, so the app bar keeps only Import an export. Opened on its
  /// own, the list keeps the Storage Manager button and Settings in its
  /// menu.
  final bool inShell;

  static const searchHint = 'Search conferences...';

  @override
  ConsumerState<ConferenceListScreen> createState() =>
      _ConferenceListScreenState();
}

class _ConferenceListScreenState extends ConsumerState<ConferenceListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// The route this list is shown in (its own, or the shell's).
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _route?.secondaryAnimation?.removeStatusListener(_onCoveringRoute);
    _route = route;
    route?.secondaryAnimation?.addStatusListener(_onCoveringRoute);
  }

  /// Any screen opened over the list, including the recorder opened from
  /// the recording banner, may have added photos or activities or removed
  /// a conference. When it has closed, the list and card counts reload.
  void _onCoveringRoute(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) _reload();
  }

  @override
  void dispose() {
    _route?.secondaryAnimation?.removeStatusListener(_onCoveringRoute);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Reloads the conferences and their card counts and covers.
  void _reload() {
    ref.invalidate(allConferencesFutureProvider);
    ref.invalidate(conferenceCardInfoProvider);
  }

  Future<void> _openConference(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConferenceHomeScreen(conferenceId: id),
      ),
    );
    _reload();
  }

  /// Deleting local copies can remove a conference, so the list reloads
  /// on return (FR-STO-06) [P1-20].
  Future<void> _openStorageManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const StorageManagerScreen(),
      ),
    );
    _reload();
  }

  Future<void> _openCreateWizard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ConferenceWizardScreen(),
      ),
    );
    _reload();
  }

  /// "Import an export" (FR-EXP-11, ADR-049) [P1-23].
  Future<void> _openImport() async {
    final id = await ImportExportScreen.open(context);
    _reload();
    if (id != null && mounted) await _openConference(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My conferences'),
        actions: [
          if (!widget.inShell)
            IconButton(
              key: const Key('open-storage-manager-button'),
              icon: const Icon(Icons.storage_outlined),
              tooltip: 'Storage Manager',
              onPressed: _openStorageManager,
            ),
          // Settings holds Privacy, app lock and the quick guide (5.11,
          // ADR-048) [P1-25]. Import an export (FR-EXP-11) [P1-23].
          PopupMenuButton<String>(
            key: const Key('conference-list-menu'),
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'settings') unawaited(SettingsScreen.open(context));
              if (value == 'import') unawaited(_openImport());
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                key: Key('menu-import'),
                value: 'import',
                child: Text('Import an export'),
              ),
              if (!widget.inShell)
                const PopupMenuItem(
                  key: Key('menu-settings'),
                  value: 'settings',
                  child: Text('Settings'),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Archived'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-conference-fab'),
        onPressed: _openCreateWizard,
        icon: const Icon(Icons.add),
        label: const Text('New conference'),
      ),
      body: WithRecordingBanner(
        child: Builder(
          builder: (context) {
            final asyncVal = ref.watch(allConferencesFutureProvider);
            if (asyncVal.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final all = asyncVal.asData?.value ?? const <Conference>[];
            final active = all.where((c) => !c.isArchived).toList();
            final archived = all.where((c) => c.isArchived).toList();
            final info =
                ref.watch(conferenceCardInfoProvider).asData?.value ??
                const <String, ConferenceCardInfo>{};

            return Column(
              children: [
                _buildSearchField(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildConferenceList(
                        active,
                        info,
                        emptyMessage:
                            'No active conferences. Tap "New conference" to '
                            'get started.',
                      ),
                      _buildConferenceList(
                        archived,
                        info,
                        emptyMessage: 'No archived conferences.',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// "Search conferences..." filters both tabs by name and place
  /// (FR-UI-10) [P1-39].
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TokenSpace.space4,
        TokenSpace.space3,
        TokenSpace.space4,
        TokenSpace.space1,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: TextField(
            key: const Key('conference-search-field'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: ConferenceListScreen.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('conference-search-clear'),
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
      ),
    );
  }

  Widget _buildConferenceList(
    List<Conference> conferences,
    Map<String, ConferenceCardInfo> info, {
    required String emptyMessage,
  }) {
    final theme = Theme.of(context);
    final query = _query.trim();
    final shown = conferences
        .where((c) => conferenceMatchesSearch(c, query))
        .toList();

    if (shown.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(TokenSpace.space4),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                conferences.isNotEmpty && query.isNotEmpty
                    ? 'No conferences match "$query".'
                    : emptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      // Room under the last card for the floating "New conference" button.
      padding: const EdgeInsets.fromLTRB(
        TokenSpace.space4,
        TokenSpace.space2,
        TokenSpace.space4,
        TokenSpace.space7 + TokenSpace.space6,
      ),
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final conf = shown[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ConferenceCard(
              key: Key('conference-card-${conf.id}'),
              conference: conf,
              info: info[conf.id] ?? ConferenceCardInfo.empty,
              onTap: () => _openConference(conf.id),
            ),
          ),
        );
      },
    );
  }
}

/// True when [query] is empty or appears in the conference's name or place,
/// ignoring case (FR-UI-10, ADR-052) [P1-39].
bool conferenceMatchesSearch(Conference conference, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return conference.name.toLowerCase().contains(q) ||
      (conference.venue ?? '').toLowerCase().contains(q);
}
