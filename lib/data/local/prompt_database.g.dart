// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prompt_database.dart';

// ignore_for_file: type=lint
class $ServerProfilesTable extends ServerProfiles
    with TableInfo<$ServerProfilesTable, ServerProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServerProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backendMeta = const VerificationMeta(
    'backend',
  );
  @override
  late final GeneratedColumn<String> backend = GeneratedColumn<String>(
    'backend',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('directOpenCode'),
  );
  static const VerificationMeta _lastAccessedAtMillisMeta =
      const VerificationMeta('lastAccessedAtMillis');
  @override
  late final GeneratedColumn<int> lastAccessedAtMillis = GeneratedColumn<int>(
    'last_accessed_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    origin,
    username,
    backend,
    lastAccessedAtMillis,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'server_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServerProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('backend')) {
      context.handle(
        _backendMeta,
        backend.isAcceptableOrUnknown(data['backend']!, _backendMeta),
      );
    }
    if (data.containsKey('last_accessed_at_millis')) {
      context.handle(
        _lastAccessedAtMillisMeta,
        lastAccessedAtMillis.isAcceptableOrUnknown(
          data['last_accessed_at_millis']!,
          _lastAccessedAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessedAtMillisMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServerProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      backend: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backend'],
      )!,
      lastAccessedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_accessed_at_millis'],
      )!,
    );
  }

  @override
  $ServerProfilesTable createAlias(String alias) {
    return $ServerProfilesTable(attachedDatabase, alias);
  }
}

class ServerProfile extends DataClass implements Insertable<ServerProfile> {
  final String id;
  final String origin;
  final String? username;
  final String backend;
  final int lastAccessedAtMillis;
  const ServerProfile({
    required this.id,
    required this.origin,
    this.username,
    required this.backend,
    required this.lastAccessedAtMillis,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    map['backend'] = Variable<String>(backend);
    map['last_accessed_at_millis'] = Variable<int>(lastAccessedAtMillis);
    return map;
  }

  ServerProfilesCompanion toCompanion(bool nullToAbsent) {
    return ServerProfilesCompanion(
      id: Value(id),
      origin: Value(origin),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      backend: Value(backend),
      lastAccessedAtMillis: Value(lastAccessedAtMillis),
    );
  }

  factory ServerProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerProfile(
      id: serializer.fromJson<String>(json['id']),
      origin: serializer.fromJson<String>(json['origin']),
      username: serializer.fromJson<String?>(json['username']),
      backend: serializer.fromJson<String>(json['backend']),
      lastAccessedAtMillis: serializer.fromJson<int>(
        json['lastAccessedAtMillis'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'origin': serializer.toJson<String>(origin),
      'username': serializer.toJson<String?>(username),
      'backend': serializer.toJson<String>(backend),
      'lastAccessedAtMillis': serializer.toJson<int>(lastAccessedAtMillis),
    };
  }

  ServerProfile copyWith({
    String? id,
    String? origin,
    Value<String?> username = const Value.absent(),
    String? backend,
    int? lastAccessedAtMillis,
  }) => ServerProfile(
    id: id ?? this.id,
    origin: origin ?? this.origin,
    username: username.present ? username.value : this.username,
    backend: backend ?? this.backend,
    lastAccessedAtMillis: lastAccessedAtMillis ?? this.lastAccessedAtMillis,
  );
  ServerProfile copyWithCompanion(ServerProfilesCompanion data) {
    return ServerProfile(
      id: data.id.present ? data.id.value : this.id,
      origin: data.origin.present ? data.origin.value : this.origin,
      username: data.username.present ? data.username.value : this.username,
      backend: data.backend.present ? data.backend.value : this.backend,
      lastAccessedAtMillis: data.lastAccessedAtMillis.present
          ? data.lastAccessedAtMillis.value
          : this.lastAccessedAtMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServerProfile(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('username: $username, ')
          ..write('backend: $backend, ')
          ..write('lastAccessedAtMillis: $lastAccessedAtMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, origin, username, backend, lastAccessedAtMillis);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerProfile &&
          other.id == this.id &&
          other.origin == this.origin &&
          other.username == this.username &&
          other.backend == this.backend &&
          other.lastAccessedAtMillis == this.lastAccessedAtMillis);
}

class ServerProfilesCompanion extends UpdateCompanion<ServerProfile> {
  final Value<String> id;
  final Value<String> origin;
  final Value<String?> username;
  final Value<String> backend;
  final Value<int> lastAccessedAtMillis;
  final Value<int> rowid;
  const ServerProfilesCompanion({
    this.id = const Value.absent(),
    this.origin = const Value.absent(),
    this.username = const Value.absent(),
    this.backend = const Value.absent(),
    this.lastAccessedAtMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServerProfilesCompanion.insert({
    required String id,
    required String origin,
    this.username = const Value.absent(),
    this.backend = const Value.absent(),
    required int lastAccessedAtMillis,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       origin = Value(origin),
       lastAccessedAtMillis = Value(lastAccessedAtMillis);
  static Insertable<ServerProfile> custom({
    Expression<String>? id,
    Expression<String>? origin,
    Expression<String>? username,
    Expression<String>? backend,
    Expression<int>? lastAccessedAtMillis,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (origin != null) 'origin': origin,
      if (username != null) 'username': username,
      if (backend != null) 'backend': backend,
      if (lastAccessedAtMillis != null)
        'last_accessed_at_millis': lastAccessedAtMillis,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServerProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? origin,
    Value<String?>? username,
    Value<String>? backend,
    Value<int>? lastAccessedAtMillis,
    Value<int>? rowid,
  }) {
    return ServerProfilesCompanion(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      username: username ?? this.username,
      backend: backend ?? this.backend,
      lastAccessedAtMillis: lastAccessedAtMillis ?? this.lastAccessedAtMillis,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (backend.present) {
      map['backend'] = Variable<String>(backend.value);
    }
    if (lastAccessedAtMillis.present) {
      map['last_accessed_at_millis'] = Variable<int>(
        lastAccessedAtMillis.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServerProfilesCompanion(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('username: $username, ')
          ..write('backend: $backend, ')
          ..write('lastAccessedAtMillis: $lastAccessedAtMillis, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueuedPromptsTable extends QueuedPrompts
    with TableInfo<$QueuedPromptsTable, QueuedPrompt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueuedPromptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverProfileIdMeta = const VerificationMeta(
    'serverProfileId',
  );
  @override
  late final GeneratedColumn<String> serverProfileId = GeneratedColumn<String>(
    'server_profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptTextMeta = const VerificationMeta(
    'promptText',
  );
  @override
  late final GeneratedColumn<String> promptText = GeneratedColumn<String>(
    'prompt_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('prompt'),
  );
  static const VerificationMeta _commandNameMeta = const VerificationMeta(
    'commandName',
  );
  @override
  late final GeneratedColumn<String> commandName = GeneratedColumn<String>(
    'command_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelProviderIdMeta = const VerificationMeta(
    'modelProviderId',
  );
  @override
  late final GeneratedColumn<String> modelProviderId = GeneratedColumn<String>(
    'model_provider_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasoningEffortMeta = const VerificationMeta(
    'reasoningEffort',
  );
  @override
  late final GeneratedColumn<String> reasoningEffort = GeneratedColumn<String>(
    'reasoning_effort',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pauseReasonMeta = const VerificationMeta(
    'pauseReason',
  );
  @override
  late final GeneratedColumn<String> pauseReason = GeneratedColumn<String>(
    'pause_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMillisMeta = const VerificationMeta(
    'createdAtMillis',
  );
  @override
  late final GeneratedColumn<int> createdAtMillis = GeneratedColumn<int>(
    'created_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMillisMeta = const VerificationMeta(
    'updatedAtMillis',
  );
  @override
  late final GeneratedColumn<int> updatedAtMillis = GeneratedColumn<int>(
    'updated_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sendingStartedAtMillisMeta =
      const VerificationMeta('sendingStartedAtMillis');
  @override
  late final GeneratedColumn<int> sendingStartedAtMillis = GeneratedColumn<int>(
    'sending_started_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedAtMillisMeta =
      const VerificationMeta('acknowledgedAtMillis');
  @override
  late final GeneratedColumn<int> acknowledgedAtMillis = GeneratedColumn<int>(
    'acknowledged_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverProfileId,
    sessionId,
    directory,
    position,
    promptText,
    operationType,
    commandName,
    attachmentsJson,
    modelProviderId,
    modelId,
    agentName,
    reasoningEffort,
    state,
    pauseReason,
    attemptCount,
    createdAtMillis,
    updatedAtMillis,
    sendingStartedAtMillis,
    acknowledgedAtMillis,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queued_prompts';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueuedPrompt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_profile_id')) {
      context.handle(
        _serverProfileIdMeta,
        serverProfileId.isAcceptableOrUnknown(
          data['server_profile_id']!,
          _serverProfileIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverProfileIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    } else if (isInserting) {
      context.missing(_directoryMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('prompt_text')) {
      context.handle(
        _promptTextMeta,
        promptText.isAcceptableOrUnknown(data['prompt_text']!, _promptTextMeta),
      );
    } else if (isInserting) {
      context.missing(_promptTextMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    }
    if (data.containsKey('command_name')) {
      context.handle(
        _commandNameMeta,
        commandName.isAcceptableOrUnknown(
          data['command_name']!,
          _commandNameMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('model_provider_id')) {
      context.handle(
        _modelProviderIdMeta,
        modelProviderId.isAcceptableOrUnknown(
          data['model_provider_id']!,
          _modelProviderIdMeta,
        ),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    if (data.containsKey('reasoning_effort')) {
      context.handle(
        _reasoningEffortMeta,
        reasoningEffort.isAcceptableOrUnknown(
          data['reasoning_effort']!,
          _reasoningEffortMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('pause_reason')) {
      context.handle(
        _pauseReasonMeta,
        pauseReason.isAcceptableOrUnknown(
          data['pause_reason']!,
          _pauseReasonMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at_millis')) {
      context.handle(
        _createdAtMillisMeta,
        createdAtMillis.isAcceptableOrUnknown(
          data['created_at_millis']!,
          _createdAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMillisMeta);
    }
    if (data.containsKey('updated_at_millis')) {
      context.handle(
        _updatedAtMillisMeta,
        updatedAtMillis.isAcceptableOrUnknown(
          data['updated_at_millis']!,
          _updatedAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMillisMeta);
    }
    if (data.containsKey('sending_started_at_millis')) {
      context.handle(
        _sendingStartedAtMillisMeta,
        sendingStartedAtMillis.isAcceptableOrUnknown(
          data['sending_started_at_millis']!,
          _sendingStartedAtMillisMeta,
        ),
      );
    }
    if (data.containsKey('acknowledged_at_millis')) {
      context.handle(
        _acknowledgedAtMillisMeta,
        acknowledgedAtMillis.isAcceptableOrUnknown(
          data['acknowledged_at_millis']!,
          _acknowledgedAtMillisMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {serverProfileId, sessionId, position},
  ];
  @override
  QueuedPrompt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueuedPrompt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_profile_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      promptText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_text'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      commandName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_name'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      ),
      modelProviderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_provider_id'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
      reasoningEffort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning_effort'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      pauseReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pause_reason'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      createdAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_millis'],
      )!,
      updatedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_millis'],
      )!,
      sendingStartedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sending_started_at_millis'],
      ),
      acknowledgedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acknowledged_at_millis'],
      ),
    );
  }

  @override
  $QueuedPromptsTable createAlias(String alias) {
    return $QueuedPromptsTable(attachedDatabase, alias);
  }
}

class QueuedPrompt extends DataClass implements Insertable<QueuedPrompt> {
  final String id;
  final String serverProfileId;
  final String sessionId;
  final String directory;
  final int position;
  final String promptText;
  final String operationType;
  final String? commandName;

  /// JSON array of `{name, mediaType, base64}` objects, or null when the
  /// prompt carries no file. Stored in the encrypted database exactly like
  /// [promptText], and never logged or exported.
  final String? attachmentsJson;
  final String? modelProviderId;
  final String? modelId;
  final String? agentName;
  final String? reasoningEffort;
  final String state;
  final String? pauseReason;
  final int attemptCount;
  final int createdAtMillis;
  final int updatedAtMillis;
  final int? sendingStartedAtMillis;
  final int? acknowledgedAtMillis;
  const QueuedPrompt({
    required this.id,
    required this.serverProfileId,
    required this.sessionId,
    required this.directory,
    required this.position,
    required this.promptText,
    required this.operationType,
    this.commandName,
    this.attachmentsJson,
    this.modelProviderId,
    this.modelId,
    this.agentName,
    this.reasoningEffort,
    required this.state,
    this.pauseReason,
    required this.attemptCount,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.sendingStartedAtMillis,
    this.acknowledgedAtMillis,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['server_profile_id'] = Variable<String>(serverProfileId);
    map['session_id'] = Variable<String>(sessionId);
    map['directory'] = Variable<String>(directory);
    map['position'] = Variable<int>(position);
    map['prompt_text'] = Variable<String>(promptText);
    map['operation_type'] = Variable<String>(operationType);
    if (!nullToAbsent || commandName != null) {
      map['command_name'] = Variable<String>(commandName);
    }
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    if (!nullToAbsent || modelProviderId != null) {
      map['model_provider_id'] = Variable<String>(modelProviderId);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    if (!nullToAbsent || reasoningEffort != null) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || pauseReason != null) {
      map['pause_reason'] = Variable<String>(pauseReason);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    map['created_at_millis'] = Variable<int>(createdAtMillis);
    map['updated_at_millis'] = Variable<int>(updatedAtMillis);
    if (!nullToAbsent || sendingStartedAtMillis != null) {
      map['sending_started_at_millis'] = Variable<int>(sendingStartedAtMillis);
    }
    if (!nullToAbsent || acknowledgedAtMillis != null) {
      map['acknowledged_at_millis'] = Variable<int>(acknowledgedAtMillis);
    }
    return map;
  }

  QueuedPromptsCompanion toCompanion(bool nullToAbsent) {
    return QueuedPromptsCompanion(
      id: Value(id),
      serverProfileId: Value(serverProfileId),
      sessionId: Value(sessionId),
      directory: Value(directory),
      position: Value(position),
      promptText: Value(promptText),
      operationType: Value(operationType),
      commandName: commandName == null && nullToAbsent
          ? const Value.absent()
          : Value(commandName),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
      modelProviderId: modelProviderId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelProviderId),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
      reasoningEffort: reasoningEffort == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningEffort),
      state: Value(state),
      pauseReason: pauseReason == null && nullToAbsent
          ? const Value.absent()
          : Value(pauseReason),
      attemptCount: Value(attemptCount),
      createdAtMillis: Value(createdAtMillis),
      updatedAtMillis: Value(updatedAtMillis),
      sendingStartedAtMillis: sendingStartedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(sendingStartedAtMillis),
      acknowledgedAtMillis: acknowledgedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAtMillis),
    );
  }

  factory QueuedPrompt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueuedPrompt(
      id: serializer.fromJson<String>(json['id']),
      serverProfileId: serializer.fromJson<String>(json['serverProfileId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      directory: serializer.fromJson<String>(json['directory']),
      position: serializer.fromJson<int>(json['position']),
      promptText: serializer.fromJson<String>(json['promptText']),
      operationType: serializer.fromJson<String>(json['operationType']),
      commandName: serializer.fromJson<String?>(json['commandName']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
      modelProviderId: serializer.fromJson<String?>(json['modelProviderId']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      agentName: serializer.fromJson<String?>(json['agentName']),
      reasoningEffort: serializer.fromJson<String?>(json['reasoningEffort']),
      state: serializer.fromJson<String>(json['state']),
      pauseReason: serializer.fromJson<String?>(json['pauseReason']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      createdAtMillis: serializer.fromJson<int>(json['createdAtMillis']),
      updatedAtMillis: serializer.fromJson<int>(json['updatedAtMillis']),
      sendingStartedAtMillis: serializer.fromJson<int?>(
        json['sendingStartedAtMillis'],
      ),
      acknowledgedAtMillis: serializer.fromJson<int?>(
        json['acknowledgedAtMillis'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverProfileId': serializer.toJson<String>(serverProfileId),
      'sessionId': serializer.toJson<String>(sessionId),
      'directory': serializer.toJson<String>(directory),
      'position': serializer.toJson<int>(position),
      'promptText': serializer.toJson<String>(promptText),
      'operationType': serializer.toJson<String>(operationType),
      'commandName': serializer.toJson<String?>(commandName),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
      'modelProviderId': serializer.toJson<String?>(modelProviderId),
      'modelId': serializer.toJson<String?>(modelId),
      'agentName': serializer.toJson<String?>(agentName),
      'reasoningEffort': serializer.toJson<String?>(reasoningEffort),
      'state': serializer.toJson<String>(state),
      'pauseReason': serializer.toJson<String?>(pauseReason),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'createdAtMillis': serializer.toJson<int>(createdAtMillis),
      'updatedAtMillis': serializer.toJson<int>(updatedAtMillis),
      'sendingStartedAtMillis': serializer.toJson<int?>(sendingStartedAtMillis),
      'acknowledgedAtMillis': serializer.toJson<int?>(acknowledgedAtMillis),
    };
  }

  QueuedPrompt copyWith({
    String? id,
    String? serverProfileId,
    String? sessionId,
    String? directory,
    int? position,
    String? promptText,
    String? operationType,
    Value<String?> commandName = const Value.absent(),
    Value<String?> attachmentsJson = const Value.absent(),
    Value<String?> modelProviderId = const Value.absent(),
    Value<String?> modelId = const Value.absent(),
    Value<String?> agentName = const Value.absent(),
    Value<String?> reasoningEffort = const Value.absent(),
    String? state,
    Value<String?> pauseReason = const Value.absent(),
    int? attemptCount,
    int? createdAtMillis,
    int? updatedAtMillis,
    Value<int?> sendingStartedAtMillis = const Value.absent(),
    Value<int?> acknowledgedAtMillis = const Value.absent(),
  }) => QueuedPrompt(
    id: id ?? this.id,
    serverProfileId: serverProfileId ?? this.serverProfileId,
    sessionId: sessionId ?? this.sessionId,
    directory: directory ?? this.directory,
    position: position ?? this.position,
    promptText: promptText ?? this.promptText,
    operationType: operationType ?? this.operationType,
    commandName: commandName.present ? commandName.value : this.commandName,
    attachmentsJson: attachmentsJson.present
        ? attachmentsJson.value
        : this.attachmentsJson,
    modelProviderId: modelProviderId.present
        ? modelProviderId.value
        : this.modelProviderId,
    modelId: modelId.present ? modelId.value : this.modelId,
    agentName: agentName.present ? agentName.value : this.agentName,
    reasoningEffort: reasoningEffort.present
        ? reasoningEffort.value
        : this.reasoningEffort,
    state: state ?? this.state,
    pauseReason: pauseReason.present ? pauseReason.value : this.pauseReason,
    attemptCount: attemptCount ?? this.attemptCount,
    createdAtMillis: createdAtMillis ?? this.createdAtMillis,
    updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
    sendingStartedAtMillis: sendingStartedAtMillis.present
        ? sendingStartedAtMillis.value
        : this.sendingStartedAtMillis,
    acknowledgedAtMillis: acknowledgedAtMillis.present
        ? acknowledgedAtMillis.value
        : this.acknowledgedAtMillis,
  );
  QueuedPrompt copyWithCompanion(QueuedPromptsCompanion data) {
    return QueuedPrompt(
      id: data.id.present ? data.id.value : this.id,
      serverProfileId: data.serverProfileId.present
          ? data.serverProfileId.value
          : this.serverProfileId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      directory: data.directory.present ? data.directory.value : this.directory,
      position: data.position.present ? data.position.value : this.position,
      promptText: data.promptText.present
          ? data.promptText.value
          : this.promptText,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      commandName: data.commandName.present
          ? data.commandName.value
          : this.commandName,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      modelProviderId: data.modelProviderId.present
          ? data.modelProviderId.value
          : this.modelProviderId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      reasoningEffort: data.reasoningEffort.present
          ? data.reasoningEffort.value
          : this.reasoningEffort,
      state: data.state.present ? data.state.value : this.state,
      pauseReason: data.pauseReason.present
          ? data.pauseReason.value
          : this.pauseReason,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      createdAtMillis: data.createdAtMillis.present
          ? data.createdAtMillis.value
          : this.createdAtMillis,
      updatedAtMillis: data.updatedAtMillis.present
          ? data.updatedAtMillis.value
          : this.updatedAtMillis,
      sendingStartedAtMillis: data.sendingStartedAtMillis.present
          ? data.sendingStartedAtMillis.value
          : this.sendingStartedAtMillis,
      acknowledgedAtMillis: data.acknowledgedAtMillis.present
          ? data.acknowledgedAtMillis.value
          : this.acknowledgedAtMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueuedPrompt(')
          ..write('id: $id, ')
          ..write('serverProfileId: $serverProfileId, ')
          ..write('sessionId: $sessionId, ')
          ..write('directory: $directory, ')
          ..write('position: $position, ')
          ..write('promptText: $promptText, ')
          ..write('operationType: $operationType, ')
          ..write('commandName: $commandName, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('modelProviderId: $modelProviderId, ')
          ..write('modelId: $modelId, ')
          ..write('agentName: $agentName, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('state: $state, ')
          ..write('pauseReason: $pauseReason, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('createdAtMillis: $createdAtMillis, ')
          ..write('updatedAtMillis: $updatedAtMillis, ')
          ..write('sendingStartedAtMillis: $sendingStartedAtMillis, ')
          ..write('acknowledgedAtMillis: $acknowledgedAtMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverProfileId,
    sessionId,
    directory,
    position,
    promptText,
    operationType,
    commandName,
    attachmentsJson,
    modelProviderId,
    modelId,
    agentName,
    reasoningEffort,
    state,
    pauseReason,
    attemptCount,
    createdAtMillis,
    updatedAtMillis,
    sendingStartedAtMillis,
    acknowledgedAtMillis,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueuedPrompt &&
          other.id == this.id &&
          other.serverProfileId == this.serverProfileId &&
          other.sessionId == this.sessionId &&
          other.directory == this.directory &&
          other.position == this.position &&
          other.promptText == this.promptText &&
          other.operationType == this.operationType &&
          other.commandName == this.commandName &&
          other.attachmentsJson == this.attachmentsJson &&
          other.modelProviderId == this.modelProviderId &&
          other.modelId == this.modelId &&
          other.agentName == this.agentName &&
          other.reasoningEffort == this.reasoningEffort &&
          other.state == this.state &&
          other.pauseReason == this.pauseReason &&
          other.attemptCount == this.attemptCount &&
          other.createdAtMillis == this.createdAtMillis &&
          other.updatedAtMillis == this.updatedAtMillis &&
          other.sendingStartedAtMillis == this.sendingStartedAtMillis &&
          other.acknowledgedAtMillis == this.acknowledgedAtMillis);
}

class QueuedPromptsCompanion extends UpdateCompanion<QueuedPrompt> {
  final Value<String> id;
  final Value<String> serverProfileId;
  final Value<String> sessionId;
  final Value<String> directory;
  final Value<int> position;
  final Value<String> promptText;
  final Value<String> operationType;
  final Value<String?> commandName;
  final Value<String?> attachmentsJson;
  final Value<String?> modelProviderId;
  final Value<String?> modelId;
  final Value<String?> agentName;
  final Value<String?> reasoningEffort;
  final Value<String> state;
  final Value<String?> pauseReason;
  final Value<int> attemptCount;
  final Value<int> createdAtMillis;
  final Value<int> updatedAtMillis;
  final Value<int?> sendingStartedAtMillis;
  final Value<int?> acknowledgedAtMillis;
  final Value<int> rowid;
  const QueuedPromptsCompanion({
    this.id = const Value.absent(),
    this.serverProfileId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.directory = const Value.absent(),
    this.position = const Value.absent(),
    this.promptText = const Value.absent(),
    this.operationType = const Value.absent(),
    this.commandName = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.modelProviderId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.agentName = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
    this.state = const Value.absent(),
    this.pauseReason = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.createdAtMillis = const Value.absent(),
    this.updatedAtMillis = const Value.absent(),
    this.sendingStartedAtMillis = const Value.absent(),
    this.acknowledgedAtMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueuedPromptsCompanion.insert({
    required String id,
    required String serverProfileId,
    required String sessionId,
    required String directory,
    required int position,
    required String promptText,
    this.operationType = const Value.absent(),
    this.commandName = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.modelProviderId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.agentName = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
    required String state,
    this.pauseReason = const Value.absent(),
    this.attemptCount = const Value.absent(),
    required int createdAtMillis,
    required int updatedAtMillis,
    this.sendingStartedAtMillis = const Value.absent(),
    this.acknowledgedAtMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       serverProfileId = Value(serverProfileId),
       sessionId = Value(sessionId),
       directory = Value(directory),
       position = Value(position),
       promptText = Value(promptText),
       state = Value(state),
       createdAtMillis = Value(createdAtMillis),
       updatedAtMillis = Value(updatedAtMillis);
  static Insertable<QueuedPrompt> custom({
    Expression<String>? id,
    Expression<String>? serverProfileId,
    Expression<String>? sessionId,
    Expression<String>? directory,
    Expression<int>? position,
    Expression<String>? promptText,
    Expression<String>? operationType,
    Expression<String>? commandName,
    Expression<String>? attachmentsJson,
    Expression<String>? modelProviderId,
    Expression<String>? modelId,
    Expression<String>? agentName,
    Expression<String>? reasoningEffort,
    Expression<String>? state,
    Expression<String>? pauseReason,
    Expression<int>? attemptCount,
    Expression<int>? createdAtMillis,
    Expression<int>? updatedAtMillis,
    Expression<int>? sendingStartedAtMillis,
    Expression<int>? acknowledgedAtMillis,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverProfileId != null) 'server_profile_id': serverProfileId,
      if (sessionId != null) 'session_id': sessionId,
      if (directory != null) 'directory': directory,
      if (position != null) 'position': position,
      if (promptText != null) 'prompt_text': promptText,
      if (operationType != null) 'operation_type': operationType,
      if (commandName != null) 'command_name': commandName,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (modelProviderId != null) 'model_provider_id': modelProviderId,
      if (modelId != null) 'model_id': modelId,
      if (agentName != null) 'agent_name': agentName,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (state != null) 'state': state,
      if (pauseReason != null) 'pause_reason': pauseReason,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (createdAtMillis != null) 'created_at_millis': createdAtMillis,
      if (updatedAtMillis != null) 'updated_at_millis': updatedAtMillis,
      if (sendingStartedAtMillis != null)
        'sending_started_at_millis': sendingStartedAtMillis,
      if (acknowledgedAtMillis != null)
        'acknowledged_at_millis': acknowledgedAtMillis,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueuedPromptsCompanion copyWith({
    Value<String>? id,
    Value<String>? serverProfileId,
    Value<String>? sessionId,
    Value<String>? directory,
    Value<int>? position,
    Value<String>? promptText,
    Value<String>? operationType,
    Value<String?>? commandName,
    Value<String?>? attachmentsJson,
    Value<String?>? modelProviderId,
    Value<String?>? modelId,
    Value<String?>? agentName,
    Value<String?>? reasoningEffort,
    Value<String>? state,
    Value<String?>? pauseReason,
    Value<int>? attemptCount,
    Value<int>? createdAtMillis,
    Value<int>? updatedAtMillis,
    Value<int?>? sendingStartedAtMillis,
    Value<int?>? acknowledgedAtMillis,
    Value<int>? rowid,
  }) {
    return QueuedPromptsCompanion(
      id: id ?? this.id,
      serverProfileId: serverProfileId ?? this.serverProfileId,
      sessionId: sessionId ?? this.sessionId,
      directory: directory ?? this.directory,
      position: position ?? this.position,
      promptText: promptText ?? this.promptText,
      operationType: operationType ?? this.operationType,
      commandName: commandName ?? this.commandName,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      modelProviderId: modelProviderId ?? this.modelProviderId,
      modelId: modelId ?? this.modelId,
      agentName: agentName ?? this.agentName,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      state: state ?? this.state,
      pauseReason: pauseReason ?? this.pauseReason,
      attemptCount: attemptCount ?? this.attemptCount,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      sendingStartedAtMillis:
          sendingStartedAtMillis ?? this.sendingStartedAtMillis,
      acknowledgedAtMillis: acknowledgedAtMillis ?? this.acknowledgedAtMillis,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverProfileId.present) {
      map['server_profile_id'] = Variable<String>(serverProfileId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (promptText.present) {
      map['prompt_text'] = Variable<String>(promptText.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (commandName.present) {
      map['command_name'] = Variable<String>(commandName.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (modelProviderId.present) {
      map['model_provider_id'] = Variable<String>(modelProviderId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (reasoningEffort.present) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (pauseReason.present) {
      map['pause_reason'] = Variable<String>(pauseReason.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (createdAtMillis.present) {
      map['created_at_millis'] = Variable<int>(createdAtMillis.value);
    }
    if (updatedAtMillis.present) {
      map['updated_at_millis'] = Variable<int>(updatedAtMillis.value);
    }
    if (sendingStartedAtMillis.present) {
      map['sending_started_at_millis'] = Variable<int>(
        sendingStartedAtMillis.value,
      );
    }
    if (acknowledgedAtMillis.present) {
      map['acknowledged_at_millis'] = Variable<int>(acknowledgedAtMillis.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueuedPromptsCompanion(')
          ..write('id: $id, ')
          ..write('serverProfileId: $serverProfileId, ')
          ..write('sessionId: $sessionId, ')
          ..write('directory: $directory, ')
          ..write('position: $position, ')
          ..write('promptText: $promptText, ')
          ..write('operationType: $operationType, ')
          ..write('commandName: $commandName, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('modelProviderId: $modelProviderId, ')
          ..write('modelId: $modelId, ')
          ..write('agentName: $agentName, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('state: $state, ')
          ..write('pauseReason: $pauseReason, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('createdAtMillis: $createdAtMillis, ')
          ..write('updatedAtMillis: $updatedAtMillis, ')
          ..write('sendingStartedAtMillis: $sendingStartedAtMillis, ')
          ..write('acknowledgedAtMillis: $acknowledgedAtMillis, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewRunsTable extends ReviewRuns
    with TableInfo<$ReviewRunsTable, ReviewRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverProfileIdMeta = const VerificationMeta(
    'serverProfileId',
  );
  @override
  late final GeneratedColumn<String> serverProfileId = GeneratedColumn<String>(
    'server_profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES server_profiles (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMillisMeta = const VerificationMeta(
    'createdAtMillis',
  );
  @override
  late final GeneratedColumn<int> createdAtMillis = GeneratedColumn<int>(
    'created_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMillisMeta = const VerificationMeta(
    'completedAtMillis',
  );
  @override
  late final GeneratedColumn<int> completedAtMillis = GeneratedColumn<int>(
    'completed_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorTypeMeta = const VerificationMeta(
    'errorType',
  );
  @override
  late final GeneratedColumn<String> errorType = GeneratedColumn<String>(
    'error_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileOriginMeta = const VerificationMeta(
    'profileOrigin',
  );
  @override
  late final GeneratedColumn<String> profileOrigin = GeneratedColumn<String>(
    'profile_origin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileUsernameMeta = const VerificationMeta(
    'profileUsername',
  );
  @override
  late final GeneratedColumn<String> profileUsername = GeneratedColumn<String>(
    'profile_username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionCreatedAtMillisMeta =
      const VerificationMeta('sessionCreatedAtMillis');
  @override
  late final GeneratedColumn<int> sessionCreatedAtMillis = GeneratedColumn<int>(
    'session_created_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionUpdatedAtMillisMeta =
      const VerificationMeta('sessionUpdatedAtMillis');
  @override
  late final GeneratedColumn<int> sessionUpdatedAtMillis = GeneratedColumn<int>(
    'session_updated_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changedFilesMeta = const VerificationMeta(
    'changedFiles',
  );
  @override
  late final GeneratedColumn<int> changedFiles = GeneratedColumn<int>(
    'changed_files',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _additionsMeta = const VerificationMeta(
    'additions',
  );
  @override
  late final GeneratedColumn<int> additions = GeneratedColumn<int>(
    'additions',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletionsMeta = const VerificationMeta(
    'deletions',
  );
  @override
  late final GeneratedColumn<int> deletions = GeneratedColumn<int>(
    'deletions',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shareUrlMeta = const VerificationMeta(
    'shareUrl',
  );
  @override
  late final GeneratedColumn<String> shareUrl = GeneratedColumn<String>(
    'share_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelProviderIdMeta = const VerificationMeta(
    'modelProviderId',
  );
  @override
  late final GeneratedColumn<String> modelProviderId = GeneratedColumn<String>(
    'model_provider_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverProfileId,
    sessionId,
    createdAtMillis,
    completedAtMillis,
    state,
    errorType,
    errorMessage,
    projectId,
    directory,
    title,
    profileOrigin,
    profileUsername,
    sessionCreatedAtMillis,
    sessionUpdatedAtMillis,
    parentId,
    changedFiles,
    additions,
    deletions,
    shareUrl,
    modelProviderId,
    modelId,
    agentName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_profile_id')) {
      context.handle(
        _serverProfileIdMeta,
        serverProfileId.isAcceptableOrUnknown(
          data['server_profile_id']!,
          _serverProfileIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverProfileIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('created_at_millis')) {
      context.handle(
        _createdAtMillisMeta,
        createdAtMillis.isAcceptableOrUnknown(
          data['created_at_millis']!,
          _createdAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMillisMeta);
    }
    if (data.containsKey('completed_at_millis')) {
      context.handle(
        _completedAtMillisMeta,
        completedAtMillis.isAcceptableOrUnknown(
          data['completed_at_millis']!,
          _completedAtMillisMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('error_type')) {
      context.handle(
        _errorTypeMeta,
        errorType.isAcceptableOrUnknown(data['error_type']!, _errorTypeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('profile_origin')) {
      context.handle(
        _profileOriginMeta,
        profileOrigin.isAcceptableOrUnknown(
          data['profile_origin']!,
          _profileOriginMeta,
        ),
      );
    }
    if (data.containsKey('profile_username')) {
      context.handle(
        _profileUsernameMeta,
        profileUsername.isAcceptableOrUnknown(
          data['profile_username']!,
          _profileUsernameMeta,
        ),
      );
    }
    if (data.containsKey('session_created_at_millis')) {
      context.handle(
        _sessionCreatedAtMillisMeta,
        sessionCreatedAtMillis.isAcceptableOrUnknown(
          data['session_created_at_millis']!,
          _sessionCreatedAtMillisMeta,
        ),
      );
    }
    if (data.containsKey('session_updated_at_millis')) {
      context.handle(
        _sessionUpdatedAtMillisMeta,
        sessionUpdatedAtMillis.isAcceptableOrUnknown(
          data['session_updated_at_millis']!,
          _sessionUpdatedAtMillisMeta,
        ),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('changed_files')) {
      context.handle(
        _changedFilesMeta,
        changedFiles.isAcceptableOrUnknown(
          data['changed_files']!,
          _changedFilesMeta,
        ),
      );
    }
    if (data.containsKey('additions')) {
      context.handle(
        _additionsMeta,
        additions.isAcceptableOrUnknown(data['additions']!, _additionsMeta),
      );
    }
    if (data.containsKey('deletions')) {
      context.handle(
        _deletionsMeta,
        deletions.isAcceptableOrUnknown(data['deletions']!, _deletionsMeta),
      );
    }
    if (data.containsKey('share_url')) {
      context.handle(
        _shareUrlMeta,
        shareUrl.isAcceptableOrUnknown(data['share_url']!, _shareUrlMeta),
      );
    }
    if (data.containsKey('model_provider_id')) {
      context.handle(
        _modelProviderIdMeta,
        modelProviderId.isAcceptableOrUnknown(
          data['model_provider_id']!,
          _modelProviderIdMeta,
        ),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_profile_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      createdAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_millis'],
      )!,
      completedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_millis'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      errorType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_type'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      profileOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_origin'],
      ),
      profileUsername: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_username'],
      ),
      sessionCreatedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_created_at_millis'],
      ),
      sessionUpdatedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_updated_at_millis'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      changedFiles: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}changed_files'],
      ),
      additions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}additions'],
      ),
      deletions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deletions'],
      ),
      shareUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}share_url'],
      ),
      modelProviderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_provider_id'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      ),
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      ),
    );
  }

  @override
  $ReviewRunsTable createAlias(String alias) {
    return $ReviewRunsTable(attachedDatabase, alias);
  }
}

class ReviewRun extends DataClass implements Insertable<ReviewRun> {
  final String id;
  final String serverProfileId;
  final String sessionId;
  final int createdAtMillis;
  final int? completedAtMillis;
  final String state;
  final String? errorType;
  final String? errorMessage;
  final String? projectId;
  final String? directory;
  final String? title;
  final String? profileOrigin;
  final String? profileUsername;
  final int? sessionCreatedAtMillis;
  final int? sessionUpdatedAtMillis;
  final String? parentId;
  final int? changedFiles;
  final int? additions;
  final int? deletions;
  final String? shareUrl;
  final String? modelProviderId;
  final String? modelId;
  final String? agentName;
  const ReviewRun({
    required this.id,
    required this.serverProfileId,
    required this.sessionId,
    required this.createdAtMillis,
    this.completedAtMillis,
    required this.state,
    this.errorType,
    this.errorMessage,
    this.projectId,
    this.directory,
    this.title,
    this.profileOrigin,
    this.profileUsername,
    this.sessionCreatedAtMillis,
    this.sessionUpdatedAtMillis,
    this.parentId,
    this.changedFiles,
    this.additions,
    this.deletions,
    this.shareUrl,
    this.modelProviderId,
    this.modelId,
    this.agentName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['server_profile_id'] = Variable<String>(serverProfileId);
    map['session_id'] = Variable<String>(sessionId);
    map['created_at_millis'] = Variable<int>(createdAtMillis);
    if (!nullToAbsent || completedAtMillis != null) {
      map['completed_at_millis'] = Variable<int>(completedAtMillis);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || errorType != null) {
      map['error_type'] = Variable<String>(errorType);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || directory != null) {
      map['directory'] = Variable<String>(directory);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || profileOrigin != null) {
      map['profile_origin'] = Variable<String>(profileOrigin);
    }
    if (!nullToAbsent || profileUsername != null) {
      map['profile_username'] = Variable<String>(profileUsername);
    }
    if (!nullToAbsent || sessionCreatedAtMillis != null) {
      map['session_created_at_millis'] = Variable<int>(sessionCreatedAtMillis);
    }
    if (!nullToAbsent || sessionUpdatedAtMillis != null) {
      map['session_updated_at_millis'] = Variable<int>(sessionUpdatedAtMillis);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || changedFiles != null) {
      map['changed_files'] = Variable<int>(changedFiles);
    }
    if (!nullToAbsent || additions != null) {
      map['additions'] = Variable<int>(additions);
    }
    if (!nullToAbsent || deletions != null) {
      map['deletions'] = Variable<int>(deletions);
    }
    if (!nullToAbsent || shareUrl != null) {
      map['share_url'] = Variable<String>(shareUrl);
    }
    if (!nullToAbsent || modelProviderId != null) {
      map['model_provider_id'] = Variable<String>(modelProviderId);
    }
    if (!nullToAbsent || modelId != null) {
      map['model_id'] = Variable<String>(modelId);
    }
    if (!nullToAbsent || agentName != null) {
      map['agent_name'] = Variable<String>(agentName);
    }
    return map;
  }

  ReviewRunsCompanion toCompanion(bool nullToAbsent) {
    return ReviewRunsCompanion(
      id: Value(id),
      serverProfileId: Value(serverProfileId),
      sessionId: Value(sessionId),
      createdAtMillis: Value(createdAtMillis),
      completedAtMillis: completedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtMillis),
      state: Value(state),
      errorType: errorType == null && nullToAbsent
          ? const Value.absent()
          : Value(errorType),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      directory: directory == null && nullToAbsent
          ? const Value.absent()
          : Value(directory),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      profileOrigin: profileOrigin == null && nullToAbsent
          ? const Value.absent()
          : Value(profileOrigin),
      profileUsername: profileUsername == null && nullToAbsent
          ? const Value.absent()
          : Value(profileUsername),
      sessionCreatedAtMillis: sessionCreatedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionCreatedAtMillis),
      sessionUpdatedAtMillis: sessionUpdatedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionUpdatedAtMillis),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      changedFiles: changedFiles == null && nullToAbsent
          ? const Value.absent()
          : Value(changedFiles),
      additions: additions == null && nullToAbsent
          ? const Value.absent()
          : Value(additions),
      deletions: deletions == null && nullToAbsent
          ? const Value.absent()
          : Value(deletions),
      shareUrl: shareUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(shareUrl),
      modelProviderId: modelProviderId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelProviderId),
      modelId: modelId == null && nullToAbsent
          ? const Value.absent()
          : Value(modelId),
      agentName: agentName == null && nullToAbsent
          ? const Value.absent()
          : Value(agentName),
    );
  }

  factory ReviewRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewRun(
      id: serializer.fromJson<String>(json['id']),
      serverProfileId: serializer.fromJson<String>(json['serverProfileId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      createdAtMillis: serializer.fromJson<int>(json['createdAtMillis']),
      completedAtMillis: serializer.fromJson<int?>(json['completedAtMillis']),
      state: serializer.fromJson<String>(json['state']),
      errorType: serializer.fromJson<String?>(json['errorType']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      directory: serializer.fromJson<String?>(json['directory']),
      title: serializer.fromJson<String?>(json['title']),
      profileOrigin: serializer.fromJson<String?>(json['profileOrigin']),
      profileUsername: serializer.fromJson<String?>(json['profileUsername']),
      sessionCreatedAtMillis: serializer.fromJson<int?>(
        json['sessionCreatedAtMillis'],
      ),
      sessionUpdatedAtMillis: serializer.fromJson<int?>(
        json['sessionUpdatedAtMillis'],
      ),
      parentId: serializer.fromJson<String?>(json['parentId']),
      changedFiles: serializer.fromJson<int?>(json['changedFiles']),
      additions: serializer.fromJson<int?>(json['additions']),
      deletions: serializer.fromJson<int?>(json['deletions']),
      shareUrl: serializer.fromJson<String?>(json['shareUrl']),
      modelProviderId: serializer.fromJson<String?>(json['modelProviderId']),
      modelId: serializer.fromJson<String?>(json['modelId']),
      agentName: serializer.fromJson<String?>(json['agentName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverProfileId': serializer.toJson<String>(serverProfileId),
      'sessionId': serializer.toJson<String>(sessionId),
      'createdAtMillis': serializer.toJson<int>(createdAtMillis),
      'completedAtMillis': serializer.toJson<int?>(completedAtMillis),
      'state': serializer.toJson<String>(state),
      'errorType': serializer.toJson<String?>(errorType),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'projectId': serializer.toJson<String?>(projectId),
      'directory': serializer.toJson<String?>(directory),
      'title': serializer.toJson<String?>(title),
      'profileOrigin': serializer.toJson<String?>(profileOrigin),
      'profileUsername': serializer.toJson<String?>(profileUsername),
      'sessionCreatedAtMillis': serializer.toJson<int?>(sessionCreatedAtMillis),
      'sessionUpdatedAtMillis': serializer.toJson<int?>(sessionUpdatedAtMillis),
      'parentId': serializer.toJson<String?>(parentId),
      'changedFiles': serializer.toJson<int?>(changedFiles),
      'additions': serializer.toJson<int?>(additions),
      'deletions': serializer.toJson<int?>(deletions),
      'shareUrl': serializer.toJson<String?>(shareUrl),
      'modelProviderId': serializer.toJson<String?>(modelProviderId),
      'modelId': serializer.toJson<String?>(modelId),
      'agentName': serializer.toJson<String?>(agentName),
    };
  }

  ReviewRun copyWith({
    String? id,
    String? serverProfileId,
    String? sessionId,
    int? createdAtMillis,
    Value<int?> completedAtMillis = const Value.absent(),
    String? state,
    Value<String?> errorType = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    Value<String?> projectId = const Value.absent(),
    Value<String?> directory = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> profileOrigin = const Value.absent(),
    Value<String?> profileUsername = const Value.absent(),
    Value<int?> sessionCreatedAtMillis = const Value.absent(),
    Value<int?> sessionUpdatedAtMillis = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    Value<int?> changedFiles = const Value.absent(),
    Value<int?> additions = const Value.absent(),
    Value<int?> deletions = const Value.absent(),
    Value<String?> shareUrl = const Value.absent(),
    Value<String?> modelProviderId = const Value.absent(),
    Value<String?> modelId = const Value.absent(),
    Value<String?> agentName = const Value.absent(),
  }) => ReviewRun(
    id: id ?? this.id,
    serverProfileId: serverProfileId ?? this.serverProfileId,
    sessionId: sessionId ?? this.sessionId,
    createdAtMillis: createdAtMillis ?? this.createdAtMillis,
    completedAtMillis: completedAtMillis.present
        ? completedAtMillis.value
        : this.completedAtMillis,
    state: state ?? this.state,
    errorType: errorType.present ? errorType.value : this.errorType,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    projectId: projectId.present ? projectId.value : this.projectId,
    directory: directory.present ? directory.value : this.directory,
    title: title.present ? title.value : this.title,
    profileOrigin: profileOrigin.present
        ? profileOrigin.value
        : this.profileOrigin,
    profileUsername: profileUsername.present
        ? profileUsername.value
        : this.profileUsername,
    sessionCreatedAtMillis: sessionCreatedAtMillis.present
        ? sessionCreatedAtMillis.value
        : this.sessionCreatedAtMillis,
    sessionUpdatedAtMillis: sessionUpdatedAtMillis.present
        ? sessionUpdatedAtMillis.value
        : this.sessionUpdatedAtMillis,
    parentId: parentId.present ? parentId.value : this.parentId,
    changedFiles: changedFiles.present ? changedFiles.value : this.changedFiles,
    additions: additions.present ? additions.value : this.additions,
    deletions: deletions.present ? deletions.value : this.deletions,
    shareUrl: shareUrl.present ? shareUrl.value : this.shareUrl,
    modelProviderId: modelProviderId.present
        ? modelProviderId.value
        : this.modelProviderId,
    modelId: modelId.present ? modelId.value : this.modelId,
    agentName: agentName.present ? agentName.value : this.agentName,
  );
  ReviewRun copyWithCompanion(ReviewRunsCompanion data) {
    return ReviewRun(
      id: data.id.present ? data.id.value : this.id,
      serverProfileId: data.serverProfileId.present
          ? data.serverProfileId.value
          : this.serverProfileId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      createdAtMillis: data.createdAtMillis.present
          ? data.createdAtMillis.value
          : this.createdAtMillis,
      completedAtMillis: data.completedAtMillis.present
          ? data.completedAtMillis.value
          : this.completedAtMillis,
      state: data.state.present ? data.state.value : this.state,
      errorType: data.errorType.present ? data.errorType.value : this.errorType,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      directory: data.directory.present ? data.directory.value : this.directory,
      title: data.title.present ? data.title.value : this.title,
      profileOrigin: data.profileOrigin.present
          ? data.profileOrigin.value
          : this.profileOrigin,
      profileUsername: data.profileUsername.present
          ? data.profileUsername.value
          : this.profileUsername,
      sessionCreatedAtMillis: data.sessionCreatedAtMillis.present
          ? data.sessionCreatedAtMillis.value
          : this.sessionCreatedAtMillis,
      sessionUpdatedAtMillis: data.sessionUpdatedAtMillis.present
          ? data.sessionUpdatedAtMillis.value
          : this.sessionUpdatedAtMillis,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      changedFiles: data.changedFiles.present
          ? data.changedFiles.value
          : this.changedFiles,
      additions: data.additions.present ? data.additions.value : this.additions,
      deletions: data.deletions.present ? data.deletions.value : this.deletions,
      shareUrl: data.shareUrl.present ? data.shareUrl.value : this.shareUrl,
      modelProviderId: data.modelProviderId.present
          ? data.modelProviderId.value
          : this.modelProviderId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewRun(')
          ..write('id: $id, ')
          ..write('serverProfileId: $serverProfileId, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAtMillis: $createdAtMillis, ')
          ..write('completedAtMillis: $completedAtMillis, ')
          ..write('state: $state, ')
          ..write('errorType: $errorType, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('projectId: $projectId, ')
          ..write('directory: $directory, ')
          ..write('title: $title, ')
          ..write('profileOrigin: $profileOrigin, ')
          ..write('profileUsername: $profileUsername, ')
          ..write('sessionCreatedAtMillis: $sessionCreatedAtMillis, ')
          ..write('sessionUpdatedAtMillis: $sessionUpdatedAtMillis, ')
          ..write('parentId: $parentId, ')
          ..write('changedFiles: $changedFiles, ')
          ..write('additions: $additions, ')
          ..write('deletions: $deletions, ')
          ..write('shareUrl: $shareUrl, ')
          ..write('modelProviderId: $modelProviderId, ')
          ..write('modelId: $modelId, ')
          ..write('agentName: $agentName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    serverProfileId,
    sessionId,
    createdAtMillis,
    completedAtMillis,
    state,
    errorType,
    errorMessage,
    projectId,
    directory,
    title,
    profileOrigin,
    profileUsername,
    sessionCreatedAtMillis,
    sessionUpdatedAtMillis,
    parentId,
    changedFiles,
    additions,
    deletions,
    shareUrl,
    modelProviderId,
    modelId,
    agentName,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewRun &&
          other.id == this.id &&
          other.serverProfileId == this.serverProfileId &&
          other.sessionId == this.sessionId &&
          other.createdAtMillis == this.createdAtMillis &&
          other.completedAtMillis == this.completedAtMillis &&
          other.state == this.state &&
          other.errorType == this.errorType &&
          other.errorMessage == this.errorMessage &&
          other.projectId == this.projectId &&
          other.directory == this.directory &&
          other.title == this.title &&
          other.profileOrigin == this.profileOrigin &&
          other.profileUsername == this.profileUsername &&
          other.sessionCreatedAtMillis == this.sessionCreatedAtMillis &&
          other.sessionUpdatedAtMillis == this.sessionUpdatedAtMillis &&
          other.parentId == this.parentId &&
          other.changedFiles == this.changedFiles &&
          other.additions == this.additions &&
          other.deletions == this.deletions &&
          other.shareUrl == this.shareUrl &&
          other.modelProviderId == this.modelProviderId &&
          other.modelId == this.modelId &&
          other.agentName == this.agentName);
}

class ReviewRunsCompanion extends UpdateCompanion<ReviewRun> {
  final Value<String> id;
  final Value<String> serverProfileId;
  final Value<String> sessionId;
  final Value<int> createdAtMillis;
  final Value<int?> completedAtMillis;
  final Value<String> state;
  final Value<String?> errorType;
  final Value<String?> errorMessage;
  final Value<String?> projectId;
  final Value<String?> directory;
  final Value<String?> title;
  final Value<String?> profileOrigin;
  final Value<String?> profileUsername;
  final Value<int?> sessionCreatedAtMillis;
  final Value<int?> sessionUpdatedAtMillis;
  final Value<String?> parentId;
  final Value<int?> changedFiles;
  final Value<int?> additions;
  final Value<int?> deletions;
  final Value<String?> shareUrl;
  final Value<String?> modelProviderId;
  final Value<String?> modelId;
  final Value<String?> agentName;
  final Value<int> rowid;
  const ReviewRunsCompanion({
    this.id = const Value.absent(),
    this.serverProfileId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.createdAtMillis = const Value.absent(),
    this.completedAtMillis = const Value.absent(),
    this.state = const Value.absent(),
    this.errorType = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.projectId = const Value.absent(),
    this.directory = const Value.absent(),
    this.title = const Value.absent(),
    this.profileOrigin = const Value.absent(),
    this.profileUsername = const Value.absent(),
    this.sessionCreatedAtMillis = const Value.absent(),
    this.sessionUpdatedAtMillis = const Value.absent(),
    this.parentId = const Value.absent(),
    this.changedFiles = const Value.absent(),
    this.additions = const Value.absent(),
    this.deletions = const Value.absent(),
    this.shareUrl = const Value.absent(),
    this.modelProviderId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.agentName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewRunsCompanion.insert({
    required String id,
    required String serverProfileId,
    required String sessionId,
    required int createdAtMillis,
    this.completedAtMillis = const Value.absent(),
    required String state,
    this.errorType = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.projectId = const Value.absent(),
    this.directory = const Value.absent(),
    this.title = const Value.absent(),
    this.profileOrigin = const Value.absent(),
    this.profileUsername = const Value.absent(),
    this.sessionCreatedAtMillis = const Value.absent(),
    this.sessionUpdatedAtMillis = const Value.absent(),
    this.parentId = const Value.absent(),
    this.changedFiles = const Value.absent(),
    this.additions = const Value.absent(),
    this.deletions = const Value.absent(),
    this.shareUrl = const Value.absent(),
    this.modelProviderId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.agentName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       serverProfileId = Value(serverProfileId),
       sessionId = Value(sessionId),
       createdAtMillis = Value(createdAtMillis),
       state = Value(state);
  static Insertable<ReviewRun> custom({
    Expression<String>? id,
    Expression<String>? serverProfileId,
    Expression<String>? sessionId,
    Expression<int>? createdAtMillis,
    Expression<int>? completedAtMillis,
    Expression<String>? state,
    Expression<String>? errorType,
    Expression<String>? errorMessage,
    Expression<String>? projectId,
    Expression<String>? directory,
    Expression<String>? title,
    Expression<String>? profileOrigin,
    Expression<String>? profileUsername,
    Expression<int>? sessionCreatedAtMillis,
    Expression<int>? sessionUpdatedAtMillis,
    Expression<String>? parentId,
    Expression<int>? changedFiles,
    Expression<int>? additions,
    Expression<int>? deletions,
    Expression<String>? shareUrl,
    Expression<String>? modelProviderId,
    Expression<String>? modelId,
    Expression<String>? agentName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverProfileId != null) 'server_profile_id': serverProfileId,
      if (sessionId != null) 'session_id': sessionId,
      if (createdAtMillis != null) 'created_at_millis': createdAtMillis,
      if (completedAtMillis != null) 'completed_at_millis': completedAtMillis,
      if (state != null) 'state': state,
      if (errorType != null) 'error_type': errorType,
      if (errorMessage != null) 'error_message': errorMessage,
      if (projectId != null) 'project_id': projectId,
      if (directory != null) 'directory': directory,
      if (title != null) 'title': title,
      if (profileOrigin != null) 'profile_origin': profileOrigin,
      if (profileUsername != null) 'profile_username': profileUsername,
      if (sessionCreatedAtMillis != null)
        'session_created_at_millis': sessionCreatedAtMillis,
      if (sessionUpdatedAtMillis != null)
        'session_updated_at_millis': sessionUpdatedAtMillis,
      if (parentId != null) 'parent_id': parentId,
      if (changedFiles != null) 'changed_files': changedFiles,
      if (additions != null) 'additions': additions,
      if (deletions != null) 'deletions': deletions,
      if (shareUrl != null) 'share_url': shareUrl,
      if (modelProviderId != null) 'model_provider_id': modelProviderId,
      if (modelId != null) 'model_id': modelId,
      if (agentName != null) 'agent_name': agentName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewRunsCompanion copyWith({
    Value<String>? id,
    Value<String>? serverProfileId,
    Value<String>? sessionId,
    Value<int>? createdAtMillis,
    Value<int?>? completedAtMillis,
    Value<String>? state,
    Value<String?>? errorType,
    Value<String?>? errorMessage,
    Value<String?>? projectId,
    Value<String?>? directory,
    Value<String?>? title,
    Value<String?>? profileOrigin,
    Value<String?>? profileUsername,
    Value<int?>? sessionCreatedAtMillis,
    Value<int?>? sessionUpdatedAtMillis,
    Value<String?>? parentId,
    Value<int?>? changedFiles,
    Value<int?>? additions,
    Value<int?>? deletions,
    Value<String?>? shareUrl,
    Value<String?>? modelProviderId,
    Value<String?>? modelId,
    Value<String?>? agentName,
    Value<int>? rowid,
  }) {
    return ReviewRunsCompanion(
      id: id ?? this.id,
      serverProfileId: serverProfileId ?? this.serverProfileId,
      sessionId: sessionId ?? this.sessionId,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      completedAtMillis: completedAtMillis ?? this.completedAtMillis,
      state: state ?? this.state,
      errorType: errorType ?? this.errorType,
      errorMessage: errorMessage ?? this.errorMessage,
      projectId: projectId ?? this.projectId,
      directory: directory ?? this.directory,
      title: title ?? this.title,
      profileOrigin: profileOrigin ?? this.profileOrigin,
      profileUsername: profileUsername ?? this.profileUsername,
      sessionCreatedAtMillis:
          sessionCreatedAtMillis ?? this.sessionCreatedAtMillis,
      sessionUpdatedAtMillis:
          sessionUpdatedAtMillis ?? this.sessionUpdatedAtMillis,
      parentId: parentId ?? this.parentId,
      changedFiles: changedFiles ?? this.changedFiles,
      additions: additions ?? this.additions,
      deletions: deletions ?? this.deletions,
      shareUrl: shareUrl ?? this.shareUrl,
      modelProviderId: modelProviderId ?? this.modelProviderId,
      modelId: modelId ?? this.modelId,
      agentName: agentName ?? this.agentName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverProfileId.present) {
      map['server_profile_id'] = Variable<String>(serverProfileId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (createdAtMillis.present) {
      map['created_at_millis'] = Variable<int>(createdAtMillis.value);
    }
    if (completedAtMillis.present) {
      map['completed_at_millis'] = Variable<int>(completedAtMillis.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (errorType.present) {
      map['error_type'] = Variable<String>(errorType.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (profileOrigin.present) {
      map['profile_origin'] = Variable<String>(profileOrigin.value);
    }
    if (profileUsername.present) {
      map['profile_username'] = Variable<String>(profileUsername.value);
    }
    if (sessionCreatedAtMillis.present) {
      map['session_created_at_millis'] = Variable<int>(
        sessionCreatedAtMillis.value,
      );
    }
    if (sessionUpdatedAtMillis.present) {
      map['session_updated_at_millis'] = Variable<int>(
        sessionUpdatedAtMillis.value,
      );
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (changedFiles.present) {
      map['changed_files'] = Variable<int>(changedFiles.value);
    }
    if (additions.present) {
      map['additions'] = Variable<int>(additions.value);
    }
    if (deletions.present) {
      map['deletions'] = Variable<int>(deletions.value);
    }
    if (shareUrl.present) {
      map['share_url'] = Variable<String>(shareUrl.value);
    }
    if (modelProviderId.present) {
      map['model_provider_id'] = Variable<String>(modelProviderId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewRunsCompanion(')
          ..write('id: $id, ')
          ..write('serverProfileId: $serverProfileId, ')
          ..write('sessionId: $sessionId, ')
          ..write('createdAtMillis: $createdAtMillis, ')
          ..write('completedAtMillis: $completedAtMillis, ')
          ..write('state: $state, ')
          ..write('errorType: $errorType, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('projectId: $projectId, ')
          ..write('directory: $directory, ')
          ..write('title: $title, ')
          ..write('profileOrigin: $profileOrigin, ')
          ..write('profileUsername: $profileUsername, ')
          ..write('sessionCreatedAtMillis: $sessionCreatedAtMillis, ')
          ..write('sessionUpdatedAtMillis: $sessionUpdatedAtMillis, ')
          ..write('parentId: $parentId, ')
          ..write('changedFiles: $changedFiles, ')
          ..write('additions: $additions, ')
          ..write('deletions: $deletions, ')
          ..write('shareUrl: $shareUrl, ')
          ..write('modelProviderId: $modelProviderId, ')
          ..write('modelId: $modelId, ')
          ..write('agentName: $agentName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewFilesTable extends ReviewFiles
    with TableInfo<$ReviewFilesTable, ReviewFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _reviewIdMeta = const VerificationMeta(
    'reviewId',
  );
  @override
  late final GeneratedColumn<String> reviewId = GeneratedColumn<String>(
    'review_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_runs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patchMeta = const VerificationMeta('patch');
  @override
  late final GeneratedColumn<String> patch = GeneratedColumn<String>(
    'patch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, reviewId, path, status, patch];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('review_id')) {
      context.handle(
        _reviewIdMeta,
        reviewId.isAcceptableOrUnknown(data['review_id']!, _reviewIdMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('patch')) {
      context.handle(
        _patchMeta,
        patch.isAcceptableOrUnknown(data['patch']!, _patchMeta),
      );
    } else if (isInserting) {
      context.missing(_patchMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewFile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      reviewId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      patch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patch'],
      )!,
    );
  }

  @override
  $ReviewFilesTable createAlias(String alias) {
    return $ReviewFilesTable(attachedDatabase, alias);
  }
}

class ReviewFile extends DataClass implements Insertable<ReviewFile> {
  final int id;
  final String reviewId;
  final String path;
  final String status;
  final String patch;
  const ReviewFile({
    required this.id,
    required this.reviewId,
    required this.path,
    required this.status,
    required this.patch,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['review_id'] = Variable<String>(reviewId);
    map['path'] = Variable<String>(path);
    map['status'] = Variable<String>(status);
    map['patch'] = Variable<String>(patch);
    return map;
  }

  ReviewFilesCompanion toCompanion(bool nullToAbsent) {
    return ReviewFilesCompanion(
      id: Value(id),
      reviewId: Value(reviewId),
      path: Value(path),
      status: Value(status),
      patch: Value(patch),
    );
  }

  factory ReviewFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewFile(
      id: serializer.fromJson<int>(json['id']),
      reviewId: serializer.fromJson<String>(json['reviewId']),
      path: serializer.fromJson<String>(json['path']),
      status: serializer.fromJson<String>(json['status']),
      patch: serializer.fromJson<String>(json['patch']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'reviewId': serializer.toJson<String>(reviewId),
      'path': serializer.toJson<String>(path),
      'status': serializer.toJson<String>(status),
      'patch': serializer.toJson<String>(patch),
    };
  }

  ReviewFile copyWith({
    int? id,
    String? reviewId,
    String? path,
    String? status,
    String? patch,
  }) => ReviewFile(
    id: id ?? this.id,
    reviewId: reviewId ?? this.reviewId,
    path: path ?? this.path,
    status: status ?? this.status,
    patch: patch ?? this.patch,
  );
  ReviewFile copyWithCompanion(ReviewFilesCompanion data) {
    return ReviewFile(
      id: data.id.present ? data.id.value : this.id,
      reviewId: data.reviewId.present ? data.reviewId.value : this.reviewId,
      path: data.path.present ? data.path.value : this.path,
      status: data.status.present ? data.status.value : this.status,
      patch: data.patch.present ? data.patch.value : this.patch,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewFile(')
          ..write('id: $id, ')
          ..write('reviewId: $reviewId, ')
          ..write('path: $path, ')
          ..write('status: $status, ')
          ..write('patch: $patch')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, reviewId, path, status, patch);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewFile &&
          other.id == this.id &&
          other.reviewId == this.reviewId &&
          other.path == this.path &&
          other.status == this.status &&
          other.patch == this.patch);
}

class ReviewFilesCompanion extends UpdateCompanion<ReviewFile> {
  final Value<int> id;
  final Value<String> reviewId;
  final Value<String> path;
  final Value<String> status;
  final Value<String> patch;
  const ReviewFilesCompanion({
    this.id = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.path = const Value.absent(),
    this.status = const Value.absent(),
    this.patch = const Value.absent(),
  });
  ReviewFilesCompanion.insert({
    this.id = const Value.absent(),
    required String reviewId,
    required String path,
    required String status,
    required String patch,
  }) : reviewId = Value(reviewId),
       path = Value(path),
       status = Value(status),
       patch = Value(patch);
  static Insertable<ReviewFile> custom({
    Expression<int>? id,
    Expression<String>? reviewId,
    Expression<String>? path,
    Expression<String>? status,
    Expression<String>? patch,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (reviewId != null) 'review_id': reviewId,
      if (path != null) 'path': path,
      if (status != null) 'status': status,
      if (patch != null) 'patch': patch,
    });
  }

  ReviewFilesCompanion copyWith({
    Value<int>? id,
    Value<String>? reviewId,
    Value<String>? path,
    Value<String>? status,
    Value<String>? patch,
  }) {
    return ReviewFilesCompanion(
      id: id ?? this.id,
      reviewId: reviewId ?? this.reviewId,
      path: path ?? this.path,
      status: status ?? this.status,
      patch: patch ?? this.patch,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (reviewId.present) {
      map['review_id'] = Variable<String>(reviewId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (patch.present) {
      map['patch'] = Variable<String>(patch.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewFilesCompanion(')
          ..write('id: $id, ')
          ..write('reviewId: $reviewId, ')
          ..write('path: $path, ')
          ..write('status: $status, ')
          ..write('patch: $patch')
          ..write(')'))
        .toString();
  }
}

class $ReviewPassesTable extends ReviewPasses
    with TableInfo<$ReviewPassesTable, ReviewPassesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewPassesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewIdMeta = const VerificationMeta(
    'reviewId',
  );
  @override
  late final GeneratedColumn<String> reviewId = GeneratedColumn<String>(
    'review_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_runs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _childSessionIdMeta = const VerificationMeta(
    'childSessionId',
  );
  @override
  late final GeneratedColumn<String> childSessionId = GeneratedColumn<String>(
    'child_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorTypeMeta = const VerificationMeta(
    'errorType',
  );
  @override
  late final GeneratedColumn<String> errorType = GeneratedColumn<String>(
    'error_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inputTokensMeta = const VerificationMeta(
    'inputTokens',
  );
  @override
  late final GeneratedColumn<int> inputTokens = GeneratedColumn<int>(
    'input_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputTokensMeta = const VerificationMeta(
    'outputTokens',
  );
  @override
  late final GeneratedColumn<int> outputTokens = GeneratedColumn<int>(
    'output_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasoningTokensMeta = const VerificationMeta(
    'reasoningTokens',
  );
  @override
  late final GeneratedColumn<int> reasoningTokens = GeneratedColumn<int>(
    'reasoning_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cacheTokensMeta = const VerificationMeta(
    'cacheTokens',
  );
  @override
  late final GeneratedColumn<int> cacheTokens = GeneratedColumn<int>(
    'cache_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costMeta = const VerificationMeta('cost');
  @override
  late final GeneratedColumn<double> cost = GeneratedColumn<double>(
    'cost',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMillisMeta = const VerificationMeta(
    'durationMillis',
  );
  @override
  late final GeneratedColumn<int> durationMillis = GeneratedColumn<int>(
    'duration_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    reviewId,
    role,
    providerId,
    modelId,
    state,
    childSessionId,
    errorType,
    errorMessage,
    inputTokens,
    outputTokens,
    reasoningTokens,
    cacheTokens,
    cost,
    durationMillis,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_passes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewPassesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('review_id')) {
      context.handle(
        _reviewIdMeta,
        reviewId.isAcceptableOrUnknown(data['review_id']!, _reviewIdMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('child_session_id')) {
      context.handle(
        _childSessionIdMeta,
        childSessionId.isAcceptableOrUnknown(
          data['child_session_id']!,
          _childSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('error_type')) {
      context.handle(
        _errorTypeMeta,
        errorType.isAcceptableOrUnknown(data['error_type']!, _errorTypeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('input_tokens')) {
      context.handle(
        _inputTokensMeta,
        inputTokens.isAcceptableOrUnknown(
          data['input_tokens']!,
          _inputTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inputTokensMeta);
    }
    if (data.containsKey('output_tokens')) {
      context.handle(
        _outputTokensMeta,
        outputTokens.isAcceptableOrUnknown(
          data['output_tokens']!,
          _outputTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_outputTokensMeta);
    }
    if (data.containsKey('reasoning_tokens')) {
      context.handle(
        _reasoningTokensMeta,
        reasoningTokens.isAcceptableOrUnknown(
          data['reasoning_tokens']!,
          _reasoningTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reasoningTokensMeta);
    }
    if (data.containsKey('cache_tokens')) {
      context.handle(
        _cacheTokensMeta,
        cacheTokens.isAcceptableOrUnknown(
          data['cache_tokens']!,
          _cacheTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cacheTokensMeta);
    }
    if (data.containsKey('cost')) {
      context.handle(
        _costMeta,
        cost.isAcceptableOrUnknown(data['cost']!, _costMeta),
      );
    } else if (isInserting) {
      context.missing(_costMeta);
    }
    if (data.containsKey('duration_millis')) {
      context.handle(
        _durationMillisMeta,
        durationMillis.isAcceptableOrUnknown(
          data['duration_millis']!,
          _durationMillisMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewPassesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewPassesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      reviewId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      childSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}child_session_id'],
      ),
      errorType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_type'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      inputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}input_tokens'],
      )!,
      outputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}output_tokens'],
      )!,
      reasoningTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reasoning_tokens'],
      )!,
      cacheTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cache_tokens'],
      )!,
      cost: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost'],
      )!,
      durationMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_millis'],
      ),
    );
  }

  @override
  $ReviewPassesTable createAlias(String alias) {
    return $ReviewPassesTable(attachedDatabase, alias);
  }
}

class ReviewPassesData extends DataClass
    implements Insertable<ReviewPassesData> {
  final String id;
  final String reviewId;
  final String role;
  final String providerId;
  final String modelId;
  final String state;
  final String? childSessionId;
  final String? errorType;
  final String? errorMessage;
  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cacheTokens;
  final double cost;
  final int? durationMillis;
  const ReviewPassesData({
    required this.id,
    required this.reviewId,
    required this.role,
    required this.providerId,
    required this.modelId,
    required this.state,
    this.childSessionId,
    this.errorType,
    this.errorMessage,
    required this.inputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
    required this.cacheTokens,
    required this.cost,
    this.durationMillis,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['review_id'] = Variable<String>(reviewId);
    map['role'] = Variable<String>(role);
    map['provider_id'] = Variable<String>(providerId);
    map['model_id'] = Variable<String>(modelId);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || childSessionId != null) {
      map['child_session_id'] = Variable<String>(childSessionId);
    }
    if (!nullToAbsent || errorType != null) {
      map['error_type'] = Variable<String>(errorType);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['input_tokens'] = Variable<int>(inputTokens);
    map['output_tokens'] = Variable<int>(outputTokens);
    map['reasoning_tokens'] = Variable<int>(reasoningTokens);
    map['cache_tokens'] = Variable<int>(cacheTokens);
    map['cost'] = Variable<double>(cost);
    if (!nullToAbsent || durationMillis != null) {
      map['duration_millis'] = Variable<int>(durationMillis);
    }
    return map;
  }

  ReviewPassesCompanion toCompanion(bool nullToAbsent) {
    return ReviewPassesCompanion(
      id: Value(id),
      reviewId: Value(reviewId),
      role: Value(role),
      providerId: Value(providerId),
      modelId: Value(modelId),
      state: Value(state),
      childSessionId: childSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(childSessionId),
      errorType: errorType == null && nullToAbsent
          ? const Value.absent()
          : Value(errorType),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      inputTokens: Value(inputTokens),
      outputTokens: Value(outputTokens),
      reasoningTokens: Value(reasoningTokens),
      cacheTokens: Value(cacheTokens),
      cost: Value(cost),
      durationMillis: durationMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMillis),
    );
  }

  factory ReviewPassesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewPassesData(
      id: serializer.fromJson<String>(json['id']),
      reviewId: serializer.fromJson<String>(json['reviewId']),
      role: serializer.fromJson<String>(json['role']),
      providerId: serializer.fromJson<String>(json['providerId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      state: serializer.fromJson<String>(json['state']),
      childSessionId: serializer.fromJson<String?>(json['childSessionId']),
      errorType: serializer.fromJson<String?>(json['errorType']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      inputTokens: serializer.fromJson<int>(json['inputTokens']),
      outputTokens: serializer.fromJson<int>(json['outputTokens']),
      reasoningTokens: serializer.fromJson<int>(json['reasoningTokens']),
      cacheTokens: serializer.fromJson<int>(json['cacheTokens']),
      cost: serializer.fromJson<double>(json['cost']),
      durationMillis: serializer.fromJson<int?>(json['durationMillis']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'reviewId': serializer.toJson<String>(reviewId),
      'role': serializer.toJson<String>(role),
      'providerId': serializer.toJson<String>(providerId),
      'modelId': serializer.toJson<String>(modelId),
      'state': serializer.toJson<String>(state),
      'childSessionId': serializer.toJson<String?>(childSessionId),
      'errorType': serializer.toJson<String?>(errorType),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'inputTokens': serializer.toJson<int>(inputTokens),
      'outputTokens': serializer.toJson<int>(outputTokens),
      'reasoningTokens': serializer.toJson<int>(reasoningTokens),
      'cacheTokens': serializer.toJson<int>(cacheTokens),
      'cost': serializer.toJson<double>(cost),
      'durationMillis': serializer.toJson<int?>(durationMillis),
    };
  }

  ReviewPassesData copyWith({
    String? id,
    String? reviewId,
    String? role,
    String? providerId,
    String? modelId,
    String? state,
    Value<String?> childSessionId = const Value.absent(),
    Value<String?> errorType = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    int? inputTokens,
    int? outputTokens,
    int? reasoningTokens,
    int? cacheTokens,
    double? cost,
    Value<int?> durationMillis = const Value.absent(),
  }) => ReviewPassesData(
    id: id ?? this.id,
    reviewId: reviewId ?? this.reviewId,
    role: role ?? this.role,
    providerId: providerId ?? this.providerId,
    modelId: modelId ?? this.modelId,
    state: state ?? this.state,
    childSessionId: childSessionId.present
        ? childSessionId.value
        : this.childSessionId,
    errorType: errorType.present ? errorType.value : this.errorType,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    reasoningTokens: reasoningTokens ?? this.reasoningTokens,
    cacheTokens: cacheTokens ?? this.cacheTokens,
    cost: cost ?? this.cost,
    durationMillis: durationMillis.present
        ? durationMillis.value
        : this.durationMillis,
  );
  ReviewPassesData copyWithCompanion(ReviewPassesCompanion data) {
    return ReviewPassesData(
      id: data.id.present ? data.id.value : this.id,
      reviewId: data.reviewId.present ? data.reviewId.value : this.reviewId,
      role: data.role.present ? data.role.value : this.role,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      state: data.state.present ? data.state.value : this.state,
      childSessionId: data.childSessionId.present
          ? data.childSessionId.value
          : this.childSessionId,
      errorType: data.errorType.present ? data.errorType.value : this.errorType,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      inputTokens: data.inputTokens.present
          ? data.inputTokens.value
          : this.inputTokens,
      outputTokens: data.outputTokens.present
          ? data.outputTokens.value
          : this.outputTokens,
      reasoningTokens: data.reasoningTokens.present
          ? data.reasoningTokens.value
          : this.reasoningTokens,
      cacheTokens: data.cacheTokens.present
          ? data.cacheTokens.value
          : this.cacheTokens,
      cost: data.cost.present ? data.cost.value : this.cost,
      durationMillis: data.durationMillis.present
          ? data.durationMillis.value
          : this.durationMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewPassesData(')
          ..write('id: $id, ')
          ..write('reviewId: $reviewId, ')
          ..write('role: $role, ')
          ..write('providerId: $providerId, ')
          ..write('modelId: $modelId, ')
          ..write('state: $state, ')
          ..write('childSessionId: $childSessionId, ')
          ..write('errorType: $errorType, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('reasoningTokens: $reasoningTokens, ')
          ..write('cacheTokens: $cacheTokens, ')
          ..write('cost: $cost, ')
          ..write('durationMillis: $durationMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    reviewId,
    role,
    providerId,
    modelId,
    state,
    childSessionId,
    errorType,
    errorMessage,
    inputTokens,
    outputTokens,
    reasoningTokens,
    cacheTokens,
    cost,
    durationMillis,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewPassesData &&
          other.id == this.id &&
          other.reviewId == this.reviewId &&
          other.role == this.role &&
          other.providerId == this.providerId &&
          other.modelId == this.modelId &&
          other.state == this.state &&
          other.childSessionId == this.childSessionId &&
          other.errorType == this.errorType &&
          other.errorMessage == this.errorMessage &&
          other.inputTokens == this.inputTokens &&
          other.outputTokens == this.outputTokens &&
          other.reasoningTokens == this.reasoningTokens &&
          other.cacheTokens == this.cacheTokens &&
          other.cost == this.cost &&
          other.durationMillis == this.durationMillis);
}

class ReviewPassesCompanion extends UpdateCompanion<ReviewPassesData> {
  final Value<String> id;
  final Value<String> reviewId;
  final Value<String> role;
  final Value<String> providerId;
  final Value<String> modelId;
  final Value<String> state;
  final Value<String?> childSessionId;
  final Value<String?> errorType;
  final Value<String?> errorMessage;
  final Value<int> inputTokens;
  final Value<int> outputTokens;
  final Value<int> reasoningTokens;
  final Value<int> cacheTokens;
  final Value<double> cost;
  final Value<int?> durationMillis;
  final Value<int> rowid;
  const ReviewPassesCompanion({
    this.id = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.role = const Value.absent(),
    this.providerId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.state = const Value.absent(),
    this.childSessionId = const Value.absent(),
    this.errorType = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.reasoningTokens = const Value.absent(),
    this.cacheTokens = const Value.absent(),
    this.cost = const Value.absent(),
    this.durationMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewPassesCompanion.insert({
    required String id,
    required String reviewId,
    required String role,
    required String providerId,
    required String modelId,
    required String state,
    this.childSessionId = const Value.absent(),
    this.errorType = const Value.absent(),
    this.errorMessage = const Value.absent(),
    required int inputTokens,
    required int outputTokens,
    required int reasoningTokens,
    required int cacheTokens,
    required double cost,
    this.durationMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       reviewId = Value(reviewId),
       role = Value(role),
       providerId = Value(providerId),
       modelId = Value(modelId),
       state = Value(state),
       inputTokens = Value(inputTokens),
       outputTokens = Value(outputTokens),
       reasoningTokens = Value(reasoningTokens),
       cacheTokens = Value(cacheTokens),
       cost = Value(cost);
  static Insertable<ReviewPassesData> custom({
    Expression<String>? id,
    Expression<String>? reviewId,
    Expression<String>? role,
    Expression<String>? providerId,
    Expression<String>? modelId,
    Expression<String>? state,
    Expression<String>? childSessionId,
    Expression<String>? errorType,
    Expression<String>? errorMessage,
    Expression<int>? inputTokens,
    Expression<int>? outputTokens,
    Expression<int>? reasoningTokens,
    Expression<int>? cacheTokens,
    Expression<double>? cost,
    Expression<int>? durationMillis,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (reviewId != null) 'review_id': reviewId,
      if (role != null) 'role': role,
      if (providerId != null) 'provider_id': providerId,
      if (modelId != null) 'model_id': modelId,
      if (state != null) 'state': state,
      if (childSessionId != null) 'child_session_id': childSessionId,
      if (errorType != null) 'error_type': errorType,
      if (errorMessage != null) 'error_message': errorMessage,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (reasoningTokens != null) 'reasoning_tokens': reasoningTokens,
      if (cacheTokens != null) 'cache_tokens': cacheTokens,
      if (cost != null) 'cost': cost,
      if (durationMillis != null) 'duration_millis': durationMillis,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewPassesCompanion copyWith({
    Value<String>? id,
    Value<String>? reviewId,
    Value<String>? role,
    Value<String>? providerId,
    Value<String>? modelId,
    Value<String>? state,
    Value<String?>? childSessionId,
    Value<String?>? errorType,
    Value<String?>? errorMessage,
    Value<int>? inputTokens,
    Value<int>? outputTokens,
    Value<int>? reasoningTokens,
    Value<int>? cacheTokens,
    Value<double>? cost,
    Value<int?>? durationMillis,
    Value<int>? rowid,
  }) {
    return ReviewPassesCompanion(
      id: id ?? this.id,
      reviewId: reviewId ?? this.reviewId,
      role: role ?? this.role,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      state: state ?? this.state,
      childSessionId: childSessionId ?? this.childSessionId,
      errorType: errorType ?? this.errorType,
      errorMessage: errorMessage ?? this.errorMessage,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      cacheTokens: cacheTokens ?? this.cacheTokens,
      cost: cost ?? this.cost,
      durationMillis: durationMillis ?? this.durationMillis,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (reviewId.present) {
      map['review_id'] = Variable<String>(reviewId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (childSessionId.present) {
      map['child_session_id'] = Variable<String>(childSessionId.value);
    }
    if (errorType.present) {
      map['error_type'] = Variable<String>(errorType.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (inputTokens.present) {
      map['input_tokens'] = Variable<int>(inputTokens.value);
    }
    if (outputTokens.present) {
      map['output_tokens'] = Variable<int>(outputTokens.value);
    }
    if (reasoningTokens.present) {
      map['reasoning_tokens'] = Variable<int>(reasoningTokens.value);
    }
    if (cacheTokens.present) {
      map['cache_tokens'] = Variable<int>(cacheTokens.value);
    }
    if (cost.present) {
      map['cost'] = Variable<double>(cost.value);
    }
    if (durationMillis.present) {
      map['duration_millis'] = Variable<int>(durationMillis.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewPassesCompanion(')
          ..write('id: $id, ')
          ..write('reviewId: $reviewId, ')
          ..write('role: $role, ')
          ..write('providerId: $providerId, ')
          ..write('modelId: $modelId, ')
          ..write('state: $state, ')
          ..write('childSessionId: $childSessionId, ')
          ..write('errorType: $errorType, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('reasoningTokens: $reasoningTokens, ')
          ..write('cacheTokens: $cacheTokens, ')
          ..write('cost: $cost, ')
          ..write('durationMillis: $durationMillis, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewOpinionsTable extends ReviewOpinions
    with TableInfo<$ReviewOpinionsTable, ReviewOpinion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewOpinionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passIdMeta = const VerificationMeta('passId');
  @override
  late final GeneratedColumn<String> passId = GeneratedColumn<String>(
    'pass_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_passes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, passId, role, summary];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_opinions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewOpinion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pass_id')) {
      context.handle(
        _passIdMeta,
        passId.isAcceptableOrUnknown(data['pass_id']!, _passIdMeta),
      );
    } else if (isInserting) {
      context.missing(_passIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {passId},
  ];
  @override
  ReviewOpinion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewOpinion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      passId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pass_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
    );
  }

  @override
  $ReviewOpinionsTable createAlias(String alias) {
    return $ReviewOpinionsTable(attachedDatabase, alias);
  }
}

class ReviewOpinion extends DataClass implements Insertable<ReviewOpinion> {
  final String id;
  final String passId;
  final String role;
  final String summary;
  const ReviewOpinion({
    required this.id,
    required this.passId,
    required this.role,
    required this.summary,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pass_id'] = Variable<String>(passId);
    map['role'] = Variable<String>(role);
    map['summary'] = Variable<String>(summary);
    return map;
  }

  ReviewOpinionsCompanion toCompanion(bool nullToAbsent) {
    return ReviewOpinionsCompanion(
      id: Value(id),
      passId: Value(passId),
      role: Value(role),
      summary: Value(summary),
    );
  }

  factory ReviewOpinion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewOpinion(
      id: serializer.fromJson<String>(json['id']),
      passId: serializer.fromJson<String>(json['passId']),
      role: serializer.fromJson<String>(json['role']),
      summary: serializer.fromJson<String>(json['summary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'passId': serializer.toJson<String>(passId),
      'role': serializer.toJson<String>(role),
      'summary': serializer.toJson<String>(summary),
    };
  }

  ReviewOpinion copyWith({
    String? id,
    String? passId,
    String? role,
    String? summary,
  }) => ReviewOpinion(
    id: id ?? this.id,
    passId: passId ?? this.passId,
    role: role ?? this.role,
    summary: summary ?? this.summary,
  );
  ReviewOpinion copyWithCompanion(ReviewOpinionsCompanion data) {
    return ReviewOpinion(
      id: data.id.present ? data.id.value : this.id,
      passId: data.passId.present ? data.passId.value : this.passId,
      role: data.role.present ? data.role.value : this.role,
      summary: data.summary.present ? data.summary.value : this.summary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewOpinion(')
          ..write('id: $id, ')
          ..write('passId: $passId, ')
          ..write('role: $role, ')
          ..write('summary: $summary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, passId, role, summary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewOpinion &&
          other.id == this.id &&
          other.passId == this.passId &&
          other.role == this.role &&
          other.summary == this.summary);
}

class ReviewOpinionsCompanion extends UpdateCompanion<ReviewOpinion> {
  final Value<String> id;
  final Value<String> passId;
  final Value<String> role;
  final Value<String> summary;
  final Value<int> rowid;
  const ReviewOpinionsCompanion({
    this.id = const Value.absent(),
    this.passId = const Value.absent(),
    this.role = const Value.absent(),
    this.summary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewOpinionsCompanion.insert({
    required String id,
    required String passId,
    required String role,
    required String summary,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       passId = Value(passId),
       role = Value(role),
       summary = Value(summary);
  static Insertable<ReviewOpinion> custom({
    Expression<String>? id,
    Expression<String>? passId,
    Expression<String>? role,
    Expression<String>? summary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (passId != null) 'pass_id': passId,
      if (role != null) 'role': role,
      if (summary != null) 'summary': summary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewOpinionsCompanion copyWith({
    Value<String>? id,
    Value<String>? passId,
    Value<String>? role,
    Value<String>? summary,
    Value<int>? rowid,
  }) {
    return ReviewOpinionsCompanion(
      id: id ?? this.id,
      passId: passId ?? this.passId,
      role: role ?? this.role,
      summary: summary ?? this.summary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (passId.present) {
      map['pass_id'] = Variable<String>(passId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewOpinionsCompanion(')
          ..write('id: $id, ')
          ..write('passId: $passId, ')
          ..write('role: $role, ')
          ..write('summary: $summary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewFindingsTable extends ReviewFindings
    with TableInfo<$ReviewFindingsTable, ReviewFinding> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewFindingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opinionIdMeta = const VerificationMeta(
    'opinionId',
  );
  @override
  late final GeneratedColumn<String> opinionId = GeneratedColumn<String>(
    'opinion_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_opinions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fileMeta = const VerificationMeta('file');
  @override
  late final GeneratedColumn<String> file = GeneratedColumn<String>(
    'file',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startLineMeta = const VerificationMeta(
    'startLine',
  );
  @override
  late final GeneratedColumn<int> startLine = GeneratedColumn<int>(
    'start_line',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endLineMeta = const VerificationMeta(
    'endLine',
  );
  @override
  late final GeneratedColumn<int> endLine = GeneratedColumn<int>(
    'end_line',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sideMeta = const VerificationMeta('side');
  @override
  late final GeneratedColumn<String> side = GeneratedColumn<String>(
    'side',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
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
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedBehaviorMeta = const VerificationMeta(
    'expectedBehavior',
  );
  @override
  late final GeneratedColumn<String> expectedBehavior = GeneratedColumn<String>(
    'expected_behavior',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedBehaviorMeta = const VerificationMeta(
    'observedBehavior',
  );
  @override
  late final GeneratedColumn<String> observedBehavior = GeneratedColumn<String>(
    'observed_behavior',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _preconditionsMeta = const VerificationMeta(
    'preconditions',
  );
  @override
  late final GeneratedColumn<String> preconditions = GeneratedColumn<String>(
    'preconditions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reproductionMeta = const VerificationMeta(
    'reproduction',
  );
  @override
  late final GeneratedColumn<String> reproduction = GeneratedColumn<String>(
    'reproduction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _impactMeta = const VerificationMeta('impact');
  @override
  late final GeneratedColumn<String> impact = GeneratedColumn<String>(
    'impact',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _suggestedTestMeta = const VerificationMeta(
    'suggestedTest',
  );
  @override
  late final GeneratedColumn<String> suggestedTest = GeneratedColumn<String>(
    'suggested_test',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    opinionId,
    file,
    startLine,
    endLine,
    side,
    category,
    severity,
    confidence,
    title,
    description,
    expectedBehavior,
    observedBehavior,
    preconditions,
    reproduction,
    impact,
    suggestedTest,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_findings';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewFinding> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('opinion_id')) {
      context.handle(
        _opinionIdMeta,
        opinionId.isAcceptableOrUnknown(data['opinion_id']!, _opinionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opinionIdMeta);
    }
    if (data.containsKey('file')) {
      context.handle(
        _fileMeta,
        file.isAcceptableOrUnknown(data['file']!, _fileMeta),
      );
    } else if (isInserting) {
      context.missing(_fileMeta);
    }
    if (data.containsKey('start_line')) {
      context.handle(
        _startLineMeta,
        startLine.isAcceptableOrUnknown(data['start_line']!, _startLineMeta),
      );
    } else if (isInserting) {
      context.missing(_startLineMeta);
    }
    if (data.containsKey('end_line')) {
      context.handle(
        _endLineMeta,
        endLine.isAcceptableOrUnknown(data['end_line']!, _endLineMeta),
      );
    } else if (isInserting) {
      context.missing(_endLineMeta);
    }
    if (data.containsKey('side')) {
      context.handle(
        _sideMeta,
        side.isAcceptableOrUnknown(data['side']!, _sideMeta),
      );
    } else if (isInserting) {
      context.missing(_sideMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    } else if (isInserting) {
      context.missing(_severityMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('expected_behavior')) {
      context.handle(
        _expectedBehaviorMeta,
        expectedBehavior.isAcceptableOrUnknown(
          data['expected_behavior']!,
          _expectedBehaviorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedBehaviorMeta);
    }
    if (data.containsKey('observed_behavior')) {
      context.handle(
        _observedBehaviorMeta,
        observedBehavior.isAcceptableOrUnknown(
          data['observed_behavior']!,
          _observedBehaviorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observedBehaviorMeta);
    }
    if (data.containsKey('preconditions')) {
      context.handle(
        _preconditionsMeta,
        preconditions.isAcceptableOrUnknown(
          data['preconditions']!,
          _preconditionsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_preconditionsMeta);
    }
    if (data.containsKey('reproduction')) {
      context.handle(
        _reproductionMeta,
        reproduction.isAcceptableOrUnknown(
          data['reproduction']!,
          _reproductionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reproductionMeta);
    }
    if (data.containsKey('impact')) {
      context.handle(
        _impactMeta,
        impact.isAcceptableOrUnknown(data['impact']!, _impactMeta),
      );
    } else if (isInserting) {
      context.missing(_impactMeta);
    }
    if (data.containsKey('suggested_test')) {
      context.handle(
        _suggestedTestMeta,
        suggestedTest.isAcceptableOrUnknown(
          data['suggested_test']!,
          _suggestedTestMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_suggestedTestMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewFinding map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewFinding(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      opinionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opinion_id'],
      )!,
      file: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file'],
      )!,
      startLine: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_line'],
      )!,
      endLine: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_line'],
      )!,
      side: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}side'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      expectedBehavior: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_behavior'],
      )!,
      observedBehavior: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observed_behavior'],
      )!,
      preconditions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preconditions'],
      )!,
      reproduction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reproduction'],
      )!,
      impact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}impact'],
      )!,
      suggestedTest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_test'],
      )!,
    );
  }

  @override
  $ReviewFindingsTable createAlias(String alias) {
    return $ReviewFindingsTable(attachedDatabase, alias);
  }
}

class ReviewFinding extends DataClass implements Insertable<ReviewFinding> {
  final String id;
  final String opinionId;
  final String file;
  final int startLine;
  final int endLine;
  final String side;
  final String category;
  final String severity;
  final double confidence;
  final String title;
  final String description;
  final String expectedBehavior;
  final String observedBehavior;
  final String preconditions;
  final String reproduction;
  final String impact;
  final String suggestedTest;
  const ReviewFinding({
    required this.id,
    required this.opinionId,
    required this.file,
    required this.startLine,
    required this.endLine,
    required this.side,
    required this.category,
    required this.severity,
    required this.confidence,
    required this.title,
    required this.description,
    required this.expectedBehavior,
    required this.observedBehavior,
    required this.preconditions,
    required this.reproduction,
    required this.impact,
    required this.suggestedTest,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['opinion_id'] = Variable<String>(opinionId);
    map['file'] = Variable<String>(file);
    map['start_line'] = Variable<int>(startLine);
    map['end_line'] = Variable<int>(endLine);
    map['side'] = Variable<String>(side);
    map['category'] = Variable<String>(category);
    map['severity'] = Variable<String>(severity);
    map['confidence'] = Variable<double>(confidence);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['expected_behavior'] = Variable<String>(expectedBehavior);
    map['observed_behavior'] = Variable<String>(observedBehavior);
    map['preconditions'] = Variable<String>(preconditions);
    map['reproduction'] = Variable<String>(reproduction);
    map['impact'] = Variable<String>(impact);
    map['suggested_test'] = Variable<String>(suggestedTest);
    return map;
  }

  ReviewFindingsCompanion toCompanion(bool nullToAbsent) {
    return ReviewFindingsCompanion(
      id: Value(id),
      opinionId: Value(opinionId),
      file: Value(file),
      startLine: Value(startLine),
      endLine: Value(endLine),
      side: Value(side),
      category: Value(category),
      severity: Value(severity),
      confidence: Value(confidence),
      title: Value(title),
      description: Value(description),
      expectedBehavior: Value(expectedBehavior),
      observedBehavior: Value(observedBehavior),
      preconditions: Value(preconditions),
      reproduction: Value(reproduction),
      impact: Value(impact),
      suggestedTest: Value(suggestedTest),
    );
  }

  factory ReviewFinding.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewFinding(
      id: serializer.fromJson<String>(json['id']),
      opinionId: serializer.fromJson<String>(json['opinionId']),
      file: serializer.fromJson<String>(json['file']),
      startLine: serializer.fromJson<int>(json['startLine']),
      endLine: serializer.fromJson<int>(json['endLine']),
      side: serializer.fromJson<String>(json['side']),
      category: serializer.fromJson<String>(json['category']),
      severity: serializer.fromJson<String>(json['severity']),
      confidence: serializer.fromJson<double>(json['confidence']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      expectedBehavior: serializer.fromJson<String>(json['expectedBehavior']),
      observedBehavior: serializer.fromJson<String>(json['observedBehavior']),
      preconditions: serializer.fromJson<String>(json['preconditions']),
      reproduction: serializer.fromJson<String>(json['reproduction']),
      impact: serializer.fromJson<String>(json['impact']),
      suggestedTest: serializer.fromJson<String>(json['suggestedTest']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'opinionId': serializer.toJson<String>(opinionId),
      'file': serializer.toJson<String>(file),
      'startLine': serializer.toJson<int>(startLine),
      'endLine': serializer.toJson<int>(endLine),
      'side': serializer.toJson<String>(side),
      'category': serializer.toJson<String>(category),
      'severity': serializer.toJson<String>(severity),
      'confidence': serializer.toJson<double>(confidence),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'expectedBehavior': serializer.toJson<String>(expectedBehavior),
      'observedBehavior': serializer.toJson<String>(observedBehavior),
      'preconditions': serializer.toJson<String>(preconditions),
      'reproduction': serializer.toJson<String>(reproduction),
      'impact': serializer.toJson<String>(impact),
      'suggestedTest': serializer.toJson<String>(suggestedTest),
    };
  }

  ReviewFinding copyWith({
    String? id,
    String? opinionId,
    String? file,
    int? startLine,
    int? endLine,
    String? side,
    String? category,
    String? severity,
    double? confidence,
    String? title,
    String? description,
    String? expectedBehavior,
    String? observedBehavior,
    String? preconditions,
    String? reproduction,
    String? impact,
    String? suggestedTest,
  }) => ReviewFinding(
    id: id ?? this.id,
    opinionId: opinionId ?? this.opinionId,
    file: file ?? this.file,
    startLine: startLine ?? this.startLine,
    endLine: endLine ?? this.endLine,
    side: side ?? this.side,
    category: category ?? this.category,
    severity: severity ?? this.severity,
    confidence: confidence ?? this.confidence,
    title: title ?? this.title,
    description: description ?? this.description,
    expectedBehavior: expectedBehavior ?? this.expectedBehavior,
    observedBehavior: observedBehavior ?? this.observedBehavior,
    preconditions: preconditions ?? this.preconditions,
    reproduction: reproduction ?? this.reproduction,
    impact: impact ?? this.impact,
    suggestedTest: suggestedTest ?? this.suggestedTest,
  );
  ReviewFinding copyWithCompanion(ReviewFindingsCompanion data) {
    return ReviewFinding(
      id: data.id.present ? data.id.value : this.id,
      opinionId: data.opinionId.present ? data.opinionId.value : this.opinionId,
      file: data.file.present ? data.file.value : this.file,
      startLine: data.startLine.present ? data.startLine.value : this.startLine,
      endLine: data.endLine.present ? data.endLine.value : this.endLine,
      side: data.side.present ? data.side.value : this.side,
      category: data.category.present ? data.category.value : this.category,
      severity: data.severity.present ? data.severity.value : this.severity,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      expectedBehavior: data.expectedBehavior.present
          ? data.expectedBehavior.value
          : this.expectedBehavior,
      observedBehavior: data.observedBehavior.present
          ? data.observedBehavior.value
          : this.observedBehavior,
      preconditions: data.preconditions.present
          ? data.preconditions.value
          : this.preconditions,
      reproduction: data.reproduction.present
          ? data.reproduction.value
          : this.reproduction,
      impact: data.impact.present ? data.impact.value : this.impact,
      suggestedTest: data.suggestedTest.present
          ? data.suggestedTest.value
          : this.suggestedTest,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewFinding(')
          ..write('id: $id, ')
          ..write('opinionId: $opinionId, ')
          ..write('file: $file, ')
          ..write('startLine: $startLine, ')
          ..write('endLine: $endLine, ')
          ..write('side: $side, ')
          ..write('category: $category, ')
          ..write('severity: $severity, ')
          ..write('confidence: $confidence, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('expectedBehavior: $expectedBehavior, ')
          ..write('observedBehavior: $observedBehavior, ')
          ..write('preconditions: $preconditions, ')
          ..write('reproduction: $reproduction, ')
          ..write('impact: $impact, ')
          ..write('suggestedTest: $suggestedTest')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    opinionId,
    file,
    startLine,
    endLine,
    side,
    category,
    severity,
    confidence,
    title,
    description,
    expectedBehavior,
    observedBehavior,
    preconditions,
    reproduction,
    impact,
    suggestedTest,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewFinding &&
          other.id == this.id &&
          other.opinionId == this.opinionId &&
          other.file == this.file &&
          other.startLine == this.startLine &&
          other.endLine == this.endLine &&
          other.side == this.side &&
          other.category == this.category &&
          other.severity == this.severity &&
          other.confidence == this.confidence &&
          other.title == this.title &&
          other.description == this.description &&
          other.expectedBehavior == this.expectedBehavior &&
          other.observedBehavior == this.observedBehavior &&
          other.preconditions == this.preconditions &&
          other.reproduction == this.reproduction &&
          other.impact == this.impact &&
          other.suggestedTest == this.suggestedTest);
}

class ReviewFindingsCompanion extends UpdateCompanion<ReviewFinding> {
  final Value<String> id;
  final Value<String> opinionId;
  final Value<String> file;
  final Value<int> startLine;
  final Value<int> endLine;
  final Value<String> side;
  final Value<String> category;
  final Value<String> severity;
  final Value<double> confidence;
  final Value<String> title;
  final Value<String> description;
  final Value<String> expectedBehavior;
  final Value<String> observedBehavior;
  final Value<String> preconditions;
  final Value<String> reproduction;
  final Value<String> impact;
  final Value<String> suggestedTest;
  final Value<int> rowid;
  const ReviewFindingsCompanion({
    this.id = const Value.absent(),
    this.opinionId = const Value.absent(),
    this.file = const Value.absent(),
    this.startLine = const Value.absent(),
    this.endLine = const Value.absent(),
    this.side = const Value.absent(),
    this.category = const Value.absent(),
    this.severity = const Value.absent(),
    this.confidence = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.expectedBehavior = const Value.absent(),
    this.observedBehavior = const Value.absent(),
    this.preconditions = const Value.absent(),
    this.reproduction = const Value.absent(),
    this.impact = const Value.absent(),
    this.suggestedTest = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewFindingsCompanion.insert({
    required String id,
    required String opinionId,
    required String file,
    required int startLine,
    required int endLine,
    required String side,
    required String category,
    required String severity,
    required double confidence,
    required String title,
    required String description,
    required String expectedBehavior,
    required String observedBehavior,
    required String preconditions,
    required String reproduction,
    required String impact,
    required String suggestedTest,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       opinionId = Value(opinionId),
       file = Value(file),
       startLine = Value(startLine),
       endLine = Value(endLine),
       side = Value(side),
       category = Value(category),
       severity = Value(severity),
       confidence = Value(confidence),
       title = Value(title),
       description = Value(description),
       expectedBehavior = Value(expectedBehavior),
       observedBehavior = Value(observedBehavior),
       preconditions = Value(preconditions),
       reproduction = Value(reproduction),
       impact = Value(impact),
       suggestedTest = Value(suggestedTest);
  static Insertable<ReviewFinding> custom({
    Expression<String>? id,
    Expression<String>? opinionId,
    Expression<String>? file,
    Expression<int>? startLine,
    Expression<int>? endLine,
    Expression<String>? side,
    Expression<String>? category,
    Expression<String>? severity,
    Expression<double>? confidence,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? expectedBehavior,
    Expression<String>? observedBehavior,
    Expression<String>? preconditions,
    Expression<String>? reproduction,
    Expression<String>? impact,
    Expression<String>? suggestedTest,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (opinionId != null) 'opinion_id': opinionId,
      if (file != null) 'file': file,
      if (startLine != null) 'start_line': startLine,
      if (endLine != null) 'end_line': endLine,
      if (side != null) 'side': side,
      if (category != null) 'category': category,
      if (severity != null) 'severity': severity,
      if (confidence != null) 'confidence': confidence,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (expectedBehavior != null) 'expected_behavior': expectedBehavior,
      if (observedBehavior != null) 'observed_behavior': observedBehavior,
      if (preconditions != null) 'preconditions': preconditions,
      if (reproduction != null) 'reproduction': reproduction,
      if (impact != null) 'impact': impact,
      if (suggestedTest != null) 'suggested_test': suggestedTest,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewFindingsCompanion copyWith({
    Value<String>? id,
    Value<String>? opinionId,
    Value<String>? file,
    Value<int>? startLine,
    Value<int>? endLine,
    Value<String>? side,
    Value<String>? category,
    Value<String>? severity,
    Value<double>? confidence,
    Value<String>? title,
    Value<String>? description,
    Value<String>? expectedBehavior,
    Value<String>? observedBehavior,
    Value<String>? preconditions,
    Value<String>? reproduction,
    Value<String>? impact,
    Value<String>? suggestedTest,
    Value<int>? rowid,
  }) {
    return ReviewFindingsCompanion(
      id: id ?? this.id,
      opinionId: opinionId ?? this.opinionId,
      file: file ?? this.file,
      startLine: startLine ?? this.startLine,
      endLine: endLine ?? this.endLine,
      side: side ?? this.side,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      confidence: confidence ?? this.confidence,
      title: title ?? this.title,
      description: description ?? this.description,
      expectedBehavior: expectedBehavior ?? this.expectedBehavior,
      observedBehavior: observedBehavior ?? this.observedBehavior,
      preconditions: preconditions ?? this.preconditions,
      reproduction: reproduction ?? this.reproduction,
      impact: impact ?? this.impact,
      suggestedTest: suggestedTest ?? this.suggestedTest,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (opinionId.present) {
      map['opinion_id'] = Variable<String>(opinionId.value);
    }
    if (file.present) {
      map['file'] = Variable<String>(file.value);
    }
    if (startLine.present) {
      map['start_line'] = Variable<int>(startLine.value);
    }
    if (endLine.present) {
      map['end_line'] = Variable<int>(endLine.value);
    }
    if (side.present) {
      map['side'] = Variable<String>(side.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (expectedBehavior.present) {
      map['expected_behavior'] = Variable<String>(expectedBehavior.value);
    }
    if (observedBehavior.present) {
      map['observed_behavior'] = Variable<String>(observedBehavior.value);
    }
    if (preconditions.present) {
      map['preconditions'] = Variable<String>(preconditions.value);
    }
    if (reproduction.present) {
      map['reproduction'] = Variable<String>(reproduction.value);
    }
    if (impact.present) {
      map['impact'] = Variable<String>(impact.value);
    }
    if (suggestedTest.present) {
      map['suggested_test'] = Variable<String>(suggestedTest.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewFindingsCompanion(')
          ..write('id: $id, ')
          ..write('opinionId: $opinionId, ')
          ..write('file: $file, ')
          ..write('startLine: $startLine, ')
          ..write('endLine: $endLine, ')
          ..write('side: $side, ')
          ..write('category: $category, ')
          ..write('severity: $severity, ')
          ..write('confidence: $confidence, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('expectedBehavior: $expectedBehavior, ')
          ..write('observedBehavior: $observedBehavior, ')
          ..write('preconditions: $preconditions, ')
          ..write('reproduction: $reproduction, ')
          ..write('impact: $impact, ')
          ..write('suggestedTest: $suggestedTest, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewEvidenceEntriesTable extends ReviewEvidenceEntries
    with TableInfo<$ReviewEvidenceEntriesTable, ReviewEvidenceEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewEvidenceEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _findingIdMeta = const VerificationMeta(
    'findingId',
  );
  @override
  late final GeneratedColumn<String> findingId = GeneratedColumn<String>(
    'finding_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_findings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _evidenceTextMeta = const VerificationMeta(
    'evidenceText',
  );
  @override
  late final GeneratedColumn<String> evidenceText = GeneratedColumn<String>(
    'evidence_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, findingId, kind, evidenceText];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_evidence_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewEvidenceEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('finding_id')) {
      context.handle(
        _findingIdMeta,
        findingId.isAcceptableOrUnknown(data['finding_id']!, _findingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_findingIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('evidence_text')) {
      context.handle(
        _evidenceTextMeta,
        evidenceText.isAcceptableOrUnknown(
          data['evidence_text']!,
          _evidenceTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceTextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewEvidenceEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewEvidenceEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      findingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finding_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      evidenceText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_text'],
      )!,
    );
  }

  @override
  $ReviewEvidenceEntriesTable createAlias(String alias) {
    return $ReviewEvidenceEntriesTable(attachedDatabase, alias);
  }
}

class ReviewEvidenceEntry extends DataClass
    implements Insertable<ReviewEvidenceEntry> {
  final int id;
  final String findingId;
  final String kind;
  final String evidenceText;
  const ReviewEvidenceEntry({
    required this.id,
    required this.findingId,
    required this.kind,
    required this.evidenceText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['finding_id'] = Variable<String>(findingId);
    map['kind'] = Variable<String>(kind);
    map['evidence_text'] = Variable<String>(evidenceText);
    return map;
  }

  ReviewEvidenceEntriesCompanion toCompanion(bool nullToAbsent) {
    return ReviewEvidenceEntriesCompanion(
      id: Value(id),
      findingId: Value(findingId),
      kind: Value(kind),
      evidenceText: Value(evidenceText),
    );
  }

  factory ReviewEvidenceEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewEvidenceEntry(
      id: serializer.fromJson<int>(json['id']),
      findingId: serializer.fromJson<String>(json['findingId']),
      kind: serializer.fromJson<String>(json['kind']),
      evidenceText: serializer.fromJson<String>(json['evidenceText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'findingId': serializer.toJson<String>(findingId),
      'kind': serializer.toJson<String>(kind),
      'evidenceText': serializer.toJson<String>(evidenceText),
    };
  }

  ReviewEvidenceEntry copyWith({
    int? id,
    String? findingId,
    String? kind,
    String? evidenceText,
  }) => ReviewEvidenceEntry(
    id: id ?? this.id,
    findingId: findingId ?? this.findingId,
    kind: kind ?? this.kind,
    evidenceText: evidenceText ?? this.evidenceText,
  );
  ReviewEvidenceEntry copyWithCompanion(ReviewEvidenceEntriesCompanion data) {
    return ReviewEvidenceEntry(
      id: data.id.present ? data.id.value : this.id,
      findingId: data.findingId.present ? data.findingId.value : this.findingId,
      kind: data.kind.present ? data.kind.value : this.kind,
      evidenceText: data.evidenceText.present
          ? data.evidenceText.value
          : this.evidenceText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewEvidenceEntry(')
          ..write('id: $id, ')
          ..write('findingId: $findingId, ')
          ..write('kind: $kind, ')
          ..write('evidenceText: $evidenceText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, findingId, kind, evidenceText);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewEvidenceEntry &&
          other.id == this.id &&
          other.findingId == this.findingId &&
          other.kind == this.kind &&
          other.evidenceText == this.evidenceText);
}

class ReviewEvidenceEntriesCompanion
    extends UpdateCompanion<ReviewEvidenceEntry> {
  final Value<int> id;
  final Value<String> findingId;
  final Value<String> kind;
  final Value<String> evidenceText;
  const ReviewEvidenceEntriesCompanion({
    this.id = const Value.absent(),
    this.findingId = const Value.absent(),
    this.kind = const Value.absent(),
    this.evidenceText = const Value.absent(),
  });
  ReviewEvidenceEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String findingId,
    required String kind,
    required String evidenceText,
  }) : findingId = Value(findingId),
       kind = Value(kind),
       evidenceText = Value(evidenceText);
  static Insertable<ReviewEvidenceEntry> custom({
    Expression<int>? id,
    Expression<String>? findingId,
    Expression<String>? kind,
    Expression<String>? evidenceText,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (findingId != null) 'finding_id': findingId,
      if (kind != null) 'kind': kind,
      if (evidenceText != null) 'evidence_text': evidenceText,
    });
  }

  ReviewEvidenceEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? findingId,
    Value<String>? kind,
    Value<String>? evidenceText,
  }) {
    return ReviewEvidenceEntriesCompanion(
      id: id ?? this.id,
      findingId: findingId ?? this.findingId,
      kind: kind ?? this.kind,
      evidenceText: evidenceText ?? this.evidenceText,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (findingId.present) {
      map['finding_id'] = Variable<String>(findingId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (evidenceText.present) {
      map['evidence_text'] = Variable<String>(evidenceText.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewEvidenceEntriesCompanion(')
          ..write('id: $id, ')
          ..write('findingId: $findingId, ')
          ..write('kind: $kind, ')
          ..write('evidenceText: $evidenceText')
          ..write(')'))
        .toString();
  }
}

class $ReviewDisagreementsTable extends ReviewDisagreements
    with TableInfo<$ReviewDisagreementsTable, ReviewDisagreement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewDisagreementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewIdMeta = const VerificationMeta(
    'reviewId',
  );
  @override
  late final GeneratedColumn<String> reviewId = GeneratedColumn<String>(
    'review_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_runs (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, reviewId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_disagreements';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewDisagreement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('review_id')) {
      context.handle(
        _reviewIdMeta,
        reviewId.isAcceptableOrUnknown(data['review_id']!, _reviewIdMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewDisagreement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewDisagreement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      reviewId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_id'],
      )!,
    );
  }

  @override
  $ReviewDisagreementsTable createAlias(String alias) {
    return $ReviewDisagreementsTable(attachedDatabase, alias);
  }
}

class ReviewDisagreement extends DataClass
    implements Insertable<ReviewDisagreement> {
  final String id;
  final String reviewId;
  const ReviewDisagreement({required this.id, required this.reviewId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['review_id'] = Variable<String>(reviewId);
    return map;
  }

  ReviewDisagreementsCompanion toCompanion(bool nullToAbsent) {
    return ReviewDisagreementsCompanion(
      id: Value(id),
      reviewId: Value(reviewId),
    );
  }

  factory ReviewDisagreement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewDisagreement(
      id: serializer.fromJson<String>(json['id']),
      reviewId: serializer.fromJson<String>(json['reviewId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'reviewId': serializer.toJson<String>(reviewId),
    };
  }

  ReviewDisagreement copyWith({String? id, String? reviewId}) =>
      ReviewDisagreement(
        id: id ?? this.id,
        reviewId: reviewId ?? this.reviewId,
      );
  ReviewDisagreement copyWithCompanion(ReviewDisagreementsCompanion data) {
    return ReviewDisagreement(
      id: data.id.present ? data.id.value : this.id,
      reviewId: data.reviewId.present ? data.reviewId.value : this.reviewId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDisagreement(')
          ..write('id: $id, ')
          ..write('reviewId: $reviewId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, reviewId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewDisagreement &&
          other.id == this.id &&
          other.reviewId == this.reviewId);
}

class ReviewDisagreementsCompanion extends UpdateCompanion<ReviewDisagreement> {
  final Value<String> id;
  final Value<String> reviewId;
  final Value<int> rowid;
  const ReviewDisagreementsCompanion({
    this.id = const Value.absent(),
    this.reviewId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewDisagreementsCompanion.insert({
    required String id,
    required String reviewId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       reviewId = Value(reviewId);
  static Insertable<ReviewDisagreement> custom({
    Expression<String>? id,
    Expression<String>? reviewId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (reviewId != null) 'review_id': reviewId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewDisagreementsCompanion copyWith({
    Value<String>? id,
    Value<String>? reviewId,
    Value<int>? rowid,
  }) {
    return ReviewDisagreementsCompanion(
      id: id ?? this.id,
      reviewId: reviewId ?? this.reviewId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (reviewId.present) {
      map['review_id'] = Variable<String>(reviewId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDisagreementsCompanion(')
          ..write('id: $id, ')
          ..write('reviewId: $reviewId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewDisagreementSourcesTable extends ReviewDisagreementSources
    with TableInfo<$ReviewDisagreementSourcesTable, ReviewDisagreementSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewDisagreementSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _disagreementIdMeta = const VerificationMeta(
    'disagreementId',
  );
  @override
  late final GeneratedColumn<String> disagreementId = GeneratedColumn<String>(
    'disagreement_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_disagreements (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _findingIdMeta = const VerificationMeta(
    'findingId',
  );
  @override
  late final GeneratedColumn<String> findingId = GeneratedColumn<String>(
    'finding_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES review_findings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, disagreementId, findingId, role];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_disagreement_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewDisagreementSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('disagreement_id')) {
      context.handle(
        _disagreementIdMeta,
        disagreementId.isAcceptableOrUnknown(
          data['disagreement_id']!,
          _disagreementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_disagreementIdMeta);
    }
    if (data.containsKey('finding_id')) {
      context.handle(
        _findingIdMeta,
        findingId.isAcceptableOrUnknown(data['finding_id']!, _findingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_findingIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewDisagreementSource map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewDisagreementSource(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      disagreementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disagreement_id'],
      )!,
      findingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finding_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
    );
  }

  @override
  $ReviewDisagreementSourcesTable createAlias(String alias) {
    return $ReviewDisagreementSourcesTable(attachedDatabase, alias);
  }
}

class ReviewDisagreementSource extends DataClass
    implements Insertable<ReviewDisagreementSource> {
  final int id;
  final String disagreementId;
  final String findingId;
  final String role;
  const ReviewDisagreementSource({
    required this.id,
    required this.disagreementId,
    required this.findingId,
    required this.role,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['disagreement_id'] = Variable<String>(disagreementId);
    map['finding_id'] = Variable<String>(findingId);
    map['role'] = Variable<String>(role);
    return map;
  }

  ReviewDisagreementSourcesCompanion toCompanion(bool nullToAbsent) {
    return ReviewDisagreementSourcesCompanion(
      id: Value(id),
      disagreementId: Value(disagreementId),
      findingId: Value(findingId),
      role: Value(role),
    );
  }

  factory ReviewDisagreementSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewDisagreementSource(
      id: serializer.fromJson<int>(json['id']),
      disagreementId: serializer.fromJson<String>(json['disagreementId']),
      findingId: serializer.fromJson<String>(json['findingId']),
      role: serializer.fromJson<String>(json['role']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'disagreementId': serializer.toJson<String>(disagreementId),
      'findingId': serializer.toJson<String>(findingId),
      'role': serializer.toJson<String>(role),
    };
  }

  ReviewDisagreementSource copyWith({
    int? id,
    String? disagreementId,
    String? findingId,
    String? role,
  }) => ReviewDisagreementSource(
    id: id ?? this.id,
    disagreementId: disagreementId ?? this.disagreementId,
    findingId: findingId ?? this.findingId,
    role: role ?? this.role,
  );
  ReviewDisagreementSource copyWithCompanion(
    ReviewDisagreementSourcesCompanion data,
  ) {
    return ReviewDisagreementSource(
      id: data.id.present ? data.id.value : this.id,
      disagreementId: data.disagreementId.present
          ? data.disagreementId.value
          : this.disagreementId,
      findingId: data.findingId.present ? data.findingId.value : this.findingId,
      role: data.role.present ? data.role.value : this.role,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDisagreementSource(')
          ..write('id: $id, ')
          ..write('disagreementId: $disagreementId, ')
          ..write('findingId: $findingId, ')
          ..write('role: $role')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, disagreementId, findingId, role);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewDisagreementSource &&
          other.id == this.id &&
          other.disagreementId == this.disagreementId &&
          other.findingId == this.findingId &&
          other.role == this.role);
}

class ReviewDisagreementSourcesCompanion
    extends UpdateCompanion<ReviewDisagreementSource> {
  final Value<int> id;
  final Value<String> disagreementId;
  final Value<String> findingId;
  final Value<String> role;
  const ReviewDisagreementSourcesCompanion({
    this.id = const Value.absent(),
    this.disagreementId = const Value.absent(),
    this.findingId = const Value.absent(),
    this.role = const Value.absent(),
  });
  ReviewDisagreementSourcesCompanion.insert({
    this.id = const Value.absent(),
    required String disagreementId,
    required String findingId,
    required String role,
  }) : disagreementId = Value(disagreementId),
       findingId = Value(findingId),
       role = Value(role);
  static Insertable<ReviewDisagreementSource> custom({
    Expression<int>? id,
    Expression<String>? disagreementId,
    Expression<String>? findingId,
    Expression<String>? role,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (disagreementId != null) 'disagreement_id': disagreementId,
      if (findingId != null) 'finding_id': findingId,
      if (role != null) 'role': role,
    });
  }

  ReviewDisagreementSourcesCompanion copyWith({
    Value<int>? id,
    Value<String>? disagreementId,
    Value<String>? findingId,
    Value<String>? role,
  }) {
    return ReviewDisagreementSourcesCompanion(
      id: id ?? this.id,
      disagreementId: disagreementId ?? this.disagreementId,
      findingId: findingId ?? this.findingId,
      role: role ?? this.role,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (disagreementId.present) {
      map['disagreement_id'] = Variable<String>(disagreementId.value);
    }
    if (findingId.present) {
      map['finding_id'] = Variable<String>(findingId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDisagreementSourcesCompanion(')
          ..write('id: $id, ')
          ..write('disagreementId: $disagreementId, ')
          ..write('findingId: $findingId, ')
          ..write('role: $role')
          ..write(')'))
        .toString();
  }
}

abstract class _$PromptDatabase extends GeneratedDatabase {
  _$PromptDatabase(QueryExecutor e) : super(e);
  $PromptDatabaseManager get managers => $PromptDatabaseManager(this);
  late final $ServerProfilesTable serverProfiles = $ServerProfilesTable(this);
  late final $QueuedPromptsTable queuedPrompts = $QueuedPromptsTable(this);
  late final $ReviewRunsTable reviewRuns = $ReviewRunsTable(this);
  late final $ReviewFilesTable reviewFiles = $ReviewFilesTable(this);
  late final $ReviewPassesTable reviewPasses = $ReviewPassesTable(this);
  late final $ReviewOpinionsTable reviewOpinions = $ReviewOpinionsTable(this);
  late final $ReviewFindingsTable reviewFindings = $ReviewFindingsTable(this);
  late final $ReviewEvidenceEntriesTable reviewEvidenceEntries =
      $ReviewEvidenceEntriesTable(this);
  late final $ReviewDisagreementsTable reviewDisagreements =
      $ReviewDisagreementsTable(this);
  late final $ReviewDisagreementSourcesTable reviewDisagreementSources =
      $ReviewDisagreementSourcesTable(this);
  late final Index reviewRunsScopeIdx = Index(
    'review_runs_scope_idx',
    'CREATE INDEX review_runs_scope_idx ON review_runs (server_profile_id, session_id, created_at_millis)',
  );
  late final Index reviewFilesReviewIdx = Index(
    'review_files_review_idx',
    'CREATE INDEX review_files_review_idx ON review_files (review_id)',
  );
  late final Index reviewPassesReviewIdx = Index(
    'review_passes_review_idx',
    'CREATE INDEX review_passes_review_idx ON review_passes (review_id)',
  );
  late final Index reviewOpinionsPassIdx = Index(
    'review_opinions_pass_idx',
    'CREATE INDEX review_opinions_pass_idx ON review_opinions (pass_id)',
  );
  late final Index reviewFindingsOpinionIdx = Index(
    'review_findings_opinion_idx',
    'CREATE INDEX review_findings_opinion_idx ON review_findings (opinion_id)',
  );
  late final Index reviewEvidenceFindingIdx = Index(
    'review_evidence_finding_idx',
    'CREATE INDEX review_evidence_finding_idx ON review_evidence_entries (finding_id)',
  );
  late final Index reviewDisagreementsReviewIdx = Index(
    'review_disagreements_review_idx',
    'CREATE INDEX review_disagreements_review_idx ON review_disagreements (review_id)',
  );
  late final Index reviewDisagreementSourcesDisagreementIdx = Index(
    'review_disagreement_sources_disagreement_idx',
    'CREATE INDEX review_disagreement_sources_disagreement_idx ON review_disagreement_sources (disagreement_id)',
  );
  late final Index reviewDisagreementSourcesFindingIdx = Index(
    'review_disagreement_sources_finding_idx',
    'CREATE INDEX review_disagreement_sources_finding_idx ON review_disagreement_sources (finding_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    serverProfiles,
    queuedPrompts,
    reviewRuns,
    reviewFiles,
    reviewPasses,
    reviewOpinions,
    reviewFindings,
    reviewEvidenceEntries,
    reviewDisagreements,
    reviewDisagreementSources,
    reviewRunsScopeIdx,
    reviewFilesReviewIdx,
    reviewPassesReviewIdx,
    reviewOpinionsPassIdx,
    reviewFindingsOpinionIdx,
    reviewEvidenceFindingIdx,
    reviewDisagreementsReviewIdx,
    reviewDisagreementSourcesDisagreementIdx,
    reviewDisagreementSourcesFindingIdx,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'server_profiles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_runs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_files', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_passes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_passes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_opinions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_opinions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_findings', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_findings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_evidence_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_disagreements', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_disagreements',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('review_disagreement_sources', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'review_findings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('review_disagreement_sources', kind: UpdateKind.delete),
      ],
    ),
  ]);
}

typedef $$ServerProfilesTableCreateCompanionBuilder =
    ServerProfilesCompanion Function({
      required String id,
      required String origin,
      Value<String?> username,
      Value<String> backend,
      required int lastAccessedAtMillis,
      Value<int> rowid,
    });
typedef $$ServerProfilesTableUpdateCompanionBuilder =
    ServerProfilesCompanion Function({
      Value<String> id,
      Value<String> origin,
      Value<String?> username,
      Value<String> backend,
      Value<int> lastAccessedAtMillis,
      Value<int> rowid,
    });

final class $$ServerProfilesTableReferences
    extends
        BaseReferences<_$PromptDatabase, $ServerProfilesTable, ServerProfile> {
  $$ServerProfilesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ReviewRunsTable, List<ReviewRun>>
  _reviewRunsRefsTable(_$PromptDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewRuns,
    aliasName: 'server_profiles__id__review_runs__server_profile_id',
  );

  $$ReviewRunsTableProcessedTableManager get reviewRunsRefs {
    final manager = $$ReviewRunsTableTableManager($_db, $_db.reviewRuns).filter(
      (f) => f.serverProfileId.id.sqlEquals($_itemColumn<String>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_reviewRunsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ServerProfilesTableFilterComposer
    extends Composer<_$PromptDatabase, $ServerProfilesTable> {
  $$ServerProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backend => $composableBuilder(
    column: $table.backend,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessedAtMillis => $composableBuilder(
    column: $table.lastAccessedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> reviewRunsRefs(
    Expression<bool> Function($$ReviewRunsTableFilterComposer f) f,
  ) {
    final $$ReviewRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.serverProfileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableFilterComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServerProfilesTableOrderingComposer
    extends Composer<_$PromptDatabase, $ServerProfilesTable> {
  $$ServerProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backend => $composableBuilder(
    column: $table.backend,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessedAtMillis => $composableBuilder(
    column: $table.lastAccessedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServerProfilesTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ServerProfilesTable> {
  $$ServerProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get backend =>
      $composableBuilder(column: $table.backend, builder: (column) => column);

  GeneratedColumn<int> get lastAccessedAtMillis => $composableBuilder(
    column: $table.lastAccessedAtMillis,
    builder: (column) => column,
  );

  Expression<T> reviewRunsRefs<T extends Object>(
    Expression<T> Function($$ReviewRunsTableAnnotationComposer a) f,
  ) {
    final $$ReviewRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.serverProfileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServerProfilesTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ServerProfilesTable,
          ServerProfile,
          $$ServerProfilesTableFilterComposer,
          $$ServerProfilesTableOrderingComposer,
          $$ServerProfilesTableAnnotationComposer,
          $$ServerProfilesTableCreateCompanionBuilder,
          $$ServerProfilesTableUpdateCompanionBuilder,
          (ServerProfile, $$ServerProfilesTableReferences),
          ServerProfile,
          PrefetchHooks Function({bool reviewRunsRefs})
        > {
  $$ServerProfilesTableTableManager(
    _$PromptDatabase db,
    $ServerProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServerProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServerProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServerProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String> backend = const Value.absent(),
                Value<int> lastAccessedAtMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServerProfilesCompanion(
                id: id,
                origin: origin,
                username: username,
                backend: backend,
                lastAccessedAtMillis: lastAccessedAtMillis,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String origin,
                Value<String?> username = const Value.absent(),
                Value<String> backend = const Value.absent(),
                required int lastAccessedAtMillis,
                Value<int> rowid = const Value.absent(),
              }) => ServerProfilesCompanion.insert(
                id: id,
                origin: origin,
                username: username,
                backend: backend,
                lastAccessedAtMillis: lastAccessedAtMillis,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ServerProfilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({reviewRunsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (reviewRunsRefs) db.reviewRuns],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (reviewRunsRefs)
                    await $_getPrefetchedData<
                      ServerProfile,
                      $ServerProfilesTable,
                      ReviewRun
                    >(
                      currentTable: table,
                      referencedTable: $$ServerProfilesTableReferences
                          ._reviewRunsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ServerProfilesTableReferences(
                            db,
                            table,
                            p0,
                          ).reviewRunsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.serverProfileId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ServerProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ServerProfilesTable,
      ServerProfile,
      $$ServerProfilesTableFilterComposer,
      $$ServerProfilesTableOrderingComposer,
      $$ServerProfilesTableAnnotationComposer,
      $$ServerProfilesTableCreateCompanionBuilder,
      $$ServerProfilesTableUpdateCompanionBuilder,
      (ServerProfile, $$ServerProfilesTableReferences),
      ServerProfile,
      PrefetchHooks Function({bool reviewRunsRefs})
    >;
typedef $$QueuedPromptsTableCreateCompanionBuilder =
    QueuedPromptsCompanion Function({
      required String id,
      required String serverProfileId,
      required String sessionId,
      required String directory,
      required int position,
      required String promptText,
      Value<String> operationType,
      Value<String?> commandName,
      Value<String?> attachmentsJson,
      Value<String?> modelProviderId,
      Value<String?> modelId,
      Value<String?> agentName,
      Value<String?> reasoningEffort,
      required String state,
      Value<String?> pauseReason,
      Value<int> attemptCount,
      required int createdAtMillis,
      required int updatedAtMillis,
      Value<int?> sendingStartedAtMillis,
      Value<int?> acknowledgedAtMillis,
      Value<int> rowid,
    });
typedef $$QueuedPromptsTableUpdateCompanionBuilder =
    QueuedPromptsCompanion Function({
      Value<String> id,
      Value<String> serverProfileId,
      Value<String> sessionId,
      Value<String> directory,
      Value<int> position,
      Value<String> promptText,
      Value<String> operationType,
      Value<String?> commandName,
      Value<String?> attachmentsJson,
      Value<String?> modelProviderId,
      Value<String?> modelId,
      Value<String?> agentName,
      Value<String?> reasoningEffort,
      Value<String> state,
      Value<String?> pauseReason,
      Value<int> attemptCount,
      Value<int> createdAtMillis,
      Value<int> updatedAtMillis,
      Value<int?> sendingStartedAtMillis,
      Value<int?> acknowledgedAtMillis,
      Value<int> rowid,
    });

class $$QueuedPromptsTableFilterComposer
    extends Composer<_$PromptDatabase, $QueuedPromptsTable> {
  $$QueuedPromptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverProfileId => $composableBuilder(
    column: $table.serverProfileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptText => $composableBuilder(
    column: $table.promptText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandName => $composableBuilder(
    column: $table.commandName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelProviderId => $composableBuilder(
    column: $table.modelProviderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMillis => $composableBuilder(
    column: $table.updatedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sendingStartedAtMillis => $composableBuilder(
    column: $table.sendingStartedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acknowledgedAtMillis => $composableBuilder(
    column: $table.acknowledgedAtMillis,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueuedPromptsTableOrderingComposer
    extends Composer<_$PromptDatabase, $QueuedPromptsTable> {
  $$QueuedPromptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverProfileId => $composableBuilder(
    column: $table.serverProfileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptText => $composableBuilder(
    column: $table.promptText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandName => $composableBuilder(
    column: $table.commandName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelProviderId => $composableBuilder(
    column: $table.modelProviderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMillis => $composableBuilder(
    column: $table.updatedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sendingStartedAtMillis => $composableBuilder(
    column: $table.sendingStartedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acknowledgedAtMillis => $composableBuilder(
    column: $table.acknowledgedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueuedPromptsTableAnnotationComposer
    extends Composer<_$PromptDatabase, $QueuedPromptsTable> {
  $$QueuedPromptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverProfileId => $composableBuilder(
    column: $table.serverProfileId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get promptText => $composableBuilder(
    column: $table.promptText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commandName => $composableBuilder(
    column: $table.commandName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelProviderId => $composableBuilder(
    column: $table.modelProviderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMillis => $composableBuilder(
    column: $table.updatedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sendingStartedAtMillis => $composableBuilder(
    column: $table.sendingStartedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acknowledgedAtMillis => $composableBuilder(
    column: $table.acknowledgedAtMillis,
    builder: (column) => column,
  );
}

class $$QueuedPromptsTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $QueuedPromptsTable,
          QueuedPrompt,
          $$QueuedPromptsTableFilterComposer,
          $$QueuedPromptsTableOrderingComposer,
          $$QueuedPromptsTableAnnotationComposer,
          $$QueuedPromptsTableCreateCompanionBuilder,
          $$QueuedPromptsTableUpdateCompanionBuilder,
          (
            QueuedPrompt,
            BaseReferences<_$PromptDatabase, $QueuedPromptsTable, QueuedPrompt>,
          ),
          QueuedPrompt,
          PrefetchHooks Function()
        > {
  $$QueuedPromptsTableTableManager(
    _$PromptDatabase db,
    $QueuedPromptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueuedPromptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueuedPromptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueuedPromptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> serverProfileId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> directory = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> promptText = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<String?> commandName = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<String?> modelProviderId = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> reasoningEffort = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> pauseReason = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> createdAtMillis = const Value.absent(),
                Value<int> updatedAtMillis = const Value.absent(),
                Value<int?> sendingStartedAtMillis = const Value.absent(),
                Value<int?> acknowledgedAtMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedPromptsCompanion(
                id: id,
                serverProfileId: serverProfileId,
                sessionId: sessionId,
                directory: directory,
                position: position,
                promptText: promptText,
                operationType: operationType,
                commandName: commandName,
                attachmentsJson: attachmentsJson,
                modelProviderId: modelProviderId,
                modelId: modelId,
                agentName: agentName,
                reasoningEffort: reasoningEffort,
                state: state,
                pauseReason: pauseReason,
                attemptCount: attemptCount,
                createdAtMillis: createdAtMillis,
                updatedAtMillis: updatedAtMillis,
                sendingStartedAtMillis: sendingStartedAtMillis,
                acknowledgedAtMillis: acknowledgedAtMillis,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String serverProfileId,
                required String sessionId,
                required String directory,
                required int position,
                required String promptText,
                Value<String> operationType = const Value.absent(),
                Value<String?> commandName = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<String?> modelProviderId = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<String?> reasoningEffort = const Value.absent(),
                required String state,
                Value<String?> pauseReason = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                required int createdAtMillis,
                required int updatedAtMillis,
                Value<int?> sendingStartedAtMillis = const Value.absent(),
                Value<int?> acknowledgedAtMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedPromptsCompanion.insert(
                id: id,
                serverProfileId: serverProfileId,
                sessionId: sessionId,
                directory: directory,
                position: position,
                promptText: promptText,
                operationType: operationType,
                commandName: commandName,
                attachmentsJson: attachmentsJson,
                modelProviderId: modelProviderId,
                modelId: modelId,
                agentName: agentName,
                reasoningEffort: reasoningEffort,
                state: state,
                pauseReason: pauseReason,
                attemptCount: attemptCount,
                createdAtMillis: createdAtMillis,
                updatedAtMillis: updatedAtMillis,
                sendingStartedAtMillis: sendingStartedAtMillis,
                acknowledgedAtMillis: acknowledgedAtMillis,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueuedPromptsTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $QueuedPromptsTable,
      QueuedPrompt,
      $$QueuedPromptsTableFilterComposer,
      $$QueuedPromptsTableOrderingComposer,
      $$QueuedPromptsTableAnnotationComposer,
      $$QueuedPromptsTableCreateCompanionBuilder,
      $$QueuedPromptsTableUpdateCompanionBuilder,
      (
        QueuedPrompt,
        BaseReferences<_$PromptDatabase, $QueuedPromptsTable, QueuedPrompt>,
      ),
      QueuedPrompt,
      PrefetchHooks Function()
    >;
typedef $$ReviewRunsTableCreateCompanionBuilder =
    ReviewRunsCompanion Function({
      required String id,
      required String serverProfileId,
      required String sessionId,
      required int createdAtMillis,
      Value<int?> completedAtMillis,
      required String state,
      Value<String?> errorType,
      Value<String?> errorMessage,
      Value<String?> projectId,
      Value<String?> directory,
      Value<String?> title,
      Value<String?> profileOrigin,
      Value<String?> profileUsername,
      Value<int?> sessionCreatedAtMillis,
      Value<int?> sessionUpdatedAtMillis,
      Value<String?> parentId,
      Value<int?> changedFiles,
      Value<int?> additions,
      Value<int?> deletions,
      Value<String?> shareUrl,
      Value<String?> modelProviderId,
      Value<String?> modelId,
      Value<String?> agentName,
      Value<int> rowid,
    });
typedef $$ReviewRunsTableUpdateCompanionBuilder =
    ReviewRunsCompanion Function({
      Value<String> id,
      Value<String> serverProfileId,
      Value<String> sessionId,
      Value<int> createdAtMillis,
      Value<int?> completedAtMillis,
      Value<String> state,
      Value<String?> errorType,
      Value<String?> errorMessage,
      Value<String?> projectId,
      Value<String?> directory,
      Value<String?> title,
      Value<String?> profileOrigin,
      Value<String?> profileUsername,
      Value<int?> sessionCreatedAtMillis,
      Value<int?> sessionUpdatedAtMillis,
      Value<String?> parentId,
      Value<int?> changedFiles,
      Value<int?> additions,
      Value<int?> deletions,
      Value<String?> shareUrl,
      Value<String?> modelProviderId,
      Value<String?> modelId,
      Value<String?> agentName,
      Value<int> rowid,
    });

final class $$ReviewRunsTableReferences
    extends BaseReferences<_$PromptDatabase, $ReviewRunsTable, ReviewRun> {
  $$ReviewRunsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ServerProfilesTable _serverProfileIdTable(_$PromptDatabase db) => db
      .serverProfiles
      .createAlias('review_runs__server_profile_id__server_profiles__id');

  $$ServerProfilesTableProcessedTableManager get serverProfileId {
    final $_column = $_itemColumn<String>('server_profile_id')!;

    final manager = $$ServerProfilesTableTableManager(
      $_db,
      $_db.serverProfiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_serverProfileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ReviewFilesTable, List<ReviewFile>>
  _reviewFilesRefsTable(_$PromptDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewFiles,
    aliasName: 'review_runs__id__review_files__review_id',
  );

  $$ReviewFilesTableProcessedTableManager get reviewFilesRefs {
    final manager = $$ReviewFilesTableTableManager(
      $_db,
      $_db.reviewFiles,
    ).filter((f) => f.reviewId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewFilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewPassesTable, List<ReviewPassesData>>
  _reviewPassesRefsTable(_$PromptDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewPasses,
    aliasName: 'review_runs__id__review_passes__review_id',
  );

  $$ReviewPassesTableProcessedTableManager get reviewPassesRefs {
    final manager = $$ReviewPassesTableTableManager(
      $_db,
      $_db.reviewPasses,
    ).filter((f) => f.reviewId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewPassesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReviewDisagreementsTable,
    List<ReviewDisagreement>
  >
  _reviewDisagreementsRefsTable(_$PromptDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reviewDisagreements,
        aliasName: 'review_runs__id__review_disagreements__review_id',
      );

  $$ReviewDisagreementsTableProcessedTableManager get reviewDisagreementsRefs {
    final manager = $$ReviewDisagreementsTableTableManager(
      $_db,
      $_db.reviewDisagreements,
    ).filter((f) => f.reviewId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewDisagreementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ReviewRunsTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewRunsTable> {
  $$ReviewRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtMillis => $composableBuilder(
    column: $table.completedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorType => $composableBuilder(
    column: $table.errorType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileOrigin => $composableBuilder(
    column: $table.profileOrigin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileUsername => $composableBuilder(
    column: $table.profileUsername,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionCreatedAtMillis => $composableBuilder(
    column: $table.sessionCreatedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionUpdatedAtMillis => $composableBuilder(
    column: $table.sessionUpdatedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changedFiles => $composableBuilder(
    column: $table.changedFiles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get additions => $composableBuilder(
    column: $table.additions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletions => $composableBuilder(
    column: $table.deletions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shareUrl => $composableBuilder(
    column: $table.shareUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelProviderId => $composableBuilder(
    column: $table.modelProviderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  $$ServerProfilesTableFilterComposer get serverProfileId {
    final $$ServerProfilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverProfileId,
      referencedTable: $db.serverProfiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServerProfilesTableFilterComposer(
            $db: $db,
            $table: $db.serverProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> reviewFilesRefs(
    Expression<bool> Function($$ReviewFilesTableFilterComposer f) f,
  ) {
    final $$ReviewFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewFiles,
      getReferencedColumn: (t) => t.reviewId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFilesTableFilterComposer(
            $db: $db,
            $table: $db.reviewFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewPassesRefs(
    Expression<bool> Function($$ReviewPassesTableFilterComposer f) f,
  ) {
    final $$ReviewPassesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewPasses,
      getReferencedColumn: (t) => t.reviewId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewPassesTableFilterComposer(
            $db: $db,
            $table: $db.reviewPasses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewDisagreementsRefs(
    Expression<bool> Function($$ReviewDisagreementsTableFilterComposer f) f,
  ) {
    final $$ReviewDisagreementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewDisagreements,
      getReferencedColumn: (t) => t.reviewId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewDisagreementsTableFilterComposer(
            $db: $db,
            $table: $db.reviewDisagreements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReviewRunsTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewRunsTable> {
  $$ReviewRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtMillis => $composableBuilder(
    column: $table.completedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorType => $composableBuilder(
    column: $table.errorType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileOrigin => $composableBuilder(
    column: $table.profileOrigin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileUsername => $composableBuilder(
    column: $table.profileUsername,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionCreatedAtMillis => $composableBuilder(
    column: $table.sessionCreatedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionUpdatedAtMillis => $composableBuilder(
    column: $table.sessionUpdatedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changedFiles => $composableBuilder(
    column: $table.changedFiles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get additions => $composableBuilder(
    column: $table.additions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletions => $composableBuilder(
    column: $table.deletions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shareUrl => $composableBuilder(
    column: $table.shareUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelProviderId => $composableBuilder(
    column: $table.modelProviderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  $$ServerProfilesTableOrderingComposer get serverProfileId {
    final $$ServerProfilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverProfileId,
      referencedTable: $db.serverProfiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServerProfilesTableOrderingComposer(
            $db: $db,
            $table: $db.serverProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewRunsTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewRunsTable> {
  $$ReviewRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtMillis => $composableBuilder(
    column: $table.completedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get errorType =>
      $composableBuilder(column: $table.errorType, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get profileOrigin => $composableBuilder(
    column: $table.profileOrigin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profileUsername => $composableBuilder(
    column: $table.profileUsername,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sessionCreatedAtMillis => $composableBuilder(
    column: $table.sessionCreatedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sessionUpdatedAtMillis => $composableBuilder(
    column: $table.sessionUpdatedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get changedFiles => $composableBuilder(
    column: $table.changedFiles,
    builder: (column) => column,
  );

  GeneratedColumn<int> get additions =>
      $composableBuilder(column: $table.additions, builder: (column) => column);

  GeneratedColumn<int> get deletions =>
      $composableBuilder(column: $table.deletions, builder: (column) => column);

  GeneratedColumn<String> get shareUrl =>
      $composableBuilder(column: $table.shareUrl, builder: (column) => column);

  GeneratedColumn<String> get modelProviderId => $composableBuilder(
    column: $table.modelProviderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  $$ServerProfilesTableAnnotationComposer get serverProfileId {
    final $$ServerProfilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverProfileId,
      referencedTable: $db.serverProfiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServerProfilesTableAnnotationComposer(
            $db: $db,
            $table: $db.serverProfiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> reviewFilesRefs<T extends Object>(
    Expression<T> Function($$ReviewFilesTableAnnotationComposer a) f,
  ) {
    final $$ReviewFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewFiles,
      getReferencedColumn: (t) => t.reviewId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewPassesRefs<T extends Object>(
    Expression<T> Function($$ReviewPassesTableAnnotationComposer a) f,
  ) {
    final $$ReviewPassesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewPasses,
      getReferencedColumn: (t) => t.reviewId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewPassesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewPasses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewDisagreementsRefs<T extends Object>(
    Expression<T> Function($$ReviewDisagreementsTableAnnotationComposer a) f,
  ) {
    final $$ReviewDisagreementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewDisagreements,
          getReferencedColumn: (t) => t.reviewId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementsTableAnnotationComposer(
                $db: $db,
                $table: $db.reviewDisagreements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ReviewRunsTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewRunsTable,
          ReviewRun,
          $$ReviewRunsTableFilterComposer,
          $$ReviewRunsTableOrderingComposer,
          $$ReviewRunsTableAnnotationComposer,
          $$ReviewRunsTableCreateCompanionBuilder,
          $$ReviewRunsTableUpdateCompanionBuilder,
          (ReviewRun, $$ReviewRunsTableReferences),
          ReviewRun,
          PrefetchHooks Function({
            bool serverProfileId,
            bool reviewFilesRefs,
            bool reviewPassesRefs,
            bool reviewDisagreementsRefs,
          })
        > {
  $$ReviewRunsTableTableManager(_$PromptDatabase db, $ReviewRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> serverProfileId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> createdAtMillis = const Value.absent(),
                Value<int?> completedAtMillis = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> errorType = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String?> directory = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> profileOrigin = const Value.absent(),
                Value<String?> profileUsername = const Value.absent(),
                Value<int?> sessionCreatedAtMillis = const Value.absent(),
                Value<int?> sessionUpdatedAtMillis = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int?> changedFiles = const Value.absent(),
                Value<int?> additions = const Value.absent(),
                Value<int?> deletions = const Value.absent(),
                Value<String?> shareUrl = const Value.absent(),
                Value<String?> modelProviderId = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewRunsCompanion(
                id: id,
                serverProfileId: serverProfileId,
                sessionId: sessionId,
                createdAtMillis: createdAtMillis,
                completedAtMillis: completedAtMillis,
                state: state,
                errorType: errorType,
                errorMessage: errorMessage,
                projectId: projectId,
                directory: directory,
                title: title,
                profileOrigin: profileOrigin,
                profileUsername: profileUsername,
                sessionCreatedAtMillis: sessionCreatedAtMillis,
                sessionUpdatedAtMillis: sessionUpdatedAtMillis,
                parentId: parentId,
                changedFiles: changedFiles,
                additions: additions,
                deletions: deletions,
                shareUrl: shareUrl,
                modelProviderId: modelProviderId,
                modelId: modelId,
                agentName: agentName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String serverProfileId,
                required String sessionId,
                required int createdAtMillis,
                Value<int?> completedAtMillis = const Value.absent(),
                required String state,
                Value<String?> errorType = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String?> directory = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> profileOrigin = const Value.absent(),
                Value<String?> profileUsername = const Value.absent(),
                Value<int?> sessionCreatedAtMillis = const Value.absent(),
                Value<int?> sessionUpdatedAtMillis = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int?> changedFiles = const Value.absent(),
                Value<int?> additions = const Value.absent(),
                Value<int?> deletions = const Value.absent(),
                Value<String?> shareUrl = const Value.absent(),
                Value<String?> modelProviderId = const Value.absent(),
                Value<String?> modelId = const Value.absent(),
                Value<String?> agentName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewRunsCompanion.insert(
                id: id,
                serverProfileId: serverProfileId,
                sessionId: sessionId,
                createdAtMillis: createdAtMillis,
                completedAtMillis: completedAtMillis,
                state: state,
                errorType: errorType,
                errorMessage: errorMessage,
                projectId: projectId,
                directory: directory,
                title: title,
                profileOrigin: profileOrigin,
                profileUsername: profileUsername,
                sessionCreatedAtMillis: sessionCreatedAtMillis,
                sessionUpdatedAtMillis: sessionUpdatedAtMillis,
                parentId: parentId,
                changedFiles: changedFiles,
                additions: additions,
                deletions: deletions,
                shareUrl: shareUrl,
                modelProviderId: modelProviderId,
                modelId: modelId,
                agentName: agentName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewRunsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                serverProfileId = false,
                reviewFilesRefs = false,
                reviewPassesRefs = false,
                reviewDisagreementsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (reviewFilesRefs) db.reviewFiles,
                    if (reviewPassesRefs) db.reviewPasses,
                    if (reviewDisagreementsRefs) db.reviewDisagreements,
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
                        if (serverProfileId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.serverProfileId,
                                    referencedTable: $$ReviewRunsTableReferences
                                        ._serverProfileIdTable(db),
                                    referencedColumn:
                                        $$ReviewRunsTableReferences
                                            ._serverProfileIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (reviewFilesRefs)
                        await $_getPrefetchedData<
                          ReviewRun,
                          $ReviewRunsTable,
                          ReviewFile
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewRunsTableReferences
                              ._reviewFilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewRunsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewFilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.reviewId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewPassesRefs)
                        await $_getPrefetchedData<
                          ReviewRun,
                          $ReviewRunsTable,
                          ReviewPassesData
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewRunsTableReferences
                              ._reviewPassesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewRunsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewPassesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.reviewId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewDisagreementsRefs)
                        await $_getPrefetchedData<
                          ReviewRun,
                          $ReviewRunsTable,
                          ReviewDisagreement
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewRunsTableReferences
                              ._reviewDisagreementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewRunsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewDisagreementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.reviewId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ReviewRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewRunsTable,
      ReviewRun,
      $$ReviewRunsTableFilterComposer,
      $$ReviewRunsTableOrderingComposer,
      $$ReviewRunsTableAnnotationComposer,
      $$ReviewRunsTableCreateCompanionBuilder,
      $$ReviewRunsTableUpdateCompanionBuilder,
      (ReviewRun, $$ReviewRunsTableReferences),
      ReviewRun,
      PrefetchHooks Function({
        bool serverProfileId,
        bool reviewFilesRefs,
        bool reviewPassesRefs,
        bool reviewDisagreementsRefs,
      })
    >;
typedef $$ReviewFilesTableCreateCompanionBuilder =
    ReviewFilesCompanion Function({
      Value<int> id,
      required String reviewId,
      required String path,
      required String status,
      required String patch,
    });
typedef $$ReviewFilesTableUpdateCompanionBuilder =
    ReviewFilesCompanion Function({
      Value<int> id,
      Value<String> reviewId,
      Value<String> path,
      Value<String> status,
      Value<String> patch,
    });

final class $$ReviewFilesTableReferences
    extends BaseReferences<_$PromptDatabase, $ReviewFilesTable, ReviewFile> {
  $$ReviewFilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ReviewRunsTable _reviewIdTable(_$PromptDatabase db) =>
      db.reviewRuns.createAlias('review_files__review_id__review_runs__id');

  $$ReviewRunsTableProcessedTableManager get reviewId {
    final $_column = $_itemColumn<String>('review_id')!;

    final manager = $$ReviewRunsTableTableManager(
      $_db,
      $_db.reviewRuns,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_reviewIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewFilesTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewFilesTable> {
  $$ReviewFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patch => $composableBuilder(
    column: $table.patch,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewRunsTableFilterComposer get reviewId {
    final $$ReviewRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableFilterComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewFilesTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewFilesTable> {
  $$ReviewFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patch => $composableBuilder(
    column: $table.patch,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewRunsTableOrderingComposer get reviewId {
    final $$ReviewRunsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableOrderingComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewFilesTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewFilesTable> {
  $$ReviewFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get patch =>
      $composableBuilder(column: $table.patch, builder: (column) => column);

  $$ReviewRunsTableAnnotationComposer get reviewId {
    final $$ReviewRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewFilesTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewFilesTable,
          ReviewFile,
          $$ReviewFilesTableFilterComposer,
          $$ReviewFilesTableOrderingComposer,
          $$ReviewFilesTableAnnotationComposer,
          $$ReviewFilesTableCreateCompanionBuilder,
          $$ReviewFilesTableUpdateCompanionBuilder,
          (ReviewFile, $$ReviewFilesTableReferences),
          ReviewFile,
          PrefetchHooks Function({bool reviewId})
        > {
  $$ReviewFilesTableTableManager(_$PromptDatabase db, $ReviewFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> reviewId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> patch = const Value.absent(),
              }) => ReviewFilesCompanion(
                id: id,
                reviewId: reviewId,
                path: path,
                status: status,
                patch: patch,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String reviewId,
                required String path,
                required String status,
                required String patch,
              }) => ReviewFilesCompanion.insert(
                id: id,
                reviewId: reviewId,
                path: path,
                status: status,
                patch: patch,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewFilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({reviewId = false}) {
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
                    if (reviewId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.reviewId,
                                referencedTable: $$ReviewFilesTableReferences
                                    ._reviewIdTable(db),
                                referencedColumn: $$ReviewFilesTableReferences
                                    ._reviewIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$ReviewFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewFilesTable,
      ReviewFile,
      $$ReviewFilesTableFilterComposer,
      $$ReviewFilesTableOrderingComposer,
      $$ReviewFilesTableAnnotationComposer,
      $$ReviewFilesTableCreateCompanionBuilder,
      $$ReviewFilesTableUpdateCompanionBuilder,
      (ReviewFile, $$ReviewFilesTableReferences),
      ReviewFile,
      PrefetchHooks Function({bool reviewId})
    >;
typedef $$ReviewPassesTableCreateCompanionBuilder =
    ReviewPassesCompanion Function({
      required String id,
      required String reviewId,
      required String role,
      required String providerId,
      required String modelId,
      required String state,
      Value<String?> childSessionId,
      Value<String?> errorType,
      Value<String?> errorMessage,
      required int inputTokens,
      required int outputTokens,
      required int reasoningTokens,
      required int cacheTokens,
      required double cost,
      Value<int?> durationMillis,
      Value<int> rowid,
    });
typedef $$ReviewPassesTableUpdateCompanionBuilder =
    ReviewPassesCompanion Function({
      Value<String> id,
      Value<String> reviewId,
      Value<String> role,
      Value<String> providerId,
      Value<String> modelId,
      Value<String> state,
      Value<String?> childSessionId,
      Value<String?> errorType,
      Value<String?> errorMessage,
      Value<int> inputTokens,
      Value<int> outputTokens,
      Value<int> reasoningTokens,
      Value<int> cacheTokens,
      Value<double> cost,
      Value<int?> durationMillis,
      Value<int> rowid,
    });

final class $$ReviewPassesTableReferences
    extends
        BaseReferences<_$PromptDatabase, $ReviewPassesTable, ReviewPassesData> {
  $$ReviewPassesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ReviewRunsTable _reviewIdTable(_$PromptDatabase db) =>
      db.reviewRuns.createAlias('review_passes__review_id__review_runs__id');

  $$ReviewRunsTableProcessedTableManager get reviewId {
    final $_column = $_itemColumn<String>('review_id')!;

    final manager = $$ReviewRunsTableTableManager(
      $_db,
      $_db.reviewRuns,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_reviewIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ReviewOpinionsTable, List<ReviewOpinion>>
  _reviewOpinionsRefsTable(_$PromptDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reviewOpinions,
        aliasName: 'review_passes__id__review_opinions__pass_id',
      );

  $$ReviewOpinionsTableProcessedTableManager get reviewOpinionsRefs {
    final manager = $$ReviewOpinionsTableTableManager(
      $_db,
      $_db.reviewOpinions,
    ).filter((f) => f.passId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewOpinionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ReviewPassesTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewPassesTable> {
  $$ReviewPassesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get childSessionId => $composableBuilder(
    column: $table.childSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorType => $composableBuilder(
    column: $table.errorType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cacheTokens => $composableBuilder(
    column: $table.cacheTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMillis => $composableBuilder(
    column: $table.durationMillis,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewRunsTableFilterComposer get reviewId {
    final $$ReviewRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableFilterComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> reviewOpinionsRefs(
    Expression<bool> Function($$ReviewOpinionsTableFilterComposer f) f,
  ) {
    final $$ReviewOpinionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewOpinions,
      getReferencedColumn: (t) => t.passId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewOpinionsTableFilterComposer(
            $db: $db,
            $table: $db.reviewOpinions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReviewPassesTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewPassesTable> {
  $$ReviewPassesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get childSessionId => $composableBuilder(
    column: $table.childSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorType => $composableBuilder(
    column: $table.errorType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cacheTokens => $composableBuilder(
    column: $table.cacheTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMillis => $composableBuilder(
    column: $table.durationMillis,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewRunsTableOrderingComposer get reviewId {
    final $$ReviewRunsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableOrderingComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewPassesTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewPassesTable> {
  $$ReviewPassesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get childSessionId => $composableBuilder(
    column: $table.childSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorType =>
      $composableBuilder(column: $table.errorType, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cacheTokens => $composableBuilder(
    column: $table.cacheTokens,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cost =>
      $composableBuilder(column: $table.cost, builder: (column) => column);

  GeneratedColumn<int> get durationMillis => $composableBuilder(
    column: $table.durationMillis,
    builder: (column) => column,
  );

  $$ReviewRunsTableAnnotationComposer get reviewId {
    final $$ReviewRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> reviewOpinionsRefs<T extends Object>(
    Expression<T> Function($$ReviewOpinionsTableAnnotationComposer a) f,
  ) {
    final $$ReviewOpinionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewOpinions,
      getReferencedColumn: (t) => t.passId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewOpinionsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewOpinions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReviewPassesTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewPassesTable,
          ReviewPassesData,
          $$ReviewPassesTableFilterComposer,
          $$ReviewPassesTableOrderingComposer,
          $$ReviewPassesTableAnnotationComposer,
          $$ReviewPassesTableCreateCompanionBuilder,
          $$ReviewPassesTableUpdateCompanionBuilder,
          (ReviewPassesData, $$ReviewPassesTableReferences),
          ReviewPassesData,
          PrefetchHooks Function({bool reviewId, bool reviewOpinionsRefs})
        > {
  $$ReviewPassesTableTableManager(_$PromptDatabase db, $ReviewPassesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewPassesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewPassesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewPassesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> reviewId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> providerId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> childSessionId = const Value.absent(),
                Value<String?> errorType = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> inputTokens = const Value.absent(),
                Value<int> outputTokens = const Value.absent(),
                Value<int> reasoningTokens = const Value.absent(),
                Value<int> cacheTokens = const Value.absent(),
                Value<double> cost = const Value.absent(),
                Value<int?> durationMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewPassesCompanion(
                id: id,
                reviewId: reviewId,
                role: role,
                providerId: providerId,
                modelId: modelId,
                state: state,
                childSessionId: childSessionId,
                errorType: errorType,
                errorMessage: errorMessage,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                reasoningTokens: reasoningTokens,
                cacheTokens: cacheTokens,
                cost: cost,
                durationMillis: durationMillis,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String reviewId,
                required String role,
                required String providerId,
                required String modelId,
                required String state,
                Value<String?> childSessionId = const Value.absent(),
                Value<String?> errorType = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                required int inputTokens,
                required int outputTokens,
                required int reasoningTokens,
                required int cacheTokens,
                required double cost,
                Value<int?> durationMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewPassesCompanion.insert(
                id: id,
                reviewId: reviewId,
                role: role,
                providerId: providerId,
                modelId: modelId,
                state: state,
                childSessionId: childSessionId,
                errorType: errorType,
                errorMessage: errorMessage,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                reasoningTokens: reasoningTokens,
                cacheTokens: cacheTokens,
                cost: cost,
                durationMillis: durationMillis,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewPassesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({reviewId = false, reviewOpinionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (reviewOpinionsRefs) db.reviewOpinions,
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
                        if (reviewId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.reviewId,
                                    referencedTable:
                                        $$ReviewPassesTableReferences
                                            ._reviewIdTable(db),
                                    referencedColumn:
                                        $$ReviewPassesTableReferences
                                            ._reviewIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (reviewOpinionsRefs)
                        await $_getPrefetchedData<
                          ReviewPassesData,
                          $ReviewPassesTable,
                          ReviewOpinion
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewPassesTableReferences
                              ._reviewOpinionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewPassesTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewOpinionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.passId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ReviewPassesTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewPassesTable,
      ReviewPassesData,
      $$ReviewPassesTableFilterComposer,
      $$ReviewPassesTableOrderingComposer,
      $$ReviewPassesTableAnnotationComposer,
      $$ReviewPassesTableCreateCompanionBuilder,
      $$ReviewPassesTableUpdateCompanionBuilder,
      (ReviewPassesData, $$ReviewPassesTableReferences),
      ReviewPassesData,
      PrefetchHooks Function({bool reviewId, bool reviewOpinionsRefs})
    >;
typedef $$ReviewOpinionsTableCreateCompanionBuilder =
    ReviewOpinionsCompanion Function({
      required String id,
      required String passId,
      required String role,
      required String summary,
      Value<int> rowid,
    });
typedef $$ReviewOpinionsTableUpdateCompanionBuilder =
    ReviewOpinionsCompanion Function({
      Value<String> id,
      Value<String> passId,
      Value<String> role,
      Value<String> summary,
      Value<int> rowid,
    });

final class $$ReviewOpinionsTableReferences
    extends
        BaseReferences<_$PromptDatabase, $ReviewOpinionsTable, ReviewOpinion> {
  $$ReviewOpinionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ReviewPassesTable _passIdTable(_$PromptDatabase db) => db.reviewPasses
      .createAlias('review_opinions__pass_id__review_passes__id');

  $$ReviewPassesTableProcessedTableManager get passId {
    final $_column = $_itemColumn<String>('pass_id')!;

    final manager = $$ReviewPassesTableTableManager(
      $_db,
      $_db.reviewPasses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_passIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ReviewFindingsTable, List<ReviewFinding>>
  _reviewFindingsRefsTable(_$PromptDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reviewFindings,
        aliasName: 'review_opinions__id__review_findings__opinion_id',
      );

  $$ReviewFindingsTableProcessedTableManager get reviewFindingsRefs {
    final manager = $$ReviewFindingsTableTableManager(
      $_db,
      $_db.reviewFindings,
    ).filter((f) => f.opinionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewFindingsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ReviewOpinionsTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewOpinionsTable> {
  $$ReviewOpinionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewPassesTableFilterComposer get passId {
    final $$ReviewPassesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.passId,
      referencedTable: $db.reviewPasses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewPassesTableFilterComposer(
            $db: $db,
            $table: $db.reviewPasses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> reviewFindingsRefs(
    Expression<bool> Function($$ReviewFindingsTableFilterComposer f) f,
  ) {
    final $$ReviewFindingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.opinionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableFilterComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReviewOpinionsTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewOpinionsTable> {
  $$ReviewOpinionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewPassesTableOrderingComposer get passId {
    final $$ReviewPassesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.passId,
      referencedTable: $db.reviewPasses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewPassesTableOrderingComposer(
            $db: $db,
            $table: $db.reviewPasses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewOpinionsTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewOpinionsTable> {
  $$ReviewOpinionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  $$ReviewPassesTableAnnotationComposer get passId {
    final $$ReviewPassesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.passId,
      referencedTable: $db.reviewPasses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewPassesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewPasses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> reviewFindingsRefs<T extends Object>(
    Expression<T> Function($$ReviewFindingsTableAnnotationComposer a) f,
  ) {
    final $$ReviewFindingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.opinionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ReviewOpinionsTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewOpinionsTable,
          ReviewOpinion,
          $$ReviewOpinionsTableFilterComposer,
          $$ReviewOpinionsTableOrderingComposer,
          $$ReviewOpinionsTableAnnotationComposer,
          $$ReviewOpinionsTableCreateCompanionBuilder,
          $$ReviewOpinionsTableUpdateCompanionBuilder,
          (ReviewOpinion, $$ReviewOpinionsTableReferences),
          ReviewOpinion,
          PrefetchHooks Function({bool passId, bool reviewFindingsRefs})
        > {
  $$ReviewOpinionsTableTableManager(
    _$PromptDatabase db,
    $ReviewOpinionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewOpinionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewOpinionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewOpinionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> passId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewOpinionsCompanion(
                id: id,
                passId: passId,
                role: role,
                summary: summary,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String passId,
                required String role,
                required String summary,
                Value<int> rowid = const Value.absent(),
              }) => ReviewOpinionsCompanion.insert(
                id: id,
                passId: passId,
                role: role,
                summary: summary,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewOpinionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({passId = false, reviewFindingsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (reviewFindingsRefs) db.reviewFindings,
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
                        if (passId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.passId,
                                    referencedTable:
                                        $$ReviewOpinionsTableReferences
                                            ._passIdTable(db),
                                    referencedColumn:
                                        $$ReviewOpinionsTableReferences
                                            ._passIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (reviewFindingsRefs)
                        await $_getPrefetchedData<
                          ReviewOpinion,
                          $ReviewOpinionsTable,
                          ReviewFinding
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewOpinionsTableReferences
                              ._reviewFindingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewOpinionsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewFindingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.opinionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ReviewOpinionsTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewOpinionsTable,
      ReviewOpinion,
      $$ReviewOpinionsTableFilterComposer,
      $$ReviewOpinionsTableOrderingComposer,
      $$ReviewOpinionsTableAnnotationComposer,
      $$ReviewOpinionsTableCreateCompanionBuilder,
      $$ReviewOpinionsTableUpdateCompanionBuilder,
      (ReviewOpinion, $$ReviewOpinionsTableReferences),
      ReviewOpinion,
      PrefetchHooks Function({bool passId, bool reviewFindingsRefs})
    >;
typedef $$ReviewFindingsTableCreateCompanionBuilder =
    ReviewFindingsCompanion Function({
      required String id,
      required String opinionId,
      required String file,
      required int startLine,
      required int endLine,
      required String side,
      required String category,
      required String severity,
      required double confidence,
      required String title,
      required String description,
      required String expectedBehavior,
      required String observedBehavior,
      required String preconditions,
      required String reproduction,
      required String impact,
      required String suggestedTest,
      Value<int> rowid,
    });
typedef $$ReviewFindingsTableUpdateCompanionBuilder =
    ReviewFindingsCompanion Function({
      Value<String> id,
      Value<String> opinionId,
      Value<String> file,
      Value<int> startLine,
      Value<int> endLine,
      Value<String> side,
      Value<String> category,
      Value<String> severity,
      Value<double> confidence,
      Value<String> title,
      Value<String> description,
      Value<String> expectedBehavior,
      Value<String> observedBehavior,
      Value<String> preconditions,
      Value<String> reproduction,
      Value<String> impact,
      Value<String> suggestedTest,
      Value<int> rowid,
    });

final class $$ReviewFindingsTableReferences
    extends
        BaseReferences<_$PromptDatabase, $ReviewFindingsTable, ReviewFinding> {
  $$ReviewFindingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ReviewOpinionsTable _opinionIdTable(_$PromptDatabase db) => db
      .reviewOpinions
      .createAlias('review_findings__opinion_id__review_opinions__id');

  $$ReviewOpinionsTableProcessedTableManager get opinionId {
    final $_column = $_itemColumn<String>('opinion_id')!;

    final manager = $$ReviewOpinionsTableTableManager(
      $_db,
      $_db.reviewOpinions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_opinionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $ReviewEvidenceEntriesTable,
    List<ReviewEvidenceEntry>
  >
  _reviewEvidenceEntriesRefsTable(_$PromptDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reviewEvidenceEntries,
        aliasName: 'review_findings__id__review_evidence_entries__finding_id',
      );

  $$ReviewEvidenceEntriesTableProcessedTableManager
  get reviewEvidenceEntriesRefs {
    final manager = $$ReviewEvidenceEntriesTableTableManager(
      $_db,
      $_db.reviewEvidenceEntries,
    ).filter((f) => f.findingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewEvidenceEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReviewDisagreementSourcesTable,
    List<ReviewDisagreementSource>
  >
  _reviewDisagreementSourcesRefsTable(_$PromptDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reviewDisagreementSources,
        aliasName:
            'review_findings__id__review_disagreement_sources__finding_id',
      );

  $$ReviewDisagreementSourcesTableProcessedTableManager
  get reviewDisagreementSourcesRefs {
    final manager = $$ReviewDisagreementSourcesTableTableManager(
      $_db,
      $_db.reviewDisagreementSources,
    ).filter((f) => f.findingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewDisagreementSourcesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ReviewFindingsTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewFindingsTable> {
  $$ReviewFindingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get file => $composableBuilder(
    column: $table.file,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startLine => $composableBuilder(
    column: $table.startLine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endLine => $composableBuilder(
    column: $table.endLine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedBehavior => $composableBuilder(
    column: $table.expectedBehavior,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observedBehavior => $composableBuilder(
    column: $table.observedBehavior,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preconditions => $composableBuilder(
    column: $table.preconditions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reproduction => $composableBuilder(
    column: $table.reproduction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get impact => $composableBuilder(
    column: $table.impact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedTest => $composableBuilder(
    column: $table.suggestedTest,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewOpinionsTableFilterComposer get opinionId {
    final $$ReviewOpinionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opinionId,
      referencedTable: $db.reviewOpinions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewOpinionsTableFilterComposer(
            $db: $db,
            $table: $db.reviewOpinions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> reviewEvidenceEntriesRefs(
    Expression<bool> Function($$ReviewEvidenceEntriesTableFilterComposer f) f,
  ) {
    final $$ReviewEvidenceEntriesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewEvidenceEntries,
          getReferencedColumn: (t) => t.findingId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewEvidenceEntriesTableFilterComposer(
                $db: $db,
                $table: $db.reviewEvidenceEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> reviewDisagreementSourcesRefs(
    Expression<bool> Function($$ReviewDisagreementSourcesTableFilterComposer f)
    f,
  ) {
    final $$ReviewDisagreementSourcesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewDisagreementSources,
          getReferencedColumn: (t) => t.findingId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementSourcesTableFilterComposer(
                $db: $db,
                $table: $db.reviewDisagreementSources,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ReviewFindingsTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewFindingsTable> {
  $$ReviewFindingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get file => $composableBuilder(
    column: $table.file,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startLine => $composableBuilder(
    column: $table.startLine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endLine => $composableBuilder(
    column: $table.endLine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedBehavior => $composableBuilder(
    column: $table.expectedBehavior,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observedBehavior => $composableBuilder(
    column: $table.observedBehavior,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preconditions => $composableBuilder(
    column: $table.preconditions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reproduction => $composableBuilder(
    column: $table.reproduction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get impact => $composableBuilder(
    column: $table.impact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedTest => $composableBuilder(
    column: $table.suggestedTest,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewOpinionsTableOrderingComposer get opinionId {
    final $$ReviewOpinionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opinionId,
      referencedTable: $db.reviewOpinions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewOpinionsTableOrderingComposer(
            $db: $db,
            $table: $db.reviewOpinions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewFindingsTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewFindingsTable> {
  $$ReviewFindingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get file =>
      $composableBuilder(column: $table.file, builder: (column) => column);

  GeneratedColumn<int> get startLine =>
      $composableBuilder(column: $table.startLine, builder: (column) => column);

  GeneratedColumn<int> get endLine =>
      $composableBuilder(column: $table.endLine, builder: (column) => column);

  GeneratedColumn<String> get side =>
      $composableBuilder(column: $table.side, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expectedBehavior => $composableBuilder(
    column: $table.expectedBehavior,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observedBehavior => $composableBuilder(
    column: $table.observedBehavior,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preconditions => $composableBuilder(
    column: $table.preconditions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reproduction => $composableBuilder(
    column: $table.reproduction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get impact =>
      $composableBuilder(column: $table.impact, builder: (column) => column);

  GeneratedColumn<String> get suggestedTest => $composableBuilder(
    column: $table.suggestedTest,
    builder: (column) => column,
  );

  $$ReviewOpinionsTableAnnotationComposer get opinionId {
    final $$ReviewOpinionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.opinionId,
      referencedTable: $db.reviewOpinions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewOpinionsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewOpinions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> reviewEvidenceEntriesRefs<T extends Object>(
    Expression<T> Function($$ReviewEvidenceEntriesTableAnnotationComposer a) f,
  ) {
    final $$ReviewEvidenceEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewEvidenceEntries,
          getReferencedColumn: (t) => t.findingId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewEvidenceEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.reviewEvidenceEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> reviewDisagreementSourcesRefs<T extends Object>(
    Expression<T> Function($$ReviewDisagreementSourcesTableAnnotationComposer a)
    f,
  ) {
    final $$ReviewDisagreementSourcesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewDisagreementSources,
          getReferencedColumn: (t) => t.findingId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementSourcesTableAnnotationComposer(
                $db: $db,
                $table: $db.reviewDisagreementSources,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ReviewFindingsTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewFindingsTable,
          ReviewFinding,
          $$ReviewFindingsTableFilterComposer,
          $$ReviewFindingsTableOrderingComposer,
          $$ReviewFindingsTableAnnotationComposer,
          $$ReviewFindingsTableCreateCompanionBuilder,
          $$ReviewFindingsTableUpdateCompanionBuilder,
          (ReviewFinding, $$ReviewFindingsTableReferences),
          ReviewFinding,
          PrefetchHooks Function({
            bool opinionId,
            bool reviewEvidenceEntriesRefs,
            bool reviewDisagreementSourcesRefs,
          })
        > {
  $$ReviewFindingsTableTableManager(
    _$PromptDatabase db,
    $ReviewFindingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewFindingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewFindingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewFindingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> opinionId = const Value.absent(),
                Value<String> file = const Value.absent(),
                Value<int> startLine = const Value.absent(),
                Value<int> endLine = const Value.absent(),
                Value<String> side = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> expectedBehavior = const Value.absent(),
                Value<String> observedBehavior = const Value.absent(),
                Value<String> preconditions = const Value.absent(),
                Value<String> reproduction = const Value.absent(),
                Value<String> impact = const Value.absent(),
                Value<String> suggestedTest = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewFindingsCompanion(
                id: id,
                opinionId: opinionId,
                file: file,
                startLine: startLine,
                endLine: endLine,
                side: side,
                category: category,
                severity: severity,
                confidence: confidence,
                title: title,
                description: description,
                expectedBehavior: expectedBehavior,
                observedBehavior: observedBehavior,
                preconditions: preconditions,
                reproduction: reproduction,
                impact: impact,
                suggestedTest: suggestedTest,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String opinionId,
                required String file,
                required int startLine,
                required int endLine,
                required String side,
                required String category,
                required String severity,
                required double confidence,
                required String title,
                required String description,
                required String expectedBehavior,
                required String observedBehavior,
                required String preconditions,
                required String reproduction,
                required String impact,
                required String suggestedTest,
                Value<int> rowid = const Value.absent(),
              }) => ReviewFindingsCompanion.insert(
                id: id,
                opinionId: opinionId,
                file: file,
                startLine: startLine,
                endLine: endLine,
                side: side,
                category: category,
                severity: severity,
                confidence: confidence,
                title: title,
                description: description,
                expectedBehavior: expectedBehavior,
                observedBehavior: observedBehavior,
                preconditions: preconditions,
                reproduction: reproduction,
                impact: impact,
                suggestedTest: suggestedTest,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewFindingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                opinionId = false,
                reviewEvidenceEntriesRefs = false,
                reviewDisagreementSourcesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (reviewEvidenceEntriesRefs) db.reviewEvidenceEntries,
                    if (reviewDisagreementSourcesRefs)
                      db.reviewDisagreementSources,
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
                        if (opinionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.opinionId,
                                    referencedTable:
                                        $$ReviewFindingsTableReferences
                                            ._opinionIdTable(db),
                                    referencedColumn:
                                        $$ReviewFindingsTableReferences
                                            ._opinionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (reviewEvidenceEntriesRefs)
                        await $_getPrefetchedData<
                          ReviewFinding,
                          $ReviewFindingsTable,
                          ReviewEvidenceEntry
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewFindingsTableReferences
                              ._reviewEvidenceEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewFindingsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewEvidenceEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.findingId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewDisagreementSourcesRefs)
                        await $_getPrefetchedData<
                          ReviewFinding,
                          $ReviewFindingsTable,
                          ReviewDisagreementSource
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewFindingsTableReferences
                              ._reviewDisagreementSourcesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewFindingsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewDisagreementSourcesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.findingId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ReviewFindingsTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewFindingsTable,
      ReviewFinding,
      $$ReviewFindingsTableFilterComposer,
      $$ReviewFindingsTableOrderingComposer,
      $$ReviewFindingsTableAnnotationComposer,
      $$ReviewFindingsTableCreateCompanionBuilder,
      $$ReviewFindingsTableUpdateCompanionBuilder,
      (ReviewFinding, $$ReviewFindingsTableReferences),
      ReviewFinding,
      PrefetchHooks Function({
        bool opinionId,
        bool reviewEvidenceEntriesRefs,
        bool reviewDisagreementSourcesRefs,
      })
    >;
typedef $$ReviewEvidenceEntriesTableCreateCompanionBuilder =
    ReviewEvidenceEntriesCompanion Function({
      Value<int> id,
      required String findingId,
      required String kind,
      required String evidenceText,
    });
typedef $$ReviewEvidenceEntriesTableUpdateCompanionBuilder =
    ReviewEvidenceEntriesCompanion Function({
      Value<int> id,
      Value<String> findingId,
      Value<String> kind,
      Value<String> evidenceText,
    });

final class $$ReviewEvidenceEntriesTableReferences
    extends
        BaseReferences<
          _$PromptDatabase,
          $ReviewEvidenceEntriesTable,
          ReviewEvidenceEntry
        > {
  $$ReviewEvidenceEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ReviewFindingsTable _findingIdTable(_$PromptDatabase db) => db
      .reviewFindings
      .createAlias('review_evidence_entries__finding_id__review_findings__id');

  $$ReviewFindingsTableProcessedTableManager get findingId {
    final $_column = $_itemColumn<String>('finding_id')!;

    final manager = $$ReviewFindingsTableTableManager(
      $_db,
      $_db.reviewFindings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_findingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewEvidenceEntriesTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewEvidenceEntriesTable> {
  $$ReviewEvidenceEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceText => $composableBuilder(
    column: $table.evidenceText,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewFindingsTableFilterComposer get findingId {
    final $$ReviewFindingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.findingId,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableFilterComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewEvidenceEntriesTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewEvidenceEntriesTable> {
  $$ReviewEvidenceEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceText => $composableBuilder(
    column: $table.evidenceText,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewFindingsTableOrderingComposer get findingId {
    final $$ReviewFindingsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.findingId,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableOrderingComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewEvidenceEntriesTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewEvidenceEntriesTable> {
  $$ReviewEvidenceEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get evidenceText => $composableBuilder(
    column: $table.evidenceText,
    builder: (column) => column,
  );

  $$ReviewFindingsTableAnnotationComposer get findingId {
    final $$ReviewFindingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.findingId,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewEvidenceEntriesTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewEvidenceEntriesTable,
          ReviewEvidenceEntry,
          $$ReviewEvidenceEntriesTableFilterComposer,
          $$ReviewEvidenceEntriesTableOrderingComposer,
          $$ReviewEvidenceEntriesTableAnnotationComposer,
          $$ReviewEvidenceEntriesTableCreateCompanionBuilder,
          $$ReviewEvidenceEntriesTableUpdateCompanionBuilder,
          (ReviewEvidenceEntry, $$ReviewEvidenceEntriesTableReferences),
          ReviewEvidenceEntry,
          PrefetchHooks Function({bool findingId})
        > {
  $$ReviewEvidenceEntriesTableTableManager(
    _$PromptDatabase db,
    $ReviewEvidenceEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewEvidenceEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReviewEvidenceEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReviewEvidenceEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> findingId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> evidenceText = const Value.absent(),
              }) => ReviewEvidenceEntriesCompanion(
                id: id,
                findingId: findingId,
                kind: kind,
                evidenceText: evidenceText,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String findingId,
                required String kind,
                required String evidenceText,
              }) => ReviewEvidenceEntriesCompanion.insert(
                id: id,
                findingId: findingId,
                kind: kind,
                evidenceText: evidenceText,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewEvidenceEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({findingId = false}) {
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
                    if (findingId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.findingId,
                                referencedTable:
                                    $$ReviewEvidenceEntriesTableReferences
                                        ._findingIdTable(db),
                                referencedColumn:
                                    $$ReviewEvidenceEntriesTableReferences
                                        ._findingIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$ReviewEvidenceEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewEvidenceEntriesTable,
      ReviewEvidenceEntry,
      $$ReviewEvidenceEntriesTableFilterComposer,
      $$ReviewEvidenceEntriesTableOrderingComposer,
      $$ReviewEvidenceEntriesTableAnnotationComposer,
      $$ReviewEvidenceEntriesTableCreateCompanionBuilder,
      $$ReviewEvidenceEntriesTableUpdateCompanionBuilder,
      (ReviewEvidenceEntry, $$ReviewEvidenceEntriesTableReferences),
      ReviewEvidenceEntry,
      PrefetchHooks Function({bool findingId})
    >;
typedef $$ReviewDisagreementsTableCreateCompanionBuilder =
    ReviewDisagreementsCompanion Function({
      required String id,
      required String reviewId,
      Value<int> rowid,
    });
typedef $$ReviewDisagreementsTableUpdateCompanionBuilder =
    ReviewDisagreementsCompanion Function({
      Value<String> id,
      Value<String> reviewId,
      Value<int> rowid,
    });

final class $$ReviewDisagreementsTableReferences
    extends
        BaseReferences<
          _$PromptDatabase,
          $ReviewDisagreementsTable,
          ReviewDisagreement
        > {
  $$ReviewDisagreementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ReviewRunsTable _reviewIdTable(_$PromptDatabase db) => db.reviewRuns
      .createAlias('review_disagreements__review_id__review_runs__id');

  $$ReviewRunsTableProcessedTableManager get reviewId {
    final $_column = $_itemColumn<String>('review_id')!;

    final manager = $$ReviewRunsTableTableManager(
      $_db,
      $_db.reviewRuns,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_reviewIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $ReviewDisagreementSourcesTable,
    List<ReviewDisagreementSource>
  >
  _reviewDisagreementSourcesRefsTable(
    _$PromptDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.reviewDisagreementSources,
    aliasName:
        'review_disagreements__id__review_disagreement_sources__disagreement_id',
  );

  $$ReviewDisagreementSourcesTableProcessedTableManager
  get reviewDisagreementSourcesRefs {
    final manager = $$ReviewDisagreementSourcesTableTableManager(
      $_db,
      $_db.reviewDisagreementSources,
    ).filter((f) => f.disagreementId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewDisagreementSourcesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ReviewDisagreementsTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewDisagreementsTable> {
  $$ReviewDisagreementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewRunsTableFilterComposer get reviewId {
    final $$ReviewRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableFilterComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> reviewDisagreementSourcesRefs(
    Expression<bool> Function($$ReviewDisagreementSourcesTableFilterComposer f)
    f,
  ) {
    final $$ReviewDisagreementSourcesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewDisagreementSources,
          getReferencedColumn: (t) => t.disagreementId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementSourcesTableFilterComposer(
                $db: $db,
                $table: $db.reviewDisagreementSources,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ReviewDisagreementsTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewDisagreementsTable> {
  $$ReviewDisagreementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewRunsTableOrderingComposer get reviewId {
    final $$ReviewRunsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableOrderingComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDisagreementsTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewDisagreementsTable> {
  $$ReviewDisagreementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$ReviewRunsTableAnnotationComposer get reviewId {
    final $$ReviewRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reviewId,
      referencedTable: $db.reviewRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> reviewDisagreementSourcesRefs<T extends Object>(
    Expression<T> Function($$ReviewDisagreementSourcesTableAnnotationComposer a)
    f,
  ) {
    final $$ReviewDisagreementSourcesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reviewDisagreementSources,
          getReferencedColumn: (t) => t.disagreementId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementSourcesTableAnnotationComposer(
                $db: $db,
                $table: $db.reviewDisagreementSources,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ReviewDisagreementsTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewDisagreementsTable,
          ReviewDisagreement,
          $$ReviewDisagreementsTableFilterComposer,
          $$ReviewDisagreementsTableOrderingComposer,
          $$ReviewDisagreementsTableAnnotationComposer,
          $$ReviewDisagreementsTableCreateCompanionBuilder,
          $$ReviewDisagreementsTableUpdateCompanionBuilder,
          (ReviewDisagreement, $$ReviewDisagreementsTableReferences),
          ReviewDisagreement,
          PrefetchHooks Function({
            bool reviewId,
            bool reviewDisagreementSourcesRefs,
          })
        > {
  $$ReviewDisagreementsTableTableManager(
    _$PromptDatabase db,
    $ReviewDisagreementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewDisagreementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewDisagreementsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReviewDisagreementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> reviewId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewDisagreementsCompanion(
                id: id,
                reviewId: reviewId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String reviewId,
                Value<int> rowid = const Value.absent(),
              }) => ReviewDisagreementsCompanion.insert(
                id: id,
                reviewId: reviewId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewDisagreementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({reviewId = false, reviewDisagreementSourcesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (reviewDisagreementSourcesRefs)
                      db.reviewDisagreementSources,
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
                        if (reviewId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.reviewId,
                                    referencedTable:
                                        $$ReviewDisagreementsTableReferences
                                            ._reviewIdTable(db),
                                    referencedColumn:
                                        $$ReviewDisagreementsTableReferences
                                            ._reviewIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (reviewDisagreementSourcesRefs)
                        await $_getPrefetchedData<
                          ReviewDisagreement,
                          $ReviewDisagreementsTable,
                          ReviewDisagreementSource
                        >(
                          currentTable: table,
                          referencedTable: $$ReviewDisagreementsTableReferences
                              ._reviewDisagreementSourcesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ReviewDisagreementsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewDisagreementSourcesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.disagreementId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ReviewDisagreementsTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewDisagreementsTable,
      ReviewDisagreement,
      $$ReviewDisagreementsTableFilterComposer,
      $$ReviewDisagreementsTableOrderingComposer,
      $$ReviewDisagreementsTableAnnotationComposer,
      $$ReviewDisagreementsTableCreateCompanionBuilder,
      $$ReviewDisagreementsTableUpdateCompanionBuilder,
      (ReviewDisagreement, $$ReviewDisagreementsTableReferences),
      ReviewDisagreement,
      PrefetchHooks Function({
        bool reviewId,
        bool reviewDisagreementSourcesRefs,
      })
    >;
typedef $$ReviewDisagreementSourcesTableCreateCompanionBuilder =
    ReviewDisagreementSourcesCompanion Function({
      Value<int> id,
      required String disagreementId,
      required String findingId,
      required String role,
    });
typedef $$ReviewDisagreementSourcesTableUpdateCompanionBuilder =
    ReviewDisagreementSourcesCompanion Function({
      Value<int> id,
      Value<String> disagreementId,
      Value<String> findingId,
      Value<String> role,
    });

final class $$ReviewDisagreementSourcesTableReferences
    extends
        BaseReferences<
          _$PromptDatabase,
          $ReviewDisagreementSourcesTable,
          ReviewDisagreementSource
        > {
  $$ReviewDisagreementSourcesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ReviewDisagreementsTable _disagreementIdTable(
    _$PromptDatabase db,
  ) => db.reviewDisagreements.createAlias(
    'review_disagreement_sources__disagreement_id__review_disagreements__id',
  );

  $$ReviewDisagreementsTableProcessedTableManager get disagreementId {
    final $_column = $_itemColumn<String>('disagreement_id')!;

    final manager = $$ReviewDisagreementsTableTableManager(
      $_db,
      $_db.reviewDisagreements,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_disagreementIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ReviewFindingsTable _findingIdTable(_$PromptDatabase db) =>
      db.reviewFindings.createAlias(
        'review_disagreement_sources__finding_id__review_findings__id',
      );

  $$ReviewFindingsTableProcessedTableManager get findingId {
    final $_column = $_itemColumn<String>('finding_id')!;

    final manager = $$ReviewFindingsTableTableManager(
      $_db,
      $_db.reviewFindings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_findingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewDisagreementSourcesTableFilterComposer
    extends Composer<_$PromptDatabase, $ReviewDisagreementSourcesTable> {
  $$ReviewDisagreementSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  $$ReviewDisagreementsTableFilterComposer get disagreementId {
    final $$ReviewDisagreementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.disagreementId,
      referencedTable: $db.reviewDisagreements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewDisagreementsTableFilterComposer(
            $db: $db,
            $table: $db.reviewDisagreements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ReviewFindingsTableFilterComposer get findingId {
    final $$ReviewFindingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.findingId,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableFilterComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDisagreementSourcesTableOrderingComposer
    extends Composer<_$PromptDatabase, $ReviewDisagreementSourcesTable> {
  $$ReviewDisagreementSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  $$ReviewDisagreementsTableOrderingComposer get disagreementId {
    final $$ReviewDisagreementsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.disagreementId,
          referencedTable: $db.reviewDisagreements,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementsTableOrderingComposer(
                $db: $db,
                $table: $db.reviewDisagreements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ReviewFindingsTableOrderingComposer get findingId {
    final $$ReviewFindingsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.findingId,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableOrderingComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDisagreementSourcesTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ReviewDisagreementSourcesTable> {
  $$ReviewDisagreementSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  $$ReviewDisagreementsTableAnnotationComposer get disagreementId {
    final $$ReviewDisagreementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.disagreementId,
          referencedTable: $db.reviewDisagreements,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReviewDisagreementsTableAnnotationComposer(
                $db: $db,
                $table: $db.reviewDisagreements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ReviewFindingsTableAnnotationComposer get findingId {
    final $$ReviewFindingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.findingId,
      referencedTable: $db.reviewFindings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewFindingsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDisagreementSourcesTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ReviewDisagreementSourcesTable,
          ReviewDisagreementSource,
          $$ReviewDisagreementSourcesTableFilterComposer,
          $$ReviewDisagreementSourcesTableOrderingComposer,
          $$ReviewDisagreementSourcesTableAnnotationComposer,
          $$ReviewDisagreementSourcesTableCreateCompanionBuilder,
          $$ReviewDisagreementSourcesTableUpdateCompanionBuilder,
          (
            ReviewDisagreementSource,
            $$ReviewDisagreementSourcesTableReferences,
          ),
          ReviewDisagreementSource,
          PrefetchHooks Function({bool disagreementId, bool findingId})
        > {
  $$ReviewDisagreementSourcesTableTableManager(
    _$PromptDatabase db,
    $ReviewDisagreementSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewDisagreementSourcesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReviewDisagreementSourcesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReviewDisagreementSourcesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> disagreementId = const Value.absent(),
                Value<String> findingId = const Value.absent(),
                Value<String> role = const Value.absent(),
              }) => ReviewDisagreementSourcesCompanion(
                id: id,
                disagreementId: disagreementId,
                findingId: findingId,
                role: role,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String disagreementId,
                required String findingId,
                required String role,
              }) => ReviewDisagreementSourcesCompanion.insert(
                id: id,
                disagreementId: disagreementId,
                findingId: findingId,
                role: role,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReviewDisagreementSourcesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({disagreementId = false, findingId = false}) {
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
                    if (disagreementId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.disagreementId,
                                referencedTable:
                                    $$ReviewDisagreementSourcesTableReferences
                                        ._disagreementIdTable(db),
                                referencedColumn:
                                    $$ReviewDisagreementSourcesTableReferences
                                        ._disagreementIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (findingId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.findingId,
                                referencedTable:
                                    $$ReviewDisagreementSourcesTableReferences
                                        ._findingIdTable(db),
                                referencedColumn:
                                    $$ReviewDisagreementSourcesTableReferences
                                        ._findingIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$ReviewDisagreementSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ReviewDisagreementSourcesTable,
      ReviewDisagreementSource,
      $$ReviewDisagreementSourcesTableFilterComposer,
      $$ReviewDisagreementSourcesTableOrderingComposer,
      $$ReviewDisagreementSourcesTableAnnotationComposer,
      $$ReviewDisagreementSourcesTableCreateCompanionBuilder,
      $$ReviewDisagreementSourcesTableUpdateCompanionBuilder,
      (ReviewDisagreementSource, $$ReviewDisagreementSourcesTableReferences),
      ReviewDisagreementSource,
      PrefetchHooks Function({bool disagreementId, bool findingId})
    >;

class $PromptDatabaseManager {
  final _$PromptDatabase _db;
  $PromptDatabaseManager(this._db);
  $$ServerProfilesTableTableManager get serverProfiles =>
      $$ServerProfilesTableTableManager(_db, _db.serverProfiles);
  $$QueuedPromptsTableTableManager get queuedPrompts =>
      $$QueuedPromptsTableTableManager(_db, _db.queuedPrompts);
  $$ReviewRunsTableTableManager get reviewRuns =>
      $$ReviewRunsTableTableManager(_db, _db.reviewRuns);
  $$ReviewFilesTableTableManager get reviewFiles =>
      $$ReviewFilesTableTableManager(_db, _db.reviewFiles);
  $$ReviewPassesTableTableManager get reviewPasses =>
      $$ReviewPassesTableTableManager(_db, _db.reviewPasses);
  $$ReviewOpinionsTableTableManager get reviewOpinions =>
      $$ReviewOpinionsTableTableManager(_db, _db.reviewOpinions);
  $$ReviewFindingsTableTableManager get reviewFindings =>
      $$ReviewFindingsTableTableManager(_db, _db.reviewFindings);
  $$ReviewEvidenceEntriesTableTableManager get reviewEvidenceEntries =>
      $$ReviewEvidenceEntriesTableTableManager(_db, _db.reviewEvidenceEntries);
  $$ReviewDisagreementsTableTableManager get reviewDisagreements =>
      $$ReviewDisagreementsTableTableManager(_db, _db.reviewDisagreements);
  $$ReviewDisagreementSourcesTableTableManager get reviewDisagreementSources =>
      $$ReviewDisagreementSourcesTableTableManager(
        _db,
        _db.reviewDisagreementSources,
      );
}
