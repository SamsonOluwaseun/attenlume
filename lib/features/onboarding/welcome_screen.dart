import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// First screen. No sign-in (NFR-01). Conference creation arrives in P1-01.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const tagline = 'Be present. Bring ideas to light.';
  static const onboardingLine =
      'Give the speaker your attention. Attenlume will hold on to the details.';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    const logoSize = 200.0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Supplied artwork, used as is. Decoded at display size.
                  Image.asset(
                    'assets/brand/logos/attenlume-logo-stacked.png',
                    width: logoSize,
                    height: logoSize,
                    cacheWidth: (logoSize * pixelRatio).round(),
                    semanticLabel: 'Attenlume by Samlytics Data Services',
                  ),
                  const SizedBox(height: TokenSpace.space6),
                  Text(
                    tagline,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TokenSpace.space4),
                  Text(
                    onboardingLine,
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
