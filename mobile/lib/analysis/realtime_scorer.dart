import '../models/stock_models.dart';
import 'scoring_config.dart';

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
      // v4.6: 11-day archive validation — already up 3~9% => next-day win rate
      // collapses (3-6% ~36%, 6-9% ~31% vs mild-rise ~55%). Reward only mild
      // rise (0~3%); do NOT add points across the 3~9% chase zone.
      if (ScoringConfig.useShortTermRealtimeReprofile) {
        // v4.10 reprofile (default off): reward peak at mild pullback/flat,
        // 3-5% chase zone penalized. Evidence: 3281-row archive outcomes.
        if (cp > 1 && cp <= 3) s += 0.3;
        else if (cp > 0 && cp <= 1) s += 0.6;
        else if (cp > 3 && cp <= 5) s -= 0.3;
        else if (cp > 5 && cp <= 8) s -= 0.2;
        else if (cp > 8) s += 0.0;
        else if (cp >= -2) s += 1.0;
        else if (cp >= -5) s -= 0.3;
        else if (cp >= -8) s -= 1.5;
        else s -= 2.5;
      } else {
        if (cp > 1 && cp <= 3) s += 1.0;
        else if (cp > 0 && cp <= 1) s += 0.5;
        else if (cp > 3 && cp <= 5) s += 0.3;
        else if (cp > 5 && cp <= 8) s += 0.0;
        else if (cp > 8) s += 0.0;
        else if (cp >= -2) s += 0.5;
        else if (cp >= -5) s -= 0.5;
        else if (cp >= -8) s -= 1.5;
        else s -= 2.5;
      }

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
