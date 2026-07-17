import '../models/stock_models.dart';

class RealtimeScorer {
  /// 倒U型评分：温和上涨最优，抑制追高
  /// v2.48.0: 增加跳空低开检测，识别恐慌抛压信号
  static double score(QuoteData? quote) {
    double s = 5.0;
    if (quote != null && quote.price > 0) {
      final cp = quote.changePct;
      // v3.34: 留档数据分析——涨幅>2%时胜率急降，评分与当日涨幅高度耦合导致追涨推荐
      // 修复: 涨幅>3%改为惩罚，涨幅>5%大幅惩罚，涨停板惩罚加倍
      // 数据: 涨幅2~3%胜率7%, 3~5%胜率18%, >5%胜率26%
      if (cp > 9.5) s -= 2.0;     // 涨停板: 次日溢价不确定性高，大幅惩罚
      else if (cp > 8) s -= 1.2;  // 大涨: 追高风险极大
      else if (cp > 5) s -= 0.5;  // 中阳线: 追高风险大
      else if (cp > 3) s -= 0.2;  // 偏强: 已涨偏多，轻微惩罚
      else if (cp > 1) s += 0.8;  // 温和上涨，最优区间
      else if (cp > 0) s += 0.5;  // 小幅上涨
      else if (cp >= -2) s += 0.5;
      else if (cp >= -5) s -= 0.5;
      else if (cp >= -8) s -= 1.5;
      else s -= 2.5;

      // v2.48.0: 跳空低开检测 — 开盘价低于昨收3%以上表明恐慌抛压
      if (quote.preClose > 0 && quote.open > 0) {
        final gapDownPct = (quote.open - quote.preClose) / quote.preClose * 100;
        if (gapDownPct < -5) {
          s -= 1.8;
        } else if (gapDownPct < -3) {
          s -= 1.0;
        } else if (gapDownPct < -1) {
          s -= 0.5;
        }
      }

      if (quote.mainNetFlow != 0) {
        final r = quote.mainNetFlowRate;
        if (r > 10) s += 1.5; else if (r > 5) s += 1.0; else if (r > 0) s += 0.5;
        else if (r > -3) s -= 0.3; else if (r > -6) s -= 0.8; else s -= 1.5;
      }

      if (quote.turnover > 0) {
        if (quote.turnover >= 2 && quote.turnover <= 5) s += 0.8;
        else if (quote.turnover >= 1 && quote.turnover < 2) s += 0.4;
        else if (quote.turnover > 8 && quote.turnover <= 15) s -= 0.2;
        else if (quote.turnover > 15) s -= 0.8;
        else if (quote.turnover < 0.5) s -= 0.5;
      }

      if (quote.amplitude > 8) { if (cp > 0 && quote.turnover > 3) s += 0.3; else s -= 0.5; }
      else if (quote.amplitude > 5) s += 0.2;
    }
    return s.clamp(0.0, 10.0);
  }
}
