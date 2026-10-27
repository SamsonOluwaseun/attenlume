import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// The single app database. Tests override this with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});
