import 'package:flutter/material.dart' show ThemeMode;

import '../../domain/models/enums.dart';
import '../../domain/services/safety_prompt_service.dart';
import '../filesystem/photo_processor.dart';
import '../local_database/app_database.dart';

/// Typed access to `app_settings` [P0-09].
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const defaultRecordingProfileKey = 'default_recording_profile';

  /// The global default recording profile, Balanced unless changed
  /// (FR-QUAL-02, 5.11). An unknown stored value reads as Balanced.
  Future<RecordingProfile> globalDefaultRecordingProfile() async {
    final stored = await _db.readSetting(defaultRecordingProfileKey);
    if (stored == null) return RecordingProfile.globalDefault;
    try {
      return enumFromKey(RecordingProfile.values, stored);
    } on ArgumentError {
      return RecordingProfile.globalDefault;
    }
  }

  /// Changing the global default never changes an existing conference.
  Future<void> setGlobalDefaultRecordingProfile(RecordingProfile profile) =>
      _db.writeSetting(defaultRecordingProfileKey, profile.key);

  static const appLockEnabledKey = 'app_lock_enabled';
  static const appLockGraceSecondsKey = 'app_lock_grace_seconds';

  /// Whether the optional app lock is on. Off unless the person turned it
  /// on (FR-PRI-06, ADR-041). Anything but "true" reads as off.
  Future<bool> appLockEnabled() async =>
      await _db.readSetting(appLockEnabledKey) == 'true';

  Future<void> setAppLockEnabled(bool enabled) =>
      _db.writeSetting(appLockEnabledKey, enabled ? 'true' : 'false');

  /// How long the app may be in the background before it locks again
  /// (ADR-041). Null when never set; a stored value that is not a
  /// non-negative whole number also reads as null.
  Future<Duration?> appLockGrace() async {
    final stored = int.tryParse(
      await _db.readSetting(appLockGraceSecondsKey) ?? '',
    );
    if (stored == null || stored < 0) return null;
    return Duration(seconds: stored);
  }

  Future<void> setAppLockGrace(Duration grace) =>
      _db.writeSetting(appLockGraceSecondsKey, '${grace.inSeconds}');

  static const safetyLongRecordingMinutesKey = 'safety_long_recording_minutes';
  static const safetySilenceMinutesKey = 'safety_silence_minutes';
  static const safetyLowBatteryPercentKey = 'safety_low_battery_percent';

  /// Choices offered in Settings for the safety prompts (FR-REC-06, 5.11,
  /// ADR-048). The build guide defaults are 2 hours, 10 minutes and 15 %.
  static const longRecordingChoices = [
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 4),
  ];
  static const silenceChoices = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];
  static const lowBatteryChoices = [10, 15, 20, 30];

  /// The safety prompt thresholds (FR-REC-06, 5.11). A setting that was
  /// never saved, or holds a value outside the offered choices, reads as
  /// the build guide default, so a damaged value can never switch a prompt
  /// off.
  Future<SafetyThresholds> safetyThresholds() async {
    const defaults = SafetyThresholds();
    Future<int?> readInt(String key) async =>
        int.tryParse(await _db.readSetting(key) ?? '');

    final longMinutes = await readInt(safetyLongRecordingMinutesKey);
    final silenceMinutes = await readInt(safetySilenceMinutesKey);
    final battery = await readInt(safetyLowBatteryPercentKey);
    final long = longMinutes == null ? null : Duration(minutes: longMinutes);
    final silence = silenceMinutes == null
        ? null
        : Duration(minutes: silenceMinutes);
    return SafetyThresholds(
      longRecording: longRecordingChoices.contains(long)
          ? long!
          : defaults.longRecording,
      silence: silenceChoices.contains(silence) ? silence! : defaults.silence,
      silenceDbfs: defaults.silenceDbfs,
      lowBatteryPercent: lowBatteryChoices.contains(battery)
          ? battery!
          : defaults.lowBatteryPercent,
    );
  }

  Future<void> setSafetyLongRecording(Duration after) =>
      _db.writeSetting(safetyLongRecordingMinutesKey, '${after.inMinutes}');

  Future<void> setSafetySilence(Duration after) =>
      _db.writeSetting(safetySilenceMinutesKey, '${after.inMinutes}');

  Future<void> setSafetyLowBatteryPercent(int percent) =>
      _db.writeSetting(safetyLowBatteryPercentKey, '$percent');

  static const photoKeepHighestQualityKey = 'photo_keep_highest_quality';

  /// "Keep highest quality" for photos (FR-PHO-02, FR-QUAL-08, ADR-030).
  /// Off unless turned on: photos are saved at the space-saving size.
  Future<bool> photoKeepHighestQuality() async =>
      await _db.readSetting(photoKeepHighestQualityKey) == 'true';

  Future<void> setPhotoKeepHighestQuality(bool keep) =>
      _db.writeSetting(photoKeepHighestQualityKey, keep ? 'true' : 'false');

  /// The [PhotoQuality] the photo service uses for the next photo.
  Future<PhotoQuality> photoQuality() async =>
      PhotoQuality(keepOriginal: await photoKeepHighestQuality());

  static const themeModeKey = 'theme_mode';

  /// System, light or dark (5.11). Follows the system unless changed.
  Future<ThemeMode> themeMode() async =>
      switch (await _db.readSetting(themeModeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) =>
      _db.writeSetting(themeModeKey, mode.name);
}
