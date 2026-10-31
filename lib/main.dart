import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'platform/windows_lifecycle/windows_lifecycle_host.dart';

void main() {
  runApp(
    const ProviderScope(child: WindowsLifecycleHost(child: AttenlumeApp())),
  );
}
