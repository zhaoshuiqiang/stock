import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../api/api_client.dart';
import '../core/trading_session.dart';

/// 持仓快照服务 —— 收盘后记录每日快照 + K线反算回填历史
class PortfolioSnapshotService {
  static final PortfolioSnapshotService _instance =
      PortfolioSnapshotService._internal();
  factory PortfolioSnapshotService() => _instance;
  PortfolioSnapshotService._internal();

  final DatabaseService _db = DatabaseService();
  final ApiClient _api = ApiClient();

  static const _kLastSnapshotDate = 'last_snapshot_date';

  /// 检查并记录今日快照（应用启动 + 收盘时调用）
  /// 仅在收盘后(15:00后)或非交易日执行，交易时段内跳过
  Future<void> recordIfNeeded({
    required Map<String, Position> positionMap,
    double totalAssets = 0,
    double availableCash = 0,
  }) async {
    if (positionMap.isEmpty) return;

    final now = DateTime.now();
    if (await _db.hasSnapshotForDate(now)) return;
    // 交易时段内不记录（等收盘）
    if (TradingSession.isInTradingSession()) return;

    await _recordSnapshot(
      date: now,
      positionMap: positionMap,
      totalAssets: totalAssets,
      availableCash: availableCash,
    );
  }

  Future<void> _recordSnapshot({
    required DateTime date,
    required Map<String, Position> positionMap,
    double totalAssets = 0,
    double availableCash = 0,
  }) async {
    try {
      double totalCost = 0;
      double totalMarketValue = 0;
      double totalPnl = 0;
      double todayPnl = 0;

      final codes = positionMap.values
          .map((p) => _api.addMarketPrefix(p.code))
          .toList();
      final quotes = await _api.getBatchRealtimeQuotes(codes);
      final quoteMap = {for (final q in quotes) q.code: q};

      for (final pos in positionMap.values) {
        final prefixedCode = _api.addMarketPrefix(pos.code);
        final quote = quoteMap[prefixedCode] ?? QuoteData.empty();
        final currentPrice = quote.price > 0
            ? quote.price
            : (pos.latestPrice > 0 ? pos.latestPrice : pos.avgPrice);

        final cost = pos.quantity * pos.avgPrice;
        final marketValue = pos.quantity * currentPrice;
        // v3.2: 始终从实时行情计算盈亏，不使用DB中可能过期的存储值
        final pnl = marketValue - cost;
        final dayPnl = quote.preClose > 0
            ? pos.quantity * (currentPrice - quote.preClose)
            : 0.0;

        totalCost += cost;
        totalMarketValue += marketValue;
        totalPnl += pnl;
        todayPnl += dayPnl;
      }

      final totalPnlPct =
          totalCost > 0 ? totalPnl / totalCost * 100 : 0.0;
      final yesterdayValue = totalMarketValue - todayPnl;
      final todayPnlPct =
          yesterdayValue > 0 ? todayPnl / yesterdayValue * 100 : 0.0;

      final snapshot = PortfolioSnapshot(
        date: date,
        totalCost: totalCost,
        totalMarketValue: totalMarketValue,
        totalPnl: totalPnl,
        totalPnlPct: totalPnlPct,
        todayPnl: todayPnl,
        todayPnlPct: todayPnlPct,
        availableCash: availableCash,
        totalAssets:
            totalAssets > 0 ? totalAssets : totalMarketValue + availableCash,
        positionsJson: _serializePositions(positionMap),
      );

      await _db.saveDailySnapshot(snapshot);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastSnapshotDate, _formatDate(date));

      debugPrint('[Snapshot] 已记录 ${_formatDate(date)} 持仓快照');
    } catch (e) {
      debugPrint('[Snapshot] 记录失败: $e');
    }
  }

  /// K线反算历史快照（假设当前持仓一直持有，用于功能上线首日回填）
  Future<List<PortfolioSnapshot>> estimateHistoryFromKlines({
    required Map<String, Position> positionMap,
    required int days,
  }) async {
    if (positionMap.isEmpty) return [];

    try {
      final klineMap = <String, List<HistoryKline>>{};
      for (final pos in positionMap.values) {
        final prefixedCode = _api.addMarketPrefix(pos.code);
        final klines =
            await _api.getStockHistory(prefixedCode, days: days);
        if (klines.isNotEmpty) {
          klineMap[pos.code] = klines;
        }
      }

      if (klineMap.isEmpty) return [];

      // 收集所有日期并排序
      final dateSet = <String>{};
      for (final klines in klineMap.values) {
        for (final k in klines) {
          dateSet.add(_formatDate(k.date));
        }
      }
      final sortedDates = dateSet.toList()..sort();

      final snapshots = <PortfolioSnapshot>[];
      double prevTotalValue = 0;

      for (final dateStr in sortedDates) {
        final date = DateTime.parse(dateStr);
        double totalCost = 0;
        double totalMarketValue = 0;

        for (final pos in positionMap.values) {
          final klines = klineMap[pos.code];
          if (klines == null) continue;

          final kline = klines.firstWhere(
            (k) => _formatDate(k.date) == dateStr,
            orElse: () => klines.first,
          );

          totalCost += pos.quantity * pos.avgPrice;
          totalMarketValue += pos.quantity * kline.close;
        }

        final totalPnl = totalMarketValue - totalCost;
        final totalPnlPct =
            totalCost > 0 ? totalPnl / totalCost * 100 : 0.0;
        final todayPnl =
            prevTotalValue > 0 ? totalMarketValue - prevTotalValue : 0.0;
        final todayPnlPct =
            prevTotalValue > 0 ? todayPnl / prevTotalValue * 100 : 0.0;

        snapshots.add(PortfolioSnapshot(
          date: date,
          totalCost: totalCost,
          totalMarketValue: totalMarketValue,
          totalPnl: totalPnl,
          totalPnlPct: totalPnlPct,
          todayPnl: todayPnl,
          todayPnlPct: todayPnlPct,
        ));

        prevTotalValue = totalMarketValue;
      }

      return snapshots;
    } catch (e) {
      debugPrint('[Snapshot] K线反算失败: $e');
      return [];
    }
  }

  /// 获取收益率趋势数据（混合数据源：快照表优先，不足用K线反算补充）
  Future<List<PortfolioSnapshot>> getReturnTrend({
    required Map<String, Position> positionMap,
    required int days,
  }) async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));

    // 1. 查询快照表
    final dbSnapshots = await _db.getSnapshots(
      startDate: startDate,
      endDate: endDate,
    );

    // 2. 快照覆盖不足时，用K线反算补充
    if (dbSnapshots.length < days * 0.5) {
      final estimated = await estimateHistoryFromKlines(
        positionMap: positionMap,
        days: days,
      );
      // 合并：同日期优先用真实快照
      final merged = <String, PortfolioSnapshot>{};
      for (final s in estimated) {
        merged[_formatDate(s.date)] = s;
      }
      for (final s in dbSnapshots) {
        merged[_formatDate(s.date)] = s;
      }
      final result = merged.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      final startIdx =
          result.length > days ? result.length - days : 0;
      return result.sublist(startIdx);
    }

    return dbSnapshots;
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _serializePositions(Map<String, Position> map) {
    final list = map.values
        .map((p) => {
              'code': p.code,
              'name': p.name,
              'quantity': p.quantity,
              'avgPrice': p.avgPrice,
            })
        .toList();
    return jsonEncode(list);
  }
}
