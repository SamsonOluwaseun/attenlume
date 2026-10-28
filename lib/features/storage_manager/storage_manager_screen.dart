import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/storage_breakdown.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';
import 'clear_temp_dialog.dart';
import 'delete_local_dialog.dart';
import 'models_dialog.dart';
import 'storage_manager_providers.dart';

/// Storage Manager screen providing granular breakdown per conference and activity,
/// export status badges, verified-export-gated local media cleanup, safe temporary
/// file removal and offline model management (FR-STO-05, FR-STO-06, FR-STO-07) [P1-20].
class StorageManagerScreen extends ConsumerStatefulWidget {
  const StorageManagerScreen({super.key, this.initialConferenceId});

  /// Optional conference ID to focus or auto-expand.
  final String? initialConferenceId;

  @override
  ConsumerState<StorageManagerScreen> createState() =>
      _StorageManagerScreenState();
}

class _StorageManagerScreenState extends ConsumerState<StorageManagerScreen> {
  final Set<String> _expandedConferences = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialConferenceId != null) {
      _expandedConferences.add(widget.initialConferenceId!);
    }
  }

  void _toggleExpanded(String conferenceId) {
    setState(() {
      if (_expandedConferences.contains(conferenceId)) {
        _expandedConferences.remove(conferenceId);
      } else {
        _expandedConferences.add(conferenceId);
      }
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(storageBreakdownProvider);
    await ref.read(storageBreakdownProvider.future);
  }

  Future<void> _openClearTempDialog(AppStorageBreakdown breakdown) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ClearTempDialog(
        safeTemporaryBytes: breakdown.safeTemporaryBytes,
        keptOriginalsBytes: breakdown.keptOriginalsTotalBytes,
        keptOriginalsCount: breakdown.keptOriginalsCount,
        onConfirm: (includeKeptOriginals) async {
          final res = await ref
              .read(storageManagerServiceProvider)
              .clearSafeTemporaryFiles(
                includeKeptOriginals: includeKeptOriginals,
              );
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Cleared ${res.filesDeleted} safe temporary file(s), freeing ${formatStorageBytes(res.bytesFreed)}.',
              ),
            ),
          );
        },
      ),
    );
    if (result == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _openRemoveKeptOriginalsDialog(
    AppStorageBreakdown breakdown,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove kept originals'),
        content: Text(
          'Remove ${breakdown.keptOriginalsCount} original recording(s) (${formatStorageBytes(breakdown.keptOriginalsTotalBytes)}) retained when applying permanent trims? These files are not referenced by any current session.',
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

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final res = await ref
          .read(storageManagerServiceProvider)
          .removeKeptOriginals();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${res.filesDeleted} kept original(s), freeing ${formatStorageBytes(res.bytesFreed)}.',
          ),
        ),
      );
      if (mounted) {
        await _refresh();
      }
    }
  }

  Future<void> _openDeleteLocalDialog({
    required String conferenceId,
    String? activityId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final preview = await ref
          .read(storageManagerServiceProvider)
          .previewDeleteLocalCopies(
            conferenceId: conferenceId,
            activityId: activityId,
            keepLightweightIndex: true, // Default to keeping index (FR-STO-07).
          );

      if (!mounted) return;

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => DeleteLocalDialog(
          preview: preview,
          onConfirm: (keepIndex) async {
            final res = await ref
                .read(storageManagerServiceProvider)
                .deleteLocalCopies(
                  conferenceId: conferenceId,
                  activityId: activityId,
                  keepLightweightIndex: keepIndex,
                );
            final msg = keepIndex
                ? 'Freed ${formatStorageBytes(res.bytesFreed)}. Lightweight archived index retained.'
                : 'Deleted ${res.filesDeleted} local media file(s), freeing ${formatStorageBytes(res.bytesFreed)}.';
            messenger.showSnackBar(SnackBar(content: Text(msg)));
          },
        ),
      );

      if (result == true && mounted) {
        await _refresh();
      }
    } on StorageManagerException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openManageModels() {
    showDialog<void>(
      context: context,
      builder: (context) => const ModelsDialog(),
    );
  }

  void _showExportNotice(String conferenceName) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export $conferenceName'),
        content: const Text(
          'Full export pipeline (streaming ZIP/folder export with checksum verification) will be available in the upcoming release (P1-21).\n\nOnce exported and checksum-verified, local copies can be safely deleted to free storage on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdownAsync = ref.watch(storageBreakdownProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Manager'),
        actions: [
          IconButton(
            key: const Key('refresh-storage-button'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh storage breakdown',
            onPressed: () async {
              await _refresh();
            },
          ),
        ],
      ),
      body: breakdownAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to calculate storage: $err'),
              const SizedBox(height: TokenSpace.space3),
              AttenlumeButton(
                label: 'Retry',
                onPressed: () async {
                  await _refresh();
                },
                variant: AttenlumeButtonVariant.secondary,
              ),
            ],
          ),
        ),
        data: (breakdown) => RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildOverviewCard(theme, breakdown),
                    const SizedBox(height: TokenSpace.space4),

                    // Kept originals banner if any exist
                    if (breakdown.keptOriginalsCount > 0) ...[
                      _buildKeptOriginalsCard(theme, breakdown),
                      const SizedBox(height: TokenSpace.space4),
                    ],

                    // Section header: Conferences
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Conferences',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${breakdown.conferences.length} total',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TokenSpace.space2),

                    if (breakdown.conferences.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(TokenSpace.space4),
                          child: Text(
                            'No conferences found. Record or create a conference to start managing storage.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      ...breakdown.conferences.map(
                        (conf) => _buildConferenceCard(theme, conf),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ThemeData theme, AppStorageBreakdown breakdown) {
    final sizes = breakdown.overallSizes;

    return Card(
      key: const Key('storage-overview-card'),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Device storage',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatStorageBytes(breakdown.appTotalBytes),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: TokenSpace.space2),
            if (breakdown.totalDeviceFreeBytes != null) ...[
              Text(
                'Free space: ${formatStorageBytes(breakdown.totalDeviceFreeBytes!)}'
                '${breakdown.totalDeviceCapacityBytes != null ? ' of ${formatStorageBytes(breakdown.totalDeviceCapacityBytes!)} available' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: TokenSpace.space3),
            ],

            // Category breakdown chips
            Wrap(
              spacing: TokenSpace.space2,
              runSpacing: TokenSpace.space2,
              children: [
                _kindChip(theme, 'Audio', sizes.audioBytes, Icons.mic_rounded),
                _kindChip(
                  theme,
                  'Photos',
                  sizes.photoBytes,
                  Icons.photo_camera_rounded,
                ),
                _kindChip(
                  theme,
                  'Thumbnails',
                  sizes.thumbnailBytes,
                  Icons.image_outlined,
                ),
                if (sizes.keptOriginalBytes > 0)
                  _kindChip(
                    theme,
                    'Kept originals',
                    sizes.keptOriginalBytes,
                    Icons.history_rounded,
                  ),
                if (breakdown.safeTemporaryBytes > 0)
                  _kindChip(
                    theme,
                    'Safe temp',
                    breakdown.safeTemporaryBytes,
                    Icons.cleaning_services_rounded,
                  ),
                _kindChip(
                  theme,
                  'Transcripts',
                  sizes.transcriptBytes,
                  Icons.description_outlined,
                ),
                _kindChip(
                  theme,
                  'Models',
                  sizes.modelBytes,
                  Icons.memory_rounded,
                ),
              ],
            ),

            const SizedBox(height: TokenSpace.space4),
            const Divider(),
            const SizedBox(height: TokenSpace.space2),

            // Global Actions Row
            Row(
              children: [
                Expanded(
                  child: AttenlumeButton(
                    key: const Key('clear-safe-temp-button'),
                    label: 'Clear temporary files',
                    leading: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                    variant: AttenlumeButtonVariant.secondary,
                    onPressed: () => _openClearTempDialog(breakdown),
                  ),
                ),
                const SizedBox(width: TokenSpace.space3),
                Expanded(
                  child: AttenlumeButton(
                    key: const Key('manage-models-button'),
                    label: 'Manage models',
                    leading: const Icon(Icons.memory_outlined, size: 18),
                    variant: AttenlumeButtonVariant.secondary,
                    onPressed: _openManageModels,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeptOriginalsCard(
    ThemeData theme,
    AppStorageBreakdown breakdown,
  ) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space3),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, color: Colors.amber),
            const SizedBox(width: TokenSpace.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Originals kept after trimming',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${breakdown.keptOriginalsCount} file(s) • ${formatStorageBytes(breakdown.keptOriginalsTotalBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AttenlumeButton(
              key: const Key('remove-kept-originals-button'),
              label: 'Remove',
              variant: AttenlumeButtonVariant.danger,
              onPressed: () => _openRemoveKeptOriginalsDialog(breakdown),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConferenceCard(
    ThemeData theme,
    ConferenceStorageBreakdown conf,
  ) {
    final isExpanded = _expandedConferences.contains(conf.conferenceId);
    final isVerified = conf.exportStatus.isVerified;

    return Card(
      key: Key('conference-storage-card-${conf.conferenceId}'),
      margin: const EdgeInsets.only(bottom: TokenSpace.space3),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpanded(conf.conferenceId),
            borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(TokenSpace.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conf.conferenceName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildExportStatusBadge(theme, conf.exportStatus),
                    ],
                  ),
                  const SizedBox(height: TokenSpace.space2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${conf.activities.length} activities • ${formatStorageBytes(conf.totalBytes)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: TokenSpace.space2),
                  _buildMiniKindBar(theme, conf.sizes),
                ],
              ),
            ),
          ),

          // Actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TokenSpace.space4,
              0,
              TokenSpace.space4,
              TokenSpace.space3,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  key: Key('export-conference-${conf.conferenceId}'),
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Export and archive'),
                  onPressed: () => _showExportNotice(conf.conferenceName),
                ),
                const SizedBox(width: TokenSpace.space2),
                Tooltip(
                  message: isVerified
                      ? 'Delete local media copies to free space'
                      : 'Requires a verified export before local copies can be deleted (FR-STO-06)',
                  child: AttenlumeButton(
                    key: Key('delete-local-conference-${conf.conferenceId}'),
                    label: 'Delete local copies',
                    variant: AttenlumeButtonVariant.danger,
                    onPressed: isVerified
                        ? () => _openDeleteLocalDialog(
                            conferenceId: conf.conferenceId,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),

          // Activities list when expanded
          if (isExpanded) ...[
            const Divider(height: 1),
            Container(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.2,
              ),
              padding: const EdgeInsets.all(TokenSpace.space3),
              child: conf.activities.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(TokenSpace.space2),
                      child: Text(
                        'No activities in this conference.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: conf.activities
                          .map((act) => _buildActivityTile(theme, conf, act))
                          .toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityTile(
    ThemeData theme,
    ConferenceStorageBreakdown conf,
    ActivityStorageBreakdown act,
  ) {
    final isVerified = act.exportStatus.isVerified;

    return Container(
      key: Key('activity-storage-tile-${act.activityId}'),
      margin: const EdgeInsets.only(bottom: TokenSpace.space2),
      padding: const EdgeInsets.all(TokenSpace.space3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  act.activityTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildExportStatusBadge(theme, act.exportStatus),
            ],
          ),
          const SizedBox(height: TokenSpace.space1),
          Row(
            children: [
              Text(
                '${act.activityTypeLabel} • Total: ${formatStorageBytes(act.totalBytes)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: TokenSpace.space2),
          // Sub-sizes row
          Wrap(
            spacing: TokenSpace.space2,
            runSpacing: TokenSpace.space1,
            children: [
              if (act.sizes.audioBytes > 0)
                _miniKindText('Audio', act.sizes.audioBytes),
              if (act.sizes.photoBytes > 0)
                _miniKindText('Photos', act.sizes.photoBytes),
              if (act.sizes.thumbnailBytes > 0)
                _miniKindText('Thumbnails', act.sizes.thumbnailBytes),
              if (act.sizes.keptOriginalBytes > 0)
                _miniKindText('Originals', act.sizes.keptOriginalBytes),
              if (act.sizes.derivedBytes > 0)
                _miniKindText('Waveforms', act.sizes.derivedBytes),
            ],
          ),
          const SizedBox(height: TokenSpace.space2),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: isVerified
                  ? 'Delete local copies of this session'
                  : 'Requires a verified export first (FR-STO-06)',
              child: TextButton.icon(
                key: Key('delete-local-activity-${act.activityId}'),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete local copies'),
                style: TextButton.styleFrom(
                  foregroundColor: isVerified
                      ? theme.colorScheme.error
                      : theme.disabledColor,
                ),
                onPressed: isVerified
                    ? () => _openDeleteLocalDialog(
                        conferenceId: conf.conferenceId,
                        activityId: act.activityId,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportStatusBadge(ThemeData theme, ExportStatus status) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status) {
      case ExportStatus.verified:
        bg = const Color(0xFFC2E812); // Token success / lime deep
        fg = const Color(0xFF00212B); // Token palette navy
        icon = Icons.check_circle_outline;
      case ExportStatus.uploaded:
        bg = const Color(0xFF4392F1); // Token brand blue
        fg = const Color(0xFFFEFFF8); // Token cream
        icon = Icons.cloud_done_outlined;
      case ExportStatus.exportedLocally:
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.colorScheme.onSurface;
        icon = Icons.folder_outlined;
      case ExportStatus.notExported:
        bg = theme.colorScheme.surfaceContainer;
        fg = theme.colorScheme.onSurfaceVariant;
        icon = Icons.cloud_off_outlined;
    }

    return Container(
      key: Key('export-status-badge-${status.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TokenRadius.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kindChip(ThemeData theme, String label, int bytes, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$label: ${formatStorageBytes(bytes)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _miniKindText(String label, int bytes) {
    return Text(
      '$label: ${formatStorageBytes(bytes)}',
      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
    );
  }

  Widget _buildMiniKindBar(ThemeData theme, StorageKindSizes sizes) {
    final total = sizes.totalBytes;
    if (total == 0) return const SizedBox.shrink();

    final audioFlex = (sizes.audioBytes / total * 100).round();
    final photoFlex = (sizes.photoBytes / total * 100).round();
    final thumbFlex = (sizes.thumbnailBytes / total * 100).round();
    final origFlex = (sizes.keptOriginalBytes / total * 100).round();
    final derivedFlex = (sizes.derivedBytes / total * 100).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            if (audioFlex > 0)
              Expanded(
                flex: audioFlex,
                child: Container(color: Colors.blue),
              ),
            if (photoFlex > 0)
              Expanded(
                flex: photoFlex,
                child: Container(color: Colors.teal),
              ),
            if (thumbFlex > 0)
              Expanded(
                flex: thumbFlex,
                child: Container(color: Colors.green),
              ),
            if (origFlex > 0)
              Expanded(
                flex: origFlex,
                child: Container(color: Colors.amber),
              ),
            if (derivedFlex > 0)
              Expanded(
                flex: derivedFlex,
                child: Container(color: Colors.purple),
              ),
          ],
        ),
      ),
    );
  }
}
