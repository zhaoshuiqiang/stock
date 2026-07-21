import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

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
  final double score;
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
      score: (map['score'] as num?)?.toDouble() ?? 0,
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
  fetchingKlines,
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
  final int failedCount;
  final List<OpportunityResult>? results;
  final String? message;
  final MarketTimingResult? marketTiming;

  OpportunityProgress({
    required this.status,
    this.completedCount = 0,
    this.totalCount = 0,
    this.failedCount = 0,
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

  /// 执行机会分析（三阶段优化：K线预取→CPU分析，IO与CPU分离）
  Future<void> analyze() async {
    if (!tryStart(
        OpportunityProgress(status: OpportunityStatus.alreadyRunning))) {
      return;
    }

    try {
      // ── 阶段1: 获取自选列表 + 批量行情 + 市场环境 ──
      emit(OpportunityProgress(status: OpportunityStatus.fetching));
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isEmpty) {
        emit(OpportunityProgress(
            status: OpportunityStatus.complete, results: [], totalCount: 0));
        return;
      }
      final totalCount = watchlist.length;

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

      // ── 阶段2: 批量预取K线数据（IO密集，与CPU分析分离） ──
      emit(OpportunityProgress(
          status: OpportunityStatus.fetchingKlines,
          totalCount: totalCount,
          completedCount: 0));

      const klineBatchSize = 15;
      const klineDays = 120;
      final klineCache = <String, List<HistoryKline>>{};
      int klineFetched = 0;
      int klineFailed = 0;

      // v3.39: 先从API缓存中提取已缓存的K线，跳过已缓存股票的HTTP请求
      final uncachedStocks = <WatchlistItem>[];
      for (final item in watchlist) {
        final prefixedCode = _apiClient.addMarketPrefix(item.code);
        final cached = _apiClient.getCachedKline(prefixedCode, days: klineDays);
        if (cached != null && cached.isNotEmpty) {
          klineCache[prefixedCode] = cached;
          klineFetched++;
        } else {
          uncachedStocks.add(item);
        }
      }

      if (uncachedStocks.isNotEmpty) {
        for (int i = 0; i < uncachedStocks.length; i += klineBatchSize) {
          final end = min(i + klineBatchSize, uncachedStocks.length);
          final batch = uncachedStocks.sublist(i, end);

          final klineResults = await Future.wait(
            batch.map((item) {
              final prefixedCode = _apiClient.addMarketPrefix(item.code);
              return _apiClient
                  .getStockHistory(prefixedCode,
                      days: klineDays, maxRacingSources: 4)
                  .catchError((e) {
                debugPrint('[OpportunityEngine] K线获取失败: $prefixedCode - $e');
                return <HistoryKline>[];
              });
            }),
          );

          for (int j = 0; j < batch.length; j++) {
            final prefixedCode = _apiClient.addMarketPrefix(batch[j].code);
            klineCache[prefixedCode] = klineResults[j];
            if (klineResults[j].isEmpty) klineFailed++;
          }

          klineFetched += batch.length;
          emit(OpportunityProgress(
              status: OpportunityStatus.fetchingKlines,
              totalCount: totalCount,
              completedCount: klineFetched,
              failedCount: klineFailed));
        }

        // v4.9: retry stocks whose K-line came back empty. The first pass fires
        // klineBatchSize x racingSources concurrent requests per burst, so
        // transient timeouts/rate-limits under that load cause partial failures;
        // a lower-concurrency retry after the burst recovers most of them.
        // Genuinely dataless stocks (delisted/suspended/too-new) stay failed.
        if (klineFailed > 0) {
          bool stillEmpty(WatchlistItem item) =>
              (klineCache[_apiClient.addMarketPrefix(item.code)] ??
                      const <HistoryKline>[])
                  .isEmpty;
          final retryItems = uncachedStocks.where(stillEmpty).toList();
          const retryBatchSize = 5;
          for (int i = 0; i < retryItems.length; i += retryBatchSize) {
            final end = min(i + retryBatchSize, retryItems.length);
            final batch = retryItems.sublist(i, end);
            final retryResults = await Future.wait(
              batch.map((item) {
                final pc = _apiClient.addMarketPrefix(item.code);
                return _apiClient
                    .getStockHistory(pc, days: klineDays, bypassCache: true)
                    .catchError((e) {
                  debugPrint('[OpportunityEngine] kline retry failed: $pc - $e');
                  return <HistoryKline>[];
                });
              }),
            );
            for (int j = 0; j < batch.length; j++) {
              final pc = _apiClient.addMarketPrefix(batch[j].code);
              if (retryResults[j].isNotEmpty) klineCache[pc] = retryResults[j];
            }
          }
          klineFailed = uncachedStocks.where(stillEmpty).length;
          emit(OpportunityProgress(
              status: OpportunityStatus.fetchingKlines,
              totalCount: totalCount,
              completedCount: klineFetched,
              failedCount: klineFailed));
        }
      } else {
        emit(OpportunityProgress(
            status: OpportunityStatus.fetchingKlines,
            totalCount: totalCount,
            completedCount: totalCount));
      }

      // 阶段2.5: 补充缺失行情（批量接口未覆盖的股票）
      final missingQuoteCodes = watchlist
          .where((item) => !quoteMap.containsKey(_apiClient.addMarketPrefix(item.code)))
          .map((item) => _apiClient.addMarketPrefix(item.code))
          .toList();
      if (missingQuoteCodes.isNotEmpty) {
        final extraQuotes = await Future.wait(
          missingQuoteCodes.map((code) =>
              _apiClient.getRealtimeQuote(code).catchError((_) => null)),
        );
        for (final q in extraQuotes.whereType<QuoteData>()) {
          quoteMap[q.code] = q;
        }
      }

      // ── 阶段3: 纯CPU分析（使用缓存数据，无网络IO） ──
      emit(OpportunityProgress(
          status: OpportunityStatus.analyzing,
          totalCount: totalCount,
          completedCount: 0));

      const analyzeBatchSize = 20;
      final results = <OpportunityResult?>[];
      final analysisList = <AnalysisResult>[];
      int completedCount = 0;
      int analysisFailed = 0;

      for (int i = 0; i < watchlist.length; i += analyzeBatchSize) {
        final end = min(i + analyzeBatchSize, watchlist.length);
        final batch = watchlist.sublist(i, end);

        for (final item in batch) {
          try {
            final prefixedCode = _apiClient.addMarketPrefix(item.code);
            final klines = klineCache[prefixedCode] ?? [];
            if (klines.isEmpty) {
              debugPrint('[OpportunityEngine] 跳过(无K线): ${item.code} ${item.name}');
              results.add(null);
              completedCount++;
              continue;
            }

            final quote = quoteMap[prefixedCode];

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

            results.add(OpportunityResult(
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
            ));
          } catch (e) {
            debugPrint('[OpportunityEngine] 分析异常: ${item.code} ${item.name} - $e');
            results.add(null);
            analysisFailed++;
          }
          completedCount++;
          klineCache.remove(_apiClient.addMarketPrefix(item.code));
        }

        emit(OpportunityProgress(
            status: OpportunityStatus.analyzing,
            totalCount: totalCount,
            completedCount: completedCount.clamp(0, totalCount)));
      }

      // ── 阶段4: 排序并保存 ──
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

      final totalFailed = klineFailed + analysisFailed;
      if (totalFailed > 0) {
        debugPrint('[OpportunityEngine] 分析完成: ${opportunities.length}/$totalCount 成功, $totalFailed 失败(K线$klineFailed + 分析$analysisFailed)');
      }

      emit(OpportunityProgress(status: OpportunityStatus.saving));
      await _dbService.replaceOpportunityResults(
          opportunities.map((o) => o.toMap(DateTime.now())).toList());

      emit(OpportunityProgress(
          status: OpportunityStatus.complete,
          results: opportunities,
          totalCount: totalCount,
          completedCount: totalCount,
          failedCount: totalFailed,
          marketTiming: marketTimingResult));

      unawaited(_runDecisionSideEffects(analysisList));
    } catch (e) {
      emit(OpportunityProgress(
          status: OpportunityStatus.error, message: '分析出错：$e'));
    } finally {
      markFinished();
    }
  }

  /// 后台执行决策追踪副作用（不阻塞分析结果展示）。
  /// [refreshPending] 内含批量网络请求，可能耗时较长，故在结果落库并通知 UI 完成后异步进行。
  Future<void> _runDecisionSideEffects(List<AnalysisResult> analysisList) async {
    try {
      final batchResult = await captureDecisionBatchForTesting(
        analyses: analysisList,
        source: 'opportunity',
        tracker: DecisionTracker(),
        signalTradeDate: DateTime.now(),
        benchmarkCode: '000300',
      );
      debugPrint(
          'OpportunityEngine.decisionTracking: 成功 ${batchResult.success} 条，'
          '失败 ${batchResult.failed} 条');
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
  }
}
