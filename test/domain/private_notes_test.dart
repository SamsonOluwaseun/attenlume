import 'package:attenlume/domain/services/private_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FR-EXP-10 private reflections in notes', () {
    test('FR-EXP-10 a private quick thought is wrapped in start and end '
        'markers', () {
      expect(
        formatQuickThought('One.\n\nTwo.', isPrivate: true),
        '**[Private reflection]** One.\n\nTwo.\n\n'
        '**[End of private reflection]**',
      );
      expect(
        formatQuickThought(' Shareable ', isPrivate: false),
        '**[Quick thought]** Shareable',
      );
    });

    test('FR-EXP-10 new format: every paragraph of a private thought goes, '
        'public notes after it stay', () {
      final notes = [
        'Public before.',
        formatQuickThought(
          'Secret one.\n\nSecret two.\n\n\nSecret three.',
          isPrivate: true,
        ),
        'Public after.',
        formatQuickThought('Shareable.', isPrivate: false),
      ].join('\n\n');
      final (kept, removed) = stripPrivateReflections(notes);
      expect(removed, 1);
      expect(kept, isNot(contains('Secret')));
      expect(kept, isNot(contains('End of private')));
      expect(
        kept,
        'Public before.\n\nPublic after.\n\n**[Quick thought]** Shareable.',
      );
    });

    test('FR-EXP-10 old format: paragraphs after a marked one are dropped up '
        'to the next marker (the safer choice)', () {
      const notes =
          'Public before.\n\n'
          '**[Private reflection]** Secret one.\n\n'
          'Secret two, same thought.\n\n'
          'Cannot tell this apart either.\n\n'
          '**[Quick thought]** Shareable.\n\n'
          'Public after the quick thought.';
      final (kept, removed) = stripPrivateReflections(notes);
      expect(removed, 1);
      expect(kept, isNot(contains('Secret')));
      expect(kept, isNot(contains('Cannot tell')));
      expect(
        kept,
        'Public before.\n\n**[Quick thought]** Shareable.\n\n'
        'Public after the quick thought.',
      );
    });

    test('FR-EXP-10 old format at the end of the notes drops the rest', () {
      const notes =
          'Public.\n\n**[Private reflection]** Secret.\n\nSecret too.';
      expect(stripPrivateReflections(notes), ('Public.', 1));
    });

    test('FR-EXP-10 old then new format, and a stray end marker', () {
      final notes = [
        '**[Private reflection]** Old secret.',
        'Old secret continued.',
        formatQuickThought('New secret.\n\nMore.', isPrivate: true),
        'Public.',
        privateReflectionEndMarker,
      ].join('\n\n');
      final (kept, removed) = stripPrivateReflections(notes);
      expect(removed, 2);
      expect(kept, 'Public.');
    });

    test('FR-EXP-10 notes with no private thoughts are unchanged', () {
      const notes = 'One.\n\n**[Quick thought]** Two.';
      expect(stripPrivateReflections(notes), (notes, 0));
    });
  });
}
