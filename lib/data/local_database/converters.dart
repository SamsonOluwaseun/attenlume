import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/enums.dart';

/// Stores a [KeyedEnum] by its stable key [P0-09].
class EnumKeyConverter<T extends KeyedEnum> extends TypeConverter<T, String> {
  const EnumKeyConverter(this.values);

  final List<T> values;

  @override
  T fromSql(String fromDb) => enumFromKey(values, fromDb);

  @override
  String toSql(T value) => value.key;
}

/// Stores a list of [KeyedEnum] values as a JSON array of keys.
class EnumKeyListConverter<T extends KeyedEnum>
    extends TypeConverter<List<T>, String> {
  const EnumKeyListConverter(this.values);

  final List<T> values;

  @override
  List<T> fromSql(String fromDb) => [
    for (final key in (jsonDecode(fromDb) as List<Object?>).cast<String>())
      enumFromKey(values, key),
  ];

  @override
  String toSql(List<T> value) => jsonEncode([for (final v in value) v.key]);
}

/// Stores a list of strings as a JSON array.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List<Object?>).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// Stores a JSON object.
class JsonMapConverter extends TypeConverter<Map<String, Object?>, String> {
  const JsonMapConverter();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as Map<String, Object?>);

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

/// Stores a calendar date as `YYYY-MM-DD`, read back as UTC midnight.
///
/// Conference dates are calendar days, not instants, so they must not shift
/// when shown in another timezone.
class CalendarDateConverter extends TypeConverter<DateTime, String> {
  const CalendarDateConverter();

  @override
  DateTime fromSql(String fromDb) {
    final parts = fromDb.split('-').map(int.parse).toList();
    return DateTime.utc(parts[0], parts[1], parts[2]);
  }

  @override
  String toSql(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}';
  }
}
