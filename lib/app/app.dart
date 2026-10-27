import 'package:flutter/material.dart';

import '../features/onboarding/welcome_screen.dart';
import 'theme/app_theme.dart';

class AttenlumeApp extends StatelessWidget {
  const AttenlumeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attenlume',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const WelcomeScreen(),
    );
  }
}
