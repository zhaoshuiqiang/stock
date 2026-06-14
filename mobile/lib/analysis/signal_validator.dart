import '../models/stock_models.dart';

/// 信号对抗验证器 - 参考 TradingAgents Bull/Bear Researcher
/// 为每个买卖信号生成反向视角，类似多智能体对抗辩论
class SignalValidator {
  /// 对信号列表进行对抗验证
  static List<ValidatedSignal> validate(
    List<SignalItem> signals,
    QuoteData? quote,
    HistoryKline last,
  ) {
    return signals.map((signal) {
      final counterPoints = signal.type == 'buy'
          ? _bearCounter(signal, quote, last)   // 买入信号 → Bear反对
          : signal.type == 'sell'
              ? _bullCounter(signal, quote, last) // 卖出信号 → Bull支撑
              : <String>[];                        // 中性信号无对抗

      final adjustedConfidence = _adjustConfidence(
        signal.confidence ?? 0.5,
        counterPoints,
      );

      return ValidatedSignal(
        signal: signal,
        counterPoints: counterPoints,
        adjustedConfidence: adjustedConfidence,
      );
    }).toList();
  }

  /// Bear视角：反对买入的理由
  static List<String> _bearCounter(
    SignalItem signal,
    QuoteData? quote,
    HistoryKline last,
  ) {
    final points = <String>[];

    // RSI超买反对
    if (last.rsi6 > 70) {
      points.add('RSI=${last.rsi6.toStringAsFixed(1)}处于超买区，回调风险较大');
    }

    // 均线空头反对
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0 &&
        last.ma5 < last.ma10 && last.ma10 < last.ma20) {
      points.add('均线空头排列，中期趋势偏弱，买入逆势');
    }

    // 量价背离反对
    if (last.volMa5 > 0 && last.close > last.open &&
        last.volume < last.volMa5 * 0.7) {
      points.add('上涨缩量，量价背离，上涨持续性存疑');
    }

    // PE过高反对
    if (quote != null && quote.pe > 60) {
      points.add('PE=${quote.pe.toStringAsFixed(1)}估值偏高，基本面不支撑');
    }

    // 主力流出反对
    if (quote != null && quote.mainNetFlowRate < -3) {
      points.add('主力净流出率${quote.mainNetFlowRate.toStringAsFixed(1)}%，资金面不支持');
    }

    // 布林上轨反对
    if (last.bollUpper > 0 && last.close > last.bollUpper) {
      points.add('价格突破布林上轨，短期过热，追高风险');
    }

    // KDJ超买反对
    if (last.j > 100) {
      points.add('KDJ的J值=${last.j.toStringAsFixed(1)}超买，短线见顶风险');
    }

    // BIAS乖离过大反对
    if (last.bias6 > 5) {
      points.add('BIAS6=${last.bias6.toStringAsFixed(1)}%乖离过大，回归均线风险');
    }

    return points;
  }

  /// Bull视角：支撑不卖出的理由
  static List<String> _bullCounter(
    SignalItem signal,
    QuoteData? quote,
    HistoryKline last,
  ) {
    final points = <String>[];

    // RSI超卖支撑
    if (last.rsi6 < 30 && last.rsi6 > 0) {
      points.add('RSI=${last.rsi6.toStringAsFixed(1)}处于超卖区，反弹概率增大');
    }

    // 均线多头支撑
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0 &&
        last.ma5 > last.ma10 && last.ma10 > last.ma20) {
      points.add('均线多头排列，中期趋势仍偏多，不宜恐慌卖出');
    }

    // 估值偏低支撑
    if (quote != null && quote.pe > 0 && quote.pe < 15) {
      points.add('PE=${quote.pe.toStringAsFixed(1)}估值较低，具有安全边际');
    }

    // 破净支撑
    if (quote != null && quote.pb > 0 && quote.pb < 1) {
      points.add('PB=${quote.pb.toStringAsFixed(2)}破净，不宜恐慌性抛售');
    }

    // 主力流入支撑
    if (quote != null && quote.mainNetFlowRate > 3) {
      points.add('主力净流入率${quote.mainNetFlowRate.toStringAsFixed(1)}%，资金面仍积极');
    }

    // 布林下轨支撑
    if (last.bollLower > 0 && last.close < last.bollLower) {
      points.add('价格跌破布林下轨，超卖状态，可能触发技术性反弹');
    }

    // KDJ超卖支撑
    if (last.j < 0) {
      points.add('KDJ的J值=${last.j.toStringAsFixed(1)}超卖，短线反弹概率增大');
    }

    // 缩量止跌支撑
    if (last.volMa5 > 0 && last.volume < last.volMa5 * 0.5) {
      points.add('成交量萎缩至均量50%以下，抛压减弱，可能接近底部');
    }

    return points;
  }

  /// 根据反向论点调整置信度
  static double _adjustConfidence(double baseConfidence, List<String> counterPoints) {
    double adjustment = 0;
    for (final point in counterPoints) {
      // 强反对关键词
      if (point.contains('超买') || point.contains('空头排列') ||
          point.contains('估值偏高') || point.contains('超卖') ||
          point.contains('多头排列') || point.contains('破净') ||
          point.contains('安全边际')) {
        adjustment -= 0.10;
      } else {
        adjustment -= 0.05;
      }
    }
    return (baseConfidence + adjustment).clamp(0.2, 0.95);
  }
}
