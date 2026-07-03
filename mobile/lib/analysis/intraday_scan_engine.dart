/// 分时低吸批量扫描引擎
///
/// 从 explore_results 表取热门股票，对每只股票跑分时分析，
/// 筛选出有高可信度低吸信号的股票，用于发现页"分时低吸"Tab。

import 'package:flutter/material.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/storage/database_service.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'intraday_level_analyzer.dart';

/// 单只股票的分时低吸扫描结果
class IntradayScanResult {
  final String code;
  final String name;
  final double currentPrice;
  final double changePct;
  final IntradayLevelPoint topBuySignal; // 最强低吸信号
  final IntradayTrend trend;
  final int score; // 1-10，基于信号置信度+趋势

  IntradayScanResult({
    required this.code,
    required this.name,
    required this.currentPrice,
    required this.changePct,
    required this.topBuySignal,
    required this.trend,
    required this.score,
  });
}

class IntradayScanEngine {
  IntradayScanEngine._();

  /// 单次扫描股票上限
  static const int _maxScanCount = 30;
  /// 并发上限
  static const int _maxConcurrency = 5;

  /// 批量扫描分时低吸信号
  ///
  /// 数据源：从 explore_results 表取热门股票前 30 只（按 score DESC）。
  /// 仅返回有高可信度（isHighConfidence=true）低吸信号的股票。
  /// 仅在交易时段内有意义；盘后调用会返回空列表（无分时数据）。
  static Future<List<IntradayScanResult>> scan() async {
    try {
      final db = DatabaseService();
      final api = ApiClient();

      final exploreResults = await db.getExploreResults();
      if (exploreResults.isEmpty) return [];

      // A股按上海时区(UTC+8)判断交易时段，避免海外用户时区偏移导致扫描为空
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final currentOffset = IntradayLevelAnalyzer.timeToMinuteOffset(now);
      if (currentOffset == null) return [];

      final candidates = exploreResults.take(_maxScanCount).toList();
      final results = <IntradayScanResult>[];

      // 限流并发执行
      for (int i = 0; i < candidates.length; i += _maxConcurrency) {
        final batch = candidates.skip(i).take(_maxConcurrency).toList();
        final batchResults = await Future.wait(
          batch.map((r) => _scanSingle(api, r.code, r.name, currentOffset)),
        );
        for (final res in batchResults) {
          if (res != null) results.add(res);
        }
      }

      // 按信号置信度降序排序
      results.sort((a, b) =>
          b.topBuySignal.confidence.compareTo(a.topBuySignal.confidence));
      return results;
    } catch (e) {
      debugPrint('IntradayScanEngine.scan error: $e');
      return [];
    }
  }

  /// 扫描单只股票
  static Future<IntradayScanResult?> _scanSingle(
    ApiClient api,
    String code,
    String name,
    int currentOffset,
  ) async {
    try {
      final timeshare = await api.getTimeshareData(code);
      if (timeshare == null) return null;
      final prices = timeshare['prices'] ?? <int, double>{};
      final volumes = timeshare['volumes'] ?? <int, double>{};
      final vwapData = timeshare['vwapData'] ?? <int, double>{};
      if (prices.isEmpty) return null;

      QuoteData? quote;
      try {
        quote = await api.getRealtimeQuote(api.addMarketPrefix(code));
      } catch (_) {
        return null;
      }
      if (quote == null || quote.price <= 0) return null;

      final result = IntradayLevelAnalyzer.analyze(
        prices: prices,
        volumes: volumes,
        vwapData: vwapData,
        preClose: quote.preClose,
        openPrice: quote.open,
        dayHigh: quote.high,
        dayLow: quote.low,
        currentOffset: currentOffset,
        estimatedAmplitude: quote.amplitude,
      );

      // 仅保留高可信度低吸信号
      final highConfBuys = result.buySignals.where((s) => s.isHighConfidence).toList();
      if (highConfBuys.isEmpty) return null;

      // 取最强信号（置信度最高）
      highConfBuys.sort((a, b) => b.confidence.compareTo(a.confidence));
      final topSignal = highConfBuys.first;

      // 评分：基础分 = 置信度 * 10，趋势加成
      int score = (topSignal.confidence * 10).round();
      if (result.trend == IntradayTrend.bullish) {
        score += 1;
      } else if (result.trend == IntradayTrend.bearish) {
        score -= 1;
      }
      score = score.clamp(1, 10);

      return IntradayScanResult(
        code: code,
        name: name,
        currentPrice: quote.price,
        changePct: quote.changePct,
        topBuySignal: topSignal,
        trend: result.trend,
        score: score,
      );
    } catch (e) {
      debugPrint('IntradayScanEngine _scanSingle($code) error: $e');
      return null;
    }
  }
}
