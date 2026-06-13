import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'indicators.dart';
import 'signal_engine.dart';

/// 探索引擎：后台批量分析沪深主板股票，筛选买入级别以上标的
class ExploreEngine {
  final ApiClient _apiClient;
  final DatabaseService _dbService;
  bool _isRunning = false;

  ExploreEngine({ApiClient? apiClient, DatabaseService? dbService})
      : _apiClient = apiClient ?? ApiClient(),
        _dbService = dbService ?? DatabaseService();

  bool get isRunning => _isRunning;

  /// 执行探索分析
  /// [onProgress] 回调：(已分析数, 总数, 当前股票名)
  /// [onComplete] 回调：(结果列表)
  Stream<ExploreProgress> explore() async* {
    if (_isRunning) {
      yield ExploreProgress(status: ExploreStatus.alreadyRunning);
      return;
    }

    _isRunning = true;
    final startTime = DateTime.now();

    try {
      // 1. 获取热门板块列表
      yield ExploreProgress(status: ExploreStatus.fetchingSectors);
      final sectors = await _apiClient.getHotSectors();
      final topSectors = sectors.take(20).toList();

      if (topSectors.isEmpty) {
        yield ExploreProgress(status: ExploreStatus.error, message: '无法获取板块数据');
        _isRunning = false;
        return;
      }

      // 2. 并发获取板块成分股
      yield ExploreProgress(status: ExploreStatus.fetchingStocks, totalStocks: 0);

      final allStocks = <QuoteData>[];
      final seenCodes = <String>{};
      const batchSize = 5;

      for (int i = 0; i < topSectors.length; i += batchSize) {
        final batch = topSectors.sublist(
          i,
          i + batchSize > topSectors.length ? topSectors.length : i + batchSize,
        );

        final sectorStocksList = await Future.wait(
          batch.map((sector) =>
              _apiClient.getSectorStocks(sector.code).catchError((_) => <QuoteData>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          for (final stock in sectorStocksList[j]) {
            if (seenCodes.contains(stock.code)) continue;
            if (!_apiClient.isMainBoardStock(stock.code)) continue;
            // 过滤掉无价格或异常的数据
            if (stock.price <= 0 || stock.name.isEmpty) continue;
            seenCodes.add(stock.code);
            allStocks.add(stock);
          }
        }

        yield ExploreProgress(
          status: ExploreStatus.fetchingStocks,
          totalStocks: allStocks.length,
        );
      }

      if (allStocks.isEmpty) {
        yield ExploreProgress(status: ExploreStatus.error, message: '未获取到有效股票数据');
        _isRunning = false;
        return;
      }

      // 3. 分批分析
      yield ExploreProgress(
        status: ExploreStatus.analyzing,
        totalStocks: allStocks.length,
        analyzedStocks: 0,
      );

      final results = <ExploreResult>[];
      const analyzeBatchSize = 10;

      for (int i = 0; i < allStocks.length; i += analyzeBatchSize) {
        final end = min(i + analyzeBatchSize, allStocks.length);
        final batch = allStocks.sublist(i, end);

        final batchResults = await Future.wait(
          batch.map((stock) => _analyzeSingle(stock)),
        );

        for (final result in batchResults) {
          if (result != null) {
            results.add(result);
          }
        }

        yield ExploreProgress(
          status: ExploreStatus.analyzing,
          totalStocks: allStocks.length,
          analyzedStocks: end,
          foundStocks: results.length,
          currentStock: batch.last.name,
        );
      }

      // 4. 按评分降序排列
      results.sort((a, b) => b.score.compareTo(a.score));

      // 5. 持久化到数据库
      yield ExploreProgress(status: ExploreStatus.saving);
      await _dbService.replaceExploreResults(results);

      final elapsed = DateTime.now().difference(startTime);
      debugPrint('Explore completed: ${results.length} stocks in ${elapsed.inSeconds}s');

      yield ExploreProgress(
        status: ExploreStatus.complete,
        results: results,
        totalStocks: allStocks.length,
        foundStocks: results.length,
        elapsedSeconds: elapsed.inSeconds,
      );
    } catch (e) {
      debugPrint('ExploreEngine error: $e');
      yield ExploreProgress(status: ExploreStatus.error, message: '分析出错：$e');
    } finally {
      _isRunning = false;
    }
  }

  /// 分析单只股票，返回 ExploreResult 或 null（不满足条件）
  Future<ExploreResult?> _analyzeSingle(QuoteData stock) async {
    try {
      // 获取K线数据（至少20条）
      final klineData = await _apiClient.getStockHistory(stock.code);
      if (klineData.length < 20) return null;

      // 计算技术指标
      final indicators = calcAllIndicators(klineData);

      // 获取实时行情（含PE/PB）
      QuoteData? quote;
      try {
        quote = await _apiClient.getRealtimeQuote(stock.code);
      } catch (_) {
        quote = stock;
      }

      // PE/PB估值过滤
      if (quote != null && !_passValuationFilter(quote)) {
        return null;
      }

      // 生成分析结果
      final analysis = generateAnalysis(indicators, quote);

      // 仅保留买入级别以上
      if (!_isBuyRecommendation(analysis.recommendation)) {
        return null;
      }

      return ExploreResult(
        code: stock.code,
        name: stock.name,
        price: quote?.price ?? stock.price,
        changePct: quote?.changePct ?? stock.changePct,
        pe: quote?.pe ?? 0,
        pb: quote?.pb ?? 0,
        score: analysis.score,
        recommendation: analysis.recommendation,
        confluenceScore: analysis.confluenceScore,
        analyzedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Analyze ${stock.code} failed: $e');
      return null;
    }
  }

  /// PE/PB估值过滤
  static bool _passValuationFilter(QuoteData quote) {
    // PE为0表示亏损或不适用，跳过估值过滤
    if (quote.pe <= 0) return true;
    // PE在合理区间(0-80)且PB>0
    if (quote.pe < 80 && quote.pb > 0) return true;
    return false;
  }

  /// 判断是否为买入推荐
  static bool _isBuyRecommendation(String recommendation) {
    const buyRecs = ['强烈买入', '买入', '谨慎买入'];
    return buyRecs.contains(recommendation);
  }

  void dispose() {
    _apiClient.dispose();
  }
}

/// 探索进度状态
enum ExploreStatus {
  idle,
  fetchingSectors,
  fetchingStocks,
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