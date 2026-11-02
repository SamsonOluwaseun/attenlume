import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import 'app_lock_controller.dart';
import 'privacy_policy_link.dart';

/// One permission and why Attenlume asks for it (FR-PRI-04).
class PermissionExplanation {
  const PermissionExplanation({
    required this.name,
    required this.whenAsked,
    required this.why,
    required this.icon,
  });

  final String name;
  final String whenAsked;
  final String why;
  final IconData icon;
}

/// Privacy: where data lives, what is asked for and why, the optional app
/// lock and the published policy (FR-PRI-03, FR-PRI-04, FR-PRI-06,
/// FR-PRI-07, ADR-041, ADR-073).
///
/// Opened from Settings (P1-25), which links here rather than repeating it.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()));

  /// FR-PRI-03, in plain words. Each line must stay true of the build.
  static const onDevicePromises = [
    'Your conferences, recordings, photos and notes stay on this device '
        'unless you export or share them.',
    'No account is needed and nothing is sent anywhere in the background.',
    'No analytics, no adverts and no trackers.',
    'Recording is always shown on screen and, on Android, in a '
        'notification with Stop. There is no hidden recording mode.',
  ];

  /// FR-PRI-04: asked only when first needed (PRIVACY_AND_SAFETY 6).
  static const permissions = [
    PermissionExplanation(
      name: 'Microphone',
      whenAsked: 'The first time you tap Record.',
      why:
          'To record the sessions you choose to capture. Recordings stay on '
          'this device unless you export them.',
      icon: Icons.mic_none_rounded,
    ),
    PermissionExplanation(
      name: 'Camera',
      whenAsked: 'The first time you take a photo in Attenlume.',
      why: 'To take photos of slides and posters and link them to a session.',
      icon: Icons.photo_camera_outlined,
    ),
    PermissionExplanation(
      name: 'Photos',
      whenAsked: 'The first time you import photos from your gallery.',
      why:
          'To list photos you took during a session so you can pick some. '
          'Only the photos you pick are copied.',
      icon: Icons.photo_library_outlined,
    ),
    PermissionExplanation(
      name: 'Notifications (Android)',
      whenAsked: 'The first time you record.',
      why:
          'To show that recording is on, with Pause, Stop and Bookmark in '
          'the notification.',
      icon: Icons.notifications_none_rounded,
    ),
    PermissionExplanation(
      name: 'Fingerprint, face, PIN or Windows Hello',
      whenAsked: 'Only if you turn on app lock.',
      why:
          'Your device checks it is you. Attenlume only learns whether the '
          'check passed and never sees or stores your face or fingerprint.',
      icon: Icons.fingerprint_rounded,
    ),
  ];

  static String graceLabel(Duration grace) {
    if (grace <= Duration.zero) return 'Immediately';
    final minutes = grace.inMinutes;
    return minutes == 1 ? 'After 1 minute' : 'After $minutes minutes';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lock = ref.watch(appLockControllerProvider);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(
        top: TokenSpace.space5,
        bottom: TokenSpace.space2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: TokenSpace.space4),
            children: [
              heading('On this device'),
              for (final line in onDevicePromises)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: Text(line),
                ),
              heading('App lock'),
              ListenableBuilder(
                listenable: lock,
                builder: (context, _) => _AppLockSection(lock: lock),
              ),
              heading('What Attenlume asks for, and when'),
              for (final p in permissions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(p.icon),
                  title: Text(p.name),
                  subtitle: Text('${p.whenAsked} ${p.why}'),
                ),
              heading('Recording other people'),
              Text(
                'Some events and speakers do not allow recording. Record only '
                'when permitted, and ask before recording a conversation. '
                'Attenlume helps you keep track, but it does not replace your '
                'own legal obligations, for example under UK GDPR.',
                style: theme.textTheme.bodyMedium,
              ),
              heading('Privacy policy'),
              const _PolicyLink(),
              const SizedBox(height: TokenSpace.space6),
            ],
          ),
        ),
      ),
    );
  }
}

/// The published privacy policy, with Open (Android and Windows) and Copy
/// link everywhere (FR-PRI-07). Google Play requires it inside the app.
class _PolicyLink extends ConsumerWidget {
  const _PolicyLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> open() async {
      final opened = await ref.read(privacyPolicyOpenerProvider)();
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'The privacy policy could not be opened. Copy the link and '
              'open it in your browser.',
            ),
          ),
        );
      }
    }

    Future<void> copy() async {
      await Clipboard.setData(const ClipboardData(text: privacyPolicyUrl));
      messenger.showSnackBar(
        const SnackBar(content: Text('Privacy policy link copied.')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The full policy explains what Attenlume stores, the optional '
          'transcription download and how to contact us.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: TokenSpace.space2),
        SelectableText(
          privacyPolicyUrl,
          key: const Key('privacy-policy-url'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: TokenSpace.space2),
        Wrap(
          spacing: TokenSpace.space2,
          runSpacing: TokenSpace.space2,
          children: [
            if (canOpenPrivacyPolicy)
              FilledButton.icon(
                key: const Key('privacy-policy-open'),
                onPressed: open,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open privacy policy'),
              ),
            OutlinedButton.icon(
              key: const Key('privacy-policy-copy'),
              onPressed: copy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy link'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppLockSection extends StatelessWidget {
  const _AppLockSection({required this.lock});

  final AppLockController lock;

  Future<void> _toggle(BuildContext context, bool on) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = on ? await lock.enable() : await lock.disable();
    final message = switch (outcome) {
      AppLockChange.changed => on ? 'App lock is on.' : 'App lock is off.',
      AppLockChange.notConfirmed => 'Not confirmed. Nothing changed.',
      AppLockChange.unavailable =>
        'App lock needs a fingerprint, face, device PIN or Windows Hello. '
            'Set one up in your device settings first.',
    };
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('app-lock-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Lock Attenlume'),
          subtitle: const Text(
            'Ask for your fingerprint, face, device PIN or Windows Hello when '
            'you open Attenlume. Recording carries on while locked, and Stop '
            'stays on the lock screen and in the notification.',
          ),
          value: lock.enabled,
          onChanged: lock.authenticating
              ? null
              : (on) => unawaited(_toggle(context, on)),
        ),
        if (lock.enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock again after leaving Attenlume'),
            trailing: DropdownButton<Duration>(
              key: const Key('app-lock-grace'),
              value: AppLockController.graceChoices.contains(lock.grace)
                  ? lock.grace
                  : null,
              hint: Text(PrivacyScreen.graceLabel(lock.grace)),
              items: [
                for (final g in AppLockController.graceChoices)
                  DropdownMenuItem(
                    value: g,
                    child: Text(PrivacyScreen.graceLabel(g)),
                  ),
              ],
              onChanged: (g) {
                if (g != null) unawaited(lock.setGrace(g));
              },
            ),
          ),
        Text(
          'If your device can no longer check it is you, Attenlume lets you '
          'turn the lock off rather than keep you from your recordings.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
