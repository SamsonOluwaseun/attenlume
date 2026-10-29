import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../domain/models/storage_breakdown.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';
import '../capture/recording_banner.dart';
import '../export/export_sheet.dart';
import 'clear_temp_dialog.dart';
import 'delete_local_dialog.dart';
import 'models_dialog.dart';
import 'storage_manager_providers.dart';

/// Storage Manager (FR-STO-05, FR-STO-06, ADR-047) [P1-20]: sizes per
/// conference and activity, export status, Export and archive (the export
/// sheet), Delete local copies after a verified export, Clear safe
/// temporary files, Remove kept originals and Manage offline models.
class StorageManagerScreen extends ConsumerStatefulWidget {
  const StorageManagerScreen({super.key, this.initialConferenceId});

  /// Opened from a conference: that conference starts expanded.
  final String? initialConferenceId;

  @override
  ConsumerState<StorageManagerScreen> createState() =>
      _StorageManagerScreenState();
}

class _StorageManagerScreenState extends ConsumerState<StorageManagerScreen> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialConferenceId != null) {
      _expanded.add(widget.initialConferenceId!);
    }
  }

  void _refresh() => ref.invalidate(storageBreakdownProvider);

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _clearTemporary(AppStorageBreakdown b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ClearTempDialog(
        temporaryExportBytes: b.temporaryExportBytes,
        orphanWaveformBytes: b.orphanWaveformBytes,
        recoveryBytes: b.sizes.recoveryBytes,
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ref
        .read(storageManagerServiceProvider)
        .clearSafeTemporaryFiles();
    if (!mounted) return;
    _snack(
      'Cleared ${res.filesDeleted} temporary '
      '${res.filesDeleted == 1 ? 'file' : 'files'} '
      '(${formatStorageBytes(res.bytesFreed)}).',
    );
    _refresh();
  }

  Future<void> _removeOriginals(AppStorageBreakdown b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove kept originals?'),
        content: Text(
          'This deletes ${b.keptOriginals.length} original '
          '${b.keptOriginals.length == 1 ? 'recording' : 'recordings'} '
          '(${formatStorageBytes(b.keptOriginalBytes)}) kept when trims were '
          'applied. The trimmed recordings stay. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          AttenlumeButton(
            key: const Key('confirm-remove-kept-originals-dialog-button'),
            label: 'Remove originals',
            variant: AttenlumeButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ref
        .read(storageManagerServiceProvider)
        .removeKeptOriginals(b.keptOriginals);
    if (!mounted) return;
    _snack(
      'Removed ${res.filesDeleted} kept '
      '${res.filesDeleted == 1 ? 'original' : 'originals'} '
      '(${formatStorageBytes(res.bytesFreed)}).',
    );
    _refresh();
  }

  Future<void> _export(String conferenceId, {String? activityId}) async {
    await ExportSheet.show(
      context,
      conferenceId: conferenceId,
      activityId: activityId,
    );
    if (mounted) _refresh();
  }

  Future<void> _deleteLocal(String conferenceId, {String? activityId}) async {
    final service = ref.read(storageManagerServiceProvider);
    try {
      final preview = await service.previewDeleteLocalCopies(
        conferenceId: conferenceId,
        activityId: activityId,
      );
      if (!mounted) return;
      // First the preview, then a separate confirmation (FR-STO-06).
      final next = await showDialog<bool>(
        context: context,
        builder: (_) => DeleteLocalDialog(preview: preview),
      );
      if (next != true || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => DeleteLocalConfirmDialog(preview: preview),
      );
      if (confirmed != true || !mounted) return;
      final res = await service.deleteLocalCopies(
        conferenceId: conferenceId,
        activityId: activityId,
      );
      if (!mounted) return;
      _snack(
        res.failedFiles == 0
            ? 'Deleted ${res.filesDeleted} '
                  '${res.filesDeleted == 1 ? 'file' : 'files'} '
                  '(${formatStorageBytes(res.bytesFreed)}).'
            : '${res.failedFiles} '
                  '${res.failedFiles == 1 ? 'file' : 'files'} could not be '
                  'deleted, so '
                  '${res.failedFiles == 1 ? 'its activity was' : 'their activities were'} '
                  'kept. Close other apps using them and try again.',
      );
      _refresh();
    } on StorageManagerException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = ref.watch(storageBreakdownProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Manager'),
        actions: [
          IconButton(
            key: const Key('refresh-storage-button'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: WithRecordingBanner(
        child: breakdown.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(TokenSpace.space4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Storage could not be measured.'),
                  const SizedBox(height: TokenSpace.space3),
                  AttenlumeButton(
                    label: 'Try again',
                    variant: AttenlumeButtonVariant.secondary,
                    onPressed: _refresh,
                  ),
                ],
              ),
            ),
          ),
          data: (b) => ListView(
            padding: const EdgeInsets.all(TokenSpace.space4),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _overview(b),
                      if (b.keptOriginals.isNotEmpty) ...[
                        const SizedBox(height: TokenSpace.space4),
                        _keptOriginals(b),
                      ],
                      const SizedBox(height: TokenSpace.space4),
                      Text(
                        'Conferences',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: TokenSpace.space2),
                      if (b.conferences.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(TokenSpace.space4),
                            child: Text('No conferences yet.'),
                          ),
                        )
                      else
                        for (final c in b.conferences) _conference(c),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overview(AppStorageBreakdown b) {
    final theme = Theme.of(context);
    final s = b.sizes;
    return Card(
      key: const Key('storage-overview-card'),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Used by Attenlume',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  formatStorageBytes(b.totalBytes),
                  key: const Key('storage-total'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (b.freeBytes != null) ...[
              const SizedBox(height: TokenSpace.space1),
              Text(
                'Free on this device: ${formatStorageBytes(b.freeBytes!)}'
                '${b.capacityBytes != null ? ' of ${formatStorageBytes(b.capacityBytes!)}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: TokenSpace.space3),
            Wrap(
              spacing: TokenSpace.space2,
              runSpacing: TokenSpace.space2,
              children: [
                _chip('Audio', s.audioBytes),
                _chip('Photos', s.photoBytes),
                _chip('Thumbnails', s.thumbnailBytes),
                _chip('Waveforms', s.waveformBytes),
                _chip('Kept originals', s.keptOriginalBytes),
                _chip('Temporary exports', b.temporaryExportBytes),
                if (s.recoveryBytes > 0)
                  _chip('Kept for recovery', s.recoveryBytes),
                _chip('Models', 0),
              ],
            ),
            const SizedBox(height: TokenSpace.space4),
            Wrap(
              spacing: TokenSpace.space3,
              runSpacing: TokenSpace.space2,
              children: [
                AttenlumeButton(
                  key: const Key('clear-safe-temp-button'),
                  label: 'Clear temporary files',
                  variant: AttenlumeButtonVariant.secondary,
                  onPressed: () => _clearTemporary(b),
                ),
                AttenlumeButton(
                  key: const Key('manage-models-button'),
                  label: 'Manage models',
                  variant: AttenlumeButtonVariant.secondary,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const ModelsDialog(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _keptOriginals(AppStorageBreakdown b) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('kept-originals-card'),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Originals kept after trimming',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: TokenSpace.space1),
            Text(
              '${b.keptOriginals.length} '
              '${b.keptOriginals.length == 1 ? 'file' : 'files'}, '
              '${formatStorageBytes(b.keptOriginalBytes)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: TokenSpace.space2),
            for (final o in b.keptOriginals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${o.conferenceName} · ${o.activityTitle ?? 'Deleted activity'}'
                  ' · ${formatStorageBytes(o.bytes)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: TokenSpace.space3),
            AttenlumeButton(
              key: const Key('remove-kept-originals-button'),
              label: 'Remove originals',
              variant: AttenlumeButtonVariant.danger,
              onPressed: () => _removeOriginals(b),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conference(ConferenceStorageBreakdown c) {
    final theme = Theme.of(context);
    final open = _expanded.contains(c.conferenceId);
    return Card(
      key: Key('conference-storage-card-${c.conferenceId}'),
      margin: const EdgeInsets.only(bottom: TokenSpace.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              open
                  ? _expanded.remove(c.conferenceId)
                  : _expanded.add(c.conferenceId);
            }),
            child: Padding(
              padding: const EdgeInsets.all(TokenSpace.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.conferenceName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      _StatusBadge(status: c.exportStatus),
                    ],
                  ),
                  const SizedBox(height: TokenSpace.space1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${c.activities.length} '
                          '${c.activities.length == 1 ? 'activity' : 'activities'}'
                          ' · ${formatStorageBytes(c.totalBytes)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        semanticLabel: open
                            ? 'Hide activities'
                            : 'Show activities',
                      ),
                    ],
                  ),
                  const SizedBox(height: TokenSpace.space1),
                  Text(_sizesLine(c.sizes), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          _actions(
            exportKey: Key('export-conference-${c.conferenceId}'),
            deleteKey: Key('delete-local-conference-${c.conferenceId}'),
            blockedReason: c.deleteBlockedReason,
            onExport: () => _export(c.conferenceId),
            onDelete: () => _deleteLocal(c.conferenceId),
          ),
          if (open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(TokenSpace.space3),
              child: c.activities.isEmpty
                  ? const Text('No activities in this conference.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final a in c.activities) _activity(c, a)],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activity(ConferenceStorageBreakdown c, ActivityStorageBreakdown a) {
    final theme = Theme.of(context);
    return Container(
      key: Key('activity-storage-tile-${a.activityId}'),
      margin: const EdgeInsets.only(bottom: TokenSpace.space2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TokenSpace.space3,
              TokenSpace.space3,
              TokenSpace.space3,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.activityTitle,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    _StatusBadge(status: a.exportStatus),
                  ],
                ),
                Text(
                  '${a.activityTypeLabel} · ${formatStorageBytes(a.totalBytes)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(_sizesLine(a.sizes), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          _actions(
            exportKey: Key('export-activity-${a.activityId}'),
            deleteKey: Key('delete-local-activity-${a.activityId}'),
            blockedReason: a.deleteBlockedReason,
            onExport: () => _export(c.conferenceId, activityId: a.activityId),
            onDelete: () =>
                _deleteLocal(c.conferenceId, activityId: a.activityId),
          ),
        ],
      ),
    );
  }

  /// Export and archive, Delete local copies, and why delete is off.
  Widget _actions({
    required Key exportKey,
    required Key deleteKey,
    required String? blockedReason,
    required VoidCallback onExport,
    required VoidCallback onDelete,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TokenSpace.space3,
        0,
        TokenSpace.space3,
        TokenSpace.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: TokenSpace.space2,
            children: [
              TextButton(
                key: exportKey,
                onPressed: onExport,
                child: const Text('Export and archive'),
              ),
              TextButton(
                key: deleteKey,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: blockedReason == null ? onDelete : null,
                child: const Text('Delete local copies'),
              ),
            ],
          ),
          if (blockedReason != null)
            Text(
              blockedReason,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  static String _sizesLine(StorageKindSizes s) => [
    if (s.audioBytes > 0) 'Audio ${formatStorageBytes(s.audioBytes)}',
    if (s.photoBytes > 0) 'Photos ${formatStorageBytes(s.photoBytes)}',
    if (s.thumbnailBytes > 0)
      'Thumbnails ${formatStorageBytes(s.thumbnailBytes)}',
    if (s.waveformBytes > 0) 'Waveforms ${formatStorageBytes(s.waveformBytes)}',
    if (s.keptOriginalBytes > 0)
      'Kept originals ${formatStorageBytes(s.keptOriginalBytes)}',
    if (s.recoveryBytes > 0)
      'Kept for recovery ${formatStorageBytes(s.recoveryBytes)}',
  ].join(' · ');

  Widget _chip(String label, int bytes) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TokenSpace.space2,
        vertical: TokenSpace.space1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
      ),
      child: Text(
        '$label: ${formatStorageBytes(bytes)}',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

/// Export status as text with an icon, never colour alone.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ExportStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.extension<AttenlumeColors>();
    final (Color bg, Color fg, IconData icon) = switch (status) {
      ExportStatus.verified => (
        colours?.success ?? theme.colorScheme.primary,
        colours?.onSuccess ?? theme.colorScheme.onPrimary,
        Icons.verified_outlined,
      ),
      ExportStatus.uploaded => (
        theme.colorScheme.primary,
        theme.colorScheme.onPrimary,
        Icons.cloud_done_outlined,
      ),
      ExportStatus.exportedLocally => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurface,
        Icons.folder_outlined,
      ),
      ExportStatus.notExported => (
        theme.colorScheme.surfaceContainer,
        theme.colorScheme.onSurfaceVariant,
        Icons.cloud_off_outlined,
      ),
    };
    return Container(
      key: Key('export-status-badge-${status.key}'),
      padding: const EdgeInsets.symmetric(
        horizontal: TokenSpace.space2,
        vertical: TokenSpace.space1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TokenRadius.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: TokenSpace.space1),
          Text(status.label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}
