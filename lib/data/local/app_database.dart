import 'package:drift/drift.dart';

import 'connection.dart';

part 'app_database.g.dart';

class CacheEntries extends Table {
  TextColumn get key => text()();
  TextColumn get payload => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 与「地址+链+币」为维度的历史记录缓存（`scopeKey` 由 [AppLocalCache] 构造）。
class CachedTxs extends Table {
  TextColumn get scopeKey => text()();
  TextColumn get txHash => text()();
  TextColumn get payloadJson => text()();
  IntColumn get sortTimeMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {scopeKey, txHash};
}

@DriftDatabase(tables: [CacheEntries, CachedTxs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openLocalDrift());

  @override
  int get schemaVersion => 1;
}
