import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../data/filesystem/app_data_directory.dart';
import '../../domain/transcription/transcript.dart';
import '../../platform/transcription/transcription_exceptions.dart';
import '../../platform/transcription/whisper_cpu.dart';
import 'transcription_controller.dart';
import 'transcription_providers.dart';

/// Optional after-recording pilot. No download or inference on page opening.
class TranscriptionScreen extends ConsumerStatefulWidget {
  const TranscriptionScreen({
    super.key,
    this.activityId,
    this.isPrivate = false,
    this.pickAudio,
  });
  final String? activityId;
  final bool isPrivate;
  final Future<XFile?> Function()? pickAudio;

  @override
  ConsumerState<TranscriptionScreen> createState() =>
      _TranscriptionScreenState();
}

class _TranscriptionScreenState extends ConsumerState<TranscriptionScreen> {
  String? _notice;
  String? _selectedImportId;
  bool _includePrivate = false;

  Future<void> _enable(TranscriptionController controller) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable optional transcription?'),
        content: Text(
          '${controller.models.name} recognises English speech on this device. '
          'Its model download is about '
          '${(controller.models.downloadBytes / (1024 * 1024)).ceil()} MB, '
          'with additional temporary storage needed for audio conversion. '
          'Processing can use battery, memory and generate heat. '
          'Text may be inaccurate; review it before relying on it. '
          'Audio is not uploaded. Enabling does not download the model or '
          'automatically transcribe recordings. Live captions are not part '
          'of this pilot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.setEnabled(true);
  }

  Future<void> _share(List<TranscriptDocument> documents, bool markdown) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share transcript?'),
        content: const Text(
          'This text may include private notes or sensitive speech. '
          'Sharing sends a copy to the destination you choose.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final text = documents
        .map(markdown ? renderTranscriptMarkdown : renderTranscriptText)
        .join('\n');
    final root = await appDataDirectory();
    final folder = await Directory(
      p.join(
        root.path,
        'transcript-shares',
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final file = File(
      p.join(folder.path, markdown ? 'transcript.md' : 'transcript.txt'),
    );
    await file.writeAsString(text, flush: true);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(
          () => _notice =
              'Could not complete that action. Saved audio and text are kept.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(transcriptionControllerProvider);
    final edits = widget.activityId == null
        ? const AsyncData(false)
        : ref.watch(transcriptionEditsPresentProvider(widget.activityId!));
    final supportsActivity = edits.asData?.value == false;
    return Scaffold(
      appBar: AppBar(title: const Text('Transcription · pilot')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final unsupportedCpu = error is UnsupportedWhisperCpuException;
          final unsupported =
              error is UnsupportedError &&
              error.message == 'The transcription pilot needs a 64-bit device.';
          final storage =
              error is FileSystemException || error is WhisperStorageException;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Transcription unavailable'),
                  const SizedBox(height: 12),
                  Text(
                    unsupportedCpu
                        ? UnsupportedWhisperCpuException.reason
                        : unsupported
                        ? 'This pilot needs a 64-bit Android app and operating system. '
                              'Reinstalling the model will not change this. '
                              'Recording and export still work.'
                        : storage
                        ? 'Transcription storage could not be opened safely. '
                              'Restart the app and try again. '
                              'Your recordings and saved text are unchanged.'
                        : 'Transcription setup could not finish. Try again, or '
                              'restart the app. Your recordings are unchanged.',
                    textAlign: TextAlign.center,
                  ),
                  if (!unsupported && !unsupportedCpu) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('transcription-setup-retry'),
                      onPressed: () =>
                          ref.invalidate(transcriptionControllerProvider),
                      child: const Text('Retry setup'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        data: (controller) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final documents =
                controller.documents
                    .where(
                      (document) =>
                          supportsActivity &&
                          document.activityId ==
                              (widget.activityId ?? _selectedImportId),
                    )
                    .toList()
                  ..sort((a, b) => a.segmentOffset.compareTo(b.segmentOffset));
            final canShare =
                supportsActivity && (!widget.isPrivate || _includePrivate);
            final imports =
                controller.documents
                    .map((d) => d.activityId)
                    .where((id) => id.startsWith('import-'))
                    .toSet()
                    .toList()
                  ..sort();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'After-recording transcription',
                  style: TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Optional and off by default. English pilot: saved audio clips up to 10 minutes. No live microphone access. Saved recordings and transcripts stay on your device unless you share them.',
                ),
                SwitchListTile(
                  key: const Key('transcription-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Make transcription available'),
                  subtitle: const Text(
                    'Switching off releases resources and keeps downloaded model and saved text.',
                  ),
                  value: controller.enabled,
                  onChanged: (value) => _action(
                    () => value
                        ? _enable(controller)
                        : controller.setEnabled(false),
                  ),
                ),
                Text(
                  '${controller.models.name} · ${(controller.models.downloadBytes / (1024 * 1024)).ceil()} MB model · ${controller.installed ? 'Installed' : 'Not installed'}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!controller.installed)
                      FilledButton.icon(
                        onPressed: controller.enabled && !controller.busy
                            ? () => _action(controller.install)
                            : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Download model'),
                      ),
                    if (controller.installed)
                      OutlinedButton(
                        onPressed: controller.busy
                            ? null
                            : () => _action(controller.removeModel),
                        child: const Text('Switch off and remove model'),
                      ),
                    if (controller.busy)
                      OutlinedButton(
                        onPressed: () => _action(controller.cancel),
                        child: const Text('Stop processing'),
                      ),
                  ],
                ),
                if (controller.busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: controller.progress),
                  const Text(
                    'Processing locally. Completed text is saved between audio segments.',
                  ),
                ],
                if (controller.message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      controller.message!,
                      semanticsLabel: controller.message,
                    ),
                  ),
                if (_notice != null) Text(_notice!),
                const SizedBox(height: 16),
                if (!supportsActivity)
                  const Text(
                    'This activity has audio cuts, or its edit state could not be checked. Transcription and text sharing are unavailable in this pilot. Import its exported trimmed audio instead.',
                  ),
                if (widget.activityId == null && imports.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: imports.contains(_selectedImportId)
                        ? _selectedImportId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Saved imported transcript',
                    ),
                    items: [
                      for (final id in imports)
                        DropdownMenuItem(
                          value: id,
                          child: Text(id, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: controller.busy
                        ? null
                        : (value) => setState(() => _selectedImportId = value),
                  ),
                FilledButton.icon(
                  key: const Key('transcribe-recording'),
                  icon: const Icon(Icons.transcribe),
                  label: Text(
                    widget.activityId == null
                        ? 'Choose audio to transcribe'
                        : 'Transcribe this activity',
                  ),
                  onPressed:
                      controller.enabled &&
                          controller.installed &&
                          !controller.busy &&
                          supportsActivity
                      ? () => _action(() async {
                          final sources = widget.activityId == null
                              ? await _pickAudio()
                              : await ref.read(
                                  transcriptionSourcesProvider(
                                    widget.activityId!,
                                  ).future,
                                );
                          if (sources.isNotEmpty) {
                            await controller.transcribe(sources);
                          }
                        })
                      : null,
                ),
                if (documents.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Machine-generated text · review for errors'),
                  if (widget.isPrivate)
                    SwitchListTile(
                      title: const Text(
                        'Include private transcript in copy or share',
                      ),
                      subtitle: const Text(
                        'Off by default. Original audio is unchanged.',
                      ),
                      value: _includePrivate,
                      onChanged: (value) =>
                          setState(() => _includePrivate = value),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy text'),
                        onPressed: !canShare
                            ? null
                            : () => _action(
                                () => Clipboard.setData(
                                  ClipboardData(
                                    text: documents
                                        .map(renderTranscriptText)
                                        .join('\n'),
                                  ),
                                ),
                              ),
                      ),
                      TextButton(
                        onPressed: !canShare
                            ? null
                            : () => _action(() => _share(documents, false)),
                        child: const Text('Share transcript.txt'),
                      ),
                      TextButton(
                        onPressed: !canShare
                            ? null
                            : () => _action(() => _share(documents, true)),
                        child: const Text('Share transcript.md'),
                      ),
                    ],
                  ),
                  for (final document in documents)
                    for (
                      var index = 0;
                      index < document.machineSpans.length;
                      index++
                    )
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: canShare
                            ? SelectableText(document.textAt(index))
                            : Text(document.textAt(index)),
                        subtitle: Text(
                          '${(document.segmentOffset + document.machineSpans[index].start).inSeconds}s',
                        ),
                        trailing: IconButton(
                          tooltip: 'Correct transcript text',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: controller.busy
                              ? null
                              : () => _action(
                                  () => _edit(controller, document, index),
                                ),
                        ),
                      ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<List<TranscriptionSource>> _pickAudio() async {
    final picked = widget.pickAudio != null
        ? await widget.pickAudio!()
        : await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'Audio',
                extensions: ['m4a', 'mp3', 'wav', 'aac'],
                uniformTypeIdentifiers: ['public.audio'],
              ),
            ],
          );
    if (picked == null) return [];
    final id = 'import-${DateTime.now().microsecondsSinceEpoch}';
    if (mounted) setState(() => _selectedImportId = id);
    return [
      TranscriptionSource(
        activityId: id,
        segmentId: 'audio',
        audioPath: picked.path,
      ),
    ];
  }

  Future<void> _edit(
    TranscriptionController controller,
    TranscriptDocument document,
    int index,
  ) async {
    final text = TextEditingController(text: document.textAt(index));
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct transcript'),
        content: TextField(controller: text, minLines: 2, maxLines: 6),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save correction'),
          ),
        ],
      ),
    );
    // Dialog animations may still use its controller until the next frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (saved != null) await controller.correct(document, index, saved);
  }
}
