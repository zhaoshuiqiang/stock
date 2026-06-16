import '../models/stock_models.dart';

class RiskAnalysisResult {
  final List<String> riskFactors;
  final String riskLevel;

  RiskAnalysisResult({required this.riskFactors, required this.riskLevel});
}

class RiskAnalyzer {
  static RiskAnalysisResult analyze(
      List<HistoryKline> data, HistoryKline last, QuoteData? quote) {
    final riskFactors = _collectRiskFactors(data, last, quote);
    final riskLevel = _determineLevel(riskFactors);
    return RiskAnalysisResult(riskFactors: riskFactors, riskLevel: riskLevel);
  }

  static List<String> _collectRiskFactors(
      List<HistoryKline> data, HistoryKline last, QuoteData? quote) {
    final riskFactors = <String>[];

    // 技术风险
    if (last.rsi6 > 70) riskFactors.add('RSI超买(${last.rsi6.toStringAsFixed(1)})，回调风险');
    if (last.rsi6 < 30 && last.rsi6 > 0) riskFactors.add('RSI超卖(${last.rsi6.toStringAsFixed(1)})，可能继续探底');
    if (last.close > last.bollUpper && last.bollUpper > 0) riskFactors.add('价格突破布林上轨，短期过热');
    if (last.close < last.bollLower && last.bollLower > 0) riskFactors.add('价格跌破布林下轨，波动加剧');
    if (last.close < last.ma20 && last.ma20 > 0) riskFactors.add('价格低于20日均线，趋势偏弱');

    // 量价风险
    if (last.close < last.open && last.volume > last.volMa5 * 1.5 && last.volMa5 > 0) {
      riskFactors.add('放量下跌，抛压较大');
    }
    if (last.close >= last.open && last.volume < last.volMa5 * 0.7 && last.volMa5 > 0) {
      riskFactors.add('上涨缩量，量价背离');
    }

    // 趋势风险
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma5 < last.ma10 && data.length >= 2) {
      final prev = data[data.length - 2];
      if (prev.ma5 >= prev.ma10) {
        riskFactors.add('MA5下穿MA10死叉，短期趋势转弱');
      }
    }

    // 振幅风险
    if (last.amplitude > 5) {
      riskFactors.add('当日振幅较大(${last.amplitude.toStringAsFixed(1)}%)，短期波动剧烈');
    }

    // 短期涨跌幅风险
    if (data.length >= 6) {
      final close5ago = data[data.length - 6].close;
      if (close5ago > 0) {
        final change5d = (last.close / close5ago - 1) * 100;
        if (change5d.abs() > 15) {
          riskFactors.add('近5日涨跌幅${change5d.toStringAsFixed(1)}%，短期波动剧烈');
        }
      }
    }
    if (data.length >= 21) {
      final close20ago = data[data.length - 21].close;
      if (close20ago > 0) {
        final change20d = (last.close / close20ago - 1) * 100;
        if (change20d > 30) {
          riskFactors.add('近20日涨幅${change20d.toStringAsFixed(1)}%，回调风险增加');
        } else if (change20d < -30) {
          riskFactors.add('近20日跌幅${change20d.toStringAsFixed(1)}%，跌幅较大');
        }
      }
    }

    // KDJ风险
    if (last.j > 100) riskFactors.add('KDJ超买风险(J=${last.j.toStringAsFixed(1)})');
    if (last.j < 0) riskFactors.add('KDJ超卖风险(J=${last.j.toStringAsFixed(1)})');

    // 基本面风险因子
    if (quote != null) {
      if (quote.pe > 60) riskFactors.add('市盈率偏高(${quote.pe.toStringAsFixed(1)})，估值风险');
      if (quote.turnover > 15) {
        riskFactors.add('换手率${quote.turnover.toStringAsFixed(1)}%，投机氛围浓厚');
      } else if (quote.turnover < 1 && quote.turnover > 0) {
        riskFactors.add('换手率仅${quote.turnover.toStringAsFixed(1)}%，流动性不足');
      }
      if (quote.changePct > 5) {
        riskFactors.add('当日涨幅${quote.changePct.toStringAsFixed(2)}%，追高需谨慎');
      } else if (quote.changePct < -5) {
        riskFactors.add('当日跌幅${quote.changePct.toStringAsFixed(2)}%，跌幅较大');
      }
    }

    // ATR波动率风险
    if (last.atr14 > 0 && last.close > 0) {
      final atrPct = last.atr14 / last.close * 100;
      if (atrPct > 5) {
        riskFactors.add('ATR波动率${atrPct.toStringAsFixed(1)}%，短期波动剧烈');
      }
    }

    // BIAS极端乖离风险
    if (last.bias6 > 5) {
      riskFactors.add('BIAS6乖离率${last.bias6.toStringAsFixed(1)}%，偏离均线过大，回归风险');
    } else if (last.bias6 < -5) {
      riskFactors.add('BIAS6乖离率${last.bias6.toStringAsFixed(1)}%，严重偏离均线，关注反弹');
    }

    // OBV量价背离风险
    if (data.length >= 5 && last.obv != 0) {
      final obv5 = data[data.length - 5].obv;
      if (obv5 != 0 && last.close > data[data.length - 5].close && last.obv < obv5) {
        riskFactors.add('OBV量价背离：价格上涨但量能趋势下降，上涨持续性存疑');
      }
    }

    // ST风险检测
    if (quote != null && _isST(quote.name)) {
      riskFactors.add('ST股票，存在退市风险，涨跌幅限制5%，投机性极强');
    }

    return riskFactors;
  }

  static bool _isST(String name) => name.contains('ST') || name.contains('*ST');

  static String _determineLevel(List<String> riskFactors) {
    if (riskFactors.length >= 3 ||
        riskFactors.any((f) => f.contains('超买') || f.contains('过热'))) {
      return '高';
    } else if (riskFactors.isNotEmpty) {
      return '中等';
    } else {
      return '低';
    }
  }
}
