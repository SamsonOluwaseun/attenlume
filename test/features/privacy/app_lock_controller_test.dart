import 'dart:async';

import 'package:attenlume/features/privacy/app_lock_controller.dart';
import 'package:attenlume/platform/device_auth/device_authenticator.dart';
import 'package:attenlume/platform/device_auth/local_auth_device_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import '../../fixtures/fake_device_authenticator.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late FakeDeviceAuthenticator auth;
  late DateTime now;

  AppLockController controller() => AppLockController(
    settings: t.settings,
    authenticator: auth,
    clock: () => now,
  );

  /// A controller with the lock on and unlocked, as after a normal unlock.
  Future<AppLockController> unlockedWithLockOn({Duration? grace}) async {
    await t.settings.setAppLockEnabled(true);
    if (grace != null) await t.settings.setAppLockGrace(grace);
    final c = controller();
    await c.load();
    await c.unlock();
    expect(c.locked, isFalse);
    return c;
  }

  setUp(() {
    t = TestData();
    auth = FakeDeviceAuthenticator();
    now = DateTime.utc(2026, 11, 4, 9);
  });

  tearDown(() => t.close());

  group('FR-PRI-06 app lock settings', () {
    test('FR-PRI-06 app lock is off by default and nothing locks', () async {
      final c = controller();
      await c.load();
      expect(c.enabled, isFalse);
      expect(c.locked, isFalse);
      expect(c.grace, AppLockController.defaultGrace);
      c.onBackground();
      now = now.add(const Duration(hours: 1));
      c.onForeground();
      expect(c.locked, isFalse);
      expect(auth.reasons, isEmpty);
    });

    test('FR-PRI-06 turning on needs one successful prompt and is saved, '
        'so the next start is locked', () async {
      final c = controller();
      await c.load();
      expect(await c.enable(), AppLockChange.changed);
      expect(c.enabled, isTrue);
      expect(c.locked, isFalse, reason: 'turning on does not lock at once');
      expect(auth.reasons, [AppLockController.enableReason]);
      expect(await t.settings.appLockEnabled(), isTrue);

      final next = controller();
      await next.load();
      expect(next.locked, isTrue);
    });

    test('FR-PRI-06 cannot be turned on when no PIN, biometrics or Windows '
        'Hello is set up', () async {
      auth.availabilityResult = DeviceAuthAvailability.notSetUp;
      final c = controller();
      await c.load();
      expect(await c.enable(), AppLockChange.unavailable);
      expect(c.enabled, isFalse);
      expect(auth.reasons, isEmpty);
      expect(await t.settings.appLockEnabled(), isFalse);
    });

    test('FR-PRI-06 a cancelled prompt leaves the lock off', () async {
      auth.result = DeviceAuthResult.cancelled;
      final c = controller();
      await c.load();
      expect(await c.enable(), AppLockChange.notConfirmed);
      expect(c.enabled, isFalse);
      expect(await t.settings.appLockEnabled(), isFalse);
    });

    test('FR-PRI-06 turning off asks first, and a cancelled prompt keeps '
        'it on', () async {
      final c = await unlockedWithLockOn();
      auth.result = DeviceAuthResult.cancelled;
      expect(await c.disable(), AppLockChange.notConfirmed);
      expect(c.enabled, isTrue);
      auth.result = DeviceAuthResult.success;
      expect(await c.disable(), AppLockChange.changed);
      expect(c.enabled, isFalse);
      expect(auth.reasons.last, AppLockController.disableReason);
      expect(await t.settings.appLockEnabled(), isFalse);
    });

    test('FR-PRI-06 fail safe: turning off works without a prompt when the '
        'device can no longer check', () async {
      final c = await unlockedWithLockOn();
      auth.availabilityResult = DeviceAuthAvailability.notSetUp;
      final asked = auth.reasons.length;
      expect(await c.disable(), AppLockChange.changed);
      expect(auth.reasons.length, asked);
      expect(c.enabled, isFalse);
    });

    test('FR-PRI-06 an unknown stored value reads as off', () async {
      await t.db.writeSetting('app_lock_enabled', 'yes please');
      await t.db.writeSetting('app_lock_grace_seconds', '-4');
      final c = controller();
      await c.load();
      expect(c.enabled, isFalse);
      expect(c.locked, isFalse);
      expect(c.grace, AppLockController.defaultGrace);
    });
  });

  group('FR-PRI-06 locking on return from the background', () {
    test('FR-PRI-06 back within the grace period: still unlocked', () async {
      final c = await unlockedWithLockOn(grace: const Duration(minutes: 1));
      c.onBackground();
      now = now.add(const Duration(seconds: 59));
      c.onForeground();
      expect(c.locked, isFalse);
    });

    test('FR-PRI-06 back after the grace period: locked', () async {
      final c = await unlockedWithLockOn(grace: const Duration(minutes: 1));
      c.onBackground();
      now = now.add(const Duration(minutes: 1));
      c.onForeground();
      expect(c.locked, isTrue);
      expect(c.lastResult, isNull);
    });

    test('FR-PRI-06 repeated background events count from the first', () async {
      final c = await unlockedWithLockOn(grace: const Duration(minutes: 1));
      c.onBackground();
      now = now.add(const Duration(seconds: 40));
      c.onBackground();
      now = now.add(const Duration(seconds: 40));
      c.onForeground();
      expect(c.locked, isTrue);
    });

    test('FR-PRI-06 with "Immediately" it locks as the app leaves, so the '
        'app switcher shows the lock', () async {
      final c = await unlockedWithLockOn(grace: Duration.zero);
      c.onBackground();
      expect(c.locked, isTrue);
    });

    test('FR-PRI-06 the OS prompt sending the app to the background does '
        'not lock it again', () async {
      await t.settings.setAppLockEnabled(true);
      await t.settings.setAppLockGrace(Duration.zero);
      final c = controller();
      await c.load();
      auth.gate = Completer<void>();
      final pending = c.unlock();
      c.onBackground();
      now = now.add(const Duration(minutes: 5));
      c.onForeground();
      auth.gate!.complete();
      expect(await pending, DeviceAuthResult.success);
      expect(c.locked, isFalse);
    });
  });

  group('FR-PRI-06 unlocking', () {
    Future<AppLockController> lockedController() async {
      await t.settings.setAppLockEnabled(true);
      final c = controller();
      await c.load();
      expect(c.locked, isTrue);
      return c;
    }

    test('FR-PRI-06 a successful prompt unlocks', () async {
      final c = await lockedController();
      expect(await c.unlock(), DeviceAuthResult.success);
      expect(c.locked, isFalse);
      expect(auth.reasons, [AppLockController.unlockReason]);
    });

    test('FR-PRI-06 cancelled or locked out stays locked and offers no way '
        'round the lock', () async {
      final c = await lockedController();
      for (final r in [
        DeviceAuthResult.cancelled,
        DeviceAuthResult.lockedOut,
      ]) {
        auth.result = r;
        expect(await c.unlock(), r);
        expect(c.locked, isTrue);
        expect(c.canTurnOffWithoutCheck, isFalse);
        expect(await c.turnOffBecauseUnavailable(), isFalse);
        expect(c.enabled, isTrue);
      }
    });

    test('FR-PRI-06 fail safe: when the device cannot check, the lock can be '
        'turned off instead of keeping the person out', () async {
      final c = await lockedController();
      auth.result = DeviceAuthResult.unavailable;
      expect(await c.unlock(), DeviceAuthResult.unavailable);
      expect(c.locked, isTrue);
      expect(c.canTurnOffWithoutCheck, isTrue);
      expect(await c.turnOffBecauseUnavailable(), isTrue);
      expect(c.locked, isFalse);
      expect(c.enabled, isFalse);
      expect(await t.settings.appLockEnabled(), isFalse);
    });

    test('FR-PRI-06 a second tap while the prompt is up does not open '
        'another', () async {
      final c = await lockedController();
      auth.gate = Completer<void>();
      final first = c.unlock();
      expect(c.authenticating, isTrue);
      expect(await c.unlock(), isNull);
      auth.gate!.complete();
      await first;
      expect(auth.reasons, hasLength(1));
    });
  });

  test('FR-PRI-06 every local_auth error maps to a safe result', () {
    final map = {
      for (final code in LocalAuthExceptionCode.values)
        code: LocalAuthDeviceAuthenticator.resultForCode(code),
    };
    expect(
      map[LocalAuthExceptionCode.userCanceled],
      DeviceAuthResult.cancelled,
    );
    expect(
      map[LocalAuthExceptionCode.systemCanceled],
      DeviceAuthResult.cancelled,
    );
    expect(
      map[LocalAuthExceptionCode.temporaryLockout],
      DeviceAuthResult.lockedOut,
    );
    expect(
      map[LocalAuthExceptionCode.biometricLockout],
      DeviceAuthResult.lockedOut,
    );
    expect(
      map[LocalAuthExceptionCode.noCredentialsSet],
      DeviceAuthResult.unavailable,
    );
    expect(
      map.values,
      isNot(contains(DeviceAuthResult.success)),
      reason: 'an error must never unlock',
    );
  });
}
