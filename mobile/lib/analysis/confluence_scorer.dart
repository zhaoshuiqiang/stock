import '../models/stock_models.dart';

/// 跨指标共振评分结果
class ConfluenceResult {
  /// 共振评分 (0-10)
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
    final wrBull = last.wr14 != null && last.wr14! > 80;
    final wrBear = last.wr14 != null && last.wr14! < 20;
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
      bullIndicators.add('DIVER_1');
      bullIndicators.add('DIVER_2');
    }
    if (hasTopDivergence) {
      bearIndicators.add('DIVER_1');
      bearIndicators.add('DIVER_2');
    }

    // 跨指标共振：不同指标数量越多，共振越强
    final bullDistinct = bullIndicators.toSet().length;
    final bearDistinct = bearIndicators.toSet().length;
    // 共振加分：每多一个不同指标偏多+0.8，最高+4；偏空同理
    final bullConfluence = (bullDistinct * 0.8).clamp(0.0, 4.0);
    final bearConfluence = (bearDistinct * 0.8).clamp(0.0, 4.0);
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
}
