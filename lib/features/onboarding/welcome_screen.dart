import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../../domain/services/device_timezone.dart';
import '../conferences/conference_home_screen.dart';
import '../conferences/conference_list_screen.dart';
import '../conferences/conference_wizard_screen.dart';

/// First screen. No sign-in (NFR-01).
///
/// Offers quick start (FR-CONF-01), full set-up wizard, and "Open previous".
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  static const tagline = 'Be present. Bring ideas to light.';
  static const onboardingLine =
      'Give the speaker your attention. Attenlume will hold on to the details.';
  static const policyNotice =
      'Some events and speakers do not allow recording. Record only when permitted.';

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _quickStart() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a conference name')),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final repo = ref.read(conferenceRepositoryProvider);
      final tzService = ref.read(deviceTimezoneServiceProvider);
      final timezone = await tzService.detectTimezone();

      final created = await repo.create(
        name: name,
        timezone: timezone,
        policyAcknowledgedAt: DateTime.now().toUtc(),
      );

      if (mounted) {
        _nameController.clear();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                ConferenceHomeScreen(conferenceId: created.id),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _openWizard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ConferenceWizardScreen(),
      ),
    );
  }

  void _openPrevious() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ConferenceListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    const logoSize = 160.0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Supplied artwork, used as is. Decoded at display size.
                  Center(
                    child: Image.asset(
                      'assets/brand/logos/attenlume-logo-stacked.png',
                      width: logoSize,
                      height: logoSize,
                      cacheWidth: (logoSize * pixelRatio).round(),
                      semanticLabel: 'Attenlume by Samlytics Data Services',
                    ),
                  ),
                  const SizedBox(height: TokenSpace.space4),
                  Text(
                    WelcomeScreen.tagline,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TokenSpace.space2),
                  Text(
                    WelcomeScreen.onboardingLine,
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TokenSpace.space5),

                  // Quick start card (FR-CONF-01, FR-CONF-06)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(TokenSpace.space4),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Quick start',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: TokenSpace.space1),
                            Text(
                              'Create a named conference in seconds. Fill in the rest later.',
                              style: text.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            TextFormField(
                              key: const Key('conference-name-input'),
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Conference name',
                                hintText: 'e.g. Health Security 2026',
                              ),
                              onFieldSubmitted: (_) => _quickStart(),
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: TokenSpace.space2),
                                Expanded(
                                  child: Text(
                                    WelcomeScreen.policyNotice,
                                    style: text.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: TokenSpace.space4),
                            FilledButton(
                              key: const Key('create-conference-button'),
                              onPressed: _isCreating ? null : _quickStart,
                              child: _isCreating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Create conference'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: TokenSpace.space4),

                  // Secondary actions: Set up with wizard, Open previous
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('set-up-wizard-button'),
                          onPressed: _openWizard,
                          child: const Text('Set up with wizard'),
                        ),
                      ),
                      const SizedBox(width: TokenSpace.space3),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('open-previous-button'),
                          onPressed: _openPrevious,
                          child: const Text('Open previous'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: TokenSpace.space5),

                  // Recent conferences
                  Builder(
                    builder: (context) {
                      final list =
                          ref.watch(recentConferencesProvider).asData?.value ??
                          const <Conference>[];
                      if (list.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recent conferences',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: TokenSpace.space2),
                          for (final conf in list.take(3))
                            Card(
                              key: Key('recent-conference-${conf.id}'),
                              margin: const EdgeInsets.only(
                                bottom: TokenSpace.space2,
                              ),
                              child: ListTile(
                                title: Text(conf.name, style: text.titleMedium),
                                subtitle: Text(
                                  conf.venue != null && conf.venue!.isNotEmpty
                                      ? conf.venue!
                                      : conf.timezone,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (context) =>
                                          ConferenceHomeScreen(
                                            conferenceId: conf.id,
                                          ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      );
                    },
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
