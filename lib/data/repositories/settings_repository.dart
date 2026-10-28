import '../../domain/models/enums.dart';
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
}
