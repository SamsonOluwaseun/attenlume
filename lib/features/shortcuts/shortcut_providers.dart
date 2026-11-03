import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../domain/services/capture_settings.dart';
import '../../platform/shortcuts/shortcut_bridge.dart';
import '../capture/recording_providers.dart';
import 'shortcut_coordinator.dart';

/// Global navigator key allowing the shortcut coordinator to push routes.
final appNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

/// Platform shortcut bridge for tile, launcher shortcuts, App Intents and deep links.
final shortcutBridgeProvider = Provider<ShortcutBridge>((ref) {
  final platform = ref.watch(capturePlatformProvider);
  if (platform == CapturePlatform.android || platform == CapturePlatform.ios) {
    final bridge = MethodChannelShortcutBridge();
    ref.onDispose(bridge.dispose);
    return bridge;
  }
  return const NoShortcutBridge();
});

/// Coordinates incoming shortcut commands with app navigation and recording.
final shortcutCoordinatorProvider = Provider<ShortcutCoordinator>((ref) {
  return ShortcutCoordinator(
    navigatorKey: ref.watch(appNavigatorKeyProvider),
    conferenceRepository: ref.watch(conferenceRepositoryProvider),
    activityRepository: ref.watch(activityRepositoryProvider),
    mediaRepository: ref.watch(mediaAssetRepositoryProvider),
    recordingService: ref.watch(recordingServiceProvider),
  );
});
