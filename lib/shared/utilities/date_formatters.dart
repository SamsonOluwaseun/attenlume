/// Pure Dart date formatting utilities in UK English (DESIGN_GUIDE, PRODUCT_SPEC).
library;

const List<String> _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _monthsFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats a single date as "27 Oct 2026".
String formatDateShort(DateTime date) {
  final d = date.toUtc();
  final month = _monthsShort[d.month - 1];
  return '${d.day} $month ${d.year}';
}

/// Formats a single date as "27 October 2026".
String formatDateFull(DateTime date) {
  final d = date.toUtc();
  final month = _monthsFull[d.month - 1];
  return '${d.day} $month ${d.year}';
}

/// Formats a date range cleanly:
/// - Same day: "27 Oct 2026"
/// - Same month: "27–29 Oct 2026"
/// - Same year: "27 Oct – 2 Nov 2026"
/// - Different years: "27 Oct 2026 – 2 Jan 2027"
/// - One date: "From 27 Oct 2026" or "Until 29 Oct 2026"
/// - None: "Dates not set"
String formatDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return 'Dates not set';
  if (start != null && end == null) return 'From ${formatDateShort(start)}';
  if (start == null && end != null) return 'Until ${formatDateShort(end)}';

  final s = start!.toUtc();
  final e = end!.toUtc();

  if (s.year == e.year && s.month == e.month && s.day == e.day) {
    return formatDateShort(s);
  }

  if (s.year == e.year && s.month == e.month) {
    return '${s.day}–${e.day} ${_monthsShort[s.month - 1]} ${s.year}';
  }

  if (s.year == e.year) {
    return '${s.day} ${_monthsShort[s.month - 1]} – ${e.day} ${_monthsShort[e.month - 1]} ${s.year}';
  }

  return '${formatDateShort(s)} – ${formatDateShort(e)}';
}
