import '../models/stock_models.dart';
import 'scoring_config.dart';

/// 跨指标共振评分结果
class ConfluenceResult {
  /// 共振评分 (0-10)
  /// 5.0 为中性，多头指标加权加分（上限+5），空头指标加权减分（下限-5）
  /// 各指标权重不同：MA/MACD=1.5, VOL=1.2, BOLL=1.0, KDJ/RSI=0.8, WR/CCI=0.6, GAP=0.4, DIVER=1.0
  final double score;

  /// 多头指标数量
  final int bullCount;

  /// 空头指标数量
  final int bearCount;

  /// 10维度详情列表
  final List<Map<String, dynamic>> details;

  ConfluenceResult({
    required this.score,
    required this.bullCount,
    required this.bearCount,
    required this.details,
  });
}

/// 跨指标共振评分器
/// 从 signal_engine.dart 的 generateAnalysis 函数中提取的共振评分逻辑
class ConfluenceScorer {
  /// 计算10指标跨指标共振评分
  static ConfluenceResult score(HistoryKline last, List<SignalItem> signals) {
    // 各指标多空状态
    final maBull = last.ma5 > last.ma10 && last.ma10 > last.ma20;
    final maBear = last.ma5 < last.ma10 && last.ma10 < last.ma20;
    final macdBull = last.macdDif > last.macdDea && last.macdHist > 0;
    final macdBear = last.macdDif < last.macdDea && last.macdHist < 0;
    final rsiBull = last.rsi6 > 60;
    final rsiBear = last.rsi6 < 40 && last.rsi6 > 0;
    final kdjBull = last.k > last.d && last.k < 80;
    final kdjBear = last.k < last.d && last.k > 20;
    final bollBull = last.bollMid > 0 && last.close > last.bollMid;
    final bollBear = last.bollMid > 0 && last.close < last.bollMid;
    final volBull = last.volMa5 > 0 && last.volume > last.volMa5 && last.close > last.open;
    final volBear = last.volMa5 > 0 && last.volume > last.volMa5 && last.close < last.open;
    // WR是倒挂指标：值越小越超买，越大越超卖
    // <20=超买(偏空)，>80=超卖(偏多)
    final wrBull = last.wr14 != null && last.wr14! > 80; // 超卖→看多
    final wrBear = last.wr14 != null && last.wr14! < 20; // 超买→看空
    final cciBull = last.cci14 != null && last.cci14! > 100;
    final cciBear = last.cci14 != null && last.cci14! < -100;
    final hasGapUp = signals.any((s) => s.signal.contains('向上跳空'));
    final hasGapDown = signals.any((s) => s.signal.contains('向下跳空'));
    final hasBottomDivergence = signals.any((s) => s.signal.contains('底背离'));
    final hasTopDivergence = signals.any((s) => s.signal.contains('顶背离'));

    // 统计各指标多空方向
    final bullIndicators = <String>[];
    final bearIndicators = <String>[];
    if (maBull) bullIndicators.add('MA');
    if (maBear) bearIndicators.add('MA');
    if (macdBull) bullIndicators.add('MACD');
    if (macdBear) bearIndicators.add('MACD');
    if (rsiBull) bullIndicators.add('RSI');
    if (rsiBear) bearIndicators.add('RSI');
    if (kdjBull) bullIndicators.add('KDJ');
    if (kdjBear) bearIndicators.add('KDJ');
    if (bollBull) bullIndicators.add('BOLL');
    if (bollBear) bearIndicators.add('BOLL');
    if (volBull) bullIndicators.add('VOL');
    if (volBear) bearIndicators.add('VOL');
    if (wrBull) bullIndicators.add('WR');
    if (wrBear) bearIndicators.add('WR');
    if (cciBull) bullIndicators.add('CCI');
    if (cciBear) bearIndicators.add('CCI');
    if (hasGapUp) bullIndicators.add('GAP');
    if (hasGapDown) bearIndicators.add('GAP');
    if (hasBottomDivergence) {
      bullIndicators.add('DIVER');
    }
    if (hasTopDivergence) {
      bearIndicators.add('DIVER');
    }

    // 跨指标共振：加权计算，高可靠性指标权重更大
    final bullDistinct = bullIndicators.toSet().length;
    final bearDistinct = bearIndicators.toSet().length;
    double weightedBullConfluence = 0;
    for (final indicator in bullIndicators.toSet()) {
      weightedBullConfluence += _indicatorWeight(indicator);
    }
    double weightedBearConfluence = 0;
    for (final indicator in bearIndicators.toSet()) {
      weightedBearConfluence += _indicatorWeight(indicator);
    }
    final bullConfluence = weightedBullConfluence.clamp(0.0, 5.0);
    final bearConfluence = weightedBearConfluence.clamp(0.0, 5.0);
    final confluenceScore =
        (5.0 + bullConfluence - bearConfluence).clamp(0.0, 10.0);

    // 10维度共振详情
    final confluenceDetails = <Map<String, dynamic>>[];
    confluenceDetails.add({'name': 'MA', 'bull': maBull, 'bear': maBear});
    confluenceDetails.add({'name': 'MACD', 'bull': macdBull, 'bear': macdBear});
    confluenceDetails.add({'name': 'RSI', 'bull': rsiBull, 'bear': rsiBear});
    confluenceDetails.add({'name': 'KDJ', 'bull': kdjBull, 'bear': kdjBear});
    confluenceDetails.add({'name': 'BOLL', 'bull': bollBull, 'bear': bollBear});
    confluenceDetails.add({'name': '量价', 'bull': volBull, 'bear': volBear});
    confluenceDetails.add({'name': 'WR', 'bull': wrBull, 'bear': wrBear});
    confluenceDetails.add({'name': 'CCI', 'bull': cciBull, 'bear': cciBear});
    confluenceDetails.add({'name': '缺口', 'bull': hasGapUp, 'bear': hasGapDown});
    confluenceDetails.add({
      'name': '背离',
      'bull': hasBottomDivergence,
      'bear': hasTopDivergence,
      'weighted': true,
    });

    return ConfluenceResult(
      score: confluenceScore,
      bullCount: bullDistinct,
      bearCount: bearDistinct,
      details: confluenceDetails,
    );
  }

  /// 指标权重：基于历史回测可靠性和信号频率
  static double _indicatorWeight(String name) {
    switch (name) {
      case 'MA': return ScoringConfig.useShortTermTrendDiscount ? 1.0 : 1.5;     // 趋势类最高可靠性，有回测数据支撑
      case 'MACD': return 1.5;   // 核心动量指标，有回测数据支撑
      case 'VOL': return 1.2;    // 量价确认重要但需结合上下文
      case 'BOLL': return 1.0;   // 中轨参考价值适中
      case 'KDJ': return 0.8;    // 短线有效但噪声较大
      case 'RSI': return 0.8;    // 超买超卖可靠，中位区噪声较大
      case 'WR': return 0.6;     // 辅助指标，波动较大
      case 'CCI': return 0.6;    // 辅助指标，使用频率较低
      case 'GAP': return 0.4;    // 缺口罕见且统计显著性有限
      case 'DIVER': return 1.0;  // v2.38.0: 背离信号是强反转预警，权重提升至1.0
      default: return 0.8;
    }
  }
}
