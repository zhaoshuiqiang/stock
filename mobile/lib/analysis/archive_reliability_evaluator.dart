import 'dart:math';

import '../models/stock_models.dart';

enum ReliabilityLevel {
  veryReasonable,
  reasonable,
  deviation,
  veryDeviation,
}

enum ArchiveRecommendationDirection {
  bullish,
  bearish,
  neutral,
  unknown,
}

class ArchiveReliabilityStats {
  final int veryReasonableCount;
  final int reasonableCount;
  final int deviationCount;
  final int veryDeviationCount;
  final int bullishTotal;
  final int bullishHits;
  final int bearishTotal;
  final int bearishHits;
  final int neutralTotal;
  final int neutralStable;

  const ArchiveReliabilityStats({
    required this.veryReasonableCount,
    required this.reasonableCount,
    required this.deviationCount,
    required this.veryDeviationCount,
    required this.bullishTotal,
    required this.bullishHits,
    required this.bearishTotal,
    required this.bearishHits,
    required this.neutralTotal,
    required this.neutralStable,
  });

  int get total =>
      veryReasonableCount +
      reasonableCount +
      deviationCount +
      veryDeviationCount;
  int get reasonableTotal => veryReasonableCount + reasonableCount;
  double get directionReasonableRate =>
      total > 0 ? reasonableTotal / total * 100 : 0.0;
  double get veryReasonablePct =>
      total > 0 ? veryReasonableCount / total * 100 : 0.0;
  double get reasonablePct => total > 0 ? reasonableCount / total * 100 : 0.0;
  double get deviationPct => total > 0 ? deviationCount / total * 100 : 0.0;
  double get veryDeviationPct =>
      total > 0 ? veryDeviationCount / total * 100 : 0.0;
  double get bullishHitRate =>
      bullishTotal > 0 ? bullishHits / bullishTotal * 100 : 0.0;
  double get bearishHitRate =>
      bearishTotal > 0 ? bearishHits / bearishTotal * 100 : 0.0;
  double get neutralStableRate =>
      neutralTotal > 0 ? neutralStable / neutralTotal * 100 : 0.0;
}

class ArchiveReliabilityEvaluator {
  /// v3.21: 短线阈值收紧 — 当天(0-1日)基准陖1.0%，次日(1-2日)1.5%，之后沿用原有平方根增长。
  /// 超短线用户关心“买入后跌1.9%算不算正确”，原2%阈值太宽松，收紧后更真实反映短线胜率。
  static (double threshold, double neutralThreshold) calculateThresholds(
    ArchiveRecord record, {
    DateTime? now,
  }) {
    final baseNow = now ?? DateTime.now();
    final daysSince =
        baseNow.difference(record.archivedAt).inDays.clamp(0, 365);
    // 短线阈值收紧：0-1天=1.0%, 1-2天=1.5%, 之后≈原有的sqrt增长
    final double baseThreshold;
    final double baseNeutralThreshold;
    if (daysSince <= 1) {
      baseThreshold = 1.0;
      baseNeutralThreshold = 3.0;
    } else if (daysSince <= 2) {
      baseThreshold = 1.5;
      baseNeutralThreshold = 4.0;
    } else {
      final timeScale = daysSince / 5.0;
      final timeFactor = sqrt(timeScale);
      baseThreshold = (2.0 * timeFactor).clamp(2.0, 12.0);
      baseNeutralThreshold = (8.0 * timeFactor).clamp(4.0, 24.0);
    }
    return (baseThreshold, baseNeutralThreshold);
  }

  /// 根据存档记录中的推荐文本判断多空方向。
  ///
  /// 同时兼容新标签(强烈买入/买入/谨慎买入/卖出等)和旧标签(看多/强看多/回避/强回避等)。
  static ArchiveRecommendationDirection directionOf(ArchiveRecord record) {
    final recommendation = record.recommendation.trim();
    // 多头：新标签含'买入'，旧标签含'看多'，偏多观望
    if (recommendation.contains('买入') ||
        recommendation.contains('看多') ||
        recommendation == '偏多观望') {
      return ArchiveRecommendationDirection.bullish;
    }
    // 空头：新标签含'卖出'，旧标签含'回避'或'减仓'，偏空观望
    if (recommendation.contains('卖出') ||
        recommendation.contains('回避') ||
        recommendation.contains('减仓') ||
        recommendation == '偏空观望') {
      return ArchiveRecommendationDirection.bearish;
    }
    if (recommendation.contains('观望')) {
      return ArchiveRecommendationDirection.neutral;
    }
    return ArchiveRecommendationDirection.unknown;
  }

  static bool matchesTypeFilter(ArchiveRecord record, String filterType) {
    switch (filterType) {
      case '全部':
        return true;
      case '买入':
      case '看多':
        return directionOf(record) == ArchiveRecommendationDirection.bullish;
      case '卖出':
      case '看空':
        return directionOf(record) == ArchiveRecommendationDirection.bearish;
      case '观望':
      case '纯观望':
        return directionOf(record) == ArchiveRecommendationDirection.neutral;
      default:
        return record.recommendation.trim() == filterType;
    }
  }

  static ReliabilityLevel getReliabilityLevel(
    ArchiveRecord record,
    double currentPrice, {
    DateTime? now,
  }) {
    if (currentPrice <= 0 || record.price <= 0) {
      return ReliabilityLevel.reasonable;
    }

    final priceChangePct = (currentPrice - record.price) / record.price * 100;
    final absChange = priceChangePct.abs();
    final (baseThreshold, neutralThreshold) =
        calculateThresholds(record, now: now);
    final direction = directionOf(record);

    if (direction == ArchiveRecommendationDirection.bullish) {
      final isWeakBullish = record.recommendation.contains('偏多观望');
      final threshold = isWeakBullish ? baseThreshold * 1.3 : baseThreshold;
      if (priceChangePct >= threshold) return ReliabilityLevel.veryReasonable;
      if (priceChangePct >= 0) return ReliabilityLevel.reasonable;
      if (priceChangePct >= -threshold) return ReliabilityLevel.deviation;
      return ReliabilityLevel.veryDeviation;
    }

    if (direction == ArchiveRecommendationDirection.bearish) {
      final isWeakBearish = record.recommendation.contains('偏空观望');
      final threshold = isWeakBearish ? baseThreshold * 1.3 : baseThreshold;
      if (priceChangePct <= -threshold) return ReliabilityLevel.veryReasonable;
      if (priceChangePct <= 0) return ReliabilityLevel.reasonable;
      if (priceChangePct <= threshold) return ReliabilityLevel.deviation;
      return ReliabilityLevel.veryDeviation;
    }

    if (direction == ArchiveRecommendationDirection.neutral) {
      if (absChange < neutralThreshold * 0.5) {
        return ReliabilityLevel.veryReasonable;
      }
      if (absChange < neutralThreshold) return ReliabilityLevel.reasonable;
      if (absChange < neutralThreshold * 2) return ReliabilityLevel.deviation;
      return ReliabilityLevel.veryDeviation;
    }

    return ReliabilityLevel.reasonable;
  }

  static ArchiveReliabilityStats calculateStats({
    required Iterable<ArchiveRecord> records,
    required double Function(ArchiveRecord record) currentPriceOf,
    DateTime? now,
  }) {
    var veryReasonableCount = 0;
    var reasonableCount = 0;
    var deviationCount = 0;
    var veryDeviationCount = 0;
    var bullishTotal = 0;
    var bullishHits = 0;
    var bearishTotal = 0;
    var bearishHits = 0;
    var neutralTotal = 0;
    var neutralStable = 0;

    for (final record in records) {
      final currentPrice = currentPriceOf(record);
      final direction = directionOf(record);
      if (currentPrice <= 0 ||
          direction == ArchiveRecommendationDirection.unknown) {
        continue;
      }

      final level = getReliabilityLevel(record, currentPrice, now: now);
      final isHit = level == ReliabilityLevel.veryReasonable ||
          level == ReliabilityLevel.reasonable;

      switch (level) {
        case ReliabilityLevel.veryReasonable:
          veryReasonableCount++;
          break;
        case ReliabilityLevel.reasonable:
          reasonableCount++;
          break;
        case ReliabilityLevel.deviation:
          deviationCount++;
          break;
        case ReliabilityLevel.veryDeviation:
          veryDeviationCount++;
          break;
      }

      switch (direction) {
        case ArchiveRecommendationDirection.bullish:
          bullishTotal++;
          if (isHit) bullishHits++;
          break;
        case ArchiveRecommendationDirection.bearish:
          bearishTotal++;
          if (isHit) bearishHits++;
          break;
        case ArchiveRecommendationDirection.neutral:
          neutralTotal++;
          if (isHit) neutralStable++;
          break;
        case ArchiveRecommendationDirection.unknown:
          break;
      }
    }

    return ArchiveReliabilityStats(
      veryReasonableCount: veryReasonableCount,
      reasonableCount: reasonableCount,
      deviationCount: deviationCount,
      veryDeviationCount: veryDeviationCount,
      bullishTotal: bullishTotal,
      bullishHits: bullishHits,
      bearishTotal: bearishTotal,
      bearishHits: bearishHits,
      neutralTotal: neutralTotal,
      neutralStable: neutralStable,
    );
  }
}
