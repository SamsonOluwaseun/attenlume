import 'package:attenlume/domain/transcription/vocabulary_hint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2-14 FR-TRN-10 vocabulary hint', () {
    test('joins the session names as short sentences', () {
      expect(
        vocabularyHint(
          conferenceName: 'Samlytics Conference 2026',
          speakerNames: ['Ada Obi', 'Tunde Bello'],
          organisation: 'Samlytics Data Services',
        ),
        'Samlytics Conference 2026. Ada Obi. Tunde Bello. '
        'Samlytics Data Services.',
      );
    });

    test('nothing typed gives no hint', () {
      expect(vocabularyHint(), isNull);
      expect(vocabularyHint(conferenceName: '  ', speakerNames: ['']), isNull);
    });

    test('repeats, extra spaces and existing full stops are tidied', () {
      expect(
        vocabularyHint(
          conferenceName: 'Samlytics  Conference 2026',
          speakerNames: ['samlytics conference 2026'],
          organisation: 'Samlytics Data Services.',
        ),
        'Samlytics Conference 2026. Samlytics Data Services.',
      );
    });

    test('stays short, keeping the conference first', () {
      final hint = vocabularyHint(
        conferenceName: 'Samlytics Conference 2026',
        speakerNames: List.generate(40, (i) => 'Speaker number $i'),
        maxLength: 80,
      )!;
      expect(hint.length, lessThanOrEqualTo(80));
      expect(hint, startsWith('Samlytics Conference 2026.'));
    });
  });

  group('P2-14 FR-TRN-10 name correction', () {
    const hint =
        'Samlytics Conference 2026. Tunde Bello. Samlytics Data '
        'Services.';

    test('a misheard session name is corrected, punctuation kept', () {
      expect(
        correctNames(
          'Welcome to SamlyTix Conference 2026. Today SamlyTix Data '
          'Services explains it.',
          hint,
        ),
        'Welcome to Samlytics Conference 2026. Today Samlytics Data '
        'Services explains it.',
      );
      expect(correctNames('Thanks, Tundy!', hint), 'Thanks, Tunde!');
    });

    test('ordinary words and forms of a name are left as heard', () {
      const heard =
          'Two conferences and our service, with simple checks every week.';
      expect(correctNames(heard, hint), heard);
      // Same letters, different case: not a mishearing.
      expect(correctNames('the samlytics team', hint), 'the samlytics team');
      // Short or far-off words never change.
      expect(
        correctNames('Sam said Samuel left', hint),
        'Sam said Samuel left',
      );
    });

    test('without a hint the text is unchanged', () {
      expect(correctNames('SamlyTix', null), 'SamlyTix');
      expect(correctNames('SamlyTix', 'a b c.'), 'SamlyTix');
    });
  });
}
