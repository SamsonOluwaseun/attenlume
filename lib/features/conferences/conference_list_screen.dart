import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../shared/utilities/date_formatters.dart';
import 'conference_home_screen.dart';
import 'conference_wizard_screen.dart';

/// List of all conferences with active / archived views (FR-CONF-08, NFR-02).
class ConferenceListScreen extends ConsumerStatefulWidget {
  const ConferenceListScreen({super.key});

  @override
  ConsumerState<ConferenceListScreen> createState() =>
      _ConferenceListScreenState();
}

class _ConferenceListScreenState extends ConsumerState<ConferenceListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openConference(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConferenceHomeScreen(conferenceId: id),
      ),
    );
    ref.invalidate(allConferencesFutureProvider);
  }

  Future<void> _openCreateWizard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ConferenceWizardScreen(),
      ),
    );
    ref.invalidate(allConferencesFutureProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My conferences'),
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
      body: Builder(
        builder: (context) {
          final asyncVal = ref.watch(allConferencesFutureProvider);
          if (asyncVal.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = asyncVal.asData?.value ?? const <Conference>[];
          final active = all.where((c) => !c.isArchived).toList();
          final archived = all.where((c) => c.isArchived).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildConferenceList(
                active,
                emptyMessage: 'No active conferences. Tap "New conference" to get started.',
              ),
              _buildConferenceList(
                archived,
                emptyMessage: 'No archived conferences.',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConferenceList(
    List<Conference> conferences, {
    required String emptyMessage,
  }) {
    final theme = Theme.of(context);

    if (conferences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(TokenSpace.space4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(TokenSpace.space4),
      itemCount: conferences.length,
      itemBuilder: (context, index) {
        final conf = conferences[index];
        final dateText = formatDateRange(conf.startDate, conf.endDate);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              key: Key('conference-card-${conf.id}'),
              margin: const EdgeInsets.only(bottom: TokenSpace.space3),
              child: InkWell(
                borderRadius: const BorderRadius.all(
                  Radius.circular(TokenRadius.radiusMd),
                ),
                onTap: () => _openConference(conf.id),
                child: Padding(
                  padding: const EdgeInsets.all(TokenSpace.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              conf.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(TokenRadius.radiusPill),
                              ),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              conf.defaultRecordingProfile.label,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TokenSpace.space2),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 14),
                          const SizedBox(width: TokenSpace.space2),
                          Text(dateText, style: theme.textTheme.bodySmall),
                          if (conf.venue != null && conf.venue!.isNotEmpty) ...[
                            const SizedBox(width: TokenSpace.space3),
                            const Icon(Icons.location_on_outlined, size: 14),
                            const SizedBox(width: TokenSpace.space1),
                            Expanded(
                              child: Text(
                                conf.venue!,
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
