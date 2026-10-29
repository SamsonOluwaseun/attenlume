import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/capture/crash_recovery_dialog.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/privacy/app_lock_gate.dart';
import '../features/settings/settings_providers.dart';
import 'theme/app_theme.dart';

class AttenlumeApp extends ConsumerWidget {
  const AttenlumeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Attenlume',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // System unless changed in Settings (5.11, ADR-048).
      themeMode: ref.watch(themeModeSettingProvider).value ?? ThemeMode.system,
      // The optional app lock covers every route, dialogs included
      // (FR-PRI-06, ADR-041). Off by default.
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
      // Crash recovery runs on every start (FR-REC-08).
      home: const CrashRecoveryGate(child: WelcomeScreen()),
    );
  }
}
