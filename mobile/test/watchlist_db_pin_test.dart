import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/storage/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    DatabaseService().resetForTesting();
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE watchlist (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            added_at INTEGER NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    await DatabaseService().setDatabaseForTesting(db);
  });

  tearDown(() async {
    await db.close();
    DatabaseService().resetForTesting();
  });

  test('batchAddToWatchlist preserves isPinned flag', () async {
    final service = DatabaseService();

    await service.batchAddToWatchlist([
      WatchlistItem(code: '000001', name: 'Normal'),
      WatchlistItem(code: '600000', name: 'Holding', isPinned: true),
    ]);

    final rows = await service.getWatchlist();

    expect(rows.first.code, '600000');
    expect(rows.first.isPinned, isTrue);
    expect(rows.last.code, '000001');
    expect(rows.last.isPinned, isFalse);
  });

  test('addToWatchlist can insert a pinned imported holding', () async {
    final service = DatabaseService();

    await service.addToWatchlist('600000', 'Holding', isPinned: true);

    final rows = await service.getWatchlist();

    expect(rows.single.code, '600000');
    expect(rows.single.isPinned, isTrue);
  });
}
