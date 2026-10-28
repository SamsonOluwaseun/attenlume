import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../platform/device_auth/device_authenticator.dart';
import '../../platform/device_auth/local_auth_device_authenticator.dart';

/// What happened when the person tried to turn app lock on or off.
enum AppLockChange {
  /// The setting changed.
  changed,

  /// The OS prompt was cancelled or failed. Nothing changed.
  notConfirmed,

  /// No biometrics, PIN or Windows Hello is set up, so the lock cannot be
  /// turned on. Nothing changed.
  unavailable,
}

/// The optional app lock (FR-PRI-06, ADR-041).
///
/// - Off by default. Turning it on needs one successful OS prompt, so the
///   person knows it works before it can lock them out.
/// - Locks on start, and on return from the background once the app has
///   been away for at least [grace]. With a zero grace it locks as soon as
///   the app goes to the background, so the app switcher shows the lock.
/// - Never touches recording. The lock is only a cover over the screens;
///   the recorder, the foreground service and its notification actions keep
///   running underneath, and the cover offers Stop (FR-PRI-02).
/// - Fails safe. If the OS says no check is possible any more (for example
///   the device PIN was removed), the cover explains that and offers to turn
///   the lock off instead of keeping the person from their recordings.
class AppLockController extends ChangeNotifier {
  AppLockController({
    required this._settings,
    required this._authenticator,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SettingsRepository _settings;
  final DeviceAuthenticator _authenticator;
  final DateTime Function() _clock;

  /// The grace period when none was chosen (ADR-041).
  static const defaultGrace = Duration(minutes: 1);

  /// Choices offered in the Privacy screen.
  static const graceChoices = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  /// The text the OS shows in its prompt.
  static const unlockReason = 'Unlock Attenlume to see your conferences.';
  static const enableReason = 'Confirm it is you to turn on app lock.';
  static const disableReason = 'Confirm it is you to turn off app lock.';

  bool _loaded = false;
  bool _enabled = false;
  Duration _grace = defaultGrace;
  bool _locked = false;
  bool _authenticating = false;
  DeviceAuthResult? _lastResult;
  DateTime? _backgroundedAt;

  bool get loaded => _loaded;
  bool get enabled => _enabled;
  Duration get grace => _grace;
  bool get locked => _locked;
  bool get authenticating => _authenticating;

  /// The result of the last unlock attempt, for the message on the cover.
  DeviceAuthResult? get lastResult => _lastResult;

  /// True when the last unlock found no way to check, so the cover offers
  /// to turn the lock off (fail safe).
  bool get canTurnOffWithoutCheck =>
      _locked && _lastResult == DeviceAuthResult.unavailable;

  /// Reads the settings. If the lock is on, the app starts locked.
  Future<void> load() async {
    try {
      _enabled = await _settings.appLockEnabled();
      _grace = await _settings.appLockGrace() ?? defaultGrace;
    } on Object {
      // A settings read that fails must not lock anyone out.
      _enabled = false;
    }
    _locked = _enabled;
    _loaded = true;
    notifyListeners();
  }

  /// The app went to the background (paused or hidden).
  void onBackground() {
    // The OS prompt itself can send the app to the background on some
    // platforms: that must not count.
    if (!_enabled || _locked || _authenticating) return;
    _backgroundedAt ??= _clock();
    if (_grace <= Duration.zero) {
      _lock();
    }
  }

  /// The app is in the foreground again.
  void onForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!_enabled || _locked || since == null) return;
    if (_clock().difference(since) >= _grace) {
      _lock();
    }
  }

  void _lock() {
    _backgroundedAt = null;
    _locked = true;
    _lastResult = null;
    notifyListeners();
  }

  /// Shows the OS prompt and unlocks on success.
  Future<DeviceAuthResult?> unlock() async {
    if (!_locked || _authenticating) return null;
    _authenticating = true;
    notifyListeners();
    final result = await _authenticator.authenticate(unlockReason);
    _authenticating = false;
    _lastResult = result;
    if (result == DeviceAuthResult.success) {
      _locked = false;
      _lastResult = null;
    }
    notifyListeners();
    return result;
  }

  /// Fail safe: turns the lock off when the OS cannot check any more.
  /// Does nothing unless the last unlock attempt said so.
  Future<bool> turnOffBecauseUnavailable() async {
    if (!canTurnOffWithoutCheck) return false;
    await _save(false);
    _locked = false;
    _lastResult = null;
    notifyListeners();
    return true;
  }

  /// Turns the lock on after one successful prompt.
  Future<AppLockChange> enable() async {
    if (_enabled) return AppLockChange.changed;
    if (await _authenticator.availability() !=
        DeviceAuthAvailability.available) {
      return AppLockChange.unavailable;
    }
    final result = await _confirm(enableReason);
    if (result == DeviceAuthResult.unavailable) {
      return AppLockChange.unavailable;
    }
    if (result != DeviceAuthResult.success) return AppLockChange.notConfirmed;
    await _save(true);
    notifyListeners();
    return AppLockChange.changed;
  }

  /// Turns the lock off. Asks the OS first when it can; if it cannot, the
  /// lock goes off without asking (fail safe).
  Future<AppLockChange> disable() async {
    if (!_enabled) return AppLockChange.changed;
    if (await _authenticator.availability() ==
        DeviceAuthAvailability.available) {
      final result = await _confirm(disableReason);
      if (result != DeviceAuthResult.success &&
          result != DeviceAuthResult.unavailable) {
        return AppLockChange.notConfirmed;
      }
    }
    await _save(false);
    _locked = false;
    notifyListeners();
    return AppLockChange.changed;
  }

  Future<void> setGrace(Duration grace) async {
    _grace = grace;
    await _settings.setAppLockGrace(grace);
    notifyListeners();
  }

  Future<DeviceAuthResult> _confirm(String reason) async {
    _authenticating = true;
    notifyListeners();
    try {
      return await _authenticator.authenticate(reason);
    } finally {
      _authenticating = false;
    }
  }

  Future<void> _save(bool enabled) async {
    _enabled = enabled;
    _backgroundedAt = null;
    await _settings.setAppLockEnabled(enabled);
  }
}

/// The OS owner check. Tests override it with a fake.
final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => LocalAuthDeviceAuthenticator(),
);

/// The single app lock. [AppLockGate] loads it on start.
final appLockControllerProvider = Provider<AppLockController>((ref) {
  final controller = AppLockController(
    settings: ref.watch(settingsRepositoryProvider),
    authenticator: ref.watch(deviceAuthenticatorProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
