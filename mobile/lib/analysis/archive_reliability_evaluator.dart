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
  static (double threshold, double neutralThreshold) calculateThresholds(
    ArchiveRecord record, {
    DateTime? now,
  }) {
    final baseNow = now ?? DateTime.now();
    final daysSince =
        baseNow.difference(record.archivedAt).inDays.clamp(0, 365);
    final timeScale = max(daysSince, 1) / 5.0;
    final timeFactor = sqrt(timeScale);
    return (
      (2.0 * timeFactor).clamp(2.0, 12.0),
      (8.0 * timeFactor).clamp(4.0, 24.0),
    );
  }

  static ArchiveRecommendationDirection directionOf(ArchiveRecord record) {
    final recommendation = record.recommendation.trim();
    if (recommendation.contains('买入') || recommendation == '偏多观望') {
      return ArchiveRecommendationDirection.bullish;
    }
    if (recommendation.contains('卖出') || recommendation == '偏空观望') {
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
      final threshold =
          record.recommendation == '偏多观望' ? baseThreshold * 1.3 : baseThreshold;
      if (priceChangePct >= threshold) return ReliabilityLevel.veryReasonable;
      if (priceChangePct >= 0) return ReliabilityLevel.reasonable;
      if (priceChangePct >= -threshold) return ReliabilityLevel.deviation;
      return ReliabilityLevel.veryDeviation;
    }

    if (direction == ArchiveRecommendationDirection.bearish) {
      final threshold =
          record.recommendation == '偏空观望' ? baseThreshold * 1.3 : baseThreshold;
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
