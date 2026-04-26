// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, payload, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(Insertable<CacheEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntry(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntry extends DataClass implements Insertable<CacheEntry> {
  final String key;
  final String payload;
  final int updatedAt;
  const CacheEntry(
      {required this.key, required this.payload, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['payload'] = Variable<String>(payload);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      key: Value(key),
      payload: Value(payload),
      updatedAt: Value(updatedAt),
    );
  }

  factory CacheEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntry(
      key: serializer.fromJson<String>(json['key']),
      payload: serializer.fromJson<String>(json['payload']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'payload': serializer.toJson<String>(payload),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CacheEntry copyWith({String? key, String? payload, int? updatedAt}) =>
      CacheEntry(
        key: key ?? this.key,
        payload: payload ?? this.payload,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CacheEntry copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntry(
      key: data.key.present ? data.key.value : this.key,
      payload: data.payload.present ? data.payload.value : this.payload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntry(')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, payload, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntry &&
          other.key == this.key &&
          other.payload == this.payload &&
          other.updatedAt == this.updatedAt);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntry> {
  final Value<String> key;
  final Value<String> payload;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.key = const Value.absent(),
    this.payload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String key,
    required String payload,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        payload = Value(payload),
        updatedAt = Value(updatedAt);
  static Insertable<CacheEntry> custom({
    Expression<String>? key,
    Expression<String>? payload,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (payload != null) 'payload': payload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith(
      {Value<String>? key,
      Value<String>? payload,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return CacheEntriesCompanion(
      key: key ?? this.key,
      payload: payload ?? this.payload,
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
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedTxsTable extends CachedTxs
    with TableInfo<$CachedTxsTable, CachedTx> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTxsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeKeyMeta =
      const VerificationMeta('scopeKey');
  @override
  late final GeneratedColumn<String> scopeKey = GeneratedColumn<String>(
      'scope_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _txHashMeta = const VerificationMeta('txHash');
  @override
  late final GeneratedColumn<String> txHash = GeneratedColumn<String>(
      'tx_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sortTimeMsMeta =
      const VerificationMeta('sortTimeMs');
  @override
  late final GeneratedColumn<int> sortTimeMs = GeneratedColumn<int>(
      'sort_time_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [scopeKey, txHash, payloadJson, sortTimeMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_txs';
  @override
  VerificationContext validateIntegrity(Insertable<CachedTx> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope_key')) {
      context.handle(_scopeKeyMeta,
          scopeKey.isAcceptableOrUnknown(data['scope_key']!, _scopeKeyMeta));
    } else if (isInserting) {
      context.missing(_scopeKeyMeta);
    }
    if (data.containsKey('tx_hash')) {
      context.handle(_txHashMeta,
          txHash.isAcceptableOrUnknown(data['tx_hash']!, _txHashMeta));
    } else if (isInserting) {
      context.missing(_txHashMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('sort_time_ms')) {
      context.handle(
          _sortTimeMsMeta,
          sortTimeMs.isAcceptableOrUnknown(
              data['sort_time_ms']!, _sortTimeMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scopeKey, txHash};
  @override
  CachedTx map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTx(
      scopeKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scope_key'])!,
      txHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tx_hash'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      sortTimeMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_time_ms']),
    );
  }

  @override
  $CachedTxsTable createAlias(String alias) {
    return $CachedTxsTable(attachedDatabase, alias);
  }
}

class CachedTx extends DataClass implements Insertable<CachedTx> {
  final String scopeKey;
  final String txHash;
  final String payloadJson;
  final int? sortTimeMs;
  const CachedTx(
      {required this.scopeKey,
      required this.txHash,
      required this.payloadJson,
      this.sortTimeMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope_key'] = Variable<String>(scopeKey);
    map['tx_hash'] = Variable<String>(txHash);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || sortTimeMs != null) {
      map['sort_time_ms'] = Variable<int>(sortTimeMs);
    }
    return map;
  }

  CachedTxsCompanion toCompanion(bool nullToAbsent) {
    return CachedTxsCompanion(
      scopeKey: Value(scopeKey),
      txHash: Value(txHash),
      payloadJson: Value(payloadJson),
      sortTimeMs: sortTimeMs == null && nullToAbsent
          ? const Value.absent()
          : Value(sortTimeMs),
    );
  }

  factory CachedTx.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTx(
      scopeKey: serializer.fromJson<String>(json['scopeKey']),
      txHash: serializer.fromJson<String>(json['txHash']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      sortTimeMs: serializer.fromJson<int?>(json['sortTimeMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scopeKey': serializer.toJson<String>(scopeKey),
      'txHash': serializer.toJson<String>(txHash),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'sortTimeMs': serializer.toJson<int?>(sortTimeMs),
    };
  }

  CachedTx copyWith(
          {String? scopeKey,
          String? txHash,
          String? payloadJson,
          Value<int?> sortTimeMs = const Value.absent()}) =>
      CachedTx(
        scopeKey: scopeKey ?? this.scopeKey,
        txHash: txHash ?? this.txHash,
        payloadJson: payloadJson ?? this.payloadJson,
        sortTimeMs: sortTimeMs.present ? sortTimeMs.value : this.sortTimeMs,
      );
  CachedTx copyWithCompanion(CachedTxsCompanion data) {
    return CachedTx(
      scopeKey: data.scopeKey.present ? data.scopeKey.value : this.scopeKey,
      txHash: data.txHash.present ? data.txHash.value : this.txHash,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      sortTimeMs:
          data.sortTimeMs.present ? data.sortTimeMs.value : this.sortTimeMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTx(')
          ..write('scopeKey: $scopeKey, ')
          ..write('txHash: $txHash, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('sortTimeMs: $sortTimeMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scopeKey, txHash, payloadJson, sortTimeMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTx &&
          other.scopeKey == this.scopeKey &&
          other.txHash == this.txHash &&
          other.payloadJson == this.payloadJson &&
          other.sortTimeMs == this.sortTimeMs);
}

class CachedTxsCompanion extends UpdateCompanion<CachedTx> {
  final Value<String> scopeKey;
  final Value<String> txHash;
  final Value<String> payloadJson;
  final Value<int?> sortTimeMs;
  final Value<int> rowid;
  const CachedTxsCompanion({
    this.scopeKey = const Value.absent(),
    this.txHash = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.sortTimeMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTxsCompanion.insert({
    required String scopeKey,
    required String txHash,
    required String payloadJson,
    this.sortTimeMs = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : scopeKey = Value(scopeKey),
        txHash = Value(txHash),
        payloadJson = Value(payloadJson);
  static Insertable<CachedTx> custom({
    Expression<String>? scopeKey,
    Expression<String>? txHash,
    Expression<String>? payloadJson,
    Expression<int>? sortTimeMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scopeKey != null) 'scope_key': scopeKey,
      if (txHash != null) 'tx_hash': txHash,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (sortTimeMs != null) 'sort_time_ms': sortTimeMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTxsCompanion copyWith(
      {Value<String>? scopeKey,
      Value<String>? txHash,
      Value<String>? payloadJson,
      Value<int?>? sortTimeMs,
      Value<int>? rowid}) {
    return CachedTxsCompanion(
      scopeKey: scopeKey ?? this.scopeKey,
      txHash: txHash ?? this.txHash,
      payloadJson: payloadJson ?? this.payloadJson,
      sortTimeMs: sortTimeMs ?? this.sortTimeMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scopeKey.present) {
      map['scope_key'] = Variable<String>(scopeKey.value);
    }
    if (txHash.present) {
      map['tx_hash'] = Variable<String>(txHash.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (sortTimeMs.present) {
      map['sort_time_ms'] = Variable<int>(sortTimeMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTxsCompanion(')
          ..write('scopeKey: $scopeKey, ')
          ..write('txHash: $txHash, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('sortTimeMs: $sortTimeMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  late final $CachedTxsTable cachedTxs = $CachedTxsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cacheEntries, cachedTxs];
}

typedef $$CacheEntriesTableCreateCompanionBuilder = CacheEntriesCompanion
    Function({
  required String key,
  required String payload,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$CacheEntriesTableUpdateCompanionBuilder = CacheEntriesCompanion
    Function({
  Value<String> key,
  Value<String> payload,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$CacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CacheEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CacheEntriesTable,
    CacheEntry,
    $$CacheEntriesTableFilterComposer,
    $$CacheEntriesTableOrderingComposer,
    $$CacheEntriesTableAnnotationComposer,
    $$CacheEntriesTableCreateCompanionBuilder,
    $$CacheEntriesTableUpdateCompanionBuilder,
    (CacheEntry, BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>),
    CacheEntry,
    PrefetchHooks Function()> {
  $$CacheEntriesTableTableManager(_$AppDatabase db, $CacheEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheEntriesCompanion(
            key: key,
            payload: payload,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String payload,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheEntriesCompanion.insert(
            key: key,
            payload: payload,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CacheEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CacheEntriesTable,
    CacheEntry,
    $$CacheEntriesTableFilterComposer,
    $$CacheEntriesTableOrderingComposer,
    $$CacheEntriesTableAnnotationComposer,
    $$CacheEntriesTableCreateCompanionBuilder,
    $$CacheEntriesTableUpdateCompanionBuilder,
    (CacheEntry, BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntry>),
    CacheEntry,
    PrefetchHooks Function()>;
typedef $$CachedTxsTableCreateCompanionBuilder = CachedTxsCompanion Function({
  required String scopeKey,
  required String txHash,
  required String payloadJson,
  Value<int?> sortTimeMs,
  Value<int> rowid,
});
typedef $$CachedTxsTableUpdateCompanionBuilder = CachedTxsCompanion Function({
  Value<String> scopeKey,
  Value<String> txHash,
  Value<String> payloadJson,
  Value<int?> sortTimeMs,
  Value<int> rowid,
});

class $$CachedTxsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTxsTable> {
  $$CachedTxsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scopeKey => $composableBuilder(
      column: $table.scopeKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get txHash => $composableBuilder(
      column: $table.txHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortTimeMs => $composableBuilder(
      column: $table.sortTimeMs, builder: (column) => ColumnFilters(column));
}

class $$CachedTxsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTxsTable> {
  $$CachedTxsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scopeKey => $composableBuilder(
      column: $table.scopeKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get txHash => $composableBuilder(
      column: $table.txHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortTimeMs => $composableBuilder(
      column: $table.sortTimeMs, builder: (column) => ColumnOrderings(column));
}

class $$CachedTxsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTxsTable> {
  $$CachedTxsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scopeKey =>
      $composableBuilder(column: $table.scopeKey, builder: (column) => column);

  GeneratedColumn<String> get txHash =>
      $composableBuilder(column: $table.txHash, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<int> get sortTimeMs => $composableBuilder(
      column: $table.sortTimeMs, builder: (column) => column);
}

class $$CachedTxsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedTxsTable,
    CachedTx,
    $$CachedTxsTableFilterComposer,
    $$CachedTxsTableOrderingComposer,
    $$CachedTxsTableAnnotationComposer,
    $$CachedTxsTableCreateCompanionBuilder,
    $$CachedTxsTableUpdateCompanionBuilder,
    (CachedTx, BaseReferences<_$AppDatabase, $CachedTxsTable, CachedTx>),
    CachedTx,
    PrefetchHooks Function()> {
  $$CachedTxsTableTableManager(_$AppDatabase db, $CachedTxsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTxsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTxsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTxsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> scopeKey = const Value.absent(),
            Value<String> txHash = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<int?> sortTimeMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTxsCompanion(
            scopeKey: scopeKey,
            txHash: txHash,
            payloadJson: payloadJson,
            sortTimeMs: sortTimeMs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String scopeKey,
            required String txHash,
            required String payloadJson,
            Value<int?> sortTimeMs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTxsCompanion.insert(
            scopeKey: scopeKey,
            txHash: txHash,
            payloadJson: payloadJson,
            sortTimeMs: sortTimeMs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedTxsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedTxsTable,
    CachedTx,
    $$CachedTxsTableFilterComposer,
    $$CachedTxsTableOrderingComposer,
    $$CachedTxsTableAnnotationComposer,
    $$CachedTxsTableCreateCompanionBuilder,
    $$CachedTxsTableUpdateCompanionBuilder,
    (CachedTx, BaseReferences<_$AppDatabase, $CachedTxsTable, CachedTx>),
    CachedTx,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
  $$CachedTxsTableTableManager get cachedTxs =>
      $$CachedTxsTableTableManager(_db, _db.cachedTxs);
}
