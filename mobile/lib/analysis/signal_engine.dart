import '../models/stock_models.dart';
import 'indicators.dart';

List<SignalItem> detectSignals(List<HistoryKline> data) {
  if (data.isEmpty || data.length < 2) return [];

  final signals = <SignalItem>[];
  final last = data[data.length - 1];
  final prev = data[data.length - 2];
  final prev2 = data.length > 2 ? data[data.length - 3] : null;

  if (last.ma5 > 0) {
    if (last.ma5 > last.ma10 && prev.ma5 <= prev.ma10) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MA',
        signal: 'MA5上穿MA10',
        description: '均线金叉，短期均线向上突破长期均线，形成买入信号',
        strength: 80,
        timestamp: last.date,
      ));
    } else if (last.ma5 < last.ma10 && prev.ma5 >= prev.ma10) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MA',
        signal: 'MA5下穿MA10',
        description: '均线死叉，短期均线向下跌破长期均线，形成卖出信号',
        strength: 80,
        timestamp: last.date,
      ));
    }

    if (last.close > last.ma5 && prev.close <= prev.ma5) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MA',
        signal: '股价站上MA5',
        description: '股价向上突破5日均线，短期走势转强',
        strength: 60,
        timestamp: last.date,
      ));
    } else if (last.close < last.ma5 && prev.close >= prev.ma5) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MA',
        signal: '股价跌破MA5',
        description: '股价向下跌破5日均线，短期走势转弱',
        strength: 60,
        timestamp: last.date,
      ));
    }
  }

  if (last.macdDif != 0) {
    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDea) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACD金叉',
        description: 'DIF线上穿DEA线，MACD柱由绿转红，买入信号',
        strength: 85,
        timestamp: last.date,
      ));
    } else if (last.macdDif < last.macdDea && prev.macdDif >= prev.macdDea) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACD死叉',
        description: 'DIF线下穿DEA线，MACD柱由红转绿，卖出信号',
        strength: 85,
        timestamp: last.date,
      ));
    }

    if (prev2 != null) {
      if (last.macdHist > prev.macdHist && prev.macdHist <= prev2.macdHist && last.macdHist < 0) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MACD',
          signal: '绿柱缩短',
          description: 'MACD绿柱开始缩短，下跌动能减弱，可能即将反弹',
          strength: 65,
          timestamp: last.date,
        ));
      } else if (last.macdHist < prev.macdHist && prev.macdHist >= prev2.macdHist && last.macdHist > 0) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MACD',
          signal: '红柱缩短',
          description: 'MACD红柱开始缩短，上涨动能减弱，可能即将回调',
          strength: 65,
          timestamp: last.date,
        ));
      }
    }
  }

  if (last.rsi6 > 0) {
    if (last.rsi6 < 20 && prev.rsi6 >= 20) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'RSI',
        signal: 'RSI超卖',
        description: 'RSI6进入超卖区域（<20），可能即将反弹',
        strength: 70,
        timestamp: last.date,
      ));
    } else if (last.rsi6 > 80 && prev.rsi6 <= 80) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'RSI',
        signal: 'RSI超买',
        description: 'RSI6进入超买区域（>80），可能即将回调',
        strength: 70,
        timestamp: last.date,
      ));
    }

    if (last.rsi6 > 50 && prev.rsi6 <= 50) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'RSI',
        signal: 'RSI站上50',
        description: 'RSI6突破50中线，多头力量增强',
        strength: 50,
        timestamp: last.date,
      ));
    } else if (last.rsi6 < 50 && prev.rsi6 >= 50) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'RSI',
        signal: 'RSI跌破50',
        description: 'RSI6跌破50中线，空头力量增强',
        strength: 50,
        timestamp: last.date,
      ));
    }
  }

  if (last.k > 0) {
    if (last.k > last.d && prev.k <= prev.d) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'KDJ金叉',
        description: 'K线上穿D线，形成金叉，买入信号',
        strength: 80,
        timestamp: last.date,
      ));
    } else if (last.k < last.d && prev.k >= prev.d) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'KDJ',
        signal: 'KDJ死叉',
        description: 'K线下穿D线，形成死叉，卖出信号',
        strength: 80,
        timestamp: last.date,
      ));
    }

    if (last.j < 0 && prev.j >= 0) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'J线超卖',
        description: 'J线进入超卖区域（<0），可能即将反弹',
        strength: 75,
        timestamp: last.date,
      ));
    } else if (last.j > 100 && prev.j <= 100) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'KDJ',
        signal: 'J线超买',
        description: 'J线进入超买区域（>100），可能即将回调',
        strength: 75,
        timestamp: last.date,
      ));
    }
  }

  if (last.bollUpper > 0) {
    if (last.close > last.bollUpper && prev.close <= prev.bollUpper) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'BOLL',
        signal: '突破上轨',
        description: '股价突破布林带上轨，处于超买状态，可能即将回落',
        strength: 70,
        timestamp: last.date,
      ));
    } else if (last.close < last.bollLower && prev.close >= prev.bollLower) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'BOLL',
        signal: '跌破下轨',
        description: '股价跌破布林带下轨，处于超卖状态，可能即将反弹',
        strength: 70,
        timestamp: last.date,
      ));
    }

    if (last.close > last.bollMid && prev.close <= prev.bollMid) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'BOLL',
        signal: '站上中轨',
        description: '股价站上布林带中轨，多头力量占优',
        strength: 55,
        timestamp: last.date,
      ));
    } else if (last.close < last.bollMid && prev.close >= prev.bollMid) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'BOLL',
        signal: '跌破中轨',
        description: '股价跌破布林带中轨，空头力量占优',
        strength: 55,
        timestamp: last.date,
      ));
    }
  }

  signals.sort((a, b) => b.strength.compareTo(a.strength));
  return signals;
}

AnalysisResult generateAnalysis(List<HistoryKline> data, QuoteData? quote) {
  if (data.isEmpty) {
    return AnalysisResult(
      signals: [],
      indicators: {},
      recommendation: '持有',
      score: 50,
      riskLevel: '中等',
      riskFactors: [],
      suggestions: [],
    );
  }

  final last = data[data.length - 1];
  final signals = detectSignals(data);
  final indicators = getIndicatorSummary(data);

  int buyScore = 0;
  int sellScore = 0;
  final buySignals = signals.where((s) => s.type == 'buy').toList();
  final sellSignals = signals.where((s) => s.type == 'sell').toList();

  for (final signal in buySignals) {
    buyScore += signal.strength;
  }
  for (final signal in sellSignals) {
    sellScore += signal.strength;
  }

  final netScore = buyScore - sellScore;
  final baseScore = 50;
  int finalScore = baseScore + (netScore ~/ 5);
  finalScore = finalScore.clamp(0, 100);

  String recommendation;
  if (finalScore >= 75) {
    recommendation = '买入';
  } else if (finalScore >= 60) {
    recommendation = '增持';
  } else if (finalScore >= 40) {
    recommendation = '持有';
  } else if (finalScore >= 25) {
    recommendation = '减持';
  } else {
    recommendation = '卖出';
  }

  String riskLevel;
  if (finalScore >= 70 || finalScore <= 30) {
    riskLevel = '高';
  } else if (finalScore >= 60 || finalScore <= 40) {
    riskLevel = '中等';
  } else {
    riskLevel = '低';
  }

  final riskFactors = <String>[];
  if (last.amplitude > 5) {
    riskFactors.add('当日振幅较大');
  }
  if (last.rsi6 > 80) {
    riskFactors.add('RSI超买风险');
  }
  if (last.rsi6 < 20) {
    riskFactors.add('RSI超卖风险');
  }
  if (last.j > 100) {
    riskFactors.add('KDJ超买风险');
  }
  if (last.j < 0) {
    riskFactors.add('KDJ超卖风险');
  }
  if (last.close > last.bollUpper) {
    riskFactors.add('突破布林带上轨');
  }
  if (last.close < last.bollLower) {
    riskFactors.add('跌破布林带下轨');
  }

  final suggestions = <String>[];
  if (recommendation == '买入') {
    suggestions.add('技术面显示买入信号较强，建议关注');
    suggestions.add('可设置止损位在近期低点或关键均线下方');
    suggestions.add('分批建仓，控制仓位');
  } else if (recommendation == '增持') {
    suggestions.add('技术面偏多，可适当加仓');
    suggestions.add('关注关键阻力位的突破情况');
  } else if (recommendation == '持有') {
    suggestions.add('技术面中性，建议继续观察');
    suggestions.add('保持现有仓位，等待方向明确');
  } else if (recommendation == '减持') {
    suggestions.add('技术面偏弱，建议适当减仓');
    suggestions.add('关注支撑位的防守情况');
  } else {
    suggestions.add('技术面显示卖出信号较强');
    suggestions.add('建议及时止盈或止损');
    suggestions.add('等待调整结束后再考虑入场');
  }

  return AnalysisResult(
    signals: signals,
    indicators: indicators,
    recommendation: recommendation,
    score: finalScore,
    riskLevel: riskLevel,
    riskFactors: riskFactors,
    suggestions: suggestions,
  );
}
