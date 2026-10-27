/// Which microphone the platform is recording from (BUILD_GUIDE 10.4)
/// [P0-07, FR-REC-07, FR-QUAL-06].
///
/// Read when a segment starts and when the route may have changed, so
/// each segment stores the input it was really recorded from. Kept behind
/// an interface so the platform code can change after device testing
/// (AGENTS.md).
abstract interface class AudioRouteProbe {
  /// The input in use now, or null when the platform does not say
  /// (Android and Windows through the current packages, ADR-016).
  Future<InputRoute?> activeInput();

  /// Every input the platform reports as available.
  Future<List<InputRoute>> availableInputs();
}

enum InputRouteKind {
  builtIn,
  wired,

  /// Hands-free (HFP or SCO) and LE audio microphones. Often call quality.
  bluetooth,
  usb,
  other,
  unknown;

  bool get isBluetooth => this == bluetooth;
}

/// One input route, as the platform names it.
class InputRoute {
  const InputRoute({required this.id, required this.label, required this.kind});

  final String id;
  final String label;
  final InputRouteKind kind;

  /// What `recording_segments.input_route` stores, for example
  /// `bluetooth: AirPods Pro`.
  String get key => '${kind.name}: $label';

  @override
  bool operator ==(Object other) =>
      other is InputRoute &&
      other.id == id &&
      other.label == label &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, label, kind);

  @override
  String toString() => key;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
  };
}

/// Guesses the kind from a device name, for platforms that only give a
/// name (Windows). A guess: the segment keeps the label as well.
InputRouteKind classifyInputLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains('bluetooth') ||
      l.contains('hands-free') ||
      l.contains('handsfree') ||
      l.contains('airpods')) {
    return InputRouteKind.bluetooth;
  }
  if (l.contains('usb')) return InputRouteKind.usb;
  if (l.contains('headset') || l.contains('line in')) {
    return InputRouteKind.wired;
  }
  if (l.contains('microphone array') ||
      l.contains('internal') ||
      l.contains('built-in')) {
    return InputRouteKind.builtIn;
  }
  return InputRouteKind.other;
}

/// For hosts with no route information at all.
class NoAudioRouteProbe implements AudioRouteProbe {
  const NoAudioRouteProbe();

  @override
  Future<InputRoute?> activeInput() async => null;

  @override
  Future<List<InputRoute>> availableInputs() async => const [];
}
