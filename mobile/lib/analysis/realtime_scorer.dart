import '../models/stock_models.dart';

/// 实时行情评分器，从 signal_engine 的 generateAnalysis 中提取
class RealtimeScorer {
  /// 对实时行情数据进行评分，返回 0-10 的分数
  static double score(QuoteData? quote) {
    double realtimeScore = 5.0;
    if (quote != null && quote.price > 0) {
      final changePct = quote.changePct;
      // 短线顺势评分：涨势加分，跌势扣分
      if (changePct > 8) {
        realtimeScore += 2.5; // 极强上涨，短线动能最强
      } else if (changePct > 5) {
        realtimeScore += 2.0; // 强势上涨
      } else if (changePct > 2) {
        realtimeScore += 1.5; // 明显上涨
      } else if (changePct > 0) {
        realtimeScore += 1.0; // 温和上涨
      } else if (changePct >= -2) {
        realtimeScore -= 0.5; // 温和下跌
      } else if (changePct >= -5) {
        realtimeScore -= 1.5; // 明显下跌，短线弱势
      } else if (changePct >= -8) {
        realtimeScore -= 2.0; // 大幅下跌
      } else {
        realtimeScore -= 2.5; // 暴跌，短线极度弱势
      }

      if (quote.mainNetFlow != 0) {
        final rate = quote.mainNetFlowRate;
        if (rate > 10) {
          realtimeScore += 1.5;
        } else if (rate > 5) {
          realtimeScore += 1.0;
        } else if (rate > 0) {
          realtimeScore += 0.5;
        } else if (rate > -5) {
          realtimeScore -= 0.5;
        } else if (rate > -10) {
          realtimeScore -= 1.0;
        } else {
          realtimeScore -= 1.5;
        }
      }

      if (quote.turnover > 0) {
        if (quote.turnover >= 1 && quote.turnover <= 5) {
          realtimeScore += 0.5;
        } else if (quote.turnover > 10) {
          realtimeScore -= 0.5;
        } else if (quote.turnover < 0.5) {
          realtimeScore -= 0.3;
        }
      }
    }
    realtimeScore = realtimeScore.clamp(0.0, 10.0);
    return realtimeScore;
  }
}
