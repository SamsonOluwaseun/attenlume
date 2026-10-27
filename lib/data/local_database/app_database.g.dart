// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AppSetting({
    required this.key,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({
    String? key,
    String? value,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AppSetting(
    key: key ?? this.key,
    value: value ?? this.value,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConferencesTable extends Conferences
    with TableInfo<$ConferencesTable, Conference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _venueMeta = const VerificationMeta('venue');
  @override
  late final GeneratedColumn<String> venue = GeneratedColumn<String>(
    'venue',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> startDate =
      GeneratedColumn<String>(
        'start_date',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ConferencesTable.$converterstartDaten);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> endDate =
      GeneratedColumn<String>(
        'end_date',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($ConferencesTable.$converterendDaten);
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<RoleType?, String> roleType =
      GeneratedColumn<String>(
        'role_type',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<RoleType?>($ConferencesTable.$converterroleTypen);
  static const VerificationMeta _roleTextMeta = const VerificationMeta(
    'roleText',
  );
  @override
  late final GeneratedColumn<String> roleText = GeneratedColumn<String>(
    'role_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<RequestedOutput>, String>
  requestedOutputs =
      GeneratedColumn<String>(
        'requested_outputs',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<RequestedOutput>>(
        $ConferencesTable.$converterrequestedOutputs,
      );
  @override
  late final GeneratedColumnWithTypeConverter<RecordingProfile, String>
  defaultRecordingProfile =
      GeneratedColumn<String>(
        'default_recording_profile',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RecordingProfile>(
        $ConferencesTable.$converterdefaultRecordingProfile,
      );
  static const VerificationMeta _policyAcknowledgedAtMeta =
      const VerificationMeta('policyAcknowledgedAt');
  @override
  late final GeneratedColumn<DateTime> policyAcknowledgedAt =
      GeneratedColumn<DateTime>(
        'policy_acknowledged_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    name,
    description,
    venue,
    startDate,
    endDate,
    timezone,
    roleType,
    roleText,
    requestedOutputs,
    defaultRecordingProfile,
    policyAcknowledgedAt,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('venue')) {
      context.handle(
        _venueMeta,
        venue.isAcceptableOrUnknown(data['venue']!, _venueMeta),
      );
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    } else if (isInserting) {
      context.missing(_timezoneMeta);
    }
    if (data.containsKey('role_text')) {
      context.handle(
        _roleTextMeta,
        roleText.isAcceptableOrUnknown(data['role_text']!, _roleTextMeta),
      );
    }
    if (data.containsKey('policy_acknowledged_at')) {
      context.handle(
        _policyAcknowledgedAtMeta,
        policyAcknowledgedAt.isAcceptableOrUnknown(
          data['policy_acknowledged_at']!,
          _policyAcknowledgedAtMeta,
        ),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      venue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}venue'],
      ),
      startDate: $ConferencesTable.$converterstartDaten.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}start_date'],
        ),
      ),
      endDate: $ConferencesTable.$converterendDaten.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}end_date'],
        ),
      ),
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      roleType: $ConferencesTable.$converterroleTypen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}role_type'],
        ),
      ),
      roleText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role_text'],
      ),
      requestedOutputs: $ConferencesTable.$converterrequestedOutputs.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}requested_outputs'],
        )!,
      ),
      defaultRecordingProfile: $ConferencesTable
          .$converterdefaultRecordingProfile
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}default_recording_profile'],
            )!,
          ),
      policyAcknowledgedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}policy_acknowledged_at'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConferencesTable createAlias(String alias) {
    return $ConferencesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $converterstartDate =
      const CalendarDateConverter();
  static TypeConverter<DateTime?, String?> $converterstartDaten =
      NullAwareTypeConverter.wrap($converterstartDate);
  static TypeConverter<DateTime, String> $converterendDate =
      const CalendarDateConverter();
  static TypeConverter<DateTime?, String?> $converterendDaten =
      NullAwareTypeConverter.wrap($converterendDate);
  static TypeConverter<RoleType, String> $converterroleType =
      const EnumKeyConverter(RoleType.values);
  static TypeConverter<RoleType?, String?> $converterroleTypen =
      NullAwareTypeConverter.wrap($converterroleType);
  static TypeConverter<List<RequestedOutput>, String>
  $converterrequestedOutputs = const EnumKeyListConverter(
    RequestedOutput.values,
  );
  static TypeConverter<RecordingProfile, String>
  $converterdefaultRecordingProfile = const EnumKeyConverter(
    RecordingProfile.values,
  );
}

class ConferencesCompanion extends UpdateCompanion<Conference> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> venue;
  final Value<DateTime?> startDate;
  final Value<DateTime?> endDate;
  final Value<String> timezone;
  final Value<RoleType?> roleType;
  final Value<String?> roleText;
  final Value<List<RequestedOutput>> requestedOutputs;
  final Value<RecordingProfile> defaultRecordingProfile;
  final Value<DateTime?> policyAcknowledgedAt;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const ConferencesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.venue = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.timezone = const Value.absent(),
    this.roleType = const Value.absent(),
    this.roleText = const Value.absent(),
    this.requestedOutputs = const Value.absent(),
    this.defaultRecordingProfile = const Value.absent(),
    this.policyAcknowledgedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConferencesCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.venue = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    required String timezone,
    this.roleType = const Value.absent(),
    this.roleText = const Value.absent(),
    required List<RequestedOutput> requestedOutputs,
    required RecordingProfile defaultRecordingProfile,
    this.policyAcknowledgedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       name = Value(name),
       timezone = Value(timezone),
       requestedOutputs = Value(requestedOutputs),
       defaultRecordingProfile = Value(defaultRecordingProfile);
  static Insertable<Conference> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? venue,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<String>? timezone,
    Expression<String>? roleType,
    Expression<String>? roleText,
    Expression<String>? requestedOutputs,
    Expression<String>? defaultRecordingProfile,
    Expression<DateTime>? policyAcknowledgedAt,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (venue != null) 'venue': venue,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (timezone != null) 'timezone': timezone,
      if (roleType != null) 'role_type': roleType,
      if (roleText != null) 'role_text': roleText,
      if (requestedOutputs != null) 'requested_outputs': requestedOutputs,
      if (defaultRecordingProfile != null)
        'default_recording_profile': defaultRecordingProfile,
      if (policyAcknowledgedAt != null)
        'policy_acknowledged_at': policyAcknowledgedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConferencesCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? venue,
    Value<DateTime?>? startDate,
    Value<DateTime?>? endDate,
    Value<String>? timezone,
    Value<RoleType?>? roleType,
    Value<String?>? roleText,
    Value<List<RequestedOutput>>? requestedOutputs,
    Value<RecordingProfile>? defaultRecordingProfile,
    Value<DateTime?>? policyAcknowledgedAt,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return ConferencesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      venue: venue ?? this.venue,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      timezone: timezone ?? this.timezone,
      roleType: roleType ?? this.roleType,
      roleText: roleText ?? this.roleText,
      requestedOutputs: requestedOutputs ?? this.requestedOutputs,
      defaultRecordingProfile:
          defaultRecordingProfile ?? this.defaultRecordingProfile,
      policyAcknowledgedAt: policyAcknowledgedAt ?? this.policyAcknowledgedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (venue.present) {
      map['venue'] = Variable<String>(venue.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(
        $ConferencesTable.$converterstartDaten.toSql(startDate.value),
      );
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(
        $ConferencesTable.$converterendDaten.toSql(endDate.value),
      );
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (roleType.present) {
      map['role_type'] = Variable<String>(
        $ConferencesTable.$converterroleTypen.toSql(roleType.value),
      );
    }
    if (roleText.present) {
      map['role_text'] = Variable<String>(roleText.value);
    }
    if (requestedOutputs.present) {
      map['requested_outputs'] = Variable<String>(
        $ConferencesTable.$converterrequestedOutputs.toSql(
          requestedOutputs.value,
        ),
      );
    }
    if (defaultRecordingProfile.present) {
      map['default_recording_profile'] = Variable<String>(
        $ConferencesTable.$converterdefaultRecordingProfile.toSql(
          defaultRecordingProfile.value,
        ),
      );
    }
    if (policyAcknowledgedAt.present) {
      map['policy_acknowledged_at'] = Variable<DateTime>(
        policyAcknowledgedAt.value,
      );
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConferencesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('venue: $venue, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('timezone: $timezone, ')
          ..write('roleType: $roleType, ')
          ..write('roleText: $roleText, ')
          ..write('requestedOutputs: $requestedOutputs, ')
          ..write('defaultRecordingProfile: $defaultRecordingProfile, ')
          ..write('policyAcknowledgedAt: $policyAcknowledgedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoalsTable extends Goals with TableInfo<$GoalsTable, Goal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conferenceIdMeta = const VerificationMeta(
    'conferenceId',
  );
  @override
  late final GeneratedColumn<String> conferenceId = GeneratedColumn<String>(
    'conference_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conferences (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _goalTextMeta = const VerificationMeta(
    'goalText',
  );
  @override
  late final GeneratedColumn<String> goalText = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    conferenceId,
    goalText,
    priority,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<Goal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conference_id')) {
      context.handle(
        _conferenceIdMeta,
        conferenceId.isAcceptableOrUnknown(
          data['conference_id']!,
          _conferenceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conferenceIdMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _goalTextMeta,
        goalText.isAcceptableOrUnknown(data['text']!, _goalTextMeta),
      );
    } else if (isInserting) {
      context.missing(_goalTextMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Goal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Goal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conferenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conference_id'],
      )!,
      goalText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $GoalsTable createAlias(String alias) {
    return $GoalsTable(attachedDatabase, alias);
  }
}

class GoalsCompanion extends UpdateCompanion<Goal> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> conferenceId;
  final Value<String> goalText;
  final Value<int?> priority;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const GoalsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.conferenceId = const Value.absent(),
    this.goalText = const Value.absent(),
    this.priority = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoalsCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String conferenceId,
    required String goalText,
    this.priority = const Value.absent(),
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       conferenceId = Value(conferenceId),
       goalText = Value(goalText),
       sortOrder = Value(sortOrder);
  static Insertable<Goal> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? conferenceId,
    Expression<String>? goalText,
    Expression<int>? priority,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (conferenceId != null) 'conference_id': conferenceId,
      if (goalText != null) 'text': goalText,
      if (priority != null) 'priority': priority,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoalsCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? conferenceId,
    Value<String>? goalText,
    Value<int?>? priority,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return GoalsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      conferenceId: conferenceId ?? this.conferenceId,
      goalText: goalText ?? this.goalText,
      priority: priority ?? this.priority,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conferenceId.present) {
      map['conference_id'] = Variable<String>(conferenceId.value);
    }
    if (goalText.present) {
      map['text'] = Variable<String>(goalText.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('conferenceId: $conferenceId, ')
          ..write('goalText: $goalText, ')
          ..write('priority: $priority, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityTypesTable extends ActivityTypes
    with TableInfo<$ActivityTypesTable, ActivityType> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityTypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isBuiltinMeta = const VerificationMeta(
    'isBuiltin',
  );
  @override
  late final GeneratedColumn<bool> isBuiltin = GeneratedColumn<bool>(
    'is_builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_builtin" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    key,
    label,
    icon,
    isBuiltin,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_types';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityType> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('is_builtin')) {
      context.handle(
        _isBuiltinMeta,
        isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta),
      );
    } else if (isInserting) {
      context.missing(_isBuiltinMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActivityType map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityType(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      isBuiltin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_builtin'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ActivityTypesTable createAlias(String alias) {
    return $ActivityTypesTable(attachedDatabase, alias);
  }
}

class ActivityTypesCompanion extends UpdateCompanion<ActivityType> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> key;
  final Value<String> label;
  final Value<String> icon;
  final Value<bool> isBuiltin;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const ActivityTypesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.label = const Value.absent(),
    this.icon = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityTypesCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String key,
    required String label,
    required String icon,
    required bool isBuiltin,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       key = Value(key),
       label = Value(label),
       icon = Value(icon),
       isBuiltin = Value(isBuiltin),
       sortOrder = Value(sortOrder);
  static Insertable<ActivityType> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? key,
    Expression<String>? label,
    Expression<String>? icon,
    Expression<bool>? isBuiltin,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (label != null) 'label': label,
      if (icon != null) 'icon': icon,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityTypesCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? key,
    Value<String>? label,
    Value<String>? icon,
    Value<bool>? isBuiltin,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return ActivityTypesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      key: key ?? this.key,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<bool>(isBuiltin.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityTypesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('label: $label, ')
          ..write('icon: $icon, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivitiesTable extends Activities
    with TableInfo<$ActivitiesTable, Activity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conferenceIdMeta = const VerificationMeta(
    'conferenceId',
  );
  @override
  late final GeneratedColumn<String> conferenceId = GeneratedColumn<String>(
    'conference_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conferences (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeIdMeta = const VerificationMeta('typeId');
  @override
  late final GeneratedColumn<String> typeId = GeneratedColumn<String>(
    'type_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activity_types (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  speakerNames = GeneratedColumn<String>(
    'speaker_names',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<List<String>>($ActivitiesTable.$converterspeakerNames);
  static const VerificationMeta _organisationMeta = const VerificationMeta(
    'organisation',
  );
  @override
  late final GeneratedColumn<String> organisation = GeneratedColumn<String>(
    'organisation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<String> room = GeneratedColumn<String>(
    'room',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMdMeta = const VerificationMeta(
    'notesMd',
  );
  @override
  late final GeneratedColumn<String> notesMd = GeneratedColumn<String>(
    'notes_md',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> tags =
      GeneratedColumn<String>(
        'tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<String>>($ActivitiesTable.$convertertags);
  static const VerificationMeta _plannedStartMeta = const VerificationMeta(
    'plannedStart',
  );
  @override
  late final GeneratedColumn<DateTime> plannedStart = GeneratedColumn<DateTime>(
    'planned_start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualStartMeta = const VerificationMeta(
    'actualStart',
  );
  @override
  late final GeneratedColumn<DateTime> actualStart = GeneratedColumn<DateTime>(
    'actual_start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualEndMeta = const VerificationMeta(
    'actualEnd',
  );
  @override
  late final GeneratedColumn<DateTime> actualEnd = GeneratedColumn<DateTime>(
    'actual_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ActivityStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ActivityStatus>($ActivitiesTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<RecordingPermissionStatus, String>
  recordingPermissionStatus =
      GeneratedColumn<String>(
        'recording_permission_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RecordingPermissionStatus>(
        $ActivitiesTable.$converterrecordingPermissionStatus,
      );
  @override
  late final GeneratedColumnWithTypeConverter<RecordingProfile?, String>
  recordingProfileOverride =
      GeneratedColumn<String>(
        'recording_profile_override',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<RecordingProfile?>(
        $ActivitiesTable.$converterrecordingProfileOverriden,
      );
  static const VerificationMeta _isPrivateMeta = const VerificationMeta(
    'isPrivate',
  );
  @override
  late final GeneratedColumn<bool> isPrivate = GeneratedColumn<bool>(
    'is_private',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_private" IN (0, 1))',
    ),
  );
  static const VerificationMeta _contactNameMeta = const VerificationMeta(
    'contactName',
  );
  @override
  late final GeneratedColumn<String> contactName = GeneratedColumn<String>(
    'contact_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contactDetailsMeta = const VerificationMeta(
    'contactDetails',
  );
  @override
  late final GeneratedColumn<String> contactDetails = GeneratedColumn<String>(
    'contact_details',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _followUpTextMeta = const VerificationMeta(
    'followUpText',
  );
  @override
  late final GeneratedColumn<String> followUpText = GeneratedColumn<String>(
    'follow_up_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    conferenceId,
    typeId,
    title,
    speakerNames,
    organisation,
    room,
    notesMd,
    tags,
    plannedStart,
    actualStart,
    actualEnd,
    status,
    recordingPermissionStatus,
    recordingProfileOverride,
    isPrivate,
    contactName,
    contactDetails,
    followUpText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<Activity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conference_id')) {
      context.handle(
        _conferenceIdMeta,
        conferenceId.isAcceptableOrUnknown(
          data['conference_id']!,
          _conferenceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conferenceIdMeta);
    }
    if (data.containsKey('type_id')) {
      context.handle(
        _typeIdMeta,
        typeId.isAcceptableOrUnknown(data['type_id']!, _typeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_typeIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('organisation')) {
      context.handle(
        _organisationMeta,
        organisation.isAcceptableOrUnknown(
          data['organisation']!,
          _organisationMeta,
        ),
      );
    }
    if (data.containsKey('room')) {
      context.handle(
        _roomMeta,
        room.isAcceptableOrUnknown(data['room']!, _roomMeta),
      );
    }
    if (data.containsKey('notes_md')) {
      context.handle(
        _notesMdMeta,
        notesMd.isAcceptableOrUnknown(data['notes_md']!, _notesMdMeta),
      );
    }
    if (data.containsKey('planned_start')) {
      context.handle(
        _plannedStartMeta,
        plannedStart.isAcceptableOrUnknown(
          data['planned_start']!,
          _plannedStartMeta,
        ),
      );
    }
    if (data.containsKey('actual_start')) {
      context.handle(
        _actualStartMeta,
        actualStart.isAcceptableOrUnknown(
          data['actual_start']!,
          _actualStartMeta,
        ),
      );
    }
    if (data.containsKey('actual_end')) {
      context.handle(
        _actualEndMeta,
        actualEnd.isAcceptableOrUnknown(data['actual_end']!, _actualEndMeta),
      );
    }
    if (data.containsKey('is_private')) {
      context.handle(
        _isPrivateMeta,
        isPrivate.isAcceptableOrUnknown(data['is_private']!, _isPrivateMeta),
      );
    } else if (isInserting) {
      context.missing(_isPrivateMeta);
    }
    if (data.containsKey('contact_name')) {
      context.handle(
        _contactNameMeta,
        contactName.isAcceptableOrUnknown(
          data['contact_name']!,
          _contactNameMeta,
        ),
      );
    }
    if (data.containsKey('contact_details')) {
      context.handle(
        _contactDetailsMeta,
        contactDetails.isAcceptableOrUnknown(
          data['contact_details']!,
          _contactDetailsMeta,
        ),
      );
    }
    if (data.containsKey('follow_up_text')) {
      context.handle(
        _followUpTextMeta,
        followUpText.isAcceptableOrUnknown(
          data['follow_up_text']!,
          _followUpTextMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Activity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Activity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conferenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conference_id'],
      )!,
      typeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      speakerNames: $ActivitiesTable.$converterspeakerNames.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}speaker_names'],
        )!,
      ),
      organisation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organisation'],
      ),
      room: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room'],
      ),
      notesMd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes_md'],
      ),
      tags: $ActivitiesTable.$convertertags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tags'],
        )!,
      ),
      plannedStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}planned_start'],
      ),
      actualStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actual_start'],
      ),
      actualEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actual_end'],
      ),
      status: $ActivitiesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      recordingPermissionStatus: $ActivitiesTable
          .$converterrecordingPermissionStatus
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}recording_permission_status'],
            )!,
          ),
      recordingProfileOverride: $ActivitiesTable
          .$converterrecordingProfileOverriden
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}recording_profile_override'],
            ),
          ),
      isPrivate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_private'],
      )!,
      contactName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_name'],
      ),
      contactDetails: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_details'],
      ),
      followUpText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}follow_up_text'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ActivitiesTable createAlias(String alias) {
    return $ActivitiesTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterspeakerNames =
      const StringListConverter();
  static TypeConverter<List<String>, String> $convertertags =
      const StringListConverter();
  static TypeConverter<ActivityStatus, String> $converterstatus =
      const EnumKeyConverter(ActivityStatus.values);
  static TypeConverter<RecordingPermissionStatus, String>
  $converterrecordingPermissionStatus = const EnumKeyConverter(
    RecordingPermissionStatus.values,
  );
  static TypeConverter<RecordingProfile, String>
  $converterrecordingProfileOverride = const EnumKeyConverter(
    RecordingProfile.values,
  );
  static TypeConverter<RecordingProfile?, String?>
  $converterrecordingProfileOverriden = NullAwareTypeConverter.wrap(
    $converterrecordingProfileOverride,
  );
}

class ActivitiesCompanion extends UpdateCompanion<Activity> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> conferenceId;
  final Value<String> typeId;
  final Value<String> title;
  final Value<List<String>> speakerNames;
  final Value<String?> organisation;
  final Value<String?> room;
  final Value<String?> notesMd;
  final Value<List<String>> tags;
  final Value<DateTime?> plannedStart;
  final Value<DateTime?> actualStart;
  final Value<DateTime?> actualEnd;
  final Value<ActivityStatus> status;
  final Value<RecordingPermissionStatus> recordingPermissionStatus;
  final Value<RecordingProfile?> recordingProfileOverride;
  final Value<bool> isPrivate;
  final Value<String?> contactName;
  final Value<String?> contactDetails;
  final Value<String?> followUpText;
  final Value<int> rowid;
  const ActivitiesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.conferenceId = const Value.absent(),
    this.typeId = const Value.absent(),
    this.title = const Value.absent(),
    this.speakerNames = const Value.absent(),
    this.organisation = const Value.absent(),
    this.room = const Value.absent(),
    this.notesMd = const Value.absent(),
    this.tags = const Value.absent(),
    this.plannedStart = const Value.absent(),
    this.actualStart = const Value.absent(),
    this.actualEnd = const Value.absent(),
    this.status = const Value.absent(),
    this.recordingPermissionStatus = const Value.absent(),
    this.recordingProfileOverride = const Value.absent(),
    this.isPrivate = const Value.absent(),
    this.contactName = const Value.absent(),
    this.contactDetails = const Value.absent(),
    this.followUpText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivitiesCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String conferenceId,
    required String typeId,
    required String title,
    required List<String> speakerNames,
    this.organisation = const Value.absent(),
    this.room = const Value.absent(),
    this.notesMd = const Value.absent(),
    required List<String> tags,
    this.plannedStart = const Value.absent(),
    this.actualStart = const Value.absent(),
    this.actualEnd = const Value.absent(),
    required ActivityStatus status,
    required RecordingPermissionStatus recordingPermissionStatus,
    this.recordingProfileOverride = const Value.absent(),
    required bool isPrivate,
    this.contactName = const Value.absent(),
    this.contactDetails = const Value.absent(),
    this.followUpText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       conferenceId = Value(conferenceId),
       typeId = Value(typeId),
       title = Value(title),
       speakerNames = Value(speakerNames),
       tags = Value(tags),
       status = Value(status),
       recordingPermissionStatus = Value(recordingPermissionStatus),
       isPrivate = Value(isPrivate);
  static Insertable<Activity> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? conferenceId,
    Expression<String>? typeId,
    Expression<String>? title,
    Expression<String>? speakerNames,
    Expression<String>? organisation,
    Expression<String>? room,
    Expression<String>? notesMd,
    Expression<String>? tags,
    Expression<DateTime>? plannedStart,
    Expression<DateTime>? actualStart,
    Expression<DateTime>? actualEnd,
    Expression<String>? status,
    Expression<String>? recordingPermissionStatus,
    Expression<String>? recordingProfileOverride,
    Expression<bool>? isPrivate,
    Expression<String>? contactName,
    Expression<String>? contactDetails,
    Expression<String>? followUpText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (conferenceId != null) 'conference_id': conferenceId,
      if (typeId != null) 'type_id': typeId,
      if (title != null) 'title': title,
      if (speakerNames != null) 'speaker_names': speakerNames,
      if (organisation != null) 'organisation': organisation,
      if (room != null) 'room': room,
      if (notesMd != null) 'notes_md': notesMd,
      if (tags != null) 'tags': tags,
      if (plannedStart != null) 'planned_start': plannedStart,
      if (actualStart != null) 'actual_start': actualStart,
      if (actualEnd != null) 'actual_end': actualEnd,
      if (status != null) 'status': status,
      if (recordingPermissionStatus != null)
        'recording_permission_status': recordingPermissionStatus,
      if (recordingProfileOverride != null)
        'recording_profile_override': recordingProfileOverride,
      if (isPrivate != null) 'is_private': isPrivate,
      if (contactName != null) 'contact_name': contactName,
      if (contactDetails != null) 'contact_details': contactDetails,
      if (followUpText != null) 'follow_up_text': followUpText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivitiesCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? conferenceId,
    Value<String>? typeId,
    Value<String>? title,
    Value<List<String>>? speakerNames,
    Value<String?>? organisation,
    Value<String?>? room,
    Value<String?>? notesMd,
    Value<List<String>>? tags,
    Value<DateTime?>? plannedStart,
    Value<DateTime?>? actualStart,
    Value<DateTime?>? actualEnd,
    Value<ActivityStatus>? status,
    Value<RecordingPermissionStatus>? recordingPermissionStatus,
    Value<RecordingProfile?>? recordingProfileOverride,
    Value<bool>? isPrivate,
    Value<String?>? contactName,
    Value<String?>? contactDetails,
    Value<String?>? followUpText,
    Value<int>? rowid,
  }) {
    return ActivitiesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      conferenceId: conferenceId ?? this.conferenceId,
      typeId: typeId ?? this.typeId,
      title: title ?? this.title,
      speakerNames: speakerNames ?? this.speakerNames,
      organisation: organisation ?? this.organisation,
      room: room ?? this.room,
      notesMd: notesMd ?? this.notesMd,
      tags: tags ?? this.tags,
      plannedStart: plannedStart ?? this.plannedStart,
      actualStart: actualStart ?? this.actualStart,
      actualEnd: actualEnd ?? this.actualEnd,
      status: status ?? this.status,
      recordingPermissionStatus:
          recordingPermissionStatus ?? this.recordingPermissionStatus,
      recordingProfileOverride:
          recordingProfileOverride ?? this.recordingProfileOverride,
      isPrivate: isPrivate ?? this.isPrivate,
      contactName: contactName ?? this.contactName,
      contactDetails: contactDetails ?? this.contactDetails,
      followUpText: followUpText ?? this.followUpText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conferenceId.present) {
      map['conference_id'] = Variable<String>(conferenceId.value);
    }
    if (typeId.present) {
      map['type_id'] = Variable<String>(typeId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (speakerNames.present) {
      map['speaker_names'] = Variable<String>(
        $ActivitiesTable.$converterspeakerNames.toSql(speakerNames.value),
      );
    }
    if (organisation.present) {
      map['organisation'] = Variable<String>(organisation.value);
    }
    if (room.present) {
      map['room'] = Variable<String>(room.value);
    }
    if (notesMd.present) {
      map['notes_md'] = Variable<String>(notesMd.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(
        $ActivitiesTable.$convertertags.toSql(tags.value),
      );
    }
    if (plannedStart.present) {
      map['planned_start'] = Variable<DateTime>(plannedStart.value);
    }
    if (actualStart.present) {
      map['actual_start'] = Variable<DateTime>(actualStart.value);
    }
    if (actualEnd.present) {
      map['actual_end'] = Variable<DateTime>(actualEnd.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ActivitiesTable.$converterstatus.toSql(status.value),
      );
    }
    if (recordingPermissionStatus.present) {
      map['recording_permission_status'] = Variable<String>(
        $ActivitiesTable.$converterrecordingPermissionStatus.toSql(
          recordingPermissionStatus.value,
        ),
      );
    }
    if (recordingProfileOverride.present) {
      map['recording_profile_override'] = Variable<String>(
        $ActivitiesTable.$converterrecordingProfileOverriden.toSql(
          recordingProfileOverride.value,
        ),
      );
    }
    if (isPrivate.present) {
      map['is_private'] = Variable<bool>(isPrivate.value);
    }
    if (contactName.present) {
      map['contact_name'] = Variable<String>(contactName.value);
    }
    if (contactDetails.present) {
      map['contact_details'] = Variable<String>(contactDetails.value);
    }
    if (followUpText.present) {
      map['follow_up_text'] = Variable<String>(followUpText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivitiesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('conferenceId: $conferenceId, ')
          ..write('typeId: $typeId, ')
          ..write('title: $title, ')
          ..write('speakerNames: $speakerNames, ')
          ..write('organisation: $organisation, ')
          ..write('room: $room, ')
          ..write('notesMd: $notesMd, ')
          ..write('tags: $tags, ')
          ..write('plannedStart: $plannedStart, ')
          ..write('actualStart: $actualStart, ')
          ..write('actualEnd: $actualEnd, ')
          ..write('status: $status, ')
          ..write('recordingPermissionStatus: $recordingPermissionStatus, ')
          ..write('recordingProfileOverride: $recordingProfileOverride, ')
          ..write('isPrivate: $isPrivate, ')
          ..write('contactName: $contactName, ')
          ..write('contactDetails: $contactDetails, ')
          ..write('followUpText: $followUpText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecordingSegmentsTable extends RecordingSegments
    with TableInfo<$RecordingSegmentsTable, RecordingSegment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordingSegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SegmentState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SegmentState>($RecordingSegmentsTable.$converterstate);
  @override
  late final GeneratedColumnWithTypeConverter<RecordingProfile, String>
  requestedProfile =
      GeneratedColumn<String>(
        'requested_profile',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RecordingProfile>(
        $RecordingSegmentsTable.$converterrequestedProfile,
      );
  static const VerificationMeta _codecMeta = const VerificationMeta('codec');
  @override
  late final GeneratedColumn<String> codec = GeneratedColumn<String>(
    'codec',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _containerMeta = const VerificationMeta(
    'container',
  );
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
    'container',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelCountMeta = const VerificationMeta(
    'channelCount',
  );
  @override
  late final GeneratedColumn<int> channelCount = GeneratedColumn<int>(
    'channel_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sampleRateHzMeta = const VerificationMeta(
    'sampleRateHz',
  );
  @override
  late final GeneratedColumn<int> sampleRateHz = GeneratedColumn<int>(
    'sample_rate_hz',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestedBitrateBpsMeta =
      const VerificationMeta('requestedBitrateBps');
  @override
  late final GeneratedColumn<int> requestedBitrateBps = GeneratedColumn<int>(
    'requested_bitrate_bps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedBitrateBpsMeta =
      const VerificationMeta('observedBitrateBps');
  @override
  late final GeneratedColumn<int> observedBitrateBps = GeneratedColumn<int>(
    'observed_bitrate_bps',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inputRouteMeta = const VerificationMeta(
    'inputRoute',
  );
  @override
  late final GeneratedColumn<String> inputRoute = GeneratedColumn<String>(
    'input_route',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startUtcMeta = const VerificationMeta(
    'startUtc',
  );
  @override
  late final GeneratedColumn<DateTime> startUtc = GeneratedColumn<DateTime>(
    'start_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMeta = const VerificationMeta('endUtc');
  @override
  late final GeneratedColumn<DateTime> endUtc = GeneratedColumn<DateTime>(
    'end_utc',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SegmentEndReason?, String>
  endReason =
      GeneratedColumn<String>(
        'end_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<SegmentEndReason?>(
        $RecordingSegmentsTable.$converterendReasonn,
      );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    activityId,
    sequence,
    filePath,
    state,
    requestedProfile,
    codec,
    container,
    channelCount,
    sampleRateHz,
    requestedBitrateBps,
    observedBitrateBps,
    inputRoute,
    startUtc,
    endUtc,
    durationMs,
    bytes,
    sha256,
    endReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recording_segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordingSegment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('codec')) {
      context.handle(
        _codecMeta,
        codec.isAcceptableOrUnknown(data['codec']!, _codecMeta),
      );
    } else if (isInserting) {
      context.missing(_codecMeta);
    }
    if (data.containsKey('container')) {
      context.handle(
        _containerMeta,
        container.isAcceptableOrUnknown(data['container']!, _containerMeta),
      );
    } else if (isInserting) {
      context.missing(_containerMeta);
    }
    if (data.containsKey('channel_count')) {
      context.handle(
        _channelCountMeta,
        channelCount.isAcceptableOrUnknown(
          data['channel_count']!,
          _channelCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_channelCountMeta);
    }
    if (data.containsKey('sample_rate_hz')) {
      context.handle(
        _sampleRateHzMeta,
        sampleRateHz.isAcceptableOrUnknown(
          data['sample_rate_hz']!,
          _sampleRateHzMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sampleRateHzMeta);
    }
    if (data.containsKey('requested_bitrate_bps')) {
      context.handle(
        _requestedBitrateBpsMeta,
        requestedBitrateBps.isAcceptableOrUnknown(
          data['requested_bitrate_bps']!,
          _requestedBitrateBpsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestedBitrateBpsMeta);
    }
    if (data.containsKey('observed_bitrate_bps')) {
      context.handle(
        _observedBitrateBpsMeta,
        observedBitrateBps.isAcceptableOrUnknown(
          data['observed_bitrate_bps']!,
          _observedBitrateBpsMeta,
        ),
      );
    }
    if (data.containsKey('input_route')) {
      context.handle(
        _inputRouteMeta,
        inputRoute.isAcceptableOrUnknown(data['input_route']!, _inputRouteMeta),
      );
    }
    if (data.containsKey('start_utc')) {
      context.handle(
        _startUtcMeta,
        startUtc.isAcceptableOrUnknown(data['start_utc']!, _startUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_startUtcMeta);
    }
    if (data.containsKey('end_utc')) {
      context.handle(
        _endUtcMeta,
        endUtc.isAcceptableOrUnknown(data['end_utc']!, _endUtcMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {activityId, sequence},
  ];
  @override
  RecordingSegment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordingSegment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      state: $RecordingSegmentsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      requestedProfile: $RecordingSegmentsTable.$converterrequestedProfile
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}requested_profile'],
            )!,
          ),
      codec: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}codec'],
      )!,
      container: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container'],
      )!,
      channelCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}channel_count'],
      )!,
      sampleRateHz: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_rate_hz'],
      )!,
      requestedBitrateBps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}requested_bitrate_bps'],
      )!,
      observedBitrateBps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}observed_bitrate_bps'],
      ),
      inputRoute: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_route'],
      ),
      startUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_utc'],
      )!,
      endUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_utc'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      endReason: $RecordingSegmentsTable.$converterendReasonn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}end_reason'],
        ),
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RecordingSegmentsTable createAlias(String alias) {
    return $RecordingSegmentsTable(attachedDatabase, alias);
  }

  static TypeConverter<SegmentState, String> $converterstate =
      const EnumKeyConverter(SegmentState.values);
  static TypeConverter<RecordingProfile, String> $converterrequestedProfile =
      const EnumKeyConverter(RecordingProfile.values);
  static TypeConverter<SegmentEndReason, String> $converterendReason =
      const EnumKeyConverter(SegmentEndReason.values);
  static TypeConverter<SegmentEndReason?, String?> $converterendReasonn =
      NullAwareTypeConverter.wrap($converterendReason);
}

class RecordingSegmentsCompanion extends UpdateCompanion<RecordingSegment> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> activityId;
  final Value<int> sequence;
  final Value<String> filePath;
  final Value<SegmentState> state;
  final Value<RecordingProfile> requestedProfile;
  final Value<String> codec;
  final Value<String> container;
  final Value<int> channelCount;
  final Value<int> sampleRateHz;
  final Value<int> requestedBitrateBps;
  final Value<int?> observedBitrateBps;
  final Value<String?> inputRoute;
  final Value<DateTime> startUtc;
  final Value<DateTime?> endUtc;
  final Value<int?> durationMs;
  final Value<int?> bytes;
  final Value<String?> sha256;
  final Value<SegmentEndReason?> endReason;
  final Value<int> rowid;
  const RecordingSegmentsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.filePath = const Value.absent(),
    this.state = const Value.absent(),
    this.requestedProfile = const Value.absent(),
    this.codec = const Value.absent(),
    this.container = const Value.absent(),
    this.channelCount = const Value.absent(),
    this.sampleRateHz = const Value.absent(),
    this.requestedBitrateBps = const Value.absent(),
    this.observedBitrateBps = const Value.absent(),
    this.inputRoute = const Value.absent(),
    this.startUtc = const Value.absent(),
    this.endUtc = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.bytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.endReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordingSegmentsCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String activityId,
    required int sequence,
    required String filePath,
    required SegmentState state,
    required RecordingProfile requestedProfile,
    required String codec,
    required String container,
    required int channelCount,
    required int sampleRateHz,
    required int requestedBitrateBps,
    this.observedBitrateBps = const Value.absent(),
    this.inputRoute = const Value.absent(),
    required DateTime startUtc,
    this.endUtc = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.bytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.endReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       activityId = Value(activityId),
       sequence = Value(sequence),
       filePath = Value(filePath),
       state = Value(state),
       requestedProfile = Value(requestedProfile),
       codec = Value(codec),
       container = Value(container),
       channelCount = Value(channelCount),
       sampleRateHz = Value(sampleRateHz),
       requestedBitrateBps = Value(requestedBitrateBps),
       startUtc = Value(startUtc);
  static Insertable<RecordingSegment> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? activityId,
    Expression<int>? sequence,
    Expression<String>? filePath,
    Expression<String>? state,
    Expression<String>? requestedProfile,
    Expression<String>? codec,
    Expression<String>? container,
    Expression<int>? channelCount,
    Expression<int>? sampleRateHz,
    Expression<int>? requestedBitrateBps,
    Expression<int>? observedBitrateBps,
    Expression<String>? inputRoute,
    Expression<DateTime>? startUtc,
    Expression<DateTime>? endUtc,
    Expression<int>? durationMs,
    Expression<int>? bytes,
    Expression<String>? sha256,
    Expression<String>? endReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (sequence != null) 'sequence': sequence,
      if (filePath != null) 'file_path': filePath,
      if (state != null) 'state': state,
      if (requestedProfile != null) 'requested_profile': requestedProfile,
      if (codec != null) 'codec': codec,
      if (container != null) 'container': container,
      if (channelCount != null) 'channel_count': channelCount,
      if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
      if (requestedBitrateBps != null)
        'requested_bitrate_bps': requestedBitrateBps,
      if (observedBitrateBps != null)
        'observed_bitrate_bps': observedBitrateBps,
      if (inputRoute != null) 'input_route': inputRoute,
      if (startUtc != null) 'start_utc': startUtc,
      if (endUtc != null) 'end_utc': endUtc,
      if (durationMs != null) 'duration_ms': durationMs,
      if (bytes != null) 'bytes': bytes,
      if (sha256 != null) 'sha256': sha256,
      if (endReason != null) 'end_reason': endReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordingSegmentsCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? activityId,
    Value<int>? sequence,
    Value<String>? filePath,
    Value<SegmentState>? state,
    Value<RecordingProfile>? requestedProfile,
    Value<String>? codec,
    Value<String>? container,
    Value<int>? channelCount,
    Value<int>? sampleRateHz,
    Value<int>? requestedBitrateBps,
    Value<int?>? observedBitrateBps,
    Value<String?>? inputRoute,
    Value<DateTime>? startUtc,
    Value<DateTime?>? endUtc,
    Value<int?>? durationMs,
    Value<int?>? bytes,
    Value<String?>? sha256,
    Value<SegmentEndReason?>? endReason,
    Value<int>? rowid,
  }) {
    return RecordingSegmentsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      sequence: sequence ?? this.sequence,
      filePath: filePath ?? this.filePath,
      state: state ?? this.state,
      requestedProfile: requestedProfile ?? this.requestedProfile,
      codec: codec ?? this.codec,
      container: container ?? this.container,
      channelCount: channelCount ?? this.channelCount,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      requestedBitrateBps: requestedBitrateBps ?? this.requestedBitrateBps,
      observedBitrateBps: observedBitrateBps ?? this.observedBitrateBps,
      inputRoute: inputRoute ?? this.inputRoute,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      durationMs: durationMs ?? this.durationMs,
      bytes: bytes ?? this.bytes,
      sha256: sha256 ?? this.sha256,
      endReason: endReason ?? this.endReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $RecordingSegmentsTable.$converterstate.toSql(state.value),
      );
    }
    if (requestedProfile.present) {
      map['requested_profile'] = Variable<String>(
        $RecordingSegmentsTable.$converterrequestedProfile.toSql(
          requestedProfile.value,
        ),
      );
    }
    if (codec.present) {
      map['codec'] = Variable<String>(codec.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (channelCount.present) {
      map['channel_count'] = Variable<int>(channelCount.value);
    }
    if (sampleRateHz.present) {
      map['sample_rate_hz'] = Variable<int>(sampleRateHz.value);
    }
    if (requestedBitrateBps.present) {
      map['requested_bitrate_bps'] = Variable<int>(requestedBitrateBps.value);
    }
    if (observedBitrateBps.present) {
      map['observed_bitrate_bps'] = Variable<int>(observedBitrateBps.value);
    }
    if (inputRoute.present) {
      map['input_route'] = Variable<String>(inputRoute.value);
    }
    if (startUtc.present) {
      map['start_utc'] = Variable<DateTime>(startUtc.value);
    }
    if (endUtc.present) {
      map['end_utc'] = Variable<DateTime>(endUtc.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(
        $RecordingSegmentsTable.$converterendReasonn.toSql(endReason.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordingSegmentsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('sequence: $sequence, ')
          ..write('filePath: $filePath, ')
          ..write('state: $state, ')
          ..write('requestedProfile: $requestedProfile, ')
          ..write('codec: $codec, ')
          ..write('container: $container, ')
          ..write('channelCount: $channelCount, ')
          ..write('sampleRateHz: $sampleRateHz, ')
          ..write('requestedBitrateBps: $requestedBitrateBps, ')
          ..write('observedBitrateBps: $observedBitrateBps, ')
          ..write('inputRoute: $inputRoute, ')
          ..write('startUtc: $startUtc, ')
          ..write('endUtc: $endUtc, ')
          ..write('durationMs: $durationMs, ')
          ..write('bytes: $bytes, ')
          ..write('sha256: $sha256, ')
          ..write('endReason: $endReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InterruptionsTable extends Interruptions
    with TableInfo<$InterruptionsTable, Interruption> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InterruptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<InterruptionReason, String>
  reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<InterruptionReason>($InterruptionsTable.$converterreason);
  static const VerificationMeta _startUtcMeta = const VerificationMeta(
    'startUtc',
  );
  @override
  late final GeneratedColumn<DateTime> startUtc = GeneratedColumn<DateTime>(
    'start_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMeta = const VerificationMeta('endUtc');
  @override
  late final GeneratedColumn<DateTime> endUtc = GeneratedColumn<DateTime>(
    'end_utc',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoResumedMeta = const VerificationMeta(
    'autoResumed',
  );
  @override
  late final GeneratedColumn<bool> autoResumed = GeneratedColumn<bool>(
    'auto_resumed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_resumed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    activityId,
    reason,
    startUtc,
    endUtc,
    autoResumed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'interruptions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Interruption> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('start_utc')) {
      context.handle(
        _startUtcMeta,
        startUtc.isAcceptableOrUnknown(data['start_utc']!, _startUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_startUtcMeta);
    }
    if (data.containsKey('end_utc')) {
      context.handle(
        _endUtcMeta,
        endUtc.isAcceptableOrUnknown(data['end_utc']!, _endUtcMeta),
      );
    }
    if (data.containsKey('auto_resumed')) {
      context.handle(
        _autoResumedMeta,
        autoResumed.isAcceptableOrUnknown(
          data['auto_resumed']!,
          _autoResumedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_autoResumedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Interruption map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Interruption(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
      reason: $InterruptionsTable.$converterreason.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}reason'],
        )!,
      ),
      startUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_utc'],
      )!,
      endUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_utc'],
      ),
      autoResumed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_resumed'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InterruptionsTable createAlias(String alias) {
    return $InterruptionsTable(attachedDatabase, alias);
  }

  static TypeConverter<InterruptionReason, String> $converterreason =
      const EnumKeyConverter(InterruptionReason.values);
}

class InterruptionsCompanion extends UpdateCompanion<Interruption> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> activityId;
  final Value<InterruptionReason> reason;
  final Value<DateTime> startUtc;
  final Value<DateTime?> endUtc;
  final Value<bool> autoResumed;
  final Value<int> rowid;
  const InterruptionsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.reason = const Value.absent(),
    this.startUtc = const Value.absent(),
    this.endUtc = const Value.absent(),
    this.autoResumed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InterruptionsCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String activityId,
    required InterruptionReason reason,
    required DateTime startUtc,
    this.endUtc = const Value.absent(),
    required bool autoResumed,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       activityId = Value(activityId),
       reason = Value(reason),
       startUtc = Value(startUtc),
       autoResumed = Value(autoResumed);
  static Insertable<Interruption> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? activityId,
    Expression<String>? reason,
    Expression<DateTime>? startUtc,
    Expression<DateTime>? endUtc,
    Expression<bool>? autoResumed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (reason != null) 'reason': reason,
      if (startUtc != null) 'start_utc': startUtc,
      if (endUtc != null) 'end_utc': endUtc,
      if (autoResumed != null) 'auto_resumed': autoResumed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InterruptionsCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? activityId,
    Value<InterruptionReason>? reason,
    Value<DateTime>? startUtc,
    Value<DateTime?>? endUtc,
    Value<bool>? autoResumed,
    Value<int>? rowid,
  }) {
    return InterruptionsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      reason: reason ?? this.reason,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      autoResumed: autoResumed ?? this.autoResumed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(
        $InterruptionsTable.$converterreason.toSql(reason.value),
      );
    }
    if (startUtc.present) {
      map['start_utc'] = Variable<DateTime>(startUtc.value);
    }
    if (endUtc.present) {
      map['end_utc'] = Variable<DateTime>(endUtc.value);
    }
    if (autoResumed.present) {
      map['auto_resumed'] = Variable<bool>(autoResumed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InterruptionsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('reason: $reason, ')
          ..write('startUtc: $startUtc, ')
          ..write('endUtc: $endUtc, ')
          ..write('autoResumed: $autoResumed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhotosTable extends Photos with TableInfo<$PhotosTable, Photo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenUtcMeta = const VerificationMeta(
    'takenUtc',
  );
  @override
  late final GeneratedColumn<DateTime> takenUtc = GeneratedColumn<DateTime>(
    'taken_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMsMeta = const VerificationMeta(
    'offsetMs',
  );
  @override
  late final GeneratedColumn<int> offsetMs = GeneratedColumn<int>(
    'offset_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PhotoSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PhotoSource>($PhotosTable.$convertersource);
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalKeptMeta = const VerificationMeta(
    'originalKept',
  );
  @override
  late final GeneratedColumn<bool> originalKept = GeneratedColumn<bool>(
    'original_kept',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("original_kept" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    activityId,
    filePath,
    thumbnailPath,
    takenUtc,
    offsetMs,
    caption,
    label,
    source,
    width,
    height,
    bytes,
    sha256,
    originalKept,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Photo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('taken_utc')) {
      context.handle(
        _takenUtcMeta,
        takenUtc.isAcceptableOrUnknown(data['taken_utc']!, _takenUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_takenUtcMeta);
    }
    if (data.containsKey('offset_ms')) {
      context.handle(
        _offsetMsMeta,
        offsetMs.isAcceptableOrUnknown(data['offset_ms']!, _offsetMsMeta),
      );
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('original_kept')) {
      context.handle(
        _originalKeptMeta,
        originalKept.isAcceptableOrUnknown(
          data['original_kept']!,
          _originalKeptMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalKeptMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Photo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Photo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      takenUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}taken_utc'],
      )!,
      offsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_ms'],
      ),
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      ),
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      source: $PhotosTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      originalKept: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}original_kept'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PhotosTable createAlias(String alias) {
    return $PhotosTable(attachedDatabase, alias);
  }

  static TypeConverter<PhotoSource, String> $convertersource =
      const EnumKeyConverter(PhotoSource.values);
}

class PhotosCompanion extends UpdateCompanion<Photo> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> activityId;
  final Value<String> filePath;
  final Value<String?> thumbnailPath;
  final Value<DateTime> takenUtc;
  final Value<int?> offsetMs;
  final Value<String?> caption;
  final Value<String?> label;
  final Value<PhotoSource> source;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> bytes;
  final Value<String?> sha256;
  final Value<bool> originalKept;
  final Value<int> rowid;
  const PhotosCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.takenUtc = const Value.absent(),
    this.offsetMs = const Value.absent(),
    this.caption = const Value.absent(),
    this.label = const Value.absent(),
    this.source = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.bytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.originalKept = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotosCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String activityId,
    required String filePath,
    this.thumbnailPath = const Value.absent(),
    required DateTime takenUtc,
    this.offsetMs = const Value.absent(),
    this.caption = const Value.absent(),
    this.label = const Value.absent(),
    required PhotoSource source,
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.bytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    required bool originalKept,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       activityId = Value(activityId),
       filePath = Value(filePath),
       takenUtc = Value(takenUtc),
       source = Value(source),
       originalKept = Value(originalKept);
  static Insertable<Photo> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? activityId,
    Expression<String>? filePath,
    Expression<String>? thumbnailPath,
    Expression<DateTime>? takenUtc,
    Expression<int>? offsetMs,
    Expression<String>? caption,
    Expression<String>? label,
    Expression<String>? source,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? bytes,
    Expression<String>? sha256,
    Expression<bool>? originalKept,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (filePath != null) 'file_path': filePath,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (takenUtc != null) 'taken_utc': takenUtc,
      if (offsetMs != null) 'offset_ms': offsetMs,
      if (caption != null) 'caption': caption,
      if (label != null) 'label': label,
      if (source != null) 'source': source,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (bytes != null) 'bytes': bytes,
      if (sha256 != null) 'sha256': sha256,
      if (originalKept != null) 'original_kept': originalKept,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotosCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? activityId,
    Value<String>? filePath,
    Value<String?>? thumbnailPath,
    Value<DateTime>? takenUtc,
    Value<int?>? offsetMs,
    Value<String?>? caption,
    Value<String?>? label,
    Value<PhotoSource>? source,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? bytes,
    Value<String?>? sha256,
    Value<bool>? originalKept,
    Value<int>? rowid,
  }) {
    return PhotosCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      takenUtc: takenUtc ?? this.takenUtc,
      offsetMs: offsetMs ?? this.offsetMs,
      caption: caption ?? this.caption,
      label: label ?? this.label,
      source: source ?? this.source,
      width: width ?? this.width,
      height: height ?? this.height,
      bytes: bytes ?? this.bytes,
      sha256: sha256 ?? this.sha256,
      originalKept: originalKept ?? this.originalKept,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (takenUtc.present) {
      map['taken_utc'] = Variable<DateTime>(takenUtc.value);
    }
    if (offsetMs.present) {
      map['offset_ms'] = Variable<int>(offsetMs.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $PhotosTable.$convertersource.toSql(source.value),
      );
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (originalKept.present) {
      map['original_kept'] = Variable<bool>(originalKept.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotosCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('filePath: $filePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('takenUtc: $takenUtc, ')
          ..write('offsetMs: $offsetMs, ')
          ..write('caption: $caption, ')
          ..write('label: $label, ')
          ..write('source: $source, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('bytes: $bytes, ')
          ..write('sha256: $sha256, ')
          ..write('originalKept: $originalKept, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _atUtcMeta = const VerificationMeta('atUtc');
  @override
  late final GeneratedColumn<DateTime> atUtc = GeneratedColumn<DateTime>(
    'at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMsMeta = const VerificationMeta(
    'offsetMs',
  );
  @override
  late final GeneratedColumn<int> offsetMs = GeneratedColumn<int>(
    'offset_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BookmarkSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<BookmarkSource>($BookmarksTable.$convertersource);
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    activityId,
    atUtc,
    offsetMs,
    label,
    note,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bookmark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('at_utc')) {
      context.handle(
        _atUtcMeta,
        atUtc.isAcceptableOrUnknown(data['at_utc']!, _atUtcMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMeta);
    }
    if (data.containsKey('offset_ms')) {
      context.handle(
        _offsetMsMeta,
        offsetMs.isAcceptableOrUnknown(data['offset_ms']!, _offsetMsMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
      atUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at_utc'],
      )!,
      offsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_ms'],
      ),
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      source: $BookmarksTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }

  static TypeConverter<BookmarkSource, String> $convertersource =
      const EnumKeyConverter(BookmarkSource.values);
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> activityId;
  final Value<DateTime> atUtc;
  final Value<int?> offsetMs;
  final Value<String?> label;
  final Value<String?> note;
  final Value<BookmarkSource> source;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.atUtc = const Value.absent(),
    this.offsetMs = const Value.absent(),
    this.label = const Value.absent(),
    this.note = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String activityId,
    required DateTime atUtc,
    this.offsetMs = const Value.absent(),
    this.label = const Value.absent(),
    this.note = const Value.absent(),
    required BookmarkSource source,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       activityId = Value(activityId),
       atUtc = Value(atUtc),
       source = Value(source);
  static Insertable<Bookmark> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? activityId,
    Expression<DateTime>? atUtc,
    Expression<int>? offsetMs,
    Expression<String>? label,
    Expression<String>? note,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (atUtc != null) 'at_utc': atUtc,
      if (offsetMs != null) 'offset_ms': offsetMs,
      if (label != null) 'label': label,
      if (note != null) 'note': note,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? activityId,
    Value<DateTime>? atUtc,
    Value<int?>? offsetMs,
    Value<String?>? label,
    Value<String?>? note,
    Value<BookmarkSource>? source,
    Value<int>? rowid,
  }) {
    return BookmarksCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      atUtc: atUtc ?? this.atUtc,
      offsetMs: offsetMs ?? this.offsetMs,
      label: label ?? this.label,
      note: note ?? this.note,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (atUtc.present) {
      map['at_utc'] = Variable<DateTime>(atUtc.value);
    }
    if (offsetMs.present) {
      map['offset_ms'] = Variable<int>(offsetMs.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $BookmarksTable.$convertersource.toSql(source.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('atUtc: $atUtc, ')
          ..write('offsetMs: $offsetMs, ')
          ..write('label: $label, ')
          ..write('note: $note, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CutRangesTable extends CutRanges
    with TableInfo<$CutRangesTable, CutRange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CutRangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _startOffsetMsMeta = const VerificationMeta(
    'startOffsetMs',
  );
  @override
  late final GeneratedColumn<int> startOffsetMs = GeneratedColumn<int>(
    'start_offset_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endOffsetMsMeta = const VerificationMeta(
    'endOffsetMs',
  );
  @override
  late final GeneratedColumn<int> endOffsetMs = GeneratedColumn<int>(
    'end_offset_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    activityId,
    startOffsetMs,
    endOffsetMs,
    reason,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cut_ranges';
  @override
  VerificationContext validateIntegrity(
    Insertable<CutRange> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('start_offset_ms')) {
      context.handle(
        _startOffsetMsMeta,
        startOffsetMs.isAcceptableOrUnknown(
          data['start_offset_ms']!,
          _startOffsetMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startOffsetMsMeta);
    }
    if (data.containsKey('end_offset_ms')) {
      context.handle(
        _endOffsetMsMeta,
        endOffsetMs.isAcceptableOrUnknown(
          data['end_offset_ms']!,
          _endOffsetMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endOffsetMsMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CutRange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CutRange(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
      startOffsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_offset_ms'],
      )!,
      endOffsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_offset_ms'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CutRangesTable createAlias(String alias) {
    return $CutRangesTable(attachedDatabase, alias);
  }
}

class CutRangesCompanion extends UpdateCompanion<CutRange> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> activityId;
  final Value<int> startOffsetMs;
  final Value<int> endOffsetMs;
  final Value<String?> reason;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const CutRangesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.startOffsetMs = const Value.absent(),
    this.endOffsetMs = const Value.absent(),
    this.reason = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CutRangesCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String activityId,
    required int startOffsetMs,
    required int endOffsetMs,
    this.reason = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       activityId = Value(activityId),
       startOffsetMs = Value(startOffsetMs),
       endOffsetMs = Value(endOffsetMs);
  static Insertable<CutRange> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? activityId,
    Expression<int>? startOffsetMs,
    Expression<int>? endOffsetMs,
    Expression<String>? reason,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (startOffsetMs != null) 'start_offset_ms': startOffsetMs,
      if (endOffsetMs != null) 'end_offset_ms': endOffsetMs,
      if (reason != null) 'reason': reason,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CutRangesCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? activityId,
    Value<int>? startOffsetMs,
    Value<int>? endOffsetMs,
    Value<String?>? reason,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CutRangesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      startOffsetMs: startOffsetMs ?? this.startOffsetMs,
      endOffsetMs: endOffsetMs ?? this.endOffsetMs,
      reason: reason ?? this.reason,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (startOffsetMs.present) {
      map['start_offset_ms'] = Variable<int>(startOffsetMs.value);
    }
    if (endOffsetMs.present) {
      map['end_offset_ms'] = Variable<int>(endOffsetMs.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CutRangesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('startOffsetMs: $startOffsetMs, ')
          ..write('endOffsetMs: $endOffsetMs, ')
          ..write('reason: $reason, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExportJobsTable extends ExportJobs
    with TableInfo<$ExportJobsTable, ExportJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExportJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conferenceIdMeta = const VerificationMeta(
    'conferenceId',
  );
  @override
  late final GeneratedColumn<String> conferenceId = GeneratedColumn<String>(
    'conference_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conferences (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, Object?>, String>
  scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<Map<String, Object?>>($ExportJobsTable.$converterscope);
  @override
  late final GeneratedColumnWithTypeConverter<ExportDestination, String>
  destination = GeneratedColumn<String>(
    'destination',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<ExportDestination>($ExportJobsTable.$converterdestination);
  @override
  late final GeneratedColumnWithTypeConverter<ExportFormat, String> format =
      GeneratedColumn<String>(
        'format',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ExportFormat>($ExportJobsTable.$converterformat);
  @override
  late final GeneratedColumnWithTypeConverter<ExportAudioMode, String>
  audioMode = GeneratedColumn<String>(
    'audio_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<ExportAudioMode>($ExportJobsTable.$converteraudioMode);
  @override
  late final GeneratedColumnWithTypeConverter<ExportJobState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ExportJobState>($ExportJobsTable.$converterstate);
  static const VerificationMeta _bytesTotalMeta = const VerificationMeta(
    'bytesTotal',
  );
  @override
  late final GeneratedColumn<int> bytesTotal = GeneratedColumn<int>(
    'bytes_total',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesDoneMeta = const VerificationMeta(
    'bytesDone',
  );
  @override
  late final GeneratedColumn<int> bytesDone = GeneratedColumn<int>(
    'bytes_done',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<VerificationLevel, String>
  verificationLevel =
      GeneratedColumn<String>(
        'verification_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<VerificationLevel>(
        $ExportJobsTable.$converterverificationLevel,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    id,
    conferenceId,
    scope,
    destination,
    format,
    audioMode,
    state,
    bytesTotal,
    bytesDone,
    startedAt,
    completedAt,
    verificationLevel,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'export_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExportJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conference_id')) {
      context.handle(
        _conferenceIdMeta,
        conferenceId.isAcceptableOrUnknown(
          data['conference_id']!,
          _conferenceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conferenceIdMeta);
    }
    if (data.containsKey('bytes_total')) {
      context.handle(
        _bytesTotalMeta,
        bytesTotal.isAcceptableOrUnknown(data['bytes_total']!, _bytesTotalMeta),
      );
    }
    if (data.containsKey('bytes_done')) {
      context.handle(
        _bytesDoneMeta,
        bytesDone.isAcceptableOrUnknown(data['bytes_done']!, _bytesDoneMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesDoneMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExportJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExportJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conferenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conference_id'],
      )!,
      scope: $ExportJobsTable.$converterscope.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}scope'],
        )!,
      ),
      destination: $ExportJobsTable.$converterdestination.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}destination'],
        )!,
      ),
      format: $ExportJobsTable.$converterformat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}format'],
        )!,
      ),
      audioMode: $ExportJobsTable.$converteraudioMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}audio_mode'],
        )!,
      ),
      state: $ExportJobsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      bytesTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_total'],
      ),
      bytesDone: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_done'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      verificationLevel: $ExportJobsTable.$converterverificationLevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}verification_level'],
        )!,
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ExportJobsTable createAlias(String alias) {
    return $ExportJobsTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, Object?>, String> $converterscope =
      const JsonMapConverter();
  static TypeConverter<ExportDestination, String> $converterdestination =
      const EnumKeyConverter(ExportDestination.values);
  static TypeConverter<ExportFormat, String> $converterformat =
      const EnumKeyConverter(ExportFormat.values);
  static TypeConverter<ExportAudioMode, String> $converteraudioMode =
      const EnumKeyConverter(ExportAudioMode.values);
  static TypeConverter<ExportJobState, String> $converterstate =
      const EnumKeyConverter(ExportJobState.values);
  static TypeConverter<VerificationLevel, String> $converterverificationLevel =
      const EnumKeyConverter(VerificationLevel.values);
}

class ExportJobsCompanion extends UpdateCompanion<ExportJob> {
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> id;
  final Value<String> conferenceId;
  final Value<Map<String, Object?>> scope;
  final Value<ExportDestination> destination;
  final Value<ExportFormat> format;
  final Value<ExportAudioMode> audioMode;
  final Value<ExportJobState> state;
  final Value<int?> bytesTotal;
  final Value<int> bytesDone;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> completedAt;
  final Value<VerificationLevel> verificationLevel;
  final Value<String?> lastError;
  final Value<int> rowid;
  const ExportJobsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.id = const Value.absent(),
    this.conferenceId = const Value.absent(),
    this.scope = const Value.absent(),
    this.destination = const Value.absent(),
    this.format = const Value.absent(),
    this.audioMode = const Value.absent(),
    this.state = const Value.absent(),
    this.bytesTotal = const Value.absent(),
    this.bytesDone = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.verificationLevel = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExportJobsCompanion.insert({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String id,
    required String conferenceId,
    required Map<String, Object?> scope,
    required ExportDestination destination,
    required ExportFormat format,
    required ExportAudioMode audioMode,
    required ExportJobState state,
    this.bytesTotal = const Value.absent(),
    required int bytesDone,
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    required VerificationLevel verificationLevel,
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       id = Value(id),
       conferenceId = Value(conferenceId),
       scope = Value(scope),
       destination = Value(destination),
       format = Value(format),
       audioMode = Value(audioMode),
       state = Value(state),
       bytesDone = Value(bytesDone),
       verificationLevel = Value(verificationLevel);
  static Insertable<ExportJob> custom({
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? id,
    Expression<String>? conferenceId,
    Expression<String>? scope,
    Expression<String>? destination,
    Expression<String>? format,
    Expression<String>? audioMode,
    Expression<String>? state,
    Expression<int>? bytesTotal,
    Expression<int>? bytesDone,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<String>? verificationLevel,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (id != null) 'id': id,
      if (conferenceId != null) 'conference_id': conferenceId,
      if (scope != null) 'scope': scope,
      if (destination != null) 'destination': destination,
      if (format != null) 'format': format,
      if (audioMode != null) 'audio_mode': audioMode,
      if (state != null) 'state': state,
      if (bytesTotal != null) 'bytes_total': bytesTotal,
      if (bytesDone != null) 'bytes_done': bytesDone,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (verificationLevel != null) 'verification_level': verificationLevel,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExportJobsCompanion copyWith({
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? id,
    Value<String>? conferenceId,
    Value<Map<String, Object?>>? scope,
    Value<ExportDestination>? destination,
    Value<ExportFormat>? format,
    Value<ExportAudioMode>? audioMode,
    Value<ExportJobState>? state,
    Value<int?>? bytesTotal,
    Value<int>? bytesDone,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? completedAt,
    Value<VerificationLevel>? verificationLevel,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return ExportJobsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      id: id ?? this.id,
      conferenceId: conferenceId ?? this.conferenceId,
      scope: scope ?? this.scope,
      destination: destination ?? this.destination,
      format: format ?? this.format,
      audioMode: audioMode ?? this.audioMode,
      state: state ?? this.state,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      bytesDone: bytesDone ?? this.bytesDone,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conferenceId.present) {
      map['conference_id'] = Variable<String>(conferenceId.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(
        $ExportJobsTable.$converterscope.toSql(scope.value),
      );
    }
    if (destination.present) {
      map['destination'] = Variable<String>(
        $ExportJobsTable.$converterdestination.toSql(destination.value),
      );
    }
    if (format.present) {
      map['format'] = Variable<String>(
        $ExportJobsTable.$converterformat.toSql(format.value),
      );
    }
    if (audioMode.present) {
      map['audio_mode'] = Variable<String>(
        $ExportJobsTable.$converteraudioMode.toSql(audioMode.value),
      );
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $ExportJobsTable.$converterstate.toSql(state.value),
      );
    }
    if (bytesTotal.present) {
      map['bytes_total'] = Variable<int>(bytesTotal.value);
    }
    if (bytesDone.present) {
      map['bytes_done'] = Variable<int>(bytesDone.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (verificationLevel.present) {
      map['verification_level'] = Variable<String>(
        $ExportJobsTable.$converterverificationLevel.toSql(
          verificationLevel.value,
        ),
      );
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExportJobsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('id: $id, ')
          ..write('conferenceId: $conferenceId, ')
          ..write('scope: $scope, ')
          ..write('destination: $destination, ')
          ..write('format: $format, ')
          ..write('audioMode: $audioMode, ')
          ..write('state: $state, ')
          ..write('bytesTotal: $bytesTotal, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('verificationLevel: $verificationLevel, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ConferencesTable conferences = $ConferencesTable(this);
  late final $GoalsTable goals = $GoalsTable(this);
  late final $ActivityTypesTable activityTypes = $ActivityTypesTable(this);
  late final $ActivitiesTable activities = $ActivitiesTable(this);
  late final $RecordingSegmentsTable recordingSegments =
      $RecordingSegmentsTable(this);
  late final $InterruptionsTable interruptions = $InterruptionsTable(this);
  late final $PhotosTable photos = $PhotosTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $CutRangesTable cutRanges = $CutRangesTable(this);
  late final $ExportJobsTable exportJobs = $ExportJobsTable(this);
  late final Index goalsConference = Index(
    'goals_conference',
    'CREATE INDEX goals_conference ON goals (conference_id)',
  );
  late final Index activitiesConference = Index(
    'activities_conference',
    'CREATE INDEX activities_conference ON activities (conference_id)',
  );
  late final Index interruptionsActivity = Index(
    'interruptions_activity',
    'CREATE INDEX interruptions_activity ON interruptions (activity_id)',
  );
  late final Index photosActivity = Index(
    'photos_activity',
    'CREATE INDEX photos_activity ON photos (activity_id)',
  );
  late final Index bookmarksActivity = Index(
    'bookmarks_activity',
    'CREATE INDEX bookmarks_activity ON bookmarks (activity_id)',
  );
  late final Index cutRangesActivity = Index(
    'cut_ranges_activity',
    'CREATE INDEX cut_ranges_activity ON cut_ranges (activity_id)',
  );
  late final Index exportJobsConference = Index(
    'export_jobs_conference',
    'CREATE INDEX export_jobs_conference ON export_jobs (conference_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appSettings,
    conferences,
    goals,
    activityTypes,
    activities,
    recordingSegments,
    interruptions,
    photos,
    bookmarks,
    cutRanges,
    exportJobs,
    goalsConference,
    activitiesConference,
    interruptionsActivity,
    photosActivity,
    bookmarksActivity,
    cutRangesActivity,
    exportJobsConference,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conferences',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('goals', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conferences',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('activities', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recording_segments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('interruptions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('photos', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('cut_ranges', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conferences',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('export_jobs', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$ConferencesTableCreateCompanionBuilder =
    ConferencesCompanion Function({
      required DateTime createdAt,
      required DateTime updatedAt,
      required String id,
      required String name,
      Value<String?> description,
      Value<String?> venue,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      required String timezone,
      Value<RoleType?> roleType,
      Value<String?> roleText,
      required List<RequestedOutput> requestedOutputs,
      required RecordingProfile defaultRecordingProfile,
      Value<DateTime?> policyAcknowledgedAt,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });
typedef $$ConferencesTableUpdateCompanionBuilder =
    ConferencesCompanion Function({
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<String?> venue,
      Value<DateTime?> startDate,
      Value<DateTime?> endDate,
      Value<String> timezone,
      Value<RoleType?> roleType,
      Value<String?> roleText,
      Value<List<RequestedOutput>> requestedOutputs,
      Value<RecordingProfile> defaultRecordingProfile,
      Value<DateTime?> policyAcknowledgedAt,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });

final class $$ConferencesTableReferences
    extends BaseReferences<_$AppDatabase, $ConferencesTable, Conference> {
  $$ConferencesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GoalsTable, List<Goal>> _goalsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.goals,
    aliasName: 'conferences__id__goals__conference_id',
  );

  $$GoalsTableProcessedTableManager get goalsRefs {
    final manager = $$GoalsTableTableManager(
      $_db,
      $_db.goals,
    ).filter((f) => f.conferenceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_goalsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActivitiesTable, List<Activity>>
  _activitiesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.activities,
    aliasName: 'conferences__id__activities__conference_id',
  );

  $$ActivitiesTableProcessedTableManager get activitiesRefs {
    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.conferenceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_activitiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExportJobsTable, List<ExportJob>>
  _exportJobsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.exportJobs,
    aliasName: 'conferences__id__export_jobs__conference_id',
  );

  $$ExportJobsTableProcessedTableManager get exportJobsRefs {
    final manager = $$ExportJobsTableTableManager(
      $_db,
      $_db.exportJobs,
    ).filter((f) => f.conferenceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_exportJobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConferencesTableFilterComposer
    extends Composer<_$AppDatabase, $ConferencesTable> {
  $$ConferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get venue => $composableBuilder(
    column: $table.venue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get startDate =>
      $composableBuilder(
        column: $table.startDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get endDate =>
      $composableBuilder(
        column: $table.endDate,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RoleType?, RoleType, String> get roleType =>
      $composableBuilder(
        column: $table.roleType,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get roleText => $composableBuilder(
    column: $table.roleText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    List<RequestedOutput>,
    List<RequestedOutput>,
    String
  >
  get requestedOutputs => $composableBuilder(
    column: $table.requestedOutputs,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<RecordingProfile, RecordingProfile, String>
  get defaultRecordingProfile => $composableBuilder(
    column: $table.defaultRecordingProfile,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get policyAcknowledgedAt => $composableBuilder(
    column: $table.policyAcknowledgedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> goalsRefs(
    Expression<bool> Function($$GoalsTableFilterComposer f) f,
  ) {
    final $$GoalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.goals,
      getReferencedColumn: (t) => t.conferenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GoalsTableFilterComposer(
            $db: $db,
            $table: $db.goals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> activitiesRefs(
    Expression<bool> Function($$ActivitiesTableFilterComposer f) f,
  ) {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.conferenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> exportJobsRefs(
    Expression<bool> Function($$ExportJobsTableFilterComposer f) f,
  ) {
    final $$ExportJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.exportJobs,
      getReferencedColumn: (t) => t.conferenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExportJobsTableFilterComposer(
            $db: $db,
            $table: $db.exportJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $ConferencesTable> {
  $$ConferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get venue => $composableBuilder(
    column: $table.venue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roleType => $composableBuilder(
    column: $table.roleType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roleText => $composableBuilder(
    column: $table.roleText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedOutputs => $composableBuilder(
    column: $table.requestedOutputs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultRecordingProfile => $composableBuilder(
    column: $table.defaultRecordingProfile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get policyAcknowledgedAt => $composableBuilder(
    column: $table.policyAcknowledgedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConferencesTable> {
  $$ConferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get venue =>
      $composableBuilder(column: $table.venue, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RoleType?, String> get roleType =>
      $composableBuilder(column: $table.roleType, builder: (column) => column);

  GeneratedColumn<String> get roleText =>
      $composableBuilder(column: $table.roleText, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<RequestedOutput>, String>
  get requestedOutputs => $composableBuilder(
    column: $table.requestedOutputs,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<RecordingProfile, String>
  get defaultRecordingProfile => $composableBuilder(
    column: $table.defaultRecordingProfile,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get policyAcknowledgedAt => $composableBuilder(
    column: $table.policyAcknowledgedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  Expression<T> goalsRefs<T extends Object>(
    Expression<T> Function($$GoalsTableAnnotationComposer a) f,
  ) {
    final $$GoalsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.goals,
      getReferencedColumn: (t) => t.conferenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GoalsTableAnnotationComposer(
            $db: $db,
            $table: $db.goals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> activitiesRefs<T extends Object>(
    Expression<T> Function($$ActivitiesTableAnnotationComposer a) f,
  ) {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.conferenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> exportJobsRefs<T extends Object>(
    Expression<T> Function($$ExportJobsTableAnnotationComposer a) f,
  ) {
    final $$ExportJobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.exportJobs,
      getReferencedColumn: (t) => t.conferenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExportJobsTableAnnotationComposer(
            $db: $db,
            $table: $db.exportJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConferencesTable,
          Conference,
          $$ConferencesTableFilterComposer,
          $$ConferencesTableOrderingComposer,
          $$ConferencesTableAnnotationComposer,
          $$ConferencesTableCreateCompanionBuilder,
          $$ConferencesTableUpdateCompanionBuilder,
          (Conference, $$ConferencesTableReferences),
          Conference,
          PrefetchHooks Function({
            bool goalsRefs,
            bool activitiesRefs,
            bool exportJobsRefs,
          })
        > {
  $$ConferencesTableTableManager(_$AppDatabase db, $ConferencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> venue = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<RoleType?> roleType = const Value.absent(),
                Value<String?> roleText = const Value.absent(),
                Value<List<RequestedOutput>> requestedOutputs =
                    const Value.absent(),
                Value<RecordingProfile> defaultRecordingProfile =
                    const Value.absent(),
                Value<DateTime?> policyAcknowledgedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConferencesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                name: name,
                description: description,
                venue: venue,
                startDate: startDate,
                endDate: endDate,
                timezone: timezone,
                roleType: roleType,
                roleText: roleText,
                requestedOutputs: requestedOutputs,
                defaultRecordingProfile: defaultRecordingProfile,
                policyAcknowledgedAt: policyAcknowledgedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> venue = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                required String timezone,
                Value<RoleType?> roleType = const Value.absent(),
                Value<String?> roleText = const Value.absent(),
                required List<RequestedOutput> requestedOutputs,
                required RecordingProfile defaultRecordingProfile,
                Value<DateTime?> policyAcknowledgedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConferencesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                name: name,
                description: description,
                venue: venue,
                startDate: startDate,
                endDate: endDate,
                timezone: timezone,
                roleType: roleType,
                roleText: roleText,
                requestedOutputs: requestedOutputs,
                defaultRecordingProfile: defaultRecordingProfile,
                policyAcknowledgedAt: policyAcknowledgedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConferencesTable, Conference>(table),
                  $$ConferencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                goalsRefs = false,
                activitiesRefs = false,
                exportJobsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (goalsRefs) db.goals,
                    if (activitiesRefs) db.activities,
                    if (exportJobsRefs) db.exportJobs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (goalsRefs)
                        await $_getPrefetchedDataByColumns<
                          Conference,
                          $ConferencesTable,
                          Goal,
                          $GoalsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ConferencesTableReferences
                              ._goalsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConferencesTableReferences(
                                db,
                                table,
                                p0,
                              ).goalsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'conference_id',
                          typedResults: items,
                        ),
                      if (activitiesRefs)
                        await $_getPrefetchedDataByColumns<
                          Conference,
                          $ConferencesTable,
                          Activity,
                          $ActivitiesTable
                        >(
                          currentTable: table,
                          referencedTable: $$ConferencesTableReferences
                              ._activitiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConferencesTableReferences(
                                db,
                                table,
                                p0,
                              ).activitiesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'conference_id',
                          typedResults: items,
                        ),
                      if (exportJobsRefs)
                        await $_getPrefetchedDataByColumns<
                          Conference,
                          $ConferencesTable,
                          ExportJob,
                          $ExportJobsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ConferencesTableReferences
                              ._exportJobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConferencesTableReferences(
                                db,
                                table,
                                p0,
                              ).exportJobsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'conference_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ConferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConferencesTable,
      Conference,
      $$ConferencesTableFilterComposer,
      $$ConferencesTableOrderingComposer,
      $$ConferencesTableAnnotationComposer,
      $$ConferencesTableCreateCompanionBuilder,
      $$ConferencesTableUpdateCompanionBuilder,
      (Conference, $$ConferencesTableReferences),
      Conference,
      PrefetchHooks Function({
        bool goalsRefs,
        bool activitiesRefs,
        bool exportJobsRefs,
      })
    >;
typedef $$GoalsTableCreateCompanionBuilder = GoalsCompanion Function({
  required DateTime createdAt,
  required DateTime updatedAt,
  required String id,
  required String conferenceId,
  required String goalText,
  Value<int?> priority,
  required int sortOrder,
  Value<int> rowid,
});
typedef $$GoalsTableUpdateCompanionBuilder = GoalsCompanion Function({
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> id,
  Value<String> conferenceId,
  Value<String> goalText,
  Value<int?> priority,
  Value<int> sortOrder,
  Value<int> rowid,
});

final class $$GoalsTableReferences
    extends BaseReferences<_$AppDatabase, $GoalsTable, Goal> {
  $$GoalsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConferencesTable _conferenceIdTable(_$AppDatabase db) =>
      db.conferences.createAlias('goals__conference_id__conferences__id');

  $$ConferencesTableProcessedTableManager get conferenceId {
    final $_column = $_itemColumn<String>('conference_id')!;

    final manager = $$ConferencesTableTableManager(
      $_db,
      $_db.conferences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conferenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GoalsTableFilterComposer extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalText => $composableBuilder(
    column: $table.goalText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$ConferencesTableFilterComposer get conferenceId {
    final $$ConferencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableFilterComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GoalsTableOrderingComposer
    extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalText => $composableBuilder(
    column: $table.goalText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConferencesTableOrderingComposer get conferenceId {
    final $$ConferencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableOrderingComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GoalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get goalText =>
      $composableBuilder(column: $table.goalText, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$ConferencesTableAnnotationComposer get conferenceId {
    final $$ConferencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableAnnotationComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GoalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GoalsTable,
          Goal,
          $$GoalsTableFilterComposer,
          $$GoalsTableOrderingComposer,
          $$GoalsTableAnnotationComposer,
          $$GoalsTableCreateCompanionBuilder,
          $$GoalsTableUpdateCompanionBuilder,
          (Goal, $$GoalsTableReferences),
          Goal,
          PrefetchHooks Function({bool conferenceId})
        > {
  $$GoalsTableTableManager(_$AppDatabase db, $GoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> conferenceId = const Value.absent(),
                Value<String> goalText = const Value.absent(),
                Value<int?> priority = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GoalsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                conferenceId: conferenceId,
                goalText: goalText,
                priority: priority,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String conferenceId,
                required String goalText,
                Value<int?> priority = const Value.absent(),
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => GoalsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                conferenceId: conferenceId,
                goalText: goalText,
                priority: priority,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GoalsTable, Goal>(table),
                  $$GoalsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conferenceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conferenceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.conferenceId,
                        referencedTable: $$GoalsTableReferences
                            ._conferenceIdTable(db),
                        referencedColumn: $$GoalsTableReferences
                            ._conferenceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GoalsTable,
      Goal,
      $$GoalsTableFilterComposer,
      $$GoalsTableOrderingComposer,
      $$GoalsTableAnnotationComposer,
      $$GoalsTableCreateCompanionBuilder,
      $$GoalsTableUpdateCompanionBuilder,
      (Goal, $$GoalsTableReferences),
      Goal,
      PrefetchHooks Function({bool conferenceId})
    >;
typedef $$ActivityTypesTableCreateCompanionBuilder =
    ActivityTypesCompanion Function({
      required DateTime createdAt,
      required DateTime updatedAt,
      required String id,
      required String key,
      required String label,
      required String icon,
      required bool isBuiltin,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$ActivityTypesTableUpdateCompanionBuilder =
    ActivityTypesCompanion Function({
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> id,
      Value<String> key,
      Value<String> label,
      Value<String> icon,
      Value<bool> isBuiltin,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$ActivityTypesTableReferences
    extends BaseReferences<_$AppDatabase, $ActivityTypesTable, ActivityType> {
  $$ActivityTypesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ActivitiesTable, List<Activity>>
  _activitiesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.activities,
    aliasName: 'activity_types__id__activities__type_id',
  );

  $$ActivitiesTableProcessedTableManager get activitiesRefs {
    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.typeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_activitiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivityTypesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityTypesTable> {
  $$ActivityTypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> activitiesRefs(
    Expression<bool> Function($$ActivitiesTableFilterComposer f) f,
  ) {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.typeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivityTypesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityTypesTable> {
  $$ActivityTypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivityTypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityTypesTable> {
  $$ActivityTypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> activitiesRefs<T extends Object>(
    Expression<T> Function($$ActivitiesTableAnnotationComposer a) f,
  ) {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.typeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivityTypesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivityTypesTable,
          ActivityType,
          $$ActivityTypesTableFilterComposer,
          $$ActivityTypesTableOrderingComposer,
          $$ActivityTypesTableAnnotationComposer,
          $$ActivityTypesTableCreateCompanionBuilder,
          $$ActivityTypesTableUpdateCompanionBuilder,
          (ActivityType, $$ActivityTypesTableReferences),
          ActivityType,
          PrefetchHooks Function({bool activitiesRefs})
        > {
  $$ActivityTypesTableTableManager(_$AppDatabase db, $ActivityTypesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityTypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityTypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityTypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivityTypesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                key: key,
                label: label,
                icon: icon,
                isBuiltin: isBuiltin,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String key,
                required String label,
                required String icon,
                required bool isBuiltin,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => ActivityTypesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                key: key,
                label: label,
                icon: icon,
                isBuiltin: isBuiltin,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActivityTypesTable, ActivityType>(table),
                  $$ActivityTypesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activitiesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (activitiesRefs) db.activities],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (activitiesRefs)
                    await $_getPrefetchedDataByColumns<
                      ActivityType,
                      $ActivityTypesTable,
                      Activity,
                      $ActivitiesTable
                    >(
                      currentTable: table,
                      referencedTable: $$ActivityTypesTableReferences
                          ._activitiesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ActivityTypesTableReferences(
                            db,
                            table,
                            p0,
                          ).activitiesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'type_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ActivityTypesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivityTypesTable,
      ActivityType,
      $$ActivityTypesTableFilterComposer,
      $$ActivityTypesTableOrderingComposer,
      $$ActivityTypesTableAnnotationComposer,
      $$ActivityTypesTableCreateCompanionBuilder,
      $$ActivityTypesTableUpdateCompanionBuilder,
      (ActivityType, $$ActivityTypesTableReferences),
      ActivityType,
      PrefetchHooks Function({bool activitiesRefs})
    >;
typedef $$ActivitiesTableCreateCompanionBuilder = ActivitiesCompanion Function({
  required DateTime createdAt,
  required DateTime updatedAt,
  required String id,
  required String conferenceId,
  required String typeId,
  required String title,
  required List<String> speakerNames,
  Value<String?> organisation,
  Value<String?> room,
  Value<String?> notesMd,
  required List<String> tags,
  Value<DateTime?> plannedStart,
  Value<DateTime?> actualStart,
  Value<DateTime?> actualEnd,
  required ActivityStatus status,
  required RecordingPermissionStatus recordingPermissionStatus,
  Value<RecordingProfile?> recordingProfileOverride,
  required bool isPrivate,
  Value<String?> contactName,
  Value<String?> contactDetails,
  Value<String?> followUpText,
  Value<int> rowid,
});
typedef $$ActivitiesTableUpdateCompanionBuilder = ActivitiesCompanion Function({
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> id,
  Value<String> conferenceId,
  Value<String> typeId,
  Value<String> title,
  Value<List<String>> speakerNames,
  Value<String?> organisation,
  Value<String?> room,
  Value<String?> notesMd,
  Value<List<String>> tags,
  Value<DateTime?> plannedStart,
  Value<DateTime?> actualStart,
  Value<DateTime?> actualEnd,
  Value<ActivityStatus> status,
  Value<RecordingPermissionStatus> recordingPermissionStatus,
  Value<RecordingProfile?> recordingProfileOverride,
  Value<bool> isPrivate,
  Value<String?> contactName,
  Value<String?> contactDetails,
  Value<String?> followUpText,
  Value<int> rowid,
});

final class $$ActivitiesTableReferences
    extends BaseReferences<_$AppDatabase, $ActivitiesTable, Activity> {
  $$ActivitiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConferencesTable _conferenceIdTable(_$AppDatabase db) =>
      db.conferences.createAlias('activities__conference_id__conferences__id');

  $$ConferencesTableProcessedTableManager get conferenceId {
    final $_column = $_itemColumn<String>('conference_id')!;

    final manager = $$ConferencesTableTableManager(
      $_db,
      $_db.conferences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conferenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActivityTypesTable _typeIdTable(_$AppDatabase db) =>
      db.activityTypes.createAlias('activities__type_id__activity_types__id');

  $$ActivityTypesTableProcessedTableManager get typeId {
    final $_column = $_itemColumn<String>('type_id')!;

    final manager = $$ActivityTypesTableTableManager(
      $_db,
      $_db.activityTypes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_typeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RecordingSegmentsTable, List<RecordingSegment>>
  _recordingSegmentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recordingSegments,
        aliasName: 'activities__id__recording_segments__activity_id',
      );

  $$RecordingSegmentsTableProcessedTableManager get recordingSegmentsRefs {
    final manager = $$RecordingSegmentsTableTableManager(
      $_db,
      $_db.recordingSegments,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recordingSegmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InterruptionsTable, List<Interruption>>
  _interruptionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.interruptions,
    aliasName: 'activities__id__interruptions__activity_id',
  );

  $$InterruptionsTableProcessedTableManager get interruptionsRefs {
    final manager = $$InterruptionsTableTableManager(
      $_db,
      $_db.interruptions,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_interruptionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PhotosTable, List<Photo>> _photosRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.photos,
    aliasName: 'activities__id__photos__activity_id',
  );

  $$PhotosTableProcessedTableManager get photosRefs {
    final manager = $$PhotosTableTableManager(
      $_db,
      $_db.photos,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_photosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'activities__id__bookmarks__activity_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CutRangesTable, List<CutRange>>
  _cutRangesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cutRanges,
    aliasName: 'activities__id__cut_ranges__activity_id',
  );

  $$CutRangesTableProcessedTableManager get cutRangesRefs {
    final manager = $$CutRangesTableTableManager(
      $_db,
      $_db.cutRanges,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cutRangesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivitiesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get speakerNames => $composableBuilder(
    column: $table.speakerNames,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get organisation => $composableBuilder(
    column: $table.organisation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get room => $composableBuilder(
    column: $table.room,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notesMd => $composableBuilder(
    column: $table.notesMd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String> get tags =>
      $composableBuilder(
        column: $table.tags,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualStart => $composableBuilder(
    column: $table.actualStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualEnd => $composableBuilder(
    column: $table.actualEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ActivityStatus, ActivityStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    RecordingPermissionStatus,
    RecordingPermissionStatus,
    String
  >
  get recordingPermissionStatus => $composableBuilder(
    column: $table.recordingPermissionStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<RecordingProfile?, RecordingProfile, String>
  get recordingProfileOverride => $composableBuilder(
    column: $table.recordingProfileOverride,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get isPrivate => $composableBuilder(
    column: $table.isPrivate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactName => $composableBuilder(
    column: $table.contactName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactDetails => $composableBuilder(
    column: $table.contactDetails,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get followUpText => $composableBuilder(
    column: $table.followUpText,
    builder: (column) => ColumnFilters(column),
  );

  $$ConferencesTableFilterComposer get conferenceId {
    final $$ConferencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableFilterComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActivityTypesTableFilterComposer get typeId {
    final $$ActivityTypesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.typeId,
      referencedTable: $db.activityTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityTypesTableFilterComposer(
            $db: $db,
            $table: $db.activityTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> recordingSegmentsRefs(
    Expression<bool> Function($$RecordingSegmentsTableFilterComposer f) f,
  ) {
    final $$RecordingSegmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recordingSegments,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecordingSegmentsTableFilterComposer(
            $db: $db,
            $table: $db.recordingSegments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> interruptionsRefs(
    Expression<bool> Function($$InterruptionsTableFilterComposer f) f,
  ) {
    final $$InterruptionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.interruptions,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InterruptionsTableFilterComposer(
            $db: $db,
            $table: $db.interruptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> photosRefs(
    Expression<bool> Function($$PhotosTableFilterComposer f) f,
  ) {
    final $$PhotosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.photos,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhotosTableFilterComposer(
            $db: $db,
            $table: $db.photos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> cutRangesRefs(
    Expression<bool> Function($$CutRangesTableFilterComposer f) f,
  ) {
    final $$CutRangesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cutRanges,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CutRangesTableFilterComposer(
            $db: $db,
            $table: $db.cutRanges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get speakerNames => $composableBuilder(
    column: $table.speakerNames,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organisation => $composableBuilder(
    column: $table.organisation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get room => $composableBuilder(
    column: $table.room,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notesMd => $composableBuilder(
    column: $table.notesMd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualStart => $composableBuilder(
    column: $table.actualStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualEnd => $composableBuilder(
    column: $table.actualEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordingPermissionStatus => $composableBuilder(
    column: $table.recordingPermissionStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordingProfileOverride => $composableBuilder(
    column: $table.recordingProfileOverride,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrivate => $composableBuilder(
    column: $table.isPrivate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactName => $composableBuilder(
    column: $table.contactName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactDetails => $composableBuilder(
    column: $table.contactDetails,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get followUpText => $composableBuilder(
    column: $table.followUpText,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConferencesTableOrderingComposer get conferenceId {
    final $$ConferencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableOrderingComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActivityTypesTableOrderingComposer get typeId {
    final $$ActivityTypesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.typeId,
      referencedTable: $db.activityTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityTypesTableOrderingComposer(
            $db: $db,
            $table: $db.activityTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get speakerNames =>
      $composableBuilder(
        column: $table.speakerNames,
        builder: (column) => column,
      );

  GeneratedColumn<String> get organisation => $composableBuilder(
    column: $table.organisation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get room =>
      $composableBuilder(column: $table.room, builder: (column) => column);

  GeneratedColumn<String> get notesMd =>
      $composableBuilder(column: $table.notesMd, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get actualStart => $composableBuilder(
    column: $table.actualStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get actualEnd =>
      $composableBuilder(column: $table.actualEnd, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ActivityStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RecordingPermissionStatus, String>
  get recordingPermissionStatus => $composableBuilder(
    column: $table.recordingPermissionStatus,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<RecordingProfile?, String>
  get recordingProfileOverride => $composableBuilder(
    column: $table.recordingProfileOverride,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPrivate =>
      $composableBuilder(column: $table.isPrivate, builder: (column) => column);

  GeneratedColumn<String> get contactName => $composableBuilder(
    column: $table.contactName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contactDetails => $composableBuilder(
    column: $table.contactDetails,
    builder: (column) => column,
  );

  GeneratedColumn<String> get followUpText => $composableBuilder(
    column: $table.followUpText,
    builder: (column) => column,
  );

  $$ConferencesTableAnnotationComposer get conferenceId {
    final $$ConferencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableAnnotationComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActivityTypesTableAnnotationComposer get typeId {
    final $$ActivityTypesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.typeId,
      referencedTable: $db.activityTypes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivityTypesTableAnnotationComposer(
            $db: $db,
            $table: $db.activityTypes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> recordingSegmentsRefs<T extends Object>(
    Expression<T> Function($$RecordingSegmentsTableAnnotationComposer a) f,
  ) {
    final $$RecordingSegmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recordingSegments,
          getReferencedColumn: (t) => t.activityId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecordingSegmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.recordingSegments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> interruptionsRefs<T extends Object>(
    Expression<T> Function($$InterruptionsTableAnnotationComposer a) f,
  ) {
    final $$InterruptionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.interruptions,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InterruptionsTableAnnotationComposer(
            $db: $db,
            $table: $db.interruptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> photosRefs<T extends Object>(
    Expression<T> Function($$PhotosTableAnnotationComposer a) f,
  ) {
    final $$PhotosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.photos,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhotosTableAnnotationComposer(
            $db: $db,
            $table: $db.photos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> cutRangesRefs<T extends Object>(
    Expression<T> Function($$CutRangesTableAnnotationComposer a) f,
  ) {
    final $$CutRangesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cutRanges,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CutRangesTableAnnotationComposer(
            $db: $db,
            $table: $db.cutRanges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivitiesTable,
          Activity,
          $$ActivitiesTableFilterComposer,
          $$ActivitiesTableOrderingComposer,
          $$ActivitiesTableAnnotationComposer,
          $$ActivitiesTableCreateCompanionBuilder,
          $$ActivitiesTableUpdateCompanionBuilder,
          (Activity, $$ActivitiesTableReferences),
          Activity,
          PrefetchHooks Function({
            bool conferenceId,
            bool typeId,
            bool recordingSegmentsRefs,
            bool interruptionsRefs,
            bool photosRefs,
            bool bookmarksRefs,
            bool cutRangesRefs,
          })
        > {
  $$ActivitiesTableTableManager(_$AppDatabase db, $ActivitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> conferenceId = const Value.absent(),
                Value<String> typeId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<List<String>> speakerNames = const Value.absent(),
                Value<String?> organisation = const Value.absent(),
                Value<String?> room = const Value.absent(),
                Value<String?> notesMd = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<DateTime?> plannedStart = const Value.absent(),
                Value<DateTime?> actualStart = const Value.absent(),
                Value<DateTime?> actualEnd = const Value.absent(),
                Value<ActivityStatus> status = const Value.absent(),
                Value<RecordingPermissionStatus> recordingPermissionStatus =
                    const Value.absent(),
                Value<RecordingProfile?> recordingProfileOverride =
                    const Value.absent(),
                Value<bool> isPrivate = const Value.absent(),
                Value<String?> contactName = const Value.absent(),
                Value<String?> contactDetails = const Value.absent(),
                Value<String?> followUpText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivitiesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                conferenceId: conferenceId,
                typeId: typeId,
                title: title,
                speakerNames: speakerNames,
                organisation: organisation,
                room: room,
                notesMd: notesMd,
                tags: tags,
                plannedStart: plannedStart,
                actualStart: actualStart,
                actualEnd: actualEnd,
                status: status,
                recordingPermissionStatus: recordingPermissionStatus,
                recordingProfileOverride: recordingProfileOverride,
                isPrivate: isPrivate,
                contactName: contactName,
                contactDetails: contactDetails,
                followUpText: followUpText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String conferenceId,
                required String typeId,
                required String title,
                required List<String> speakerNames,
                Value<String?> organisation = const Value.absent(),
                Value<String?> room = const Value.absent(),
                Value<String?> notesMd = const Value.absent(),
                required List<String> tags,
                Value<DateTime?> plannedStart = const Value.absent(),
                Value<DateTime?> actualStart = const Value.absent(),
                Value<DateTime?> actualEnd = const Value.absent(),
                required ActivityStatus status,
                required RecordingPermissionStatus recordingPermissionStatus,
                Value<RecordingProfile?> recordingProfileOverride =
                    const Value.absent(),
                required bool isPrivate,
                Value<String?> contactName = const Value.absent(),
                Value<String?> contactDetails = const Value.absent(),
                Value<String?> followUpText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivitiesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                conferenceId: conferenceId,
                typeId: typeId,
                title: title,
                speakerNames: speakerNames,
                organisation: organisation,
                room: room,
                notesMd: notesMd,
                tags: tags,
                plannedStart: plannedStart,
                actualStart: actualStart,
                actualEnd: actualEnd,
                status: status,
                recordingPermissionStatus: recordingPermissionStatus,
                recordingProfileOverride: recordingProfileOverride,
                isPrivate: isPrivate,
                contactName: contactName,
                contactDetails: contactDetails,
                followUpText: followUpText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActivitiesTable, Activity>(table),
                  $$ActivitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                conferenceId = false,
                typeId = false,
                recordingSegmentsRefs = false,
                interruptionsRefs = false,
                photosRefs = false,
                bookmarksRefs = false,
                cutRangesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recordingSegmentsRefs) db.recordingSegments,
                    if (interruptionsRefs) db.interruptions,
                    if (photosRefs) db.photos,
                    if (bookmarksRefs) db.bookmarks,
                    if (cutRangesRefs) db.cutRanges,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (conferenceId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.conferenceId,
                            referencedTable: $$ActivitiesTableReferences
                                ._conferenceIdTable(db),
                            referencedColumn: $$ActivitiesTableReferences
                                ._conferenceIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (typeId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.typeId,
                            referencedTable: $$ActivitiesTableReferences
                                ._typeIdTable(db),
                            referencedColumn: $$ActivitiesTableReferences
                                ._typeIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recordingSegmentsRefs)
                        await $_getPrefetchedDataByColumns<
                          Activity,
                          $ActivitiesTable,
                          RecordingSegment,
                          $RecordingSegmentsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ActivitiesTableReferences
                              ._recordingSegmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).recordingSegmentsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'activity_id',
                          typedResults: items,
                        ),
                      if (interruptionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Activity,
                          $ActivitiesTable,
                          Interruption,
                          $InterruptionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ActivitiesTableReferences
                              ._interruptionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).interruptionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'activity_id',
                          typedResults: items,
                        ),
                      if (photosRefs)
                        await $_getPrefetchedDataByColumns<
                          Activity,
                          $ActivitiesTable,
                          Photo,
                          $PhotosTable
                        >(
                          currentTable: table,
                          referencedTable: $$ActivitiesTableReferences
                              ._photosRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).photosRefs,
                          currentColumn: 'id',
                          referencedColumn: 'activity_id',
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedDataByColumns<
                          Activity,
                          $ActivitiesTable,
                          Bookmark,
                          $BookmarksTable
                        >(
                          currentTable: table,
                          referencedTable: $$ActivitiesTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          currentColumn: 'id',
                          referencedColumn: 'activity_id',
                          typedResults: items,
                        ),
                      if (cutRangesRefs)
                        await $_getPrefetchedDataByColumns<
                          Activity,
                          $ActivitiesTable,
                          CutRange,
                          $CutRangesTable
                        >(
                          currentTable: table,
                          referencedTable: $$ActivitiesTableReferences
                              ._cutRangesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).cutRangesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'activity_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivitiesTable,
      Activity,
      $$ActivitiesTableFilterComposer,
      $$ActivitiesTableOrderingComposer,
      $$ActivitiesTableAnnotationComposer,
      $$ActivitiesTableCreateCompanionBuilder,
      $$ActivitiesTableUpdateCompanionBuilder,
      (Activity, $$ActivitiesTableReferences),
      Activity,
      PrefetchHooks Function({
        bool conferenceId,
        bool typeId,
        bool recordingSegmentsRefs,
        bool interruptionsRefs,
        bool photosRefs,
        bool bookmarksRefs,
        bool cutRangesRefs,
      })
    >;
typedef $$RecordingSegmentsTableCreateCompanionBuilder =
    RecordingSegmentsCompanion Function({
      required DateTime createdAt,
      required DateTime updatedAt,
      required String id,
      required String activityId,
      required int sequence,
      required String filePath,
      required SegmentState state,
      required RecordingProfile requestedProfile,
      required String codec,
      required String container,
      required int channelCount,
      required int sampleRateHz,
      required int requestedBitrateBps,
      Value<int?> observedBitrateBps,
      Value<String?> inputRoute,
      required DateTime startUtc,
      Value<DateTime?> endUtc,
      Value<int?> durationMs,
      Value<int?> bytes,
      Value<String?> sha256,
      Value<SegmentEndReason?> endReason,
      Value<int> rowid,
    });
typedef $$RecordingSegmentsTableUpdateCompanionBuilder =
    RecordingSegmentsCompanion Function({
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> id,
      Value<String> activityId,
      Value<int> sequence,
      Value<String> filePath,
      Value<SegmentState> state,
      Value<RecordingProfile> requestedProfile,
      Value<String> codec,
      Value<String> container,
      Value<int> channelCount,
      Value<int> sampleRateHz,
      Value<int> requestedBitrateBps,
      Value<int?> observedBitrateBps,
      Value<String?> inputRoute,
      Value<DateTime> startUtc,
      Value<DateTime?> endUtc,
      Value<int?> durationMs,
      Value<int?> bytes,
      Value<String?> sha256,
      Value<SegmentEndReason?> endReason,
      Value<int> rowid,
    });

final class $$RecordingSegmentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RecordingSegmentsTable,
          RecordingSegment
        > {
  $$RecordingSegmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) => db.activities
      .createAlias('recording_segments__activity_id__activities__id');

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<String>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecordingSegmentsTableFilterComposer
    extends Composer<_$AppDatabase, $RecordingSegmentsTable> {
  $$RecordingSegmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SegmentState, SegmentState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<RecordingProfile, RecordingProfile, String>
  get requestedProfile => $composableBuilder(
    column: $table.requestedProfile,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get codec => $composableBuilder(
    column: $table.codec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get channelCount => $composableBuilder(
    column: $table.channelCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requestedBitrateBps => $composableBuilder(
    column: $table.requestedBitrateBps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get observedBitrateBps => $composableBuilder(
    column: $table.observedBitrateBps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputRoute => $composableBuilder(
    column: $table.inputRoute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startUtc => $composableBuilder(
    column: $table.startUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endUtc => $composableBuilder(
    column: $table.endUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SegmentEndReason?, SegmentEndReason, String>
  get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecordingSegmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecordingSegmentsTable> {
  $$RecordingSegmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedProfile => $composableBuilder(
    column: $table.requestedProfile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codec => $composableBuilder(
    column: $table.codec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get channelCount => $composableBuilder(
    column: $table.channelCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requestedBitrateBps => $composableBuilder(
    column: $table.requestedBitrateBps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get observedBitrateBps => $composableBuilder(
    column: $table.observedBitrateBps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputRoute => $composableBuilder(
    column: $table.inputRoute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startUtc => $composableBuilder(
    column: $table.startUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endUtc => $composableBuilder(
    column: $table.endUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecordingSegmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecordingSegmentsTable> {
  $$RecordingSegmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SegmentState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RecordingProfile, String>
  get requestedProfile => $composableBuilder(
    column: $table.requestedProfile,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codec =>
      $composableBuilder(column: $table.codec, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<int> get channelCount => $composableBuilder(
    column: $table.channelCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => column,
  );

  GeneratedColumn<int> get requestedBitrateBps => $composableBuilder(
    column: $table.requestedBitrateBps,
    builder: (column) => column,
  );

  GeneratedColumn<int> get observedBitrateBps => $composableBuilder(
    column: $table.observedBitrateBps,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inputRoute => $composableBuilder(
    column: $table.inputRoute,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startUtc =>
      $composableBuilder(column: $table.startUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get endUtc =>
      $composableBuilder(column: $table.endUtc, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SegmentEndReason?, String> get endReason =>
      $composableBuilder(column: $table.endReason, builder: (column) => column);

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecordingSegmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecordingSegmentsTable,
          RecordingSegment,
          $$RecordingSegmentsTableFilterComposer,
          $$RecordingSegmentsTableOrderingComposer,
          $$RecordingSegmentsTableAnnotationComposer,
          $$RecordingSegmentsTableCreateCompanionBuilder,
          $$RecordingSegmentsTableUpdateCompanionBuilder,
          (RecordingSegment, $$RecordingSegmentsTableReferences),
          RecordingSegment,
          PrefetchHooks Function({bool activityId})
        > {
  $$RecordingSegmentsTableTableManager(
    _$AppDatabase db,
    $RecordingSegmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordingSegmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordingSegmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordingSegmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<SegmentState> state = const Value.absent(),
                Value<RecordingProfile> requestedProfile = const Value.absent(),
                Value<String> codec = const Value.absent(),
                Value<String> container = const Value.absent(),
                Value<int> channelCount = const Value.absent(),
                Value<int> sampleRateHz = const Value.absent(),
                Value<int> requestedBitrateBps = const Value.absent(),
                Value<int?> observedBitrateBps = const Value.absent(),
                Value<String?> inputRoute = const Value.absent(),
                Value<DateTime> startUtc = const Value.absent(),
                Value<DateTime?> endUtc = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> bytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<SegmentEndReason?> endReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordingSegmentsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                sequence: sequence,
                filePath: filePath,
                state: state,
                requestedProfile: requestedProfile,
                codec: codec,
                container: container,
                channelCount: channelCount,
                sampleRateHz: sampleRateHz,
                requestedBitrateBps: requestedBitrateBps,
                observedBitrateBps: observedBitrateBps,
                inputRoute: inputRoute,
                startUtc: startUtc,
                endUtc: endUtc,
                durationMs: durationMs,
                bytes: bytes,
                sha256: sha256,
                endReason: endReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String activityId,
                required int sequence,
                required String filePath,
                required SegmentState state,
                required RecordingProfile requestedProfile,
                required String codec,
                required String container,
                required int channelCount,
                required int sampleRateHz,
                required int requestedBitrateBps,
                Value<int?> observedBitrateBps = const Value.absent(),
                Value<String?> inputRoute = const Value.absent(),
                required DateTime startUtc,
                Value<DateTime?> endUtc = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> bytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<SegmentEndReason?> endReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordingSegmentsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                sequence: sequence,
                filePath: filePath,
                state: state,
                requestedProfile: requestedProfile,
                codec: codec,
                container: container,
                channelCount: channelCount,
                sampleRateHz: sampleRateHz,
                requestedBitrateBps: requestedBitrateBps,
                observedBitrateBps: observedBitrateBps,
                inputRoute: inputRoute,
                startUtc: startUtc,
                endUtc: endUtc,
                durationMs: durationMs,
                bytes: bytes,
                sha256: sha256,
                endReason: endReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecordingSegmentsTable, RecordingSegment>(table),
                  $$RecordingSegmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.activityId,
                        referencedTable: $$RecordingSegmentsTableReferences
                            ._activityIdTable(db),
                        referencedColumn: $$RecordingSegmentsTableReferences
                            ._activityIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecordingSegmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecordingSegmentsTable,
      RecordingSegment,
      $$RecordingSegmentsTableFilterComposer,
      $$RecordingSegmentsTableOrderingComposer,
      $$RecordingSegmentsTableAnnotationComposer,
      $$RecordingSegmentsTableCreateCompanionBuilder,
      $$RecordingSegmentsTableUpdateCompanionBuilder,
      (RecordingSegment, $$RecordingSegmentsTableReferences),
      RecordingSegment,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$InterruptionsTableCreateCompanionBuilder =
    InterruptionsCompanion Function({
      required DateTime createdAt,
      required DateTime updatedAt,
      required String id,
      required String activityId,
      required InterruptionReason reason,
      required DateTime startUtc,
      Value<DateTime?> endUtc,
      required bool autoResumed,
      Value<int> rowid,
    });
typedef $$InterruptionsTableUpdateCompanionBuilder =
    InterruptionsCompanion Function({
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> id,
      Value<String> activityId,
      Value<InterruptionReason> reason,
      Value<DateTime> startUtc,
      Value<DateTime?> endUtc,
      Value<bool> autoResumed,
      Value<int> rowid,
    });

final class $$InterruptionsTableReferences
    extends BaseReferences<_$AppDatabase, $InterruptionsTable, Interruption> {
  $$InterruptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) =>
      db.activities.createAlias('interruptions__activity_id__activities__id');

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<String>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InterruptionsTableFilterComposer
    extends Composer<_$AppDatabase, $InterruptionsTable> {
  $$InterruptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<InterruptionReason, InterruptionReason, String>
  get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get startUtc => $composableBuilder(
    column: $table.startUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endUtc => $composableBuilder(
    column: $table.endUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoResumed => $composableBuilder(
    column: $table.autoResumed,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InterruptionsTableOrderingComposer
    extends Composer<_$AppDatabase, $InterruptionsTable> {
  $$InterruptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startUtc => $composableBuilder(
    column: $table.startUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endUtc => $composableBuilder(
    column: $table.endUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoResumed => $composableBuilder(
    column: $table.autoResumed,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InterruptionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InterruptionsTable> {
  $$InterruptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<InterruptionReason, String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get startUtc =>
      $composableBuilder(column: $table.startUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get endUtc =>
      $composableBuilder(column: $table.endUtc, builder: (column) => column);

  GeneratedColumn<bool> get autoResumed => $composableBuilder(
    column: $table.autoResumed,
    builder: (column) => column,
  );

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InterruptionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InterruptionsTable,
          Interruption,
          $$InterruptionsTableFilterComposer,
          $$InterruptionsTableOrderingComposer,
          $$InterruptionsTableAnnotationComposer,
          $$InterruptionsTableCreateCompanionBuilder,
          $$InterruptionsTableUpdateCompanionBuilder,
          (Interruption, $$InterruptionsTableReferences),
          Interruption,
          PrefetchHooks Function({bool activityId})
        > {
  $$InterruptionsTableTableManager(_$AppDatabase db, $InterruptionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InterruptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InterruptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InterruptionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<InterruptionReason> reason = const Value.absent(),
                Value<DateTime> startUtc = const Value.absent(),
                Value<DateTime?> endUtc = const Value.absent(),
                Value<bool> autoResumed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InterruptionsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                reason: reason,
                startUtc: startUtc,
                endUtc: endUtc,
                autoResumed: autoResumed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String activityId,
                required InterruptionReason reason,
                required DateTime startUtc,
                Value<DateTime?> endUtc = const Value.absent(),
                required bool autoResumed,
                Value<int> rowid = const Value.absent(),
              }) => InterruptionsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                reason: reason,
                startUtc: startUtc,
                endUtc: endUtc,
                autoResumed: autoResumed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InterruptionsTable, Interruption>(table),
                  $$InterruptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.activityId,
                        referencedTable: $$InterruptionsTableReferences
                            ._activityIdTable(db),
                        referencedColumn: $$InterruptionsTableReferences
                            ._activityIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$InterruptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InterruptionsTable,
      Interruption,
      $$InterruptionsTableFilterComposer,
      $$InterruptionsTableOrderingComposer,
      $$InterruptionsTableAnnotationComposer,
      $$InterruptionsTableCreateCompanionBuilder,
      $$InterruptionsTableUpdateCompanionBuilder,
      (Interruption, $$InterruptionsTableReferences),
      Interruption,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$PhotosTableCreateCompanionBuilder = PhotosCompanion Function({
  required DateTime createdAt,
  required DateTime updatedAt,
  required String id,
  required String activityId,
  required String filePath,
  Value<String?> thumbnailPath,
  required DateTime takenUtc,
  Value<int?> offsetMs,
  Value<String?> caption,
  Value<String?> label,
  required PhotoSource source,
  Value<int?> width,
  Value<int?> height,
  Value<int?> bytes,
  Value<String?> sha256,
  required bool originalKept,
  Value<int> rowid,
});
typedef $$PhotosTableUpdateCompanionBuilder = PhotosCompanion Function({
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> id,
  Value<String> activityId,
  Value<String> filePath,
  Value<String?> thumbnailPath,
  Value<DateTime> takenUtc,
  Value<int?> offsetMs,
  Value<String?> caption,
  Value<String?> label,
  Value<PhotoSource> source,
  Value<int?> width,
  Value<int?> height,
  Value<int?> bytes,
  Value<String?> sha256,
  Value<bool> originalKept,
  Value<int> rowid,
});

final class $$PhotosTableReferences
    extends BaseReferences<_$AppDatabase, $PhotosTable, Photo> {
  $$PhotosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) =>
      db.activities.createAlias('photos__activity_id__activities__id');

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<String>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PhotosTableFilterComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get takenUtc => $composableBuilder(
    column: $table.takenUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offsetMs => $composableBuilder(
    column: $table.offsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PhotoSource, PhotoSource, String> get source =>
      $composableBuilder(
        column: $table.source,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get originalKept => $composableBuilder(
    column: $table.originalKept,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get takenUtc => $composableBuilder(
    column: $table.takenUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offsetMs => $composableBuilder(
    column: $table.offsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get originalKept => $composableBuilder(
    column: $table.originalKept,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get takenUtc =>
      $composableBuilder(column: $table.takenUtc, builder: (column) => column);

  GeneratedColumn<int> get offsetMs =>
      $composableBuilder(column: $table.offsetMs, builder: (column) => column);

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PhotoSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<bool> get originalKept => $composableBuilder(
    column: $table.originalKept,
    builder: (column) => column,
  );

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PhotosTable,
          Photo,
          $$PhotosTableFilterComposer,
          $$PhotosTableOrderingComposer,
          $$PhotosTableAnnotationComposer,
          $$PhotosTableCreateCompanionBuilder,
          $$PhotosTableUpdateCompanionBuilder,
          (Photo, $$PhotosTableReferences),
          Photo,
          PrefetchHooks Function({bool activityId})
        > {
  $$PhotosTableTableManager(_$AppDatabase db, $PhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<DateTime> takenUtc = const Value.absent(),
                Value<int?> offsetMs = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<PhotoSource> source = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> bytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<bool> originalKept = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                filePath: filePath,
                thumbnailPath: thumbnailPath,
                takenUtc: takenUtc,
                offsetMs: offsetMs,
                caption: caption,
                label: label,
                source: source,
                width: width,
                height: height,
                bytes: bytes,
                sha256: sha256,
                originalKept: originalKept,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String activityId,
                required String filePath,
                Value<String?> thumbnailPath = const Value.absent(),
                required DateTime takenUtc,
                Value<int?> offsetMs = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<String?> label = const Value.absent(),
                required PhotoSource source,
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> bytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                required bool originalKept,
                Value<int> rowid = const Value.absent(),
              }) => PhotosCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                filePath: filePath,
                thumbnailPath: thumbnailPath,
                takenUtc: takenUtc,
                offsetMs: offsetMs,
                caption: caption,
                label: label,
                source: source,
                width: width,
                height: height,
                bytes: bytes,
                sha256: sha256,
                originalKept: originalKept,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PhotosTable, Photo>(table),
                  $$PhotosTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.activityId,
                        referencedTable: $$PhotosTableReferences
                            ._activityIdTable(db),
                        referencedColumn: $$PhotosTableReferences
                            ._activityIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PhotosTable,
      Photo,
      $$PhotosTableFilterComposer,
      $$PhotosTableOrderingComposer,
      $$PhotosTableAnnotationComposer,
      $$PhotosTableCreateCompanionBuilder,
      $$PhotosTableUpdateCompanionBuilder,
      (Photo, $$PhotosTableReferences),
      Photo,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$BookmarksTableCreateCompanionBuilder = BookmarksCompanion Function({
  required DateTime createdAt,
  required DateTime updatedAt,
  required String id,
  required String activityId,
  required DateTime atUtc,
  Value<int?> offsetMs,
  Value<String?> label,
  Value<String?> note,
  required BookmarkSource source,
  Value<int> rowid,
});
typedef $$BookmarksTableUpdateCompanionBuilder = BookmarksCompanion Function({
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> id,
  Value<String> activityId,
  Value<DateTime> atUtc,
  Value<int?> offsetMs,
  Value<String?> label,
  Value<String?> note,
  Value<BookmarkSource> source,
  Value<int> rowid,
});

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) =>
      db.activities.createAlias('bookmarks__activity_id__activities__id');

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<String>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get atUtc => $composableBuilder(
    column: $table.atUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offsetMs => $composableBuilder(
    column: $table.offsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BookmarkSource, BookmarkSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get atUtc => $composableBuilder(
    column: $table.atUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offsetMs => $composableBuilder(
    column: $table.offsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get atUtc =>
      $composableBuilder(column: $table.atUtc, builder: (column) => column);

  GeneratedColumn<int> get offsetMs =>
      $composableBuilder(column: $table.offsetMs, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BookmarkSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          Bookmark,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (Bookmark, $$BookmarksTableReferences),
          Bookmark,
          PrefetchHooks Function({bool activityId})
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<DateTime> atUtc = const Value.absent(),
                Value<int?> offsetMs = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<BookmarkSource> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                atUtc: atUtc,
                offsetMs: offsetMs,
                label: label,
                note: note,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String activityId,
                required DateTime atUtc,
                Value<int?> offsetMs = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required BookmarkSource source,
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                atUtc: atUtc,
                offsetMs: offsetMs,
                label: label,
                note: note,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookmarksTable, Bookmark>(table),
                  $$BookmarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.activityId,
                        referencedTable: $$BookmarksTableReferences
                            ._activityIdTable(db),
                        referencedColumn: $$BookmarksTableReferences
                            ._activityIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      Bookmark,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (Bookmark, $$BookmarksTableReferences),
      Bookmark,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$CutRangesTableCreateCompanionBuilder = CutRangesCompanion Function({
  required DateTime createdAt,
  required DateTime updatedAt,
  required String id,
  required String activityId,
  required int startOffsetMs,
  required int endOffsetMs,
  Value<String?> reason,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$CutRangesTableUpdateCompanionBuilder = CutRangesCompanion Function({
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> id,
  Value<String> activityId,
  Value<int> startOffsetMs,
  Value<int> endOffsetMs,
  Value<String?> reason,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$CutRangesTableReferences
    extends BaseReferences<_$AppDatabase, $CutRangesTable, CutRange> {
  $$CutRangesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) =>
      db.activities.createAlias('cut_ranges__activity_id__activities__id');

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<String>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CutRangesTableFilterComposer
    extends Composer<_$AppDatabase, $CutRangesTable> {
  $$CutRangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startOffsetMs => $composableBuilder(
    column: $table.startOffsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endOffsetMs => $composableBuilder(
    column: $table.endOffsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CutRangesTableOrderingComposer
    extends Composer<_$AppDatabase, $CutRangesTable> {
  $$CutRangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startOffsetMs => $composableBuilder(
    column: $table.startOffsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endOffsetMs => $composableBuilder(
    column: $table.endOffsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CutRangesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CutRangesTable> {
  $$CutRangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startOffsetMs => $composableBuilder(
    column: $table.startOffsetMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endOffsetMs => $composableBuilder(
    column: $table.endOffsetMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CutRangesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CutRangesTable,
          CutRange,
          $$CutRangesTableFilterComposer,
          $$CutRangesTableOrderingComposer,
          $$CutRangesTableAnnotationComposer,
          $$CutRangesTableCreateCompanionBuilder,
          $$CutRangesTableUpdateCompanionBuilder,
          (CutRange, $$CutRangesTableReferences),
          CutRange,
          PrefetchHooks Function({bool activityId})
        > {
  $$CutRangesTableTableManager(_$AppDatabase db, $CutRangesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CutRangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CutRangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CutRangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<int> startOffsetMs = const Value.absent(),
                Value<int> endOffsetMs = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CutRangesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                startOffsetMs: startOffsetMs,
                endOffsetMs: endOffsetMs,
                reason: reason,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String activityId,
                required int startOffsetMs,
                required int endOffsetMs,
                Value<String?> reason = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CutRangesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                activityId: activityId,
                startOffsetMs: startOffsetMs,
                endOffsetMs: endOffsetMs,
                reason: reason,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CutRangesTable, CutRange>(table),
                  $$CutRangesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.activityId,
                        referencedTable: $$CutRangesTableReferences
                            ._activityIdTable(db),
                        referencedColumn: $$CutRangesTableReferences
                            ._activityIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CutRangesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CutRangesTable,
      CutRange,
      $$CutRangesTableFilterComposer,
      $$CutRangesTableOrderingComposer,
      $$CutRangesTableAnnotationComposer,
      $$CutRangesTableCreateCompanionBuilder,
      $$CutRangesTableUpdateCompanionBuilder,
      (CutRange, $$CutRangesTableReferences),
      CutRange,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$ExportJobsTableCreateCompanionBuilder = ExportJobsCompanion Function({
  required DateTime createdAt,
  required DateTime updatedAt,
  required String id,
  required String conferenceId,
  required Map<String, Object?> scope,
  required ExportDestination destination,
  required ExportFormat format,
  required ExportAudioMode audioMode,
  required ExportJobState state,
  Value<int?> bytesTotal,
  required int bytesDone,
  Value<DateTime?> startedAt,
  Value<DateTime?> completedAt,
  required VerificationLevel verificationLevel,
  Value<String?> lastError,
  Value<int> rowid,
});
typedef $$ExportJobsTableUpdateCompanionBuilder = ExportJobsCompanion Function({
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<String> id,
  Value<String> conferenceId,
  Value<Map<String, Object?>> scope,
  Value<ExportDestination> destination,
  Value<ExportFormat> format,
  Value<ExportAudioMode> audioMode,
  Value<ExportJobState> state,
  Value<int?> bytesTotal,
  Value<int> bytesDone,
  Value<DateTime?> startedAt,
  Value<DateTime?> completedAt,
  Value<VerificationLevel> verificationLevel,
  Value<String?> lastError,
  Value<int> rowid,
});

final class $$ExportJobsTableReferences
    extends BaseReferences<_$AppDatabase, $ExportJobsTable, ExportJob> {
  $$ExportJobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConferencesTable _conferenceIdTable(_$AppDatabase db) =>
      db.conferences.createAlias('export_jobs__conference_id__conferences__id');

  $$ConferencesTableProcessedTableManager get conferenceId {
    final $_column = $_itemColumn<String>('conference_id')!;

    final manager = $$ConferencesTableTableManager(
      $_db,
      $_db.conferences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conferenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExportJobsTableFilterComposer
    extends Composer<_$AppDatabase, $ExportJobsTable> {
  $$ExportJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, Object?>,
    Map<String, Object>,
    String
  >
  get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ExportDestination, ExportDestination, String>
  get destination => $composableBuilder(
    column: $table.destination,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ExportFormat, ExportFormat, String>
  get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ExportAudioMode, ExportAudioMode, String>
  get audioMode => $composableBuilder(
    column: $table.audioMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ExportJobState, ExportJobState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get bytesTotal => $composableBuilder(
    column: $table.bytesTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<VerificationLevel, VerificationLevel, String>
  get verificationLevel => $composableBuilder(
    column: $table.verificationLevel,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  $$ConferencesTableFilterComposer get conferenceId {
    final $$ConferencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableFilterComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExportJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExportJobsTable> {
  $$ExportJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destination => $composableBuilder(
    column: $table.destination,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioMode => $composableBuilder(
    column: $table.audioMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesTotal => $composableBuilder(
    column: $table.bytesTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationLevel => $composableBuilder(
    column: $table.verificationLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConferencesTableOrderingComposer get conferenceId {
    final $$ConferencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableOrderingComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExportJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExportJobsTable> {
  $$ExportJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, Object?>, String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ExportDestination, String> get destination =>
      $composableBuilder(
        column: $table.destination,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<ExportFormat, String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ExportAudioMode, String> get audioMode =>
      $composableBuilder(column: $table.audioMode, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ExportJobState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get bytesTotal => $composableBuilder(
    column: $table.bytesTotal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bytesDone =>
      $composableBuilder(column: $table.bytesDone, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<VerificationLevel, String>
  get verificationLevel => $composableBuilder(
    column: $table.verificationLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  $$ConferencesTableAnnotationComposer get conferenceId {
    final $$ConferencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conferenceId,
      referencedTable: $db.conferences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConferencesTableAnnotationComposer(
            $db: $db,
            $table: $db.conferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExportJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExportJobsTable,
          ExportJob,
          $$ExportJobsTableFilterComposer,
          $$ExportJobsTableOrderingComposer,
          $$ExportJobsTableAnnotationComposer,
          $$ExportJobsTableCreateCompanionBuilder,
          $$ExportJobsTableUpdateCompanionBuilder,
          (ExportJob, $$ExportJobsTableReferences),
          ExportJob,
          PrefetchHooks Function({bool conferenceId})
        > {
  $$ExportJobsTableTableManager(_$AppDatabase db, $ExportJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExportJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExportJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExportJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> conferenceId = const Value.absent(),
                Value<Map<String, Object?>> scope = const Value.absent(),
                Value<ExportDestination> destination = const Value.absent(),
                Value<ExportFormat> format = const Value.absent(),
                Value<ExportAudioMode> audioMode = const Value.absent(),
                Value<ExportJobState> state = const Value.absent(),
                Value<int?> bytesTotal = const Value.absent(),
                Value<int> bytesDone = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<VerificationLevel> verificationLevel =
                    const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExportJobsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                conferenceId: conferenceId,
                scope: scope,
                destination: destination,
                format: format,
                audioMode: audioMode,
                state: state,
                bytesTotal: bytesTotal,
                bytesDone: bytesDone,
                startedAt: startedAt,
                completedAt: completedAt,
                verificationLevel: verificationLevel,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime createdAt,
                required DateTime updatedAt,
                required String id,
                required String conferenceId,
                required Map<String, Object?> scope,
                required ExportDestination destination,
                required ExportFormat format,
                required ExportAudioMode audioMode,
                required ExportJobState state,
                Value<int?> bytesTotal = const Value.absent(),
                required int bytesDone,
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                required VerificationLevel verificationLevel,
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExportJobsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                id: id,
                conferenceId: conferenceId,
                scope: scope,
                destination: destination,
                format: format,
                audioMode: audioMode,
                state: state,
                bytesTotal: bytesTotal,
                bytesDone: bytesDone,
                startedAt: startedAt,
                completedAt: completedAt,
                verificationLevel: verificationLevel,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExportJobsTable, ExportJob>(table),
                  $$ExportJobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conferenceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conferenceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.conferenceId,
                        referencedTable: $$ExportJobsTableReferences
                            ._conferenceIdTable(db),
                        referencedColumn: $$ExportJobsTableReferences
                            ._conferenceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExportJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExportJobsTable,
      ExportJob,
      $$ExportJobsTableFilterComposer,
      $$ExportJobsTableOrderingComposer,
      $$ExportJobsTableAnnotationComposer,
      $$ExportJobsTableCreateCompanionBuilder,
      $$ExportJobsTableUpdateCompanionBuilder,
      (ExportJob, $$ExportJobsTableReferences),
      ExportJob,
      PrefetchHooks Function({bool conferenceId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ConferencesTableTableManager get conferences =>
      $$ConferencesTableTableManager(_db, _db.conferences);
  $$GoalsTableTableManager get goals =>
      $$GoalsTableTableManager(_db, _db.goals);
  $$ActivityTypesTableTableManager get activityTypes =>
      $$ActivityTypesTableTableManager(_db, _db.activityTypes);
  $$ActivitiesTableTableManager get activities =>
      $$ActivitiesTableTableManager(_db, _db.activities);
  $$RecordingSegmentsTableTableManager get recordingSegments =>
      $$RecordingSegmentsTableTableManager(_db, _db.recordingSegments);
  $$InterruptionsTableTableManager get interruptions =>
      $$InterruptionsTableTableManager(_db, _db.interruptions);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db, _db.photos);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$CutRangesTableTableManager get cutRanges =>
      $$CutRangesTableTableManager(_db, _db.cutRanges);
  $$ExportJobsTableTableManager get exportJobs =>
      $$ExportJobsTableTableManager(_db, _db.exportJobs);
}
