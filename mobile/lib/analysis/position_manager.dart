import '../models/stock_models.dart';

/// 基于 ATR 波动率的动态仓位管理器
class PositionManager {
  /// 计算建议仓位比例（0.0-1.0）
  /// 
  /// 公式: suggestedPosition = clamp(baseRiskPct / atrPct, minPosition, maxPosition)
  /// - atrPct = ATR14 / close × 100（波动率百分比）
  /// - 波动率越高，建议仓位越低
  static double calculatePosition(HistoryKline kline, {double baseRiskPct = 2.5, double minPosition = 0.1, double maxPosition = 1.0}) {
    if (kline.atr14 <= 0 || kline.close <= 0) return 0.5; // 默认半仓

    final atrPct = kline.atr14 / kline.close * 100;

    // 极端情况保护
    if (atrPct <= 0.5) return maxPosition;
    if (atrPct >= 20) return minPosition;

    final suggestedPosition = baseRiskPct / atrPct;
    return suggestedPosition.clamp(minPosition, maxPosition);
  }

  /// 获取仓位建议文本
  static String getPositionAdvice(double position) {
    if (position >= 0.8) {
      return '波动率较低，可重仓操作，建议仓位 ${(position * 100).round()}%';
    } else if (position >= 0.6) {
      return '波动率适中偏小，建议仓位 ${(position * 100).round()}%';
    } else if (position >= 0.4) {
      return '波动率适中，建议半仓 ${(position * 100).round()}%';
    } else if (position >= 0.25) {
      return '波动率较高，建议轻仓 ${(position * 100).round()}%';
    } else {
      return '波动率极高，建议迷你仓 ${(position * 100).round()}%，严格止损';
    }
  }

  /// 获取波动率等级
  static String getVolatilityLevel(double atrPct) {
    if (atrPct < 2) return '低波动';
    if (atrPct < 3) return '中等波动';
    if (atrPct < 5) return '高波动';
    return '极高波动';
  }
}