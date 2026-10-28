/// How quick thoughts are written into an activity's notes, and how the
/// export finds private ones (FR-UI-05, FR-EXP-10, ADR-040) [P1-21].
library;

/// Starts a private reflection in the notes.
const privateReflectionMarker = '**[Private reflection]**';

/// Ends a private reflection. Written on its own paragraph since P1-21,
/// so a reflection with blank lines in it stays one private block.
const privateReflectionEndMarker = '**[End of private reflection]**';

/// Starts a shareable quick thought.
const quickThoughtMarker = '**[Quick thought]**';

/// Bookmark label the quick-thought sheet gives a private thought.
const privateThoughtLabel = 'Private thought';

final _paragraphBreak = RegExp(r'\n\s*\n');

/// The text a quick thought adds to the notes. A private one is wrapped
/// in [privateReflectionMarker] ... [privateReflectionEndMarker], however
/// many paragraphs it has.
String formatQuickThought(String text, {required bool isPrivate}) {
  final body = text.trim();
  return isPrivate
      ? '$privateReflectionMarker $body\n\n$privateReflectionEndMarker'
      : '$quickThoughtMarker $body';
}

/// [notes] without private reflections (FR-EXP-10). Returns the kept text
/// and how many reflections were removed.
///
/// - A reflection with an end marker (written since P1-21) is removed up
///   to and including that marker.
/// - A reflection without one was saved in the old format, where a
///   private thought with blank lines was marked on its first paragraph
///   only. The paragraphs after it cannot be told apart from later public
///   notes, so they are removed too, up to the next quick-thought or
///   private marker or the end of the notes. This can leave out public
///   text typed after an old private thought; it never exports private
///   text.
/// - A stray end marker is removed.
(String, int) stripPrivateReflections(String notes) {
  final paragraphs = notes.split(_paragraphBreak);
  bool startsPrivate(String p) =>
      p.trimLeft().startsWith(privateReflectionMarker);
  bool endsPrivate(String p) =>
      p.trimRight().endsWith(privateReflectionEndMarker);
  bool startsEntry(String p) =>
      startsPrivate(p) || p.trimLeft().startsWith(quickThoughtMarker);

  final kept = <String>[];
  var removed = 0;
  var i = 0;
  while (i < paragraphs.length) {
    final para = paragraphs[i];
    if (startsPrivate(para)) {
      removed++;
      var end = -1;
      for (var j = i; j < paragraphs.length; j++) {
        if (endsPrivate(paragraphs[j])) {
          end = j;
          break;
        }
        if (j > i && startsPrivate(paragraphs[j])) break;
      }
      if (end >= 0) {
        i = end + 1;
      } else {
        // Old format: drop until the next marked entry.
        i++;
        while (i < paragraphs.length && !startsEntry(paragraphs[i])) {
          i++;
        }
      }
      continue;
    }
    if (para.trim() != privateReflectionEndMarker) kept.add(para);
    i++;
  }
  return (kept.join('\n\n').trim(), removed);
}
