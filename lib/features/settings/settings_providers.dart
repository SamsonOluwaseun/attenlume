import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/safety_prompt_service.dart';

// Settings read from `app_settings` (5.11, ADR-048) [P1-25]. The Settings
// screen saves through SettingsRepository, then invalidates the provider it
// changed so everything watching it picks up the new value.

/// The global default recording profile copied into new conferences
/// (FR-QUAL-02).
final defaultRecordingProfileSettingProvider = FutureProvider<RecordingProfile>(
  (ref) =>
      ref.watch(settingsRepositoryProvider).globalDefaultRecordingProfile(),
);

/// Safety prompt thresholds (FR-REC-06). The safety prompt service listens
/// to this, so a change applies to a recording already running.
final safetyThresholdsSettingProvider = FutureProvider<SafetyThresholds>(
  (ref) => ref.watch(settingsRepositoryProvider).safetyThresholds(),
);

/// "Keep highest quality" for photos (FR-PHO-02). The photo service reads
/// the setting itself before each photo; this is for the Settings screen.
final photoKeepHighestQualitySettingProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).photoKeepHighestQuality(),
);

/// System, light or dark. The app follows the system until it has loaded.
final themeModeSettingProvider = FutureProvider<ThemeMode>(
  (ref) => ref.watch(settingsRepositoryProvider).themeMode(),
);
