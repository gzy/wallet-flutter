import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用沙盒内 SQLite 文件（不存放助记词等敏感项）。
QueryExecutor openLocalDrift() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'uone_local_cache.db'));
    return NativeDatabase.createInBackground(file);
  });
}
