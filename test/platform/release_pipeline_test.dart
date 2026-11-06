@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P3-01c FR-TRN-10 Whisper uses fixed AVX2 FMA F16C without native or AVX512', () {
    final hook = File('windows/whisper_static.cmake').absolute.path;
    final fixture = Directory.systemTemp.createTempSync('p301c-cmake-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    // Evaluate the hook, rather than accepting option names in comments or
    // an OFF loop as evidence that the required instructions are enabled.
    final script = File('${fixture.path}/check.cmake')
      ..writeAsStringSync('''
include("${hook.replaceAll('\\', '/')}")
foreach(option SSE42 AVX AVX2 FMA F16C BMI2)
  if(NOT GGML_\${option})
    message(FATAL_ERROR "Required instruction disabled: \${option}")
  endif()
endforeach()
foreach(option NATIVE BACKEND_DL CPU_ALL_VARIANTS AVX_VNNI AVX512 AVX512_VBMI AVX512_VNNI AVX512_BF16 AMX_TILE AMX_INT8 AMX_BF16)
  if(GGML_\${option})
    message(FATAL_ERROR "Forbidden setting enabled: \${option}")
  endif()
endforeach()
if(BUILD_SHARED_LIBS OR NOT GGML_STATIC OR NOT GGML_CPU)
  message(FATAL_ERROR "Whisper must use a static built-in CPU backend")
endif()
''');
    var cmake = 'cmake';
    if (Platform.isWindows) {
      final discovery = Process.runSync(
        '${Platform.environment['ProgramFiles(x86)']}/Microsoft Visual Studio/Installer/vswhere.exe',
        [
          '-latest',
          '-products',
          '*',
          '-find',
          'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe',
        ],
      );
      expect(discovery.exitCode, 0, reason: '${discovery.stderr}');
      final discovered = (discovery.stdout as String).trim();
      if (discovered.isNotEmpty) cmake = discovered.split('\n').first.trim();
    }
    final result = Process.runSync(cmake, ['-P', script.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('P3-01b installer rejects conflicting ggml providers', () {
    final source = File('tool/build_windows_installer.ps1').readAsStringSync();
    final start = source.indexOf(
      r"    $runner = 'build\windows\x64\runner\Release'",
    );
    final end = source.indexOf(r'    $version =', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final guard = source.substring(start, end);
    final fixture = Directory.systemTemp.createTempSync('p301b-installer-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final runner = Directory('${fixture.path}/build/windows/x64/runner/Release')
      ..createSync(recursive: true);
    final native =
        File('${fixture.path}/build/native_assets/windows/ggml-base.dll')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('llama');
    final base = File('${runner.path}/ggml-base.dll')
      ..writeAsStringSync(native.readAsStringSync());
    ProcessResult check() => Process.runSync('powershell', [
      '-NoProfile',
      '-Command',
      guard,
    ], workingDirectory: fixture.path);
    expect(check().exitCode, 0);
    final extra = File('${runner.path}/nested/ggml-base.dll')
      ..parent.createSync()
      ..writeAsStringSync('whisper');
    expect(check().exitCode, isNot(0), reason: 'distinct nested DLL');
    extra.deleteSync();
    base.writeAsStringSync('whisper');
    expect(check().exitCode, isNot(0), reason: 'overwritten runner DLL');
    base.writeAsStringSync('llama');
    File('${runner.path}/ggml-cpu.dll').writeAsStringSync('whisper');
    expect(check().exitCode, isNot(0), reason: 'stale Whisper CPU DLL');
  }, skip: !Platform.isWindows);

  test('P3-01b Windows isolates static Whisper from llama native assets', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final hook = File('windows/whisper_static.cmake').readAsStringSync();
    expect(cmake, contains('CMAKE_PROJECT_whisper.cpp_INCLUDE'));
    expect(
      cmake.indexOf('CMAKE_PROJECT_whisper.cpp_INCLUDE'),
      lessThan(cmake.indexOf('include(flutter/generated_plugins.cmake)')),
    );
    expect(cmake, contains('STREQUAL "STATIC_LIBRARY"'));
    expect(cmake, contains('list(REMOVE_ITEM PLUGIN_BUNDLED_LIBRARIES'));
    for (final setting in [
      'BUILD_SHARED_LIBS OFF',
      'GGML_STATIC ON',
      'GGML_BACKEND_DL OFF',
      'GGML_CPU ON',
      'GGML_CPU_ALL_VARIANTS OFF',
      'GGML_NATIVE OFF',
    ]) {
      expect(hook, contains(setting));
    }
    final installer = File('tool/build_windows_installer.ps1')
        .readAsStringSync();
    expect(installer, contains(r'$ggmlHashes.Count -ne 1'));
    expect(installer, contains('does not match fllama native assets'));
    expect(installer, contains('shared ggml-cpu.dll must not be packaged'));
  });

  const workflowPath = '.github/workflows/release.yml';

  group('P1-28 GitHub Actions release pipeline', () {
    test(
      'P1-28 workflow exists and uses explicit manual workflow_dispatch only',
      () {
        final file = File(workflowPath);
        expect(file.existsSync(), isTrue, reason: '$workflowPath must exist');

        final content = file.readAsStringSync();

        // Explicit workflow_dispatch trigger
        expect(content, contains('workflow_dispatch:'));
        expect(content, contains('--draft'));
        expect(content, isNot(contains('inputs.draft')));
        expect(
          content,
          contains('--draft \\'),
          reason: 'draft releases must be default for safety',
        );

        // No automatic release triggers on push/schedule
        expect(
          RegExp(r'^\s*push:\s*$', multiLine: true).hasMatch(content),
          isFalse,
          reason: 'no automatic public release on ordinary push',
        );
        expect(
          RegExp(r'^\s*schedule:\s*$', multiLine: true).hasMatch(content),
          isFalse,
          reason: 'no periodic automated release schedule',
        );
      },
    );

    test('P1-28 shell bodies never interpolate Actions expressions', () {
      final content = File(workflowPath).readAsStringSync();
      var inRun = false;
      for (final line in content.split('\n')) {
        if (line.trimRight() == '        run: |') {
          inRun = true;
        } else if (line.trim().isNotEmpty && !line.startsWith('          ')) {
          inRun = false;
        }
        if (inRun) {
          expect(line, isNot(contains(r'${{')), reason: line);
        }
      }
      expect(content, contains(r'gh release create "$RELEASE_TAG"'));
      expect(content, contains(r'--title "$RELEASE_TITLE"'));
      expect(
        content,
        contains('Required Android signing configuration is missing'),
      );
      expect(content, isNot(contains('fallback release APK')));
    });

    test(
      'P1-28 preserves canonical download asset names matching README links',
      () {
        final file = File(workflowPath);
        final content = file.readAsStringSync();

        // Expected canonical asset names from Section 14 and README
        const expectedApk = 'attenlume-android.apk';
        const expectedExe = 'attenlume-windows-setup.exe';
        const expectedSums = 'SHA256SUMS.txt';

        expect(content, contains(expectedApk));
        expect(content, contains(expectedExe));
        expect(content, contains(expectedSums));

        // Verify README links align with canonical names
        final readme = File('README.md').readAsStringSync();
        expect(readme, contains('/releases/latest/download/$expectedApk'));
        expect(readme, contains('/releases/latest/download/$expectedExe'));
      },
    );

    test(
      'P1-28 references signing secret names without hardcoded credentials',
      () {
        final file = File(workflowPath);
        final content = file.readAsStringSync();

        // Repository secret placeholders
        expect(content, contains(r'${{ secrets.ANDROID_KEYSTORE_BASE64 }}'));
        expect(content, contains(r'${{ secrets.ANDROID_KEYSTORE_PASSWORD }}'));
        expect(content, contains(r'${{ secrets.ANDROID_KEY_ALIAS }}'));
        expect(content, contains(r'${{ secrets.ANDROID_KEY_PASSWORD }}'));

        // Ensure no raw private keys or embedded passwords exist
        expect(content, isNot(contains('-----BEGIN PRIVATE KEY-----')));
        expect(content, isNot(contains('-----BEGIN CERTIFICATE-----')));

        // Reuses build scripts
        expect(content, contains('flutter build apk --release'));
        expect(content, contains('tool/build_windows_installer.ps1'));
      },
    );
  });
}
