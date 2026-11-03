import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_support.dart';
import '../../domain/services/activity_title.dart';

/// An agenda file the user picked: its name and bytes (ADR-082) [P2-07].
class PickedAgendaFile {
  const PickedAgendaFile(this.name, this.bytes, {this.tooLarge = false});

  final String name;
  final List<int> bytes;

  /// Larger than the picker's limit: not read, [bytes] is empty.
  final bool tooLarge;
}

/// How the user picks an agenda file. Tests override it.
abstract interface class AgendaFilePicker {
  /// The picked file, or null when cancelled. A file larger than [maxBytes]
  /// is not read ([PickedAgendaFile.tooLarge]), so the caller can say why.
  Future<PickedAgendaFile?> pick({required int maxBytes});
}

/// The system file picker from `file_selector`, already used for exports
/// and imports (ADR-040, ADR-049). Reads the file on the device only.
class FileSelectorAgendaPicker implements AgendaFilePicker {
  const FileSelectorAgendaPicker();

  @override
  Future<PickedAgendaFile?> pick({required int maxBytes}) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Agenda (CSV or ICS)',
          extensions: ['csv', 'ics', 'ical', 'txt', 'tsv'],
          mimeTypes: [
            'text/csv',
            'text/comma-separated-values',
            'text/calendar',
            'text/plain',
            'text/tab-separated-values',
            'application/csv',
            'application/vnd.ms-excel',
          ],
          uniformTypeIdentifiers: [
            'public.comma-separated-values-text',
            'com.apple.ical.ics',
            'public.calendar-event',
            'public.plain-text',
          ],
        ),
      ],
      confirmButtonText: 'Import',
    );
    if (file == null) return null;
    final length = await file.length();
    if (length > maxBytes) {
      return PickedAgendaFile(file.name, const [], tooLarge: true);
    }
    return PickedAgendaFile(file.name, await file.readAsBytes());
  }
}

final agendaFilePickerProvider = Provider<AgendaFilePicker>(
  (ref) => const FileSelectorAgendaPicker(),
);

/// "Now" for ordering the agenda (sessions near now first). Tests set it.
final agendaClockProvider = Provider<UtcClock>((ref) => systemUtcClock);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
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

/// "Wed 4 Nov, 09:30 to 10:15" (or "Wed 4 Nov, all day") in the conference
/// time zone. "to" rather than a dash reads well on screen readers.
String formatAgendaTime({
  required DateTime startUtc,
  DateTime? endUtc,
  required bool allDay,
  required String timezone,
}) {
  final start = toConferenceTime(startUtc, timezone);
  String two(int n) => n.toString().padLeft(2, '0');
  String hm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
  final day =
      '${_weekdays[start.weekday - 1]} ${start.day} ${_months[start.month - 1]}';
  if (allDay) return '$day, all day';
  if (endUtc == null) return '$day, ${hm(start)}';
  final end = toConferenceTime(endUtc, timezone);
  final sameDay =
      end.year == start.year &&
      end.month == start.month &&
      end.day == start.day;
  final endText = sameDay
      ? hm(end)
      : '${_weekdays[end.weekday - 1]} ${end.day} ${_months[end.month - 1]} '
            '${hm(end)}';
  return '$day, ${hm(start)} to $endText';
}

/// "Ada Lovelace · Room 2", leaving out what is missing.
String agendaDetailsLine(List<String> speakers, String? room) => [
  if (speakers.isNotEmpty) speakers.join(', '),
  if (room != null && room.isNotEmpty) room,
].join(' · ');
