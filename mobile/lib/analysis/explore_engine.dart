import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'indicators.dart';
import 'signal_engine.dart';

/// 探索引擎：后台批量分析沪深主板股票，筛选买入级别以上标的
/// 使用全局单例 + BroadcastStream，确保切换Tab不中断分析
/// v2.25 优化：批量K线获取 + 内存缓存 + 批量行情
class ExploreEngine {
  static final ExploreEngine _instance = ExploreEngine._();
  static ExploreEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;
  bool _isRunning = false;

  StreamController<ExploreProgress> _progressController =
      StreamController<ExploreProgress>.broadcast();

  ExploreEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService();

  bool get isRunning => _isRunning;

  /// 进度广播流，切换Tab后重新订阅可获取最新进度
  Stream<ExploreProgress> get progressStream => _ensureController().stream;

  /// 释放资源并重置内部状态，允许单例后续继续使用
  /// 注意: 不会中止正在运行的 explore() 调用（使用 _ensureController 自动重建）
  void dispose() {
    _progressController.close();
  }

  /// 获取或重建 StreamController（dispose后自动重建）
  StreamController<ExploreProgress> _ensureController() {
    if (_progressController.isClosed) {
      _progressController = StreamController<ExploreProgress>.broadcast();
    }
    return _progressController;
  }

  /// 最新进度快照，切换Tab回来后恢复状态
  ExploreProgress? _latestProgress;
  ExploreProgress? get latestProgress => _latestProgress;

  /// 执行探索分析（异步，通过 progressStream 广播进度）
  Future<void> explore() async {
    if (_isRunning) {
      _emit(ExploreProgress(status: ExploreStatus.alreadyRunning));
      return;
    }

    _isRunning = true;
    final startTime = DateTime.now();

    try {
      // 1. 获取热门板块列表
      _emit(ExploreProgress(status: ExploreStatus.fetchingSectors));
      final sectors = await _apiClient.getHotSectors();
      final topSectors = sectors.take(20).toList();

      if (topSectors.isEmpty) {
        _emit(ExploreProgress(status: ExploreStatus.error, message: '无法获取板块数据'));
        _isRunning = false;
        return;
      }

      // 2. 并发获取板块成分股
      _emit(ExploreProgress(status: ExploreStatus.fetchingStocks, totalStocks: 0));

      final allStocks = <QuoteData>[];
      final seenCodes = <String>{};
      const sectorBatchSize = 5;

      for (int i = 0; i < topSectors.length; i += sectorBatchSize) {
        final batch = topSectors.sublist(
          i,
          i + sectorBatchSize > topSectors.length ? topSectors.length : i + sectorBatchSize,
        );

        final sectorStocksList = await Future.wait(
          batch.map((sector) =>
              _apiClient.getSectorStocks(sector.code).catchError((_) => <QuoteData>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          for (final stock in sectorStocksList[j]) {
            if (seenCodes.contains(stock.code)) continue;
            if (!_apiClient.isMainBoardStock(stock.code)) continue;
            if (stock.price <= 0 || stock.name.isEmpty || stock.name.startsWith('ST') || stock.name.startsWith('*ST')) continue;
            seenCodes.add(stock.code);
            allStocks.add(stock);
          }
        }

        _emit(ExploreProgress(
          status: ExploreStatus.fetchingStocks,
          totalStocks: allStocks.length,
        ));
      }

      if (allStocks.isEmpty) {
        _emit(ExploreProgress(status: ExploreStatus.error, message: '未获取到有效股票数据'));
        _isRunning = false;
        return;
      }

      // 3. 批量预取K线数据（内存缓存，单次探索内复用）
      _emit(ExploreProgress(status: ExploreStatus.fetchingKlines, totalStocks: allStocks.length));

      final klineCache = <String, List<HistoryKline>>{};
      const klineBatchSize = 15;

      for (int i = 0; i < allStocks.length; i += klineBatchSize) {
        final end = min(i + klineBatchSize, allStocks.length);
        final batch = allStocks.sublist(i, end);

        final klineResults = await Future.wait(
          batch.map((stock) =>
              _apiClient.getStockHistory(stock.code).catchError((_) => <HistoryKline>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          klineCache[batch[j].code] = klineResults[j];
        }

        _emit(ExploreProgress(
          status: ExploreStatus.fetchingKlines,
          totalStocks: allStocks.length,
          analyzedStocks: end,
        ));
      }

      // 4. 批量获取实时行情（一次请求替代N次独立请求）
      _emit(ExploreProgress(status: ExploreStatus.fetchingQuotes, totalStocks: allStocks.length));

      final quoteCache = <String, QuoteData>{};
      const quoteBatchSize = 50; // 腾讯批量接口支持多个代码

      for (int i = 0; i < allStocks.length; i += quoteBatchSize) {
        final end = min(i + quoteBatchSize, allStocks.length);
        final batchCodes = allStocks.sublist(i, end).map((s) => s.code).toList();

        List<QuoteData> batchQuotes;
        try {
          batchQuotes = await _apiClient.getBatchRealtimeQuotes(batchCodes);
        } catch (_) {
          batchQuotes = [];
        }

        for (final quote in batchQuotes) {
          quoteCache[quote.code] = quote;
        }

        _emit(ExploreProgress(
          status: ExploreStatus.fetchingQuotes,
          totalStocks: allStocks.length,
          analyzedStocks: end,
        ));
      }

      // 5. 分析阶段（使用缓存数据，无需网络请求）
      _emit(ExploreProgress(
        status: ExploreStatus.analyzing,
        totalStocks: allStocks.length,
        analyzedStocks: 0,
      ));

      final results = <ExploreResult>[];
      const analyzeBatchSize = 30; // 增大分析批次，只需CPU计算

      for (int i = 0; i < allStocks.length; i += analyzeBatchSize) {
        final end = min(i + analyzeBatchSize, allStocks.length);
        final batch = allStocks.sublist(i, end);

        // 同步分析（无网络IO），使用 compute 或 isolate 加速大量计算
        for (int j = 0; j < batch.length; j++) {
          final stock = batch[j];
          final klineData = klineCache[stock.code] ?? <HistoryKline>[];
          final quote = quoteCache[stock.code] ?? stock;
          final result = _analyzeCached(stock, klineData, quote);
          if (result != null) {
            results.add(result);
          }
        }

        _emit(ExploreProgress(
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
      _emit(ExploreProgress(status: ExploreStatus.saving));
      await _dbService.replaceExploreResults(results);

      final elapsed = DateTime.now().difference(startTime);
      debugPrint('Explore completed: ${results.length} stocks in ${elapsed.inSeconds}s (optimized)');

      _emit(ExploreProgress(
        status: ExploreStatus.complete,
        results: results,
        totalStocks: allStocks.length,
        foundStocks: results.length,
        elapsedSeconds: elapsed.inSeconds,
      ));
    } catch (e) {
      debugPrint('ExploreEngine error: $e');
      _emit(ExploreProgress(status: ExploreStatus.error, message: '分析出错：$e'));
    } finally {
      _isRunning = false;
    }
  }

  void _emit(ExploreProgress progress) {
    _latestProgress = progress;
    _ensureController().add(progress);
  }

  /// 使用缓存数据同步分析（无网络IO）
  ExploreResult? _analyzeCached(
    QuoteData stock,
    List<HistoryKline> klineData,
    QuoteData quote,
  ) {
    try {
      if (klineData.length < 20) return null;

      final indicators = calcAllIndicators(klineData);

      if (!_passValuationFilter(quote)) {
        return null;
      }

      final analysis = generateAnalysis(indicators, quote);

      if (!_isBuyRecommendation(analysis.recommendation)) {
        return null;
      }

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
      );
    } catch (e) {
      debugPrint('Analyze cached ${stock.code} failed: $e');
      return null;
    }
  }

  static bool _passValuationFilter(QuoteData quote) {
    // PE <= 0 表示亏损，过滤（探索引擎优先找有盈利能力的标的）
    if (quote.pe <= 0) return false;
    // PE >= 80 估值过高，过滤
    if (quote.pe < 80 && quote.pb > 0) return true;
    return false;
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

  ExploreProgress({
    required this.status,
    this.totalStocks = 0,
    this.analyzedStocks = 0,
    this.foundStocks = 0,
    this.currentStock,
    this.message,
    this.results,
    this.elapsedSeconds,
  });
}