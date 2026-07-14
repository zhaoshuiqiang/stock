import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/storage/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v20 to v21 migration preserves legacy data and creates constraints',
      () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 20,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE archive_records (id INTEGER PRIMARY KEY, code TEXT)');
        await db.execute(
            'CREATE TABLE recommendation_tracking (id INTEGER PRIMARY KEY, code TEXT)');
        await db.insert('archive_records', {'id': 1, 'code': '000001'});
        await db.insert('recommendation_tracking', {'id': 1, 'code': '600519'});
      },
    );

    await DatabaseService.upgradeDatabaseForTesting(db, 20, 21);

    expect(await db.query('archive_records'), hasLength(1));
    expect(await db.query('recommendation_tracking'), hasLength(1));
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'decision_%'",
    );
    expect(tables.map((row) => row['name']),
        containsAll(['decision_snapshots', 'decision_outcomes']));

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_decision_%'",
    );
    expect(
      indexes.map((row) => row['name']),
      containsAll([
        'idx_decision_snapshots_trade_date',
        'idx_decision_snapshots_filter',
        'idx_decision_outcomes_pending',
      ]),
    );

    await expectLater(
      db.insert('decision_snapshots', _snapshotMap(directionScore: 101)),
      throwsA(anything),
    );
    final snapshotId = await db.insert(
      'decision_snapshots',
      _snapshotMap(directionScore: 50),
    );
    await expectLater(
      db.insert('decision_outcomes', {'snapshot_id': snapshotId, 'horizon': 2}),
      throwsA(anything),
    );
    await db
        .delete('decision_snapshots', where: 'id = ?', whereArgs: [snapshotId]);
    expect(await db.query('decision_outcomes'), isEmpty);
    await db.close();
  });
}

Map<String, Object?> _snapshotMap({required double directionScore}) => {
      'code': '000001',
      'name': '',
      'source': 'test',
      'signal_time': DateTime(2026, 7, 14).millisecondsSinceEpoch,
      'signal_trade_date': '2026-07-14',
      'signal_price': 10.0,
      'benchmark_code': '000300',
      'direction': 'bullish',
      'direction_score': directionScore,
      'trade_quality_score': 70.0,
      'risk_score': 30.0,
      'evidence_confidence': 75.0,
      'recommendation_level': 'bullish',
      'recommendation_label': '看多',
      'legacy_score': 8,
      'market_regime': 'bullishTrend',
      'model_version': 'v2',
      'created_at': DateTime(2026, 7, 14).millisecondsSinceEpoch,
    };
