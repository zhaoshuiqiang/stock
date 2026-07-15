import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/analysis/archive_service.dart';
import 'package:stock_analyzer/analysis/decision_market_data_provider.dart';
import 'package:stock_analyzer/analysis/decision_tracker.dart';
import 'package:stock_analyzer/analysis/opportunity_engine.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/storage/database_service.dart';
import 'package:stock_analyzer/storage/decision_tracking_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late DatabaseService storage;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE archive_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            change_pct REAL NOT NULL,
            score INTEGER NOT NULL,
            recommendation TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            buy_signal_count INTEGER NOT NULL DEFAULT 0,
            sell_signal_count INTEGER NOT NULL DEFAULT 0,
            active_strategy_count INTEGER NOT NULL DEFAULT 0,
            confluence_score INTEGER NOT NULL DEFAULT 0,
            trade_levels_json TEXT,
            top_signals TEXT DEFAULT '',
            archived_at INTEGER NOT NULL
          )
        ''');
        await createDecisionTrackingSchema(db);
      },
    );
    storage = DatabaseService();
    storage.resetForTesting();
    await storage.setDatabaseForTesting(db);
  });

  tearDown(() async => db.close());

  test('archiveStock 同时写入 archive_records 与 decision_snapshots', () async {
    final analysis = _analysis('000001', RecommendationDirection.bullish);
    final result = await ArchiveService.archiveStock(
      code: '000001',
      name: '平安银行',
      analysis: analysis,
      db: storage,
    );

    expect(result.archived, isTrue);
    expect(result.captured, isTrue);
    expect(await db.query('archive_records'), hasLength(1));
    expect(await db.query('decision_snapshots'), hasLength(1));
    expect(await db.query('decision_outcomes'), hasLength(3));

    final snap = (await db.query('decision_snapshots')).first;
    expect(snap['source'], ArchiveService.kManualSource);
  });

  test('无 shortTermDecision 时仍写 archive_records 且不抛异常、不写快照', () async {
    final analysis = AnalysisResult(
      quote: QuoteData(code: '000002', name: '浦发银行', price: 9),
      score: 5,
      recommendation: '观望',
    );
    final result = await ArchiveService.archiveStock(
      code: '000002',
      name: '浦发银行',
      analysis: analysis,
      db: storage,
    );

    expect(result.archived, isTrue);
    expect(result.captured, isFalse);
    expect(await db.query('archive_records'), hasLength(1));
    expect(await db.query('decision_snapshots'), hasLength(0));
  });

  test('由 OpportunityResult 直接捕获决策快照（不触发联网重分析）', () async {
    final opp = OpportunityResult(
      code: '000004',
      name: '招商银行',
      price: 35.5,
      changePct: 1.2,
      score: 8,
      recommendation: '买入',
      riskLevel: '低',
      buySignalCount: 3,
      sellSignalCount: 0,
      activeStrategyCount: 2,
      confluenceScore: 80,
      shortTermDecision: ShortTermDecision(
        directionScore: 70,
        tradeQualityScore: 75,
        riskScore: 30,
        evidenceConfidence: 72,
        direction: RecommendationDirection.bullish,
        marketRegime: MarketRegime.range,
        modelVersion: 'short-term-v2',
        rawComprehensiveScore: 7,
      ),
    );
    final result = await ArchiveService.archiveStock(
      code: opp.code,
      name: opp.name,
      opp: opp,
      db: storage,
      skipArchiveRecord: true,
    );

    expect(result.archived, isFalse);
    expect(result.captured, isTrue);
    expect(await db.query('decision_snapshots'), hasLength(1));
    final snap = (await db.query('decision_snapshots')).first;
    expect(snap['source'], ArchiveService.kManualSource);
    expect(snap['code'], '000004');
  });

  test('skipRefreshPending 时不触发 refreshPending 仍完成捕获', () async {
    final opp = OpportunityResult(
      code: '000005',
      name: '兴业银行',
      price: 18.0,
      changePct: -0.5,
      score: 6,
      recommendation: '观望',
      riskLevel: '中',
      buySignalCount: 1,
      sellSignalCount: 1,
      activeStrategyCount: 1,
      confluenceScore: 60,
      shortTermDecision: ShortTermDecision(
        directionScore: 10,
        tradeQualityScore: 50,
        riskScore: 45,
        evidenceConfidence: 60,
        direction: RecommendationDirection.neutral,
        marketRegime: MarketRegime.range,
        modelVersion: 'short-term-v2',
        rawComprehensiveScore: 5,
      ),
    );
    final result = await ArchiveService.archiveStock(
      code: opp.code,
      name: opp.name,
      opp: opp,
      db: storage,
      skipArchiveRecord: true,
      skipRefreshPending: true,
    );

    expect(result.captured, isTrue);
    expect(await db.query('decision_snapshots'), hasLength(1));
  });

  test('30天内同向重复留档被跳过', () async {
    final a = _analysis('000003', RecommendationDirection.bullish);
    final first = await ArchiveService.archiveStock(
      code: '000003', name: 'X', analysis: a, db: storage);
    final second = await ArchiveService.archiveStock(
      code: '000003', name: 'X', analysis: a, db: storage);

    expect(first.archived, isTrue);
    expect(second.archived, isFalse);
    expect(await db.query('archive_records'), hasLength(1));
  });

  test('purgeOldDecisionData 不清理用户留档(source=archive)', () async {
    final tracker = DecisionTracker(storage: storage, marketData: _FakeData());
    final old = DateTime.now().subtract(const Duration(days: 120));
    await tracker.capture(
      analysis: _analysis('600000', RecommendationDirection.bullish),
      source: 'archive',
      signalTradeDate: old,
      benchmarkCode: '000300',
    );
    await tracker.capture(
      analysis: _analysis('600001', RecommendationDirection.bullish),
      source: 'explore',
      signalTradeDate: old,
      benchmarkCode: '000300',
    );

    expect(await db.query('decision_snapshots'), hasLength(2));

    final removed = await storage.purgeOldDecisionData();

    final remaining = await db.query('decision_snapshots');
    expect(remaining, hasLength(1));
    expect(remaining.first['source'], 'archive');
    expect(removed, 1);
  });
}

AnalysisResult _analysis(String code, RecommendationDirection direction) =>
    AnalysisResult(
      quote: QuoteData(code: code, name: '测试', price: 10),
      score: direction == RecommendationDirection.bearish ? 3 : 8,
      recommendation:
          direction == RecommendationDirection.bullish ? '买入' : '卖出',
      shortTermDecision: ShortTermDecision(
        directionScore: direction == RecommendationDirection.bearish ? -70 : 70,
        tradeQualityScore: 75,
        riskScore: 30,
        evidenceConfidence: 72,
        direction: direction,
        marketRegime: MarketRegime.range,
        modelVersion: 'short-term-v2',
        rawComprehensiveScore: 7,
      ),
    );

class _FakeData implements DecisionMarketDataSource {
  @override
  Future<DecisionMarketData> load({
    required String code,
    required String benchmarkCode,
    int days = 180,
  }) async =>
      DecisionMarketData(
        adjustedStock: [
          HistoryKline(date: DateTime(2026, 7, 14), open: 10, high: 10, low: 10, close: 10),
        ],
        adjustedBenchmark: [
          HistoryKline(date: DateTime(2026, 7, 14), open: 100, high: 100, low: 100, close: 100),
        ],
      );
}
