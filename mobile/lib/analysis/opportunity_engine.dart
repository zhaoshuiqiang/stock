import 'dart:async';
import 'dart:convert';

import '../api/api_client.dart';
import '../api/market_context_provider.dart';
import '../core/stock_code_utils.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'base_analysis_engine.dart';
import 'indicators.dart';
import 'signal_engine.dart';
import 'market_timing.dart';
import 'decision_tracker.dart';
import 'decision_calibration_service.dart';
import '../storage/database_service.dart';

typedef OpportunityAnalysisGenerator = AnalysisResult Function(
  List<HistoryKline> data,
  QuoteData? quote, {
  MarketContext? marketContext,
  bool enableAsyncSideEffects,
});

AnalysisResult generateOpportunityAnalysisForTesting({
  required List<HistoryKline> calculated,
  required QuoteData? quote,
  required MarketContext? marketContext,
  required OpportunityAnalysisGenerator generator,
}) {
  return generator(
    calculated,
    quote,
    marketContext: marketContext,
    enableAsyncSideEffects: false,
  );
}

/// 机会分析结果
class OpportunityResult {
  final String code;
  final String name;
  final double price;
  final double changePct;
  final int score;
  final String recommendation;
  final String riskLevel;
  final int buySignalCount;
  final int sellSignalCount;
  final int activeStrategyCount;
  final int confluenceScore;
  final Map<String, dynamic>? tradeLevels;
  final ShortTermDecision? shortTermDecision;
  final List<String> topSignals;

  OpportunityResult({
    required this.code,
    required this.name,
    required this.price,
    required this.changePct,
    required this.score,
    required this.recommendation,
    required this.riskLevel,
    required this.buySignalCount,
    required this.sellSignalCount,
    required this.activeStrategyCount,
    required this.confluenceScore,
    this.tradeLevels,
    this.shortTermDecision,
    this.topSignals = const [],
  });

  Map<String, dynamic> toMap([DateTime? analyzedAt]) {
    return {
      'code': code,
      'name': name,
      'price': price,
      'change_pct': changePct,
      'score': score,
      'recommendation': recommendation,
      'risk_level': riskLevel,
      'buy_signal_count': buySignalCount,
      'sell_signal_count': sellSignalCount,
      'active_strategy_count': activeStrategyCount,
      'confluence_score': confluenceScore,
      'trade_levels_json': tradeLevels != null ? jsonEncode(tradeLevels) : null,
      'top_signals': topSignals.join('  '),
      'short_term_decision_json': shortTermDecision != null
          ? jsonEncode(shortTermDecision!.toJson())
          : null,
      'analyzed_at': (analyzedAt ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }

  static OpportunityResult fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? tradeLevels;
    if (map['trade_levels_json'] != null &&
        (map['trade_levels_json'] as String).isNotEmpty) {
      try {
        tradeLevels = jsonDecode(map['trade_levels_json'] as String);
      } catch (_) {}
    }
    List<String> topSignals = [];
    if (map['top_signals'] != null &&
        (map['top_signals'] as String).isNotEmpty) {
      topSignals = (map['top_signals'] as String)
          .split('  ')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    ShortTermDecision? shortTermDecision;
    if (map['short_term_decision_json'] != null &&
        (map['short_term_decision_json'] as String).isNotEmpty) {
      try {
        shortTermDecision = ShortTermDecision.fromJson(
          jsonDecode(map['short_term_decision_json'] as String)
              as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return OpportunityResult(
      code: map['code'] as String,
      name: map['name'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      changePct: (map['change_pct'] as num?)?.toDouble() ?? 0,
      score: (map['score'] as num?)?.toInt() ?? 0,
      recommendation: map['recommendation'] as String? ?? '',
      riskLevel: map['risk_level'] as String? ?? '',
      buySignalCount: (map['buy_signal_count'] as num?)?.toInt() ?? 0,
      sellSignalCount: (map['sell_signal_count'] as num?)?.toInt() ?? 0,
      activeStrategyCount: (map['active_strategy_count'] as num?)?.toInt() ?? 0,
      confluenceScore: (map['confluence_score'] as num?)?.toInt() ?? 0,
      tradeLevels: tradeLevels,
      shortTermDecision: shortTermDecision,
      topSignals: topSignals,
    );
  }
}

/// 机会分析进度状态
enum OpportunityStatus {
  idle,
  fetching,
  analyzing,
  saving,
  complete,
  error,
  alreadyRunning
}

/// 机会分析进度信息
class OpportunityProgress {
  final OpportunityStatus status;
  final int completedCount;
  final int totalCount;
  final List<OpportunityResult>? results;
  final String? message;
  final MarketTimingResult? marketTiming;

  OpportunityProgress({
    required this.status,
    this.completedCount = 0,
    this.totalCount = 0,
    this.results,
    this.message,
    this.marketTiming,
  });
}

/// 机会分析引擎：后台分析自选股机会与风险，切换Tab不中断
class OpportunityEngine extends BaseAnalysisEngine<OpportunityProgress> {
  static final OpportunityEngine _instance = OpportunityEngine._();
  static OpportunityEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;
  final DecisionCalibrationService _calibrationService;

  OpportunityEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService(),
        _calibrationService = DecisionCalibrationService();

  /// 执行机会分析（优化版：MarketTiming仅计算一次，并发度提升，K线天数缩减）
  Future<void> analyze() async {
    if (!tryStart(
        OpportunityProgress(status: OpportunityStatus.alreadyRunning))) {
      return;
    }

    try {
      // 1. 获取自选列表
      emit(OpportunityProgress(status: OpportunityStatus.fetching));
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isEmpty) {
        emit(OpportunityProgress(
            status: OpportunityStatus.complete, results: [], totalCount: 0));
        return;
      }
      final totalCount = watchlist.length;

      // 2. 批量获取行情 + 市场环境（并行）
      final prefixedCodes = watchlist
          .map((item) => _apiClient.addMarketPrefix(item.code))
          .toList();
      final futures = <Future>[
        _apiClient
            .getBatchRealtimeQuotes(prefixedCodes)
            .catchError((_) => <QuoteData>[]),
        MarketTiming.fetchTiming(),
        MarketContextProvider.getMarketContext()
            .then<MarketContext?>((value) => value)
            .catchError((_) => null),
      ];
      final futureResults = await Future.wait(futures);
      final batchQuotes = futureResults[0] as List<QuoteData>;

      final quoteMap = <String, QuoteData>{};
      for (final q in batchQuotes) {
        quoteMap[q.code] = q;
      }

      final marketTimingResult = futureResults[1] as MarketTimingResult?;
      final marketContext = futureResults[2] as MarketContext?;

      emit(OpportunityProgress(
          status: OpportunityStatus.analyzing,
          totalCount: totalCount,
          completedCount: 0));

      // 3. 分批分析，并发10（与发现页一致使用120天K线）
      const batchSize = 10;
      const klineDays = 120;
      final results = <OpportunityResult?>[];
      final analysisList = <AnalysisResult>[];
      int completedCount = 0;

      for (int i = 0; i < watchlist.length; i += batchSize) {
        final batch =
            watchlist.sublist(i, (i + batchSize).clamp(0, watchlist.length));
        final batchResults = await Future.wait(batch.map((item) async {
          try {
            final prefixedCode = _apiClient.addMarketPrefix(item.code);
            QuoteData? quote = quoteMap[prefixedCode];
            if (quote == null) {
              try {
                quote = await _apiClient.getRealtimeQuote(prefixedCode);
              } catch (_) {}
            }

            final klines =
                await _apiClient.getStockHistory(prefixedCode, days: klineDays);
            if (klines.isEmpty) return null;

            final calculated = calcAllIndicators(klines);
            var analysis = generateOpportunityAnalysisForTesting(
              calculated: calculated,
              quote: quote,
              marketContext: marketContext,
              generator: generateAnalysis,
            );
            try {
              analysis = await _calibrationService.enrich(
                analysis,
                asOfTradeDate: calculated.last.date,
              );
            } catch (_) {}
            analysisList.add(analysis);

            final signals = analysis.signals;
            final last = calculated.last;
            final topSignals = signals
                .take(2)
                .map((s) => '${s.type == 'buy' ? '▲' : '▼'}${s.signal}')
                .toList();

            return OpportunityResult(
              code: StockCodeUtils.normalizeForArchive(item.code),
              name: item.name,
              price: quote?.price ?? last.close,
              changePct: quote?.changePct ?? last.changePct,
              score: analysis.score,
              recommendation: analysis.recommendation,
              riskLevel: analysis.riskLevel,
              buySignalCount: signals.where((s) => s.type == 'buy').length,
              sellSignalCount: signals.where((s) => s.type == 'sell').length,
              activeStrategyCount: [
                ...analysis.shortTermStrategies,
                ...analysis.longTermStrategies,
              ].where((s) => s.isActive).length,
              confluenceScore: analysis.confluenceScore,
              tradeLevels: analysis.tradeLevels,
              shortTermDecision: analysis.shortTermDecision,
              topSignals: topSignals,
            );
          } catch (_) {
            return null;
          }
        }));

        results.addAll(batchResults);
        completedCount += batch.length;
        emit(OpportunityProgress(
            status: OpportunityStatus.analyzing,
            totalCount: totalCount,
            completedCount: completedCount.clamp(0, totalCount)));
      }

      // 4. 排序并保存
      final deduped = <String, OpportunityResult>{};
      for (final item in results.whereType<OpportunityResult>()) {
        final normalized = StockCodeUtils.normalizeForArchive(item.code);
        final existing = deduped[normalized];
        if (existing == null || item.score > existing.score) {
          deduped[normalized] = item;
        }
      }
      final opportunities = deduped.values.toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      emit(OpportunityProgress(status: OpportunityStatus.saving));
      await _dbService.replaceOpportunityResults(
          opportunities.map((o) => o.toMap(DateTime.now())).toList());

      try {
        await captureDecisionBatchForTesting(
          analyses: analysisList,
          source: 'opportunity',
          tracker: DecisionTracker(),
          signalTradeDate: DateTime.now(),
          benchmarkCode: '000300',
        );
      } catch (_) {}

      // 1.15: capture 后评估 pending outcomes，否则 decision_outcomes 永远为 pending
      try {
        await DecisionTracker().refreshPending(limit: 100);
      } catch (_) {}

      // 自动清理超过保留期的历史决策数据，防止决策表无限增长
      try {
        final removed = await DecisionTracker().purgeOldSnapshots();
        if (removed > 0) {
          print('OpportunityEngine.purgeOldSnapshots: 已清理 $removed 条旧决策快照');
        }
      } catch (_) {}

      emit(OpportunityProgress(
          status: OpportunityStatus.complete,
          results: opportunities,
          totalCount: totalCount,
          completedCount: totalCount,
          marketTiming: marketTimingResult));
    } catch (e) {
      emit(OpportunityProgress(
          status: OpportunityStatus.error, message: '分析出错：$e'));
    } finally {
      markFinished();
    }
  }
}
