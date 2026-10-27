import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/profile_estimates.dart';
import 'recording_providers.dart';

/// Quality selector (FR-UI-08, FR-QUAL-05) [P1-09].
///
/// Lists Economy, Balanced and Enhanced with the MB per hour this device
/// will really use and the estimated recording time left. When a profile
/// cannot be met here, the effective settings are shown before recording.
/// It never starts or stops a recording: the Record button stays apart.
///
/// With [live] it shows the profile in use; a change then goes through
/// [onChanged] to `RecordingService.changeProfile` (FR-QUAL-04).
class RecordingProfileSelector extends ConsumerWidget {
  const RecordingProfileSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.live = false,
  });

  final RecordingProfile selected;

  /// Null disables the selector.
  final ValueChanged<RecordingProfile>? onChanged;

  /// True while this activity is recording or paused.
  final bool live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final platform = ref.watch(capturePlatformProvider);
    final free = ref.watch(mediaFreeBytesProvider);
    final freeBytes = free.asData?.value;
    final estimates = {
      for (final p in RecordingProfile.values)
        p: estimateProfile(p, platform, freeBytes: freeBytes),
    };
    final notice = effectiveSettingsNotice(
      estimates[selected]!.settings,
      platform,
    );

    return Column(
      key: const Key('recording-profile-selector'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          live ? 'Recording quality: ${selected.label}' : 'Recording quality',
          key: const Key('profile-selector-title'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (live)
          Padding(
            padding: const EdgeInsets.only(top: TokenSpace.space1),
            child: Text(
              'Changing it saves the current part and carries on in a new '
              'one. Nothing already recorded is changed.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        const SizedBox(height: TokenSpace.space2),
        RadioGroup<RecordingProfile>(
          groupValue: selected,
          onChanged: (value) {
            final change = onChanged;
            if (value != null && value != selected && change != null) {
              change(value);
            }
          },
          child: Column(
            children: [
              for (final profile in RecordingProfile.values)
                _ProfileTile(
                  estimate: estimates[profile]!,
                  selected: profile == selected,
                  enabled: onChanged != null,
                  checkingSpace: free.isLoading,
                ),
            ],
          ),
        ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: TokenSpace.space1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: muted),
                const SizedBox(width: TokenSpace.space2),
                Expanded(
                  child: Text(
                    notice,
                    key: const Key('profile-effective-notice'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.estimate,
    required this.selected,
    required this.enabled,
    required this.checkingSpace,
  });

  final ProfileEstimate estimate;
  final bool selected;
  final bool enabled;
  final bool checkingSpace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = estimate.profile;
    final timeLeft = checkingSpace
        ? 'Checking space…'
        : formatTimeLeft(estimate.minutesLeft);
    return Card(
      margin: const EdgeInsets.only(bottom: TokenSpace.space2),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: const BorderRadius.all(
          Radius.circular(TokenRadius.radiusMd),
        ),
      ),
      child: RadioListTile<RecordingProfile>(
        key: Key('profile-option-${profile.key}'),
        value: profile,
        enabled: enabled,
        title: Text(profile.label, style: theme.textTheme.titleMedium),
        subtitle: Text(
          '${formatMegabytesPerHour(estimate.megabytesPerHour)} · $timeLeft',
          key: Key('profile-estimate-${profile.key}'),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
