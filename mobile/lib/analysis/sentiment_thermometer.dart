import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// 情绪温度计纯函数引擎
/// 输入：今日打板池 + 昨日打板池 + 今日行情涨跌幅 + 昨日阶段
/// 输出：SentimentResult（5维指标 + 温度 + 阶段 + 信号）
class SentimentThermometer {
  const SentimentThermometer._();

  /// 主计算入口
  static SentimentResult compute({
    required List<LimitUpAnalysis> todayPool,
    required List<LimitUpAnalysis> yesterdayPool,
    required Map<String, double> todayQuotePct,
    EmotionPhase? yesterdayPhase,
  }) {
    final zhabanRate = _computeZhabanRate(todayPool);
    final continuationRate = _computeContinuationRate(todayPool, yesterdayPool);
    final sealSuccessRate = _computeSealSuccessRate(todayPool);
    final moneyMakingEffect = _computeMoneyMakingEffect(yesterdayPool, todayQuotePct);
    final continuationHeight = _computeContinuationHeight(todayPool);
    final limitUpCount = todayPool.where((a) => !a.isZhaBan).length;
    const limitDownCount = 0;  // P0 暂不接入跌停数据

    final temperature = _computeTemperature(
      zhabanRate: zhabanRate,
      continuationRate: continuationRate,
      sealSuccessRate: sealSuccessRate,
      moneyMakingEffect: moneyMakingEffect,
      continuationHeight: continuationHeight,
    );

    final phase = _inferPhase(
      temperature: temperature,
      limitUpCount: limitUpCount,
      continuationHeight: continuationHeight,
      continuationRate: continuationRate,
      yesterdayPhase: yesterdayPhase,
    );

    final signals = _generateSignals(
      zhabanRate: zhabanRate,
      continuationRate: continuationRate,
      moneyMakingEffect: moneyMakingEffect,
      continuationHeight: continuationHeight,
      limitUpCount: limitUpCount,
    );

    return SentimentResult(
      temperature: temperature,
      phase: phase,
      zhabanRate: zhabanRate,
      continuationRate: continuationRate,
      sealSuccessRate: sealSuccessRate,
      moneyMakingEffect: moneyMakingEffect,
      limitUpCount: limitUpCount,
      limitDownCount: limitDownCount,
      continuationHeight: continuationHeight,
      signals: signals,
      timestamp: DateTime.now(),
    );
  }

  // === 维度 1: 炸板率 ===
  static double _computeZhabanRate(List<LimitUpAnalysis> pool) {
    if (pool.isEmpty) return 0.5;
    final zhaban = pool.where((a) => a.isZhaBan).length;
    return zhaban / pool.length;
  }

  // === 维度 2: 连板晋级率（1板→2板）===
  static double _computeContinuationRate(
    List<LimitUpAnalysis> today,
    List<LimitUpAnalysis> yesterday,
  ) {
    if (yesterday.isEmpty) return 0.3;
    final y1 = yesterday.where((a) => a.consecutiveDays == 1).length;
    // 晋级率 = 1板→2板，分子只计今日 2板（即昨日 1板晋级而来）
    final t2 = today.where((a) => a.consecutiveDays == 2).length;
    if (y1 == 0) return 0.3;
    return (t2 / y1).clamp(0.0, 1.0);
  }

  // === 维度 3: 涨停封板成功率 ===
  static double _computeSealSuccessRate(List<LimitUpAnalysis> pool) {
    if (pool.isEmpty) return 0.5;
    final sealed = pool.where((a) => !a.isZhaBan).length;
    final rawRate = sealed / pool.length;
    final weakSealCount = pool.where((a) =>
        !a.isZhaBan && a.sealAmount < 1000).length;
    final penalty = weakSealCount / pool.length * 0.2;
    return (rawRate - penalty).clamp(0.0, 1.0);
  }

  // === 维度 4: 赚钱效应 ===
  static double _computeMoneyMakingEffect(
    List<LimitUpAnalysis> yesterdayPool,
    Map<String, double> todayQuotePct,
  ) {
    if (yesterdayPool.isEmpty) return 0.0;
    final pcts = yesterdayPool.map((a) => todayQuotePct[a.code] ?? 0.0).toList();
    return pcts.reduce((a, b) => a + b) / pcts.length;
  }

  // === 维度 5: 连板高度 ===
  static int _computeContinuationHeight(List<LimitUpAnalysis> pool) {
    return pool.fold(0, (max, a) => a.consecutiveDays > max ? a.consecutiveDays : max);
  }

  // === 综合温度 ===
  static double _computeTemperature({
    required double zhabanRate,
    required double continuationRate,
    required double sealSuccessRate,
    required double moneyMakingEffect,
    required int continuationHeight,
  }) {
    final zhabanScore = 1.0 - zhabanRate;
    final contScore = continuationRate.clamp(0.0, 1.0);
    final sealScore = sealSuccessRate.clamp(0.0, 1.0);
    final moneyScore = ((moneyMakingEffect + 5) / 10).clamp(0.0, 1.0);
    final heightScore = (continuationHeight / 7).clamp(0.0, 1.0);
    final temp = zhabanScore * 20 + contScore * 25 + sealScore * 15
               + moneyScore * 30 + heightScore * 10;
    return temp.clamp(0.0, 100.0);
  }

  // === 阶段判定 ===
  static EmotionPhase _inferPhase({
    required double temperature,
    required int limitUpCount,
    required int continuationHeight,
    required double continuationRate,
    required EmotionPhase? yesterdayPhase,
  }) {
    if (limitUpCount >= 30 && continuationHeight <= 3 &&
        temperature >= 30 && temperature < 55) {
      return EmotionPhase.startup;
    }
    if (limitUpCount >= 50 && continuationHeight >= 4 && temperature >= 60) {
      return EmotionPhase.climax;
    }
    if (temperature >= 40 && temperature < 60 &&
        (continuationRate < 0.3 || yesterdayPhase == EmotionPhase.climax)) {
      return EmotionPhase.retreat;
    }
    if (limitUpCount < 20 && continuationHeight <= 2 && temperature < 30 &&
        yesterdayPhase != EmotionPhase.climax) {
      return EmotionPhase.freezing;
    }
    if (yesterdayPhase == null) return EmotionPhase.startup;
    switch (yesterdayPhase) {
      case EmotionPhase.freezing:
        return temperature >= 35 ? EmotionPhase.startup : EmotionPhase.freezing;
      case EmotionPhase.startup:
        return temperature >= 60 ? EmotionPhase.climax : EmotionPhase.startup;
      case EmotionPhase.climax:
        return temperature < 55 ? EmotionPhase.retreat : EmotionPhase.climax;
      case EmotionPhase.retreat:
        return temperature < 30 ? EmotionPhase.freezing : EmotionPhase.retreat;
    }
  }

  // === 信号生成 ===
  static List<String> _generateSignals({
    required double zhabanRate,
    required double continuationRate,
    required double moneyMakingEffect,
    required int continuationHeight,
    required int limitUpCount,
  }) {
    return [
      if (zhabanRate >= 0.7) '⚠️ 炸板潮：封板意愿极弱，打板胜率低',
      if (zhabanRate < 0.15) '🔥 封板极强：打板情绪高涨',
      if (continuationRate > 0.5) '🚀 接力强：连板晋级率高',
      if (continuationRate < 0.1) '❄️ 接力冰点：避免追高',
      if (moneyMakingEffect > 3) '💰 赚钱效应强：昨日打板今日盈利',
      if (moneyMakingEffect < -3) '💸 亏钱效应：昨日打板今日亏损',
      if (continuationHeight >= 5) '👑 龙头$continuationHeight板：高度突破',
      if (limitUpCount >= 80) '🌊 涨停潮：$limitUpCount家涨停',
      if (limitUpCount < 15) '🧊 涨停稀少：$limitUpCount家',
    ];
  }
}
