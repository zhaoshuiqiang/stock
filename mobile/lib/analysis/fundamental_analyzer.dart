import '../models/stock_models.dart';

/// 基本面分析器 - 参考 TradingAgents Fundamental Analyst
/// 利用 QuoteData 中的 PE/PB/主力资金/市值/换手率构建基本面评分
class FundamentalAnalyzer {
  /// 分析基本面评分
  static FundamentalScore analyze(QuoteData quote) {
    final factors = <String>[];

    // 1. 估值评分 (0-10): PE + PB
    final peScore = _scorePE(quote.pe);
    final pbScore = _scorePB(quote.pb);
    final valuationScore = (peScore * 0.6 + pbScore * 0.4).clamp(0.0, 10.0);

    if (quote.pe > 0 && quote.pe < 15) {
      factors.add('PE=${quote.pe.toStringAsFixed(1)}，估值偏低，安全边际较高');
    } else if (quote.pe > 50) {
      factors.add('PE=${quote.pe.toStringAsFixed(1)}，估值偏高，注意风险');
    }
    if (quote.pb > 0 && quote.pb < 1) {
      factors.add('PB=${quote.pb.toStringAsFixed(2)}破净，可能存在安全边际');
    } else if (quote.pb > 5) {
      factors.add('PB=${quote.pb.toStringAsFixed(2)}偏高，溢价较大');
    }

    // 2. 资金评分 (0-10): 主力净流入率
    final capitalFlowScore = _scoreCapitalFlow(quote.mainNetFlowRate);

    if (quote.mainNetFlowRate > 5) {
      factors.add('主力净流入率${quote.mainNetFlowRate.toStringAsFixed(1)}%，资金积极流入');
    } else if (quote.mainNetFlowRate < -5) {
      factors.add('主力净流入率${quote.mainNetFlowRate.toStringAsFixed(1)}%，资金持续流出');
    }

    // 3. 流动性评分 (0-10): 换手率
    final liquidityScore = _scoreLiquidity(quote.turnover);

    if (quote.turnover >= 1 && quote.turnover <= 5) {
      factors.add('换手率${quote.turnover.toStringAsFixed(1)}%，流动性适中');
    } else if (quote.turnover > 10) {
      factors.add('换手率${quote.turnover.toStringAsFixed(1)}%，交投过热');
    } else if (quote.turnover > 0 && quote.turnover < 1) {
      factors.add('换手率${quote.turnover.toStringAsFixed(1)}%，流动性不足');
    }

    // 总分: 估值40% + 资金35% + 流动性25%
    final totalScore = (valuationScore * 0.40 +
        capitalFlowScore * 0.35 +
        liquidityScore * 0.25).clamp(0.0, 10.0);

    return FundamentalScore(
      valuationScore: valuationScore,
      capitalFlowScore: capitalFlowScore,
      liquidityScore: liquidityScore,
      totalScore: totalScore,
      factors: factors,
    );
  }

  /// PE评分
  static double _scorePE(double pe) {
    if (pe <= 0) return 3.0;       // 亏损股，中性偏低
    if (pe < 8) return 9.0;        // 极低估值
    if (pe < 15) return 7.5;       // 低估值
    if (pe < 30) return 5.5;       // 合理估值
    if (pe < 50) return 3.5;       // 偏高
    if (pe < 80) return 2.0;       // 高估值
    return 1.0;                     // 极高估值
  }

  /// PB评分
  static double _scorePB(double pb) {
    if (pb <= 0) return 2.0;       // 负净资产
    if (pb < 0.8) return 9.0;      // 破净，极低估值
    if (pb < 1.5) return 7.0;      // 低估值
    if (pb < 3) return 5.0;        // 合理估值
    if (pb < 5) return 3.0;        // 偏高
    if (pb < 10) return 2.0;       // 高估值
    return 1.0;                     // 极高估值
  }

  /// 主力资金净流入率评分
  static double _scoreCapitalFlow(double rate) {
    if (rate > 10) return 9.0;     // 强力流入
    if (rate > 5) return 7.5;      // 明显流入
    if (rate > 2) return 6.0;      // 温和流入
    if (rate > 0) return 5.0;      // 微弱流入
    if (rate > -2) return 4.0;     // 微弱流出
    if (rate > -5) return 3.0;     // 温和流出
    if (rate > -10) return 2.0;    // 明显流出
    return 1.0;                     // 强力流出
  }

  /// 流动性评分（换手率）
  static double _scoreLiquidity(double turnover) {
    if (turnover <= 0) return 3.0; // 无数据
    if (turnover < 0.5) return 3.0; // 极度不活跃
    if (turnover < 1) return 5.0;   // 不活跃
    if (turnover < 3) return 8.0;   // 适中偏好
    if (turnover < 5) return 7.0;   // 适中
    if (turnover < 10) return 5.5;  // 活跃
    if (turnover < 15) return 4.0;  // 过度活跃
    return 3.0;                      // 极度活跃（投机）
  }
}
