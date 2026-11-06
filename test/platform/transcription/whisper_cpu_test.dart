import 'package:attenlume/platform/transcription/whisper_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P3-01c FR-TRN-10 supported Windows CPU checks all Win32 features', () {
    final queried = <int>[];
    final cpu = PlatformWhisperCpu(
      isWindows: true,
      featurePresent: (feature) {
        queried.add(feature);
        return true;
      },
    );
    expect(cpu.supported, isTrue);
    expect(queried, [38, 39, 40]);
  });

  for (final missing in [38, 39, 40]) {
    test('P3-01c FR-TRN-10 unsupported Windows feature $missing', () {
      final cpu = PlatformWhisperCpu(
        isWindows: true,
        featurePresent: (feature) => feature != missing,
      );
      expect(cpu.supported, isFalse);
      expect(
        () => requireWhisperCpu(cpu),
        throwsA(isA<UnsupportedWhisperCpuException>()),
      );
    });
  }

  test('P3-01c FR-TRN-10 Windows query failure blocks Whisper', () {
    final cpu = PlatformWhisperCpu(
      isWindows: true,
      featurePresent: (_) => throw StateError('unavailable'),
    );
    expect(cpu.supported, isFalse);
  });

  test('P3-01c FR-TRN-10 other platforms never query kernel32', () {
    final cpu = PlatformWhisperCpu(
      isWindows: false,
      featurePresent: (_) => throw StateError('must not query'),
    );
    expect(cpu.supported, isTrue);
  });
}
