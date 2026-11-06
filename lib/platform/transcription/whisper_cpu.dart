import 'dart:ffi';
import 'dart:io';

/// Kept separate from Whisper so unsupported PCs never initialise its runtime.
abstract interface class WhisperCpu {
  bool get supported;
}

class PlatformWhisperCpu implements WhisperCpu {
  const PlatformWhisperCpu({this.isWindows, this.featurePresent});

  final bool? isWindows;
  final bool Function(int)? featurePresent;

  @override
  bool get supported {
    if (!(isWindows ?? Platform.isWindows)) return true;
    try {
      final present = featurePresent ?? _windowsFeaturePresent;
      // Win32 PF_SSE4_2, PF_AVX and PF_AVX2_INSTRUCTIONS_AVAILABLE.
      // Windows reports usable features, including OS support for AVX state.
      return [38, 39, 40].every(present);
    } on Object {
      return false;
    }
  }

  static bool _windowsFeaturePresent(int feature) {
    final query = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'IsProcessorFeaturePresent',
        );
    return query(feature) != 0;
  }
}

class UnsupportedWhisperCpuException implements Exception {
  const UnsupportedWhisperCpuException();

  static const reason =
      "This PC's processor is too old for on-device transcription. "
      'Recording and everything else still work.';

  @override
  String toString() => reason;
}

void requireWhisperCpu(WhisperCpu cpu) {
  if (!cpu.supported) throw const UnsupportedWhisperCpuException();
}
