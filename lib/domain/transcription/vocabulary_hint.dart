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

/// Replaces near-misses of the hint's names in recognised [text], keeping
/// punctuation. Only capitalised hint words of 5+ letters count as names; a
/// transcript word changes only when it starts with the same letter, differs
/// in length by at most 2 and is at least 75% similar, so ordinary words
/// stay as heard. Exact matches in any case are left alone.
String correctNames(String text, String? hint) {
  if (hint == null) return text;
  final names = {
    for (final m in RegExp(r"[A-Za-z][A-Za-z'-]*").allMatches(hint))
      if (m[0]!.length >= 5 && m[0]![0] != m[0]![0].toLowerCase()) m[0]!,
  };
  if (names.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r"[A-Za-z][A-Za-z'-]*"), (m) {
    final word = m[0]!;
    if (word.length < 4) return word;
    final lower = word.toLowerCase();
    String? best;
    var bestScore = 0.75;
    for (final name in names) {
      final target = name.toLowerCase();
      if (target == lower) return word;
      // "conferences" is a form of "Conference", not a misheard name.
      if (target.startsWith(lower) || lower.startsWith(target)) continue;
      if (target[0] != lower[0] || (target.length - lower.length).abs() > 2) {
        continue;
      }
      final score =
          1 -
          _distance(lower, target) /
              (lower.length > target.length ? lower.length : target.length);
      if (score >= bestScore) {
        bestScore = score;
        best = name;
      }
    }
    return best ?? word;
  });
}

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
