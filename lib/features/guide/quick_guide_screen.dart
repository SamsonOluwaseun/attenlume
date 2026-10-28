import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import 'guide_content.dart';
import 'guide_model.dart';

/// The quick guide: how to set up, capture, review and export, with
/// screenshots. Opened from the welcome screen and the My conferences menu.
/// Works offline; everything is bundled with the app.
class QuickGuideScreen extends StatelessWidget {
  const QuickGuideScreen({super.key, this.guide = quickGuide});

  final QuickGuide guide;

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const QuickGuideScreen()));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    var stepNumber = 0;

    return Scaffold(
      key: const Key('quick-guide-screen'),
      appBar: AppBar(title: Text(guide.title)),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(TokenSpace.space4),
              children: [
                Text(guide.intro, style: text.bodyLarge),
                const SizedBox(height: TokenSpace.space4),
                _Overview(items: guide.overview),
                for (final section in guide.sections) ...[
                  const SizedBox(height: TokenSpace.space6),
                  _SectionHeader(section: section),
                  for (final step in section.steps)
                    _StepCard(number: ++stepNumber, step: step),
                ],
                const SizedBox(height: TokenSpace.space6),
                Text(
                  guide.privacyTitle,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: TokenSpace.space3),
                for (final point in guide.privacyPoints) _Check(text: point),
                const SizedBox(height: TokenSpace.space3),
                _Screens(images: [guide.privacyImage]),
                const SizedBox(height: TokenSpace.space6),
                Text(
                  'Good to know',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: TokenSpace.space3),
                for (final tip in guide.tips) _Tip(tip: tip),
                const SizedBox(height: TokenSpace.space6),
                Text(
                  guide.closing,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: TokenSpace.space6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.items});

  final List<GuideOverviewItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: TokenSpace.space2,
      runSpacing: TokenSpace.space2,
      children: [
        for (final item in items)
          SizedBox(
            width: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
              ),
              child: Padding(
                padding: const EdgeInsets.all(TokenSpace.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.number}  ${item.title}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: TokenSpace.space1),
                    Text(
                      item.text,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${section.number}  ${section.title}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: TokenSpace.space1),
          Text(
            section.blurb,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: TokenSpace.space3),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.step});

  final int number;
  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: TokenSpace.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step $number: ${step.title}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: TokenSpace.space2),
          for (final point in step.points) _Bullet(text: point),
          const SizedBox(height: TokenSpace.space2),
          _Screens(images: step.images),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: TokenSpace.space1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(child: Text('•  ')),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: TokenSpace.space2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: TokenSpace.space2),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Tip extends StatelessWidget {
  const _Tip({required this.tip});

  final GuideTip tip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: TokenSpace.space2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TokenSpace.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tip.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: TokenSpace.space1),
              Text(tip.text),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screenshots in a navy phone frame, side by side.
class _Screens extends StatelessWidget {
  const _Screens({required this.images});

  final List<String> images;

  static const _width = 150.0;

  @override
  Widget build(BuildContext context) {
    final navy =
        Theme.of(context).extension<AttenlumeColors>()?.liveSurface ??
        const Color(0xFF00212B);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Wrap(
      spacing: TokenSpace.space3,
      runSpacing: TokenSpace.space3,
      children: [
        for (final name in images)
          DecoratedBox(
            decoration: BoxDecoration(
              color: navy,
              borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
                child: Image.asset(
                  guideImageAsset(name),
                  width: _width,
                  cacheWidth: (_width * dpr).round(),
                  semanticLabel:
                      'Screenshot: ${name.replaceFirst(RegExp(r'^\d+-'), '').replaceAll('-', ' ')}',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
