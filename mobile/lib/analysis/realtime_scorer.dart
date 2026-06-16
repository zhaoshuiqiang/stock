import '../models/stock_models.dart';

class RealtimeScorer {
  /// 倒U型评分：温和上涨最优，抑制追高
  static double score(QuoteData? quote) {
    double s = 5.0;
    if (quote != null && quote.price > 0) {
      final cp = quote.changePct;
      if (cp > 8) s += 0.3;
      else if (cp > 5) s += 1.5;
      else if (cp > 2) s += 2.0;
      else if (cp > 0) s += 1.2;
      else if (cp >= -2) s += 0.5;
      else if (cp >= -5) s -= 0.5;
      else if (cp >= -8) s -= 1.5;
      else s -= 2.5;

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
