import 'dart:io';

/// Resident memory of this process [P0-10, AT-MEM-01].
///
/// Behind an interface so tests can script a memory trend and so a
/// platform tool (Android `dumpsys meminfo`, Instruments) can replace it
/// after device testing.
abstract interface class MemoryProbe {
  /// Resident set size now, in bytes.
  int currentRssBytes();

  /// Highest resident set size since the process started, in bytes.
  int peakRssBytes();
}

/// Reads `ProcessInfo` from `dart:io`. On Android and iOS this is the
/// whole app process (engine, plugins and native encoder included), which
/// is what the OS weighs when it kills apps.
class ProcessMemoryProbe implements MemoryProbe {
  const ProcessMemoryProbe();

  @override
  int currentRssBytes() => ProcessInfo.currentRss;

  @override
  int peakRssBytes() => ProcessInfo.maxRss;
}
