import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/ai/summary_prompt.dart';

/// Lets the user change how the on-device model writes summaries (P3-12).
///
/// Only the instructions are editable. The rule to use nothing but the
/// session's material and the answer format stay fixed, so summaries remain
/// grounded, linked to their moments and readable by the app.
class SummaryInstructionsScreen extends ConsumerStatefulWidget {
  const SummaryInstructionsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SummaryInstructionsScreen()),
  );

  @override
  ConsumerState<SummaryInstructionsScreen> createState() =>
      _SummaryInstructionsScreenState();
}

class _SummaryInstructionsScreenState
    extends ConsumerState<SummaryInstructionsScreen> {
  final _text = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ref.read(settingsRepositoryProvider).summaryInstructions().then((saved) {
      if (!mounted) return;
      setState(() {
        _text.text = saved ?? defaultSummaryInstructions;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    // Saving the default text unchanged keeps following future defaults.
    await ref
        .read(settingsRepositoryProvider)
        .setSummaryInstructions(
          text == defaultSummaryInstructions.trim() ? null : text,
        );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Summary instructions saved.')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await ref.read(settingsRepositoryProvider).setSummaryInstructions(null);
    if (!mounted) return;
    setState(() => _text.text = defaultSummaryInstructions);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Back to the default instructions.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Summary instructions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(TokenSpace.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tell the on-device model how to write the summary, key '
                    'points, follow-ups and questions. It always uses only '
                    "the session's own transcript, bookmarks and notes, and "
                    'keeps each point linked to its moment.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: TokenSpace.space3),
                  TextField(
                    key: const Key('summary-instructions-field'),
                    controller: _text,
                    minLines: 8,
                    maxLines: 20,
                    maxLength: maxSummaryInstructionsChars,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Instructions',
                    ),
                  ),
                  const SizedBox(height: TokenSpace.space2),
                  Text(
                    'Longer instructions leave less room for the transcript, '
                    'so long sessions are summarised in more parts. New '
                    'instructions apply to summaries you create from now on.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: TokenSpace.space4),
                  Wrap(
                    spacing: TokenSpace.space3,
                    runSpacing: TokenSpace.space2,
                    children: [
                      FilledButton(
                        key: const Key('summary-instructions-save'),
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                      OutlinedButton(
                        key: const Key('summary-instructions-reset'),
                        onPressed: _reset,
                        child: const Text('Reset to default'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
