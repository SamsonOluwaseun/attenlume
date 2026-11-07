import 'dart:io';

import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/features/ai/language_model_providers.dart';
import 'package:attenlume/platform/ai/language_model_store.dart';
import 'package:attenlume/platform/device/device_memory_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

class _Memory implements DeviceMemoryProbe {
  const _Memory(this.bytes);
  final int? bytes;
  @override
  Future<int?> totalBytes() async => bytes;
}

/// A store that reports [installed] model ids as present, without writing
/// gigabytes to disk.
class _Store extends LanguageModelStore {
  _Store(Directory dir, this.installed) : super(baseDirectory: dir);
  final Set<String> installed;
  @override
  Future<String?> installedPath(VerifiedModelDescriptor descriptor) async =>
      installed.contains(descriptor.id) ? descriptor.fileName : null;
}

const _gib = 1024 * 1024 * 1024;

void main() {
  const big = LanguageModelDescriptor.gemma4E2B;
  const small = LanguageModelDescriptor.gemma3_1B;

  group('P3-11 FR-AI-01 model catalogue', () {
    test('the small model is pinned, checksummed and carries its terms', () {
      expect(small.downloadUrl, contains('/resolve/f9c28bcd85737ffc5aef'));
      expect(small.sizeBytes, 806058240);
      expect(small.sha256, hasLength(64));
      expect(small.sizeLabel, '769 MB');
      expect(small.licence, 'Gemma Terms of Use');
      expect(small.termsLinks.map((l) => l.$2), [
        'https://ai.google.dev/gemma/terms',
        'https://ai.google.dev/gemma/prohibited_use_policy',
      ]);
      // Apache 2.0 needs no terms step.
      expect(big.termsLinks, isEmpty);
      expect(big.sizeLabel, '2.65 GB');
      expect(LanguageModelDescriptor.catalogue, [big, small]);
      expect(LanguageModelDescriptor.byId(small.id), small);
      expect(LanguageModelDescriptor.byId('unknown'), isNull);
    });

    test('4 GB devices get the small model; 6 GB and up the big one', () {
      // What phones report: a 4 GB phone about 3.6 GiB, a 6 GB one 5.5 GiB.
      expect(
        LanguageModelDescriptor.recommendedFor((3.6 * _gib).round()),
        small,
      );
      expect(LanguageModelDescriptor.recommendedFor((5.5 * _gib).round()), big);
      expect(LanguageModelDescriptor.recommendedFor(16 * _gib), big);
      expect(LanguageModelDescriptor.recommendedFor(null), isNull);
      expect(LanguageModelDescriptor.recommendedFor(0), isNull);
    });
  });

  group('P3-11 FR-AI-01 active model', () {
    late TestData data;
    late Directory dir;

    setUp(() {
      data = TestData();
      dir = Directory.systemTemp.createTempSync('model_choice_');
    });
    tearDown(() async {
      await data.close();
      dir.deleteSync(recursive: true);
    });

    ProviderContainer container({
      int? memory,
      Set<String> installed = const {},
    }) {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(data.db),
          languageModelStoreProvider.overrideWith(
            (ref) async => _Store(dir, installed),
          ),
          deviceMemoryProbeProvider.overrideWithValue(_Memory(memory)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<LanguageModelDescriptor> active(ProviderContainer c) =>
        c.read(activeLanguageModelDescriptorProvider.future);

    test('without a choice: the recommendation, else Gemma 4', () async {
      expect(await active(container(memory: (3.6 * _gib).round())), small);
      expect(await active(container(memory: 8 * _gib)), big);
      expect(await active(container()), big);
    });

    test('an installed model wins over the recommendation', () async {
      // An earlier install of Gemma 4 on a 4 GB phone keeps working.
      expect(
        await active(
          container(memory: (3.6 * _gib).round(), installed: {big.id}),
        ),
        big,
      );
      expect(
        await active(container(memory: 16 * _gib, installed: {small.id})),
        small,
      );
    });

    test('the saved choice wins over everything', () async {
      await data.settings.setLanguageModelId(big.id);
      expect(await active(container(memory: (3.6 * _gib).round())), big);
      await data.settings.setLanguageModelId('removed-model');
      expect(await active(container(memory: (3.6 * _gib).round())), small);
    });
  });
}
