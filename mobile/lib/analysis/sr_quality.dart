import '../models/stock_models.dart';

/// 支撑压力位质量评估结果
class SRQualityResult {
  final double level;
  final String type; // 'support' or 'resistance'
  final String quality; // '强支撑'/'弱支撑'/'强压力'/'弱压力'
  final int testCount; // 被测试次数
  final double avgVolumeAtLevel; // 该位置平均成交量
  final int daysSinceLastTest; // 距上次测试天数
  final double reliability; // 可靠性评分 0-1

  SRQualityResult({
    required this.level,
    required this.type,
    required this.quality,
    required this.testCount,
    required this.avgVolumeAtLevel,
    required this.daysSinceLastTest,
    required this.reliability,
  });
}

/// 支撑压力位质量评估器
class SRQualityEvaluator {
  /// 评估支撑位的质量
  /// [data] 已计算指标的历史K线
  /// [level] 支撑位价格
  /// [tolerance] 容差百分比（默认1%）
  static SRQualityResult evaluateSupport(
    List<HistoryKline> data,
    double level, {
    double tolerance = 0.01,
  }) {
    int testCount = 0;
    double totalVolume = 0;
    int lastTestIdx = -1;

    // 近60日内回测
    final lookback = data.length > 60 ? data.sublist(data.length - 60) : data;

    for (int i = 0; i < lookback.length - 1; i++) {
      final k = lookback[i];
      // 检查是否触及支撑位（最低价在容差范围内）
      if ((k.low - level).abs() / level < tolerance) {
        // 确认是反弹而非突破（次根K线收盘价高于支撑位）
        if (i + 1 < lookback.length && lookback[i + 1].close > level) {
          testCount++;
          totalVolume += k.volume;
          lastTestIdx = i;
        }
      }
    }

    final avgVolume = testCount > 0 ? totalVolume / testCount : 0.0;
    final daysSinceLastTest = lastTestIdx >= 0 ? lookback.length - 1 - lastTestIdx : 60;

    // 可靠性计算：测试次数越多、最近测试越近、越可靠
    double reliability = 0.3;
    if (testCount >= 3) {
      reliability += 0.4;
    } else if (testCount >= 2) {
      reliability += 0.2;
    } else if (testCount >= 1) {
      reliability += 0.1;
    }

    if (daysSinceLastTest < 10) {
      reliability += 0.2;
    } else if (daysSinceLastTest < 20) {
      reliability += 0.1;
    }

    // 时间衰减
    if (daysSinceLastTest > 40) {
      reliability -= 0.2;
    }

    reliability = reliability.clamp(0.0, 1.0);

    String quality;
    if (testCount >= 3 && daysSinceLastTest < 15) {
      quality = '强支撑';
    } else if (testCount >= 2) {
      quality = '中等支撑';
    } else if (testCount >= 1) {
      quality = '弱支撑';
    } else {
      quality = '未验证支撑';
    }

    return SRQualityResult(
      level: level,
      type: 'support',
      quality: quality,
      testCount: testCount,
      avgVolumeAtLevel: avgVolume,
      daysSinceLastTest: daysSinceLastTest,
      reliability: reliability,
    );
  }

  /// 评估压力位的质量
  static SRQualityResult evaluateResistance(
    List<HistoryKline> data,
    double level, {
    double tolerance = 0.01,
  }) {
    int testCount = 0;
    double totalVolume = 0;
    int lastTestIdx = -1;

    final lookback = data.length > 60 ? data.sublist(data.length - 60) : data;

    for (int i = 0; i < lookback.length - 1; i++) {
      final k = lookback[i];
      // 检查是否触及压力位（最高价在容差范围内）
      if ((k.high - level).abs() / level < tolerance) {
        // 确认是受阻回落（次根K线收盘价低于压力位）
        if (i + 1 < lookback.length && lookback[i + 1].close < level) {
          testCount++;
          totalVolume += k.volume;
          lastTestIdx = i;
        }
      }
    }

    final avgVolume = testCount > 0 ? totalVolume / testCount : 0.0;
    final daysSinceLastTest = lastTestIdx >= 0 ? lookback.length - 1 - lastTestIdx : 60;

    double reliability = 0.3;
    if (testCount >= 3) {
      reliability += 0.4;
    } else if (testCount >= 2) {
      reliability += 0.2;
    } else if (testCount >= 1) {
      reliability += 0.1;
    }

    if (daysSinceLastTest < 10) {
      reliability += 0.2;
    } else if (daysSinceLastTest < 20) {
      reliability += 0.1;
    }

    if (daysSinceLastTest > 40) {
      reliability -= 0.2;
    }

    reliability = reliability.clamp(0.0, 1.0);

    String quality;
    if (testCount >= 3 && daysSinceLastTest < 15) {
      quality = '强压力';
    } else if (testCount >= 2) {
      quality = '中等压力';
    } else if (testCount >= 1) {
      quality = '弱压力';
    } else {
      quality = '未验证压力';
    }

    return SRQualityResult(
      level: level,
      type: 'resistance',
      quality: quality,
      testCount: testCount,
      avgVolumeAtLevel: avgVolume,
      daysSinceLastTest: daysSinceLastTest,
      reliability: reliability,
    );
  }
}