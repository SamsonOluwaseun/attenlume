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
      // A short name is too close to real words to fix from spelling alone.
      expect(correctNames('Thanks, Tundy!', hint), 'Thanks, Tundy!');
      expect(correctNames('Thanks, TunDy!', hint), 'Thanks, Tunde!');
      expect(
        correctNames('Select the Grade column.', 'Grace.'),
        'Select the Grade column.',
      );
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

    test('real words close to a name stay as heard (review cases)', () {
      expect(correctNames('a grade', 'Grace.'), 'a grade');
      expect(correctNames('we serviced it', 'Services.'), 'we serviced it');
      // Start of a sentence: an ordinary capital is not a name.
      expect(correctNames('Grade two passed.', 'Grace.'), 'Grade two passed.');
      // Joined to a digit or apostrophe: never rewritten.
      expect(
        correctNames('Grade2 and Grade’s', 'Grace.'),
        'Grade2 and Grade’s',
      );
    });

    test('accents and close misspellings of a name are fixed', () {
      expect(
        correctNames('Thanks, Francois.', 'François.'),
        'Thanks, François.',
      );
      expect(
        correctNames('Thanks, Francoise.', 'François.'),
        'Thanks, François.',
      );
      // Odd inner capital at a sentence start is still a mishearing.
      expect(
        correctNames('SamlyTix is here.', 'Samlytics.'),
        'Samlytics is here.',
      );
      // A plural of a name is a real word.
      expect(correctNames('two Conferences', 'Conference.'), 'two Conferences');
    });

    test('capitalised ordinary words and singulars stay as heard (round 2)', () {
      expect(
        correctNames('Open the Service menu.', 'Services.'),
        'Open the Service menu.',
      );
      // Common organisation words are never names, so nothing near them moves.
      expect(
        correctNames('the Conferencing Suite', 'Samlytics Conference 2026.'),
        'the Conferencing Suite',
      );
      // A singular of a distinctive name is left too: safe over sorry.
      expect(
        correctNames('at Samlytic today', 'Samlytics.'),
        'at Samlytic today',
      );
      expect(
        correctNames('at Samlyticss today', 'Samlytics.'),
        'at Samlyticss today',
      );
      expect(correctNames('Thanks, Bellos', 'Tunde Bello.'), 'Thanks, Bellos');
    });

    test('without a hint the text is unchanged', () {
      expect(correctNames('SamlyTix', null), 'SamlyTix');
      expect(correctNames('SamlyTix', 'a b c.'), 'SamlyTix');
    });
  });
}
