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
}
