import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_version.dart';
import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/enums.dart';
import '../guide/quick_guide_screen.dart';
import '../privacy/privacy_screen.dart';
import '../storage_manager/storage_manager_screen.dart';
import 'settings_providers.dart';

/// Settings (BUILD_GUIDE 5.11, ADR-048) [P1-25].
///
/// Only settings that exist and are safe to change today: the default
/// recording profile for new conferences, safety prompt thresholds, photo
/// quality and theme, plus links to Privacy (with app lock), the quick
/// guide and About. Everything is saved in `app_settings` on this device.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  static const appName = 'Attenlume';
  static const publisher = 'Samlytics Data Services';
  static const licenceLine =
      'Free and open source under the MIT licence. '
      'Copyright 2026 Samlytics Data Services.';

  static String durationLabel(Duration d) {
    if (d.inMinutes >= 60 && d.inMinutes % 60 == 0) {
      final hours = d.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '${d.inMinutes} minutes';
  }

  static String themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Same as device',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  static String photoQualityLabel(bool keepHighest) =>
      keepHighest ? 'Keep highest quality' : 'Space saving (up to 2048 px)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.read(settingsRepositoryProvider);
    final profile = ref.watch(defaultRecordingProfileSettingProvider).value;
    final safety = ref.watch(safetyThresholdsSettingProvider).value;
    final keepPhotos = ref.watch(photoKeepHighestQualitySettingProvider).value;
    final themeMode = ref.watch(themeModeSettingProvider).value;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        TokenSpace.space4,
        TokenSpace.space5,
        TokenSpace.space4,
        TokenSpace.space1,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          // ink: brand blue is 3.15:1 on cream, below 4.5:1 for 14px
          // text (NFR-09, DESIGN_GUIDE colour rules).
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    Future<void> save(
      Future<void> Function() write,
      FutureProvider<Object?> changed,
    ) async {
      await write();
      ref.invalidate(changed);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: TokenSpace.space6),
            children: [
              heading('Recording'),
              _ChoiceTile<RecordingProfile>(
                key: const Key('settings-default-profile'),
                icon: Icons.graphic_eq_rounded,
                title: 'Default recording quality',
                help:
                    'Used for new conferences. Existing conferences keep '
                    'their own setting.',
                value: profile,
                choices: RecordingProfile.values,
                label: (p) => p.label,
                onChanged: (p) => save(
                  () => settings.setGlobalDefaultRecordingProfile(p),
                  defaultRecordingProfileSettingProvider,
                ),
              ),
              _ChoiceTile<Duration>(
                key: const Key('settings-long-recording'),
                icon: Icons.timer_outlined,
                title: 'Check in on long recordings after',
                value: safety?.longRecording,
                choices: SettingsRepository.longRecordingChoices,
                label: durationLabel,
                onChanged: (d) => save(
                  () => settings.setSafetyLongRecording(d),
                  safetyThresholdsSettingProvider,
                ),
              ),
              _ChoiceTile<Duration>(
                key: const Key('settings-silence'),
                icon: Icons.volume_off_outlined,
                title: 'Ask after no sound for',
                value: safety?.silence,
                choices: SettingsRepository.silenceChoices,
                label: durationLabel,
                onChanged: (d) => save(
                  () => settings.setSafetySilence(d),
                  safetyThresholdsSettingProvider,
                ),
              ),
              _ChoiceTile<int>(
                key: const Key('settings-low-battery'),
                icon: Icons.battery_alert_outlined,
                title: 'Warn when battery is below',
                help: 'These reminders never stop a recording.',
                value: safety?.lowBatteryPercent,
                choices: SettingsRepository.lowBatteryChoices,
                label: (p) => '$p%',
                onChanged: (p) => save(
                  () => settings.setSafetyLowBatteryPercent(p),
                  safetyThresholdsSettingProvider,
                ),
              ),
              heading('Photos'),
              _ChoiceTile<bool>(
                key: const Key('settings-photo-quality'),
                icon: Icons.photo_size_select_large_outlined,
                title: 'Photo quality',
                help:
                    'Space saving keeps slide text readable and uses less '
                    'storage. Applies to new photos only.',
                value: keepPhotos,
                choices: const [false, true],
                label: photoQualityLabel,
                onChanged: (keep) => save(
                  () => settings.setPhotoKeepHighestQuality(keep),
                  photoKeepHighestQualitySettingProvider,
                ),
              ),
              heading('Appearance'),
              _ChoiceTile<ThemeMode>(
                key: const Key('settings-theme'),
                icon: Icons.brightness_6_outlined,
                title: 'Theme',
                value: themeMode,
                choices: ThemeMode.values,
                label: themeLabel,
                onChanged: (m) => save(
                  () => settings.setThemeMode(m),
                  themeModeSettingProvider,
                ),
              ),
              heading('Storage'),
              ListTile(
                key: const Key('settings-storage'),
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Storage manager'),
                subtitle: const Text(
                  'Space used, clear temporary files, delete copies you exported',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const StorageManagerScreen(),
                    ),
                  );
                  // A conference may have been deleted: My conferences
                  // must not show it when the user goes back.
                  ref.invalidate(allConferencesFutureProvider);
                },
              ),
              heading('Privacy and security'),
              ListTile(
                key: const Key('settings-privacy'),
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Privacy and app lock'),
                subtitle: const Text(
                  'Where your data stays, permissions and app lock',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(PrivacyScreen.open(context)),
              ),
              heading('Help'),
              ListTile(
                key: const Key('settings-quick-guide'),
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Quick guide'),
                subtitle: const Text('How to set up, record, review and share'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(QuickGuideScreen.open(context)),
              ),
              heading('About'),
              const ListTile(
                key: Key('settings-about'),
                leading: Icon(Icons.info_outline_rounded),
                title: Text(appName),
                subtitle: Text(
                  'Version $appVersion\nBy $publisher\n$licenceLine',
                ),
                isThreeLine: true,
              ),
              ListTile(
                key: const Key('settings-licences'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('Third-party licences'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: appName,
                  applicationVersion: appVersion,
                  applicationLegalese: licenceLine,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A setting with a few fixed choices, opened as a dialog so it works at
/// large text sizes (DESIGN_GUIDE: layouts hold at 200 % text).
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.choices,
    required this.label,
    required this.onChanged,
    this.help,
  });

  final IconData icon;
  final String title;
  final String? help;

  /// Null while the setting loads.
  final T? value;
  final List<T> choices;
  final String Function(T) label;
  final Future<void> Function(T) onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final choice in choices)
            SimpleDialogOption(
              key: Key('choice-${label(choice)}'),
              onPressed: () => Navigator.of(context).pop(choice),
              child: Row(
                children: [
                  Icon(
                    choice == value
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: TokenSize.iconMd,
                  ),
                  const SizedBox(width: TokenSpace.space3),
                  Expanded(child: Text(label(choice))),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null && picked != value) await onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    final valueText = current == null ? '' : label(current);
    final helpText = help;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(helpText == null ? valueText : '$valueText\n$helpText'),
      isThreeLine: helpText != null,
      enabled: current != null,
      onTap: current == null ? null : () => unawaited(_pick(context)),
    );
  }
}
