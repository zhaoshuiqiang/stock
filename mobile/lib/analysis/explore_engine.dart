import 'dart:math';

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/market_context_provider.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../data/concept_tag_provider.dart';
import 'base_analysis_engine.dart';
import 'indicators.dart';
import 'signal_engine.dart';
import 'market_timing.dart';
import 'market_structure_analyzer.dart';
import 'recommendation_tracker.dart';
import 'decision_tracker.dart';
import 'decision_calibration_service.dart';

/// 探索引擎：后台批量分析沪深主板股票，筛选买入级别以上标的
/// 使用全局单例 + BroadcastStream，确保切换Tab不中断分析
/// v2.25 优化：批量K线获取 + 内存缓存 + 批量行情
class ExploreEngine extends BaseAnalysisEngine<ExploreProgress> {
  static final ExploreEngine _instance = ExploreEngine._();
  static ExploreEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;
  final DecisionCalibrationService _calibrationService;

  ExploreEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService(),
        _calibrationService = DecisionCalibrationService();

  /// 执行探索分析（异步，通过 progressStream 广播进度）
  Future<void> explore() async {
    if (!tryStart(ExploreProgress(status: ExploreStatus.alreadyRunning))) {
      return;
    }

    final startTime = DateTime.now();

    try {
      // 1. 并行获取热门板块 + 市场择时（择时结果用于UI展示）
      emit(ExploreProgress(status: ExploreStatus.fetchingSectors));
      final sectorAndTiming = await Future.wait<dynamic>([
        _apiClient.getHotSectors(),
        MarketTiming.fetchTiming(),
        MarketContextProvider.getMarketContext()
            .then<MarketContext?>((value) => value)
            .catchError((_) => null),
      ]);
      final sectors = sectorAndTiming[0] as List<SectorInfo>;
      final marketTiming = sectorAndTiming[1] as MarketTimingResult?;
      final marketContext = sectorAndTiming[2] as MarketContext?;
      final topSectors = sectors.take(20).toList();

      if (topSectors.isEmpty) {
        emit(ExploreProgress(status: ExploreStatus.error, message: '无法获取板块数据'));
        return;
      }

      // 2. 并发获取板块成分股
      emit(ExploreProgress(
          status: ExploreStatus.fetchingStocks, totalStocks: 0));

      final allStocks = <QuoteData>[];
      final seenCodes = <String>{};
      const sectorBatchSize = 5;

      for (int i = 0; i < topSectors.length; i += sectorBatchSize) {
        final batch = topSectors.sublist(
          i,
          i + sectorBatchSize > topSectors.length
              ? topSectors.length
              : i + sectorBatchSize,
        );

        final sectorStocksList = await Future.wait(
          batch.map((sector) => _apiClient
              .getSectorStocks(sector.code)
              .catchError((_) => <QuoteData>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          for (final stock in sectorStocksList[j]) {
            if (seenCodes.contains(stock.code)) continue;
            if (!_apiClient.isMainBoardStock(stock.code)) continue;
            if (stock.price <= 0 ||
                stock.name.isEmpty ||
                stock.name.startsWith('ST') ||
                stock.name.startsWith('*ST')) {
              continue;
            }
            seenCodes.add(stock.code);
            allStocks.add(stock);
          }
        }

        emit(ExploreProgress(
          status: ExploreStatus.fetchingStocks,
          totalStocks: allStocks.length,
        ));
      }

      if (allStocks.isEmpty) {
        emit(ExploreProgress(
            status: ExploreStatus.error, message: '未获取到有效股票数据'));
        return;
      }

      // 3. 批量预取K线数据（内存缓存，单次探索内复用）
      emit(ExploreProgress(
          status: ExploreStatus.fetchingKlines, totalStocks: allStocks.length));

      final klineCache = <String, List<HistoryKline>>{};
      const klineBatchSize = 15;

      for (int i = 0; i < allStocks.length; i += klineBatchSize) {
        final end = min(i + klineBatchSize, allStocks.length);
        final batch = allStocks.sublist(i, end);

        final klineResults = await Future.wait(
          batch.map((stock) => _apiClient
              .getStockHistory(stock.code)
              .catchError((_) => <HistoryKline>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          klineCache[batch[j].code] = klineResults[j];
        }

        emit(ExploreProgress(
          status: ExploreStatus.fetchingKlines,
          totalStocks: allStocks.length,
          analyzedStocks: end,
        ));
      }

      // 4. 批量获取实时行情（一次请求替代N次独立请求）
      emit(ExploreProgress(
          status: ExploreStatus.fetchingQuotes, totalStocks: allStocks.length));

      final quoteCache = <String, QuoteData>{};
      const quoteBatchSize = 50; // 腾讯批量接口支持多个代码

      for (int i = 0; i < allStocks.length; i += quoteBatchSize) {
        final end = min(i + quoteBatchSize, allStocks.length);
        final batchCodes =
            allStocks.sublist(i, end).map((s) => s.code).toList();

        List<QuoteData> batchQuotes;
        try {
          batchQuotes = await _apiClient.getBatchRealtimeQuotes(batchCodes);
        } catch (_) {
          batchQuotes = [];
        }

        for (final quote in batchQuotes) {
          quoteCache[quote.code] = quote;
        }

        emit(ExploreProgress(
          status: ExploreStatus.fetchingQuotes,
          totalStocks: allStocks.length,
          analyzedStocks: end,
        ));
      }

      // 5. 分析阶段（使用缓存数据，无需网络请求）
      emit(ExploreProgress(
        status: ExploreStatus.analyzing,
        totalStocks: allStocks.length,
        analyzedStocks: 0,
      ));

      final results = <ExploreResult>[];
      final analysisList = <AnalysisResult>[];
      const analyzeBatchSize = 30; // 增大分析批次，只需CPU计算

      for (int i = 0; i < allStocks.length; i += analyzeBatchSize) {
        final end = min(i + analyzeBatchSize, allStocks.length);
        final batch = allStocks.sublist(i, end);

        // 同步分析（无网络IO），使用 compute 或 isolate 加速大量计算
        for (int j = 0; j < batch.length; j++) {
          final stock = batch[j];
          final klineData = klineCache[stock.code] ?? <HistoryKline>[];
          final quote = quoteCache[stock.code] ?? stock;
          final result = await _analyzeCached(
            stock,
            klineData,
            quote,
            analysisList,
            marketContext,
          );
          if (result != null) {
            results.add(result);
          }
          // 释放内存：分析完成后立即清理K线缓存
          klineCache.remove(stock.code);
        }

        emit(ExploreProgress(
          status: ExploreStatus.analyzing,
          totalStocks: allStocks.length,
          analyzedStocks: end,
          foundStocks: results.length,
          currentStock: batch.last.name,
        ));
      }

      // 6. 按评分降序排列
      results.sort((a, b) => b.score.compareTo(a.score));

      // 7. 持久化到数据库
      emit(ExploreProgress(status: ExploreStatus.saving));
      await _dbService.replaceExploreResults(results);

      try {
        await captureDecisionBatchForTesting(
          analyses: analysisList,
          source: 'explore',
          tracker: DecisionTracker(),
          signalTradeDate: DateTime.now(),
          benchmarkCode: '000300',
        );
      } catch (e) {
        debugPrint('ExploreEngine.decisionTracking: $e');
      }

      // 1.15: capture 后评估 pending outcomes，否则 decision_outcomes 永远为 pending
      try {
        await DecisionTracker().refreshPending(limit: 100);
      } catch (e) {
        debugPrint('ExploreEngine.refreshPending: $e');
      }

      // 自动清理超过保留期的历史决策数据，防止决策表无限增长
      try {
        final removed = await DecisionTracker().purgeOldSnapshots();
        if (removed > 0) {
          debugPrint('ExploreEngine.purgeOldSnapshots: 已清理 $removed 条旧决策快照');
        }
      } catch (e) {
        debugPrint('ExploreEngine.purgeOldSnapshots: $e');
      }

      // Phase 3: 批量记录推荐快照（事务内一次性写入，避免逐只 track 的并发开销）
      try {
        await RecommendationTracker().trackBatch(analysisList);
      } catch (e) {
        debugPrint('trackBatch失败: $e');
      }

      // Phase 3: 更新历史推荐收益率
      try {
        final pricesByCode = <String, double>{};
        for (final q in quoteCache.values) {
          pricesByCode[q.code] = q.price;
        }
        await RecommendationTracker().updateReturns(pricesByCode);
      } catch (e) {
        debugPrint('ExploreEngine.updateReturns: $e');
      }

      final elapsed = DateTime.now().difference(startTime);
      debugPrint(
          'Explore completed: ${results.length} stocks in ${elapsed.inSeconds}s (optimized)');

      emit(ExploreProgress(
        status: ExploreStatus.complete,
        results: results,
        totalStocks: allStocks.length,
        foundStocks: results.length,
        elapsedSeconds: elapsed.inSeconds,
        marketTiming: marketTiming,
      ));
    } catch (e) {
      debugPrint('ExploreEngine error: $e');
      emit(ExploreProgress(status: ExploreStatus.error, message: '分析出错：$e'));
    } finally {
      markFinished();
    }
  }

  /// 使用缓存数据同步分析（无网络IO）
  Future<ExploreResult?> _analyzeCached(
    QuoteData stock,
    List<HistoryKline> klineData,
    QuoteData quote,
    List<AnalysisResult> analysisList,
    MarketContext? marketContext,
  ) async {
    try {
      if (klineData.length < 20) return null;

      final indicators = calcAllIndicators(klineData);

      if (!_passValuationFilter(quote, shortTermMode: true)) {
        return null;
      }

      var analysis = generateAnalysis(
        indicators,
        quote,
        marketContext: marketContext,
        enableAsyncSideEffects: false,
      );
      try {
        analysis = await _calibrationService.enrich(
          analysis,
          asOfTradeDate: indicators.last.date,
        );
      } catch (e) {
        debugPrint('ExploreEngine.calibration: $e');
      }

      analysisList.add(analysis);

      if (!_isBuyRecommendation(analysis.recommendation)) {
        return null;
      }

      // Phase 2: 概念标签
      String? conceptSummary;
      try {
        conceptSummary =
            ConceptTagProvider.instance.getConceptSummary(stock.code);
      } catch (e) {
        debugPrint('ExploreEngine.conceptTags: $e');
      }

      // Phase 3: 推荐追踪（收集到列表，循环结束后批量写入）
      // Phase 1: 市场结构
      final structureLabel = analysis.marketStructure != null
          ? MarketStructureAnalyzer.getLabel(
              analysis.marketStructure!.structure)
          : '';

      return ExploreResult(
        code: stock.code,
        name: stock.name,
        price: quote.price,
        changePct: quote.changePct,
        pe: quote.pe,
        pb: quote.pb,
        score: analysis.score,
        recommendation: analysis.recommendation,
        confluenceScore: analysis.confluenceScore,
        analyzedAt: DateTime.now(),
        conceptSummary: (conceptSummary != null && conceptSummary.isNotEmpty)
            ? conceptSummary
            : null,
        marketStructure: structureLabel.isNotEmpty ? structureLabel : null,
      );
    } catch (e) {
      debugPrint('Analyze cached ${stock.code} failed: $e');
      return null;
    }
  }

  @visibleForTesting
  static bool passesValuationFilter(
    QuoteData quote, {
    bool shortTermMode = false,
  }) {
    if (shortTermMode) {
      return quote.price > 0;
    }

    // PE <= 0 表示亏损，过滤（探索引擎优先找有盈利能力的标的）
    if (quote.pe <= 0) return false;
    // PE >= 80 估值过高，过滤
    if (quote.pe < 80 && quote.pb > 0) return true;
    return false;
  }

  static bool _passValuationFilter(
    QuoteData quote, {
    bool shortTermMode = false,
  }) {
    return passesValuationFilter(quote, shortTermMode: shortTermMode);
  }

  static bool _isBuyRecommendation(String recommendation) {
    const buyRecs = ['强烈买入', '买入', '谨慎买入'];
    return buyRecs.contains(recommendation);
  }
}

/// 探索进度状态
enum ExploreStatus {
  idle,
  fetchingSectors,
  fetchingStocks,
  fetchingKlines,
  fetchingQuotes,
  analyzing,
  saving,
  complete,
  error,
  alreadyRunning,
}

/// 探索进度信息
class ExploreProgress {
  final ExploreStatus status;
  final int totalStocks;
  final int analyzedStocks;
  final int foundStocks;
  final String? currentStock;
  final String? message;
  final List<ExploreResult>? results;
  final int? elapsedSeconds;
  final MarketTimingResult? marketTiming;

  ExploreProgress({
    required this.status,
    this.totalStocks = 0,
    this.analyzedStocks = 0,
    this.foundStocks = 0,
    this.currentStock,
    this.message,
    this.results,
    this.elapsedSeconds,
    this.marketTiming,
  });
}
