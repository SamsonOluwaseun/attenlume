import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/capture/recording_providers.dart';
import 'windows_lifecycle.dart';

/// Mounted once outside navigation so hiding/restoring cannot dispose capture.
class WindowsLifecycleHost extends ConsumerStatefulWidget {
  const WindowsLifecycleHost({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<WindowsLifecycleHost> createState() =>
      _WindowsLifecycleHostState();
}

class _WindowsLifecycleHostState extends ConsumerState<WindowsLifecycleHost> {
  WindowsLifecycle? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows) return;
    final recorder = ref.read(recordingServiceProvider);
    _lifecycle = WindowsLifecycle(
      status: () => recorder.status,
      changes: recorder.statusStream,
      stop: () async {
        await recorder.stop();
      },
    );
    _lifecycle!.start();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }
}
