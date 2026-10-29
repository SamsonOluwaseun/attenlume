import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../conferences/conference_card.dart';
import '../conferences/conference_list_screen.dart';
import '../settings/settings_screen.dart';
import 'library_page.dart';
import 'record_page.dart';

/// The four destinations of the screens board's navigation (ADR-052).
enum ShellDestination {
  conferences('Conferences', Icons.event_outlined, Icons.event),
  record('Record', Icons.mic_none_outlined, Icons.mic),
  library('Library', Icons.folder_outlined, Icons.folder),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Navigation shell (FR-UI-11, ADR-052) [P1-39]: a bottom navigation bar on
/// phones and a side rail on tablets and Windows.
///
/// Screens opened from a destination (conference home, recording, review,
/// export) are pushed on the app's navigator, so they cover the shell and
/// the recording screen stays full screen without the bar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initial = ShellDestination.conferences});

  final ShellDestination initial;

  /// Window width, in dp, from which the side rail replaces the bottom bar:
  /// Material's "expanded" window class. Phones in portrait and landscape
  /// and small tablets in portrait get the bar; larger tablets, Surface and
  /// Windows windows get the rail.
  static const railBreakpoint = 840.0;

  static bool useRail(double width) => width >= railBreakpoint;

  static Future<void> open(
    BuildContext context, {
    ShellDestination initial = ShellDestination.conferences,
  }) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => AppShell(initial: initial)));

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late ShellDestination _current = widget.initial;

  /// Destinations built so far. Each keeps its state (search text, scroll)
  /// when the user switches away; ones never opened are not built.
  late final Set<ShellDestination> _built = {widget.initial};

  void _select(int index) {
    final next = ShellDestination.values[index];
    // Data may have changed on another destination (a conference created
    // from Record, local copies deleted from Library), so reload it.
    switch (next) {
      case ShellDestination.conferences:
        ref.invalidate(allConferencesFutureProvider);
        ref.invalidate(conferenceCardInfoProvider);
      case ShellDestination.record:
        ref.invalidate(recentConferencesProvider);
      case ShellDestination.library || ShellDestination.settings:
        break;
    }
    setState(() {
      _current = next;
      _built.add(next);
    });
  }

  Widget _page(ShellDestination d) => switch (d) {
    ShellDestination.conferences => const ConferenceListScreen(inShell: true),
    ShellDestination.record => const RecordPage(),
    ShellDestination.library => const LibraryPage(),
    ShellDestination.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final rail = AppShell.useRail(MediaQuery.sizeOf(context).width);
    final index = _current.index;

    final body = IndexedStack(
      index: index,
      children: [
        for (final d in ShellDestination.values)
          _built.contains(d)
              ? KeyedSubtree(key: ValueKey(d), child: _page(d))
              : const SizedBox.shrink(),
      ],
    );

    if (rail) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                key: const Key('shell-navigation-rail'),
                selectedIndex: index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -1,
                destinations: [
                  for (final d in ShellDestination.values)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        key: const Key('shell-navigation-bar'),
        selectedIndex: index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in ShellDestination.values)
            NavigationDestination(
              key: Key('nav-${d.name}'),
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
