/// Names likely in this session, from what the user typed (conference,
/// speakers, organisation), so names in the transcript come out right
/// ("Samlytics", not "SamlyTix") [P2-14, FR-TRN-10]. It stays on the device.
///
/// It is not given to Whisper as a prompt: on Windows that merged segments
/// and moved timestamps by seconds. [correctNames] uses it after recognition.
/// The session title is left out: its ordinary words ("Small", "Teams")
/// would turn real words into near matches. [maxLength] keeps it short,
/// dropping later parts first.
String? vocabularyHint({
  String? conferenceName,
  List<String> speakerNames = const [],
  String? organisation,
  int maxLength = 300,
}) {
  final parts = <String>[];
  final seen = <String>{};
  void add(String? text) {
    final value = text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (value.isEmpty || !seen.add(value.toLowerCase())) return;
    parts.add(value);
  }

  add(conferenceName);
  for (final name in speakerNames) {
    add(name);
  }
  add(organisation);

  final buffer = StringBuffer();
  for (final part in parts) {
    final sentence = RegExp(r'[.!?]$').hasMatch(part) ? part : '$part.';
    final next = buffer.isEmpty ? sentence : ' $sentence';
    if (buffer.length + next.length > maxLength) break;
    buffer.write(next);
  }
  return buffer.isEmpty ? null : buffer.toString();
}

/// A whole word: letters only, not joined to a digit, apostrophe or hyphen,
/// so "grade2", "grade's" and "Samly-Tix" are never rewritten.
final _word = RegExp(
  r"(?<![\p{L}\p{M}\p{N}'’-])[\p{L}\p{M}]+(?![\p{L}\p{M}\p{N}'’-])",
  unicode: true,
);

/// Proposes fixes for misheard session names in recognised [text]
/// [P2-14]. The caller saves them as corrections, so the machine text stays
/// as heard (FR-TRN-08).
///
/// Conservative by design. Names are capitalised hint words of 5+ letters.
/// Only a capitalised transcript word can change, so ordinary lower-case
/// words ("a grade", "serviced") never do; at the start of a sentence it
/// must also have an odd inner capital ("SamlyTix"). It must start with the
/// same letter, differ in length by at most 2 and be at least 75% similar,
/// ignoring accents ("Francois" becomes "François"). Plurals of a name
/// ("Conferences") are left as heard.
String correctNames(String text, String? hint) {
  if (hint == null) return text;
  final names = {
    for (final m in _word.allMatches(hint))
      if (m[0]!.length >= 5 && _isCapital(m[0]!)) m[0]!,
  };
  if (names.isEmpty) return text;
  return text.replaceAllMapped(_word, (m) {
    final word = m[0]!;
    if (word.length < 4 || !_isCapital(word)) return word;
    final innerCapital = word.substring(1) != word.substring(1).toLowerCase();
    final before = text.substring(0, m.start).trimRight();
    final sentenceStart =
        before.isEmpty || RegExp(r'[.!?:"“]$').hasMatch(before);
    if (sentenceStart && !innerCapital) return word;
    final heard = _fold(word);
    String? best;
    var bestScore = 0.75;
    for (final name in names) {
      final target = _fold(name);
      if (word.toLowerCase() == name.toLowerCase()) return word;
      if (target == heard) return name;
      final plural = target.endsWith('s') ? '${target}es' : '${target}s';
      if (heard == plural) continue;
      if (target[0] != heard[0] || (target.length - heard.length).abs() > 2) {
        continue;
      }
      final score =
          1 -
          _distance(heard, target) /
              (heard.length > target.length ? heard.length : target.length);
      if (score >= bestScore) {
        bestScore = score;
        best = name;
      }
    }
    return best ?? word;
  });
}

bool _isCapital(String word) => word[0] != word[0].toLowerCase();

/// Lower case without the accents most names carry.
String _fold(String word) {
  final out = StringBuffer();
  for (final rune in word.toLowerCase().runes) {
    final c = String.fromCharCode(rune);
    out.write(_plain[c] ?? c);
  }
  return out.toString();
}

final _plain = <String, String>{
  for (final c in ['à', 'á', 'â', 'ã', 'ä', 'å', 'ā']) c: 'a',
  for (final c in ['ç', 'ć', 'č']) c: 'c',
  for (final c in ['è', 'é', 'ê', 'ë', 'ē', 'ě']) c: 'e',
  for (final c in ['ì', 'í', 'î', 'ï', 'ī']) c: 'i',
  for (final c in ['ñ', 'ń']) c: 'n',
  for (final c in ['ò', 'ó', 'ô', 'õ', 'ö', 'ø', 'ō']) c: 'o',
  for (final c in ['ù', 'ú', 'û', 'ü', 'ū']) c: 'u',
  for (final c in ['ý', 'ÿ']) c: 'y',
  'ž': 'z',
  'š': 's',
  'ł': 'l',
};

int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
