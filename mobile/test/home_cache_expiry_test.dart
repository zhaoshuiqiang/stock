import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/storage/database_service.dart';

/// v4.17: home_cache used to return entries regardless of age, so the home
/// screen could paint a previous day's market snapshot. getHomeCache(freshDaily:
/// true) now drops entries saved on an earlier Beijing calendar day.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<DatabaseService> newService() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE home_cache (key TEXT PRIMARY KEY, '
        'value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
      ),
    );
    final service = DatabaseService();
    service.resetForTesting();
    await service.setDatabaseForTesting(db);
    return service;
  }

  test('freshDaily keeps a same-day entry', () async {
    final service = await newService();
    await service.saveHomeCache('market_quotes', 'today');
    expect(await service.getHomeCache('market_quotes', freshDaily: true),
        equals('today'));
  });

  test('freshDaily drops a previous-day entry', () async {
    final service = await newService();
    final db = await service.database;
    final staleMs = DateTime.now()
        .subtract(const Duration(days: 2))
        .millisecondsSinceEpoch;
    await db.insert('home_cache',
        {'key': 'hot_sectors', 'value': 'stale', 'updated_at': staleMs});

    // freshDaily => cross-day entry is treated as stale.
    expect(await service.getHomeCache('hot_sectors', freshDaily: true), isNull);
    // Default (legacy) behavior is unchanged: the value is still returned.
    expect(await service.getHomeCache('hot_sectors'), equals('stale'));
  });
}
