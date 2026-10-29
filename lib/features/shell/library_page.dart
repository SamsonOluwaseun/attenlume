import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../capture/recording_banner.dart';
import '../conferences/conference_home_screen.dart';
import '../export/import_export_screen.dart';
import '../storage_manager/storage_manager_screen.dart';

/// The Library destination (FR-UI-11, ADR-052) [P1-39]: what is kept on
/// this device and how to bring an export back. Both entries open screens
/// that already exist: the Storage Manager (P1-20) and Import an export
/// (P1-23). Nothing here talks to a network.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  Future<void> _import(BuildContext context) async {
    final id = await ImportExportScreen.open(context);
    if (id == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConferenceHomeScreen(conferenceId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: WithRecordingBanner(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: TokenSpace.space2),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('library-storage-manager'),
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Files on this device'),
                      subtitle: const Text(
                        'Recordings and photos by conference and activity: '
                        'sizes, export and delete local copies',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StorageManagerScreen(),
                          ),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key('library-import'),
                      leading: const Icon(Icons.unarchive_outlined),
                      title: const Text('Import an export'),
                      subtitle: const Text(
                        'Bring back a conference from an export folder or ZIP',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => unawaited(_import(context)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
