import 'package:flutter/foundation.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// 涨停池数据采集器
/// 负责：API 拉取 + DB 缓存合并 + 行情字段补全 + 去重
class LimitUpUniverseProvider {
  const LimitUpUniverseProvider._();

  /// 合并今日 DB 缓存与 API 最新数据，去重（fresh 覆盖 today）
  static List<LimitUpStock> mergeAndDedup(
    List<LimitUpStock> today,
    List<LimitUpStock> fresh,
  ) {
    final map = <String, LimitUpStock>{};
    for (final s in today) {
      map[s.code] = s;
    }
    for (final s in fresh) {
      map[s.code] = s;  // fresh 覆盖
    }
    return map.values.toList();
  }

  /// 用实时行情补充 price/changePct/volumeRatio
  /// quotes 的 code 可能带 sh./sz. 前缀（带点）或 sh/sz 前缀（无点），均需剥离匹配
  static List<LimitUpStock> supplementQuotes(
    List<LimitUpStock> stocks,
    List<QuoteData> quotes,
  ) {
    final quoteMap = <String, QuoteData>{};
    for (final q in quotes) {
      // 剥离 sh./sz./bj. 前缀（带点）或 sh/sz/bj 前缀（无点）
      final bareCode = q.code.replaceAll(RegExp(r'^(sh|sz|bj)\.?', caseSensitive: false), '');
      quoteMap[bareCode] = q;
    }
    return stocks.map((s) {
      final q = quoteMap[s.code];
      if (q == null) return s;
      return LimitUpStock(
        code: s.code, name: s.name,
        price: q.price, changePct: q.changePct,
        consecutiveDays: s.consecutiveDays,
        firstLimitTime: s.firstLimitTime, lastLimitTime: s.lastLimitTime,
        sealAmount: s.sealAmount, turnoverRate: s.turnoverRate,
        volumeRatio: s.volumeRatio,
        sector: s.sector, limitUpType: s.limitUpType,
        sealRatio: s.sealRatio, limitUpPrice: s.limitUpPrice,
        totalValue: s.totalValue, circulationValue: s.circulationValue,
        zhabanCount: s.zhabanCount, isZhaBan: s.isZhaBan,
      );
    }).toList();
  }

  /// 完整采集流程：API 拉取 + 行情补全
  /// 调用方负责分片（每批 30 只调用 getBatchRealtimeQuotes）
  static Future<List<LimitUpStock>> fetchLatest({ApiClient? apiClient}) async {
    final api = apiClient ?? ApiClient();
    try {
      final pool = await api.getLimitUpBoard();
      if (pool.isEmpty) return [];
      // 分片补充行情
      const batchSize = 30;
      final allQuotes = <QuoteData>[];
      for (var i = 0; i < pool.length; i += batchSize) {
        try {
          final batch = pool.skip(i).take(batchSize).map((s) => s.code).toList();
          // 复用 ApiClient.addMarketPrefix 实例方法（返回 sh600519 无点格式，腾讯接口要求）
          final prefixed = batch.map((c) => api.addMarketPrefix(c)).toList();
          final quotes = await api.getBatchRealtimeQuotes(prefixed);
          allQuotes.addAll(quotes);
        } catch (e) {
          // 批次失败不阻塞后续批次，部分行情数据仍可用于补充
          debugPrint('LimitUpUniverseProvider.fetchLatest batch $i failed: $e');
        }
      }
      return supplementQuotes(pool, allQuotes);
    } catch (e) {
      debugPrint('LimitUpUniverseProvider.fetchLatest failed: $e');
      return [];
    }
  }
}
