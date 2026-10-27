/// Pure Dart date formatting utilities in UK English (DESIGN_GUIDE, PRODUCT_SPEC).
library;

import '../../domain/services/activity_title.dart';

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

/// Formats a duration in UK English (FR-ACT-01, FR-ACT-03):
/// - 0 min: "0 min"
/// - Under a minute (> 0): "< 1 min"
/// - Under an hour: "47 min"
/// - Exact hours: "2 h"
/// - Hours and minutes: "1 h 12 min"
String formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes == 0) {
    if (duration.inSeconds > 0) return '< 1 min';
    return '0 min';
  }
  final hours = duration.inHours;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return '$minutes min';
  }
  if (minutes == 0) {
    return '$hours h';
  }
  return '$hours h $minutes min';
}

/// Formats storage bytes cleanly (FR-ACT-01):
/// - 0: "0 B"
/// - < 1 KB: "512 B"
/// - < 1 MB: "350.2 KB"
/// - < 1 GB: "14.2 MB" (or "14 MB" if integer)
/// - >= 1 GB: "1.2 GB"
String formatStorageBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 10) {
      final whole = mb.roundToDouble();
      if ((mb - whole).abs() < 0.05) {
        return '${whole.toInt()} MB';
      }
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = bytes / (1024 * 1024 * 1024);
  return '${gb.toStringAsFixed(1)} GB';
}

/// Formats UTC instant as "HH:mm" in conference timezone (FR-ACT-03).
String formatTimeOfDayInTimezone(DateTime utcTime, String timezone) {
  final local = toConferenceTime(utcTime, timezone);
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
