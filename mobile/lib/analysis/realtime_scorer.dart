import '../models/stock_models.dart';

class RealtimeScorer {
  /// 倒U型评分：温和上涨最优，抑制追高
  /// v2.48.0: 增加跳空低开检测，识别恐慌抛压信号
  static double score(QuoteData? quote) {
    double s = 5.0;
    if (quote != null && quote.price > 0) {
      final cp = quote.changePct;
      // 倒U型评分：小涨最优，大涨抑制追高，大跌惩罚
      // v2.38.0: 中阳线(5%~8%)奖励从+1.5降至+1.0，避免诱多（次日反转风险高）
      if (cp > 8) s += 0.8;       // 大涨：抑制追高但给一定认可
      else if (cp > 5) s += 1.0;  // 中阳线：降低奖励，避免诱多
      else if (cp > 2) s += 2.0;  // 温和上涨，最优区间
      else if (cp > 0) s += 1.2;  // 小幅上涨
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
