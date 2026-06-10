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

    // MA10/MA20 金叉死叉（中期趋势信号）
    if (last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma10 > last.ma20 && prev.ma10 <= prev.ma20) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: 'MA10上穿MA20',
          description: 'MA10上穿MA20，中期趋势转强',
          strength: 80,
          timestamp: last.date,
        ));
      } else if (last.ma10 < last.ma20 && prev.ma10 >= prev.ma20) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MA',
          signal: 'MA10下穿MA20',
          description: 'MA10下穿MA20，中期趋势转弱',
          strength: 80,
          timestamp: last.date,
        ));
      }
    }

    // 均线多头/空头排列
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0 && last.ma60 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma20 > last.ma60) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: '均线多头排列',
          description: 'MA5>MA10>MA20>MA60，均线多头排列，趋势向好',
          strength: 85,
          timestamp: last.date,
        ));
      } else if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma20 < last.ma60) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MA',
          signal: '均线空头排列',
          description: 'MA5<MA10<MA20<MA60，均线空头排列，趋势向淡',
          strength: 85,
          timestamp: last.date,
        ));
      }
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

    // MACD 绿转红/红转绿（需近5根K线）
    if (data.length >= 5) {
      final recent5 = data.sublist(data.length - 5);
      final prev4AllNeg = recent5.sublist(0, 4).every((k) => k.macdHist < 0);
      final prev4AllPos = recent5.sublist(0, 4).every((k) => k.macdHist > 0);
      if (prev4AllNeg && last.macdHist > 0) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MACD',
          signal: 'MACD绿转红',
          description: 'MACD柱由绿转红，趋势可能反转向多',
          strength: 80,
          timestamp: last.date,
        ));
      } else if (prev4AllPos && last.macdHist < 0) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MACD',
          signal: 'MACD红转绿',
          description: 'MACD柱由红转绿，趋势可能反转向空',
          strength: 80,
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

    // RSI 30/70 阈值信号
    if (last.rsi6 < 30 && prev.rsi6 >= 30) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'RSI',
        signal: 'RSI进入超卖区',
        description: 'RSI6跌破30，进入超卖区域，关注反弹机会',
        strength: 65,
        timestamp: last.date,
      ));
    } else if (last.rsi6 > 70 && prev.rsi6 <= 70) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'RSI',
        signal: 'RSI进入超买区',
        description: 'RSI6突破70，进入超买区域，注意回调风险',
        strength: 65,
        timestamp: last.date,
      ));
    }

    // RSI 回升突码30 / 回落跌破70
    if (prev.rsi6 < 30 && last.rsi6 >= 30) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'RSI',
        signal: 'RSI回升突破30',
        description: 'RSI6从超卖区回升突破30，可能出现反弹',
        strength: 60,
        timestamp: last.date,
      ));
    } else if (prev.rsi6 > 70 && last.rsi6 <= 70) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'RSI',
        signal: 'RSI回落跌破70',
        description: 'RSI6从超买区回落跌破70，上涨动能减弱',
        strength: 60,
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

    // 布林带收窄（即将变盘信号）
    if (last.bollMid > 0) {
      final bollWidth = (last.bollUpper - last.bollLower) / last.bollMid * 100;
      if (bollWidth < 5) {
        signals.add(SignalItem(
          type: 'neutral',
          indicator: 'BOLL',
          signal: '布林带收窄',
          description: '布林带宽度仅${bollWidth.toStringAsFixed(1)}%，波动率极低，即将变盘但方向待确认',
          strength: 55,
          timestamp: last.date,
        ));
      }
    }
  }

  // 量价信号
  if (last.volMa5 > 0) {
    final volRatio = last.volume / last.volMa5;
    if (volRatio > 2) {
      if (last.close > prev.close) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: '量价',
          signal: '放量上涨',
          description: '成交量是5日均量的${volRatio.toStringAsFixed(1)}倍，且股价上涨，量价配合良好',
          strength: 70,
          timestamp: last.date,
        ));
      } else {
        signals.add(SignalItem(
          type: 'sell',
          indicator: '量价',
          signal: '放量下跌',
          description: '成交量是5日均量的${volRatio.toStringAsFixed(1)}倍，但股价下跌，放量下跌需警惕',
          strength: 70,
          timestamp: last.date,
        ));
      }
    } else if (volRatio < 0.5) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: '量价',
        signal: '缩量观望',
        description: '成交量显著萎缩，市场观望情绪浓厚',
        strength: 40,
        timestamp: last.date,
      ));
    }
  }

  signals.addAll(_detectMacdDivergence(data));
  signals.addAll(_detectVolumePriceDivergence(data));
  signals.addAll(_detectBollSqueezeBreakout(data));

  signals.sort((a, b) => b.strength.compareTo(a.strength));
  return signals;
}

List<int> _findLocalPeaks(List<HistoryKline> data, {required bool findHighs, int minSeparation = 5}) {
  final peaks = <int>[];
  for (int i = 2; i < data.length - 2; i++) {
    final val = findHighs ? data[i].high : data[i].low;
    final prev1 = findHighs ? data[i - 1].high : data[i - 1].low;
    final prev2 = findHighs ? data[i - 2].high : data[i - 2].low;
    final next1 = findHighs ? data[i + 1].high : data[i + 1].low;
    final next2 = findHighs ? data[i + 2].high : data[i + 2].low;

    if (findHighs) {
      if (val > prev1 && val > prev2 && val > next1 && val > next2) {
        if (peaks.isEmpty || i - peaks.last >= minSeparation) {
          peaks.add(i);
        }
      }
    } else {
      if (val < prev1 && val < prev2 && val < next1 && val < next2) {
        if (peaks.isEmpty || i - peaks.last >= minSeparation) {
          peaks.add(i);
        }
      }
    }
  }
  return peaks;
}

List<SignalItem> _detectMacdDivergence(List<HistoryKline> data) {
  final signals = <SignalItem>[];
  if (data.length < 30) return signals;

  final last = data[data.length - 1];
  final searchRange = data.sublist(data.length - 30);

  final highPeaks = _findLocalPeaks(searchRange, findHighs: true, minSeparation: 5);
  if (highPeaks.length >= 2) {
    final p1 = highPeaks[highPeaks.length - 2];
    final p2 = highPeaks[highPeaks.length - 1];
    if (searchRange[p2].high > searchRange[p1].high &&
        searchRange[p2].macdDif < searchRange[p1].macdDif) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACD顶背离',
        description: '股价创新高(${searchRange[p2].high.toStringAsFixed(2)})但DIF未创新高(${searchRange[p2].macdDif.toStringAsFixed(2)}<${searchRange[p1].macdDif.toStringAsFixed(2)})，上涨动能衰竭',
        strength: 85,
        timestamp: last.date,
      ));
    }
  }

  final lowPeaks = _findLocalPeaks(searchRange, findHighs: false, minSeparation: 5);
  if (lowPeaks.length >= 2) {
    final p1 = lowPeaks[lowPeaks.length - 2];
    final p2 = lowPeaks[lowPeaks.length - 1];
    if (searchRange[p2].low < searchRange[p1].low &&
        searchRange[p2].macdDif > searchRange[p1].macdDif) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACD底背离',
        description: '股价创新低(${searchRange[p2].low.toStringAsFixed(2)})但DIF未创新低(${searchRange[p2].macdDif.toStringAsFixed(2)}>${searchRange[p1].macdDif.toStringAsFixed(2)})，下跌动能减弱',
        strength: 85,
        timestamp: last.date,
      ));
    }
  }

  return signals;
}

List<SignalItem> _detectVolumePriceDivergence(List<HistoryKline> data) {
  final signals = <SignalItem>[];
  if (data.length < 15) return signals;

  final last = data[data.length - 1];
  final avg10Vol = data.sublist(data.length - 10).map((d) => d.volume).reduce((a, b) => a + b) / 10;
  final avg3Vol = data.sublist(data.length - 3).map((d) => d.volume).reduce((a, b) => a + b) / 3;

  if (avg3Vol > avg10Vol * 1.5) {
    final priceChange3d = (last.close / data[data.length - 4].close - 1) * 100;
    if (priceChange3d.abs() < 2) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: '量价',
        signal: '放量滞涨',
        description: '近3日均量是10日均量的${(avg3Vol / avg10Vol).toStringAsFixed(1)}倍，但涨幅仅${priceChange3d.toStringAsFixed(1)}%，主力可能在出货',
        strength: 75,
        timestamp: last.date,
      ));
    }
  }

  if (data.length >= 6) {
    final priceChange5d = (last.close / data[data.length - 6].close - 1) * 100;
    if (priceChange5d > 3) {
      var volDeclining = true;
      for (int i = data.length - 1; i > data.length - 5; i--) {
        if (data[i].volume >= data[i - 1].volume) {
          volDeclining = false;
          break;
        }
      }
      if (volDeclining) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: '量价',
          signal: '缩量上涨',
          description: '近5日涨幅${priceChange5d.toStringAsFixed(1)}%但量能持续萎缩，上涨动力不足',
          strength: 70,
          timestamp: last.date,
        ));
      }
    }
  }

  if (data.length >= 13) {
    final priceChange10d = (last.close / data[data.length - 11].close - 1) * 100;
    if (priceChange10d < -10) {
      final recent3Change = (last.close / data[data.length - 4].close - 1) * 100;
      if (recent3Change.abs() < 1 && avg3Vol < avg10Vol * 0.5) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: '量价',
          signal: '缩量止跌',
          description: '前期跌幅${priceChange10d.toStringAsFixed(1)}%后量能萎缩至均量的${(avg3Vol / avg10Vol * 100).toStringAsFixed(0)}%，价格企稳，抛压减弱',
          strength: 65,
          timestamp: last.date,
        ));
      }
    }
  }

  return signals;
}

List<SignalItem> _detectBollSqueezeBreakout(List<HistoryKline> data) {
  final signals = <SignalItem>[];
  if (data.length < 25) return signals;

  final last = data[data.length - 1];
  if (last.bollMid == 0) return signals;

  final bandwidths = <double>[];
  for (int i = data.length - 20; i < data.length; i++) {
    final d = data[i];
    if (d.bollMid > 0) {
      bandwidths.add((d.bollUpper - d.bollLower) / d.bollMid * 100);
    }
  }
  if (bandwidths.length < 10) return signals;

  final currentBw = bandwidths.last;
  final minBw = bandwidths.reduce((a, b) => a < b ? a : b);

  var contracting = true;
  for (int i = bandwidths.length - 1; i > bandwidths.length - 6 && i > 0; i--) {
    if (bandwidths[i] >= bandwidths[i - 1]) {
      contracting = false;
      break;
    }
  }

  if (currentBw <= minBw * 1.1 && contracting) {
    signals.add(SignalItem(
      type: 'neutral',
      indicator: 'BOLL',
      signal: '布林带收口蓄势',
      description: '布林带宽度收窄至${currentBw.toStringAsFixed(1)}%，连续5日递减，即将选择方向突破但方向待确认',
      strength: 60,
      timestamp: last.date,
    ));

    final avgVol = data.sublist(data.length - 10).map((d) => d.volume).reduce((a, b) => a + b) / 10;
    if (last.close > last.bollUpper && last.volume > avgVol * 1.5) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'BOLL',
        signal: '布林带放量突破上轨',
        description: '收口后放量突破布林带上轨(${last.bollUpper.toStringAsFixed(2)})，向上突破确认',
        strength: 80,
        timestamp: last.date,
      ));
    } else if (last.close < last.bollLower) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'BOLL',
        signal: '布林带跌破下轨',
        description: '收口后跌破布林带下轨(${last.bollLower.toStringAsFixed(2)})，向下突破',
        strength: 80,
        timestamp: last.date,
      ));
    }
  }

  return signals;
}

Map<String, dynamic> calcTradeLevels(List<HistoryKline> data) {
  if (data.isEmpty) return {};

  final last = data[data.length - 1];
  final price = last.close;

  final supportLevels = calcSupportResistance(data);
  final supports = supportLevels['support'] as List<double>? ?? [];
  final resistances = supportLevels['resistance'] as List<double>? ?? [];

  final nearestSupport = supports.isNotEmpty ? supports.first : null;
  final nearestResistance = resistances.isNotEmpty ? resistances.first : null;

  final entryLow = nearestSupport ?? price * 0.98;
  final entryHigh = price * 1.01;
  final target = nearestResistance ?? price * 1.1;
  final stopLoss = last.ma60 > 0
      ? ([entryLow * 0.98, last.ma60 * 0.97].reduce((a, b) => a > b ? a : b))
      : entryLow * 0.98;

  final entryMid = (entryLow + entryHigh) / 2;
  final reward = target - entryMid;
  final risk = entryMid - stopLoss;
  final riskRewardRatio = risk > 0 ? reward / risk : 0.0;

  return {
    'entry_low': entryLow,
    'entry_high': entryHigh,
    'target': target,
    'stop_loss': stopLoss,
    'risk_reward_ratio': riskRewardRatio,
    'has_support': nearestSupport != null,
    'has_resistance': nearestResistance != null,
  };
}

AnalysisResult generateAnalysis(List<HistoryKline> data, QuoteData? quote) {
  if (data.isEmpty) {
    return AnalysisResult(
      signals: [],
      indicators: {},
      recommendation: '观望',
      score: 50,
      riskLevel: '中等',
      riskFactors: ['数据不足'],
      suggestions: ['等待更多数据'],
      reasons: ['数据不足，无法生成有效建议'],
      opportunities: [],
    );
  }

  final last = data[data.length - 1];
  final signals = detectSignals(data);
  final indicators = getIndicatorSummary(data);

  final buySignals = signals.where((s) => s.type == 'buy').toList();
  final sellSignals = signals.where((s) => s.type == 'sell').toList();

  // ========== 多维加权评分（三维度） ==========

  // 1. 信号评分 (0-30分) - 按信号强度加权
  int buyCount = buySignals.length;
  int sellCount = sellSignals.length;
  double buyStrength = buySignals.fold(0.0, (sum, s) => sum + s.strength);
  double sellStrength = sellSignals.fold(0.0, (sum, s) => sum + s.strength);
  // Normalize: max possible strength per signal is 100, typical 3-4 signals
  double maxTotal = 300.0;
  double signalScore = 15 + (buyStrength - sellStrength) / maxTotal * 30;
  signalScore = signalScore.clamp(0.0, 30.0);

  // ADX trend/ranging weight adjustment
  final adx = last.adx14;
  if (adx > 25) {
    // Trending market: boost trend signals, dampen oscillator signals
    final trendSignals = signals.where((s) =>
      s.indicator == 'MA' || s.indicator == 'MACD' || s.signal.contains('排列') || s.signal.contains('金叉') || s.signal.contains('死叉')
    ).fold(0.0, (sum, s) => sum + s.strength);
    final oscSignals = signals.where((s) =>
      s.indicator == 'RSI' || s.indicator == 'KDJ' || s.signal.contains('超买') || s.signal.contains('超卖')
    ).fold(0.0, (sum, s) => sum + s.strength);
    if (trendSignals > oscSignals) {
      signalScore = (signalScore * 1.2).clamp(0.0, 30.0);
    }
  } else if (adx > 0 && adx < 20) {
    // Ranging market: boost oscillator signals, dampen trend signals
    final oscSignals = signals.where((s) =>
      s.indicator == 'RSI' || s.indicator == 'KDJ' || s.signal.contains('超买') || s.signal.contains('超卖')
    ).fold(0.0, (sum, s) => sum + s.strength);
    final trendSignals = signals.where((s) =>
      s.indicator == 'MA' || s.indicator == 'MACD' || s.signal.contains('排列') || s.signal.contains('金叉') || s.signal.contains('死叉')
    ).fold(0.0, (sum, s) => sum + s.strength);
    if (oscSignals > trendSignals) {
      signalScore = (signalScore * 1.2).clamp(0.0, 30.0);
    }
  }

  // 2. 趋势强度评分 (0-20分) - 基于均线排列 + ADX趋势强度
  double trendScore = 0;
  if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
    if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
      trendScore = 18;
    } else if (last.ma5 > last.ma10) {
      trendScore = 11;
    } else if (last.ma5 > last.ma20) {
      trendScore = 7;
    } else {
      trendScore = 3;
    }
  }
  if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
    if (last.ma5 < last.ma10 && last.ma10 < last.ma20) {
      trendScore = 0;
    }
  }
  // ADX trend strength bonus
  if (last.adx14 > 25) {
    trendScore += 5;
  } else if (last.adx14 > 0 && last.adx14 < 20) {
    trendScore -= 3;
  }
  trendScore = trendScore.clamp(0.0, 20.0);

  // 3. 动量评分 (0-20分) - 基于RSI + BIAS乖离率
  double momentumScore = 10;
  if (last.rsi6 > 0) {
    if (last.rsi6 < 30) {
      momentumScore = 16;
    } else if (last.rsi6 < 40) {
      momentumScore = 13;
    } else if (last.rsi6 < 60) {
      momentumScore = 10;
    } else if (last.rsi6 < 70) {
      momentumScore = 7;
    } else {
      momentumScore = 3;
    }
  }
  // BIAS extreme deviation penalty
  if (last.bias6.abs() > 5) {
    momentumScore -= 4;
  } else if (last.bias6.abs() > 3) {
    momentumScore -= 2;
  }
  momentumScore = momentumScore.clamp(0.0, 20.0);

  // 4. 量价确认评分 (0-15分) - 基于量比 + OBV趋势
  double volumeScore = 8;
  if (last.volMa5 > 0) {
    final volRatio = last.volume / last.volMa5;
    if (last.close >= last.open) {
      if (volRatio > 1.5) {
        volumeScore = 14;
      } else if (volRatio > 1.0) {
        volumeScore = 11;
      } else {
        volumeScore = 6;
      }
    } else {
      if (volRatio > 1.5) {
        volumeScore = 2;
      } else if (volRatio > 1.0) {
        volumeScore = 5;
      } else {
        volumeScore = 8;
      }
    }
  }
  // OBV trend confirmation
  if (data.length >= 5 && last.obv != 0) {
    final obv5 = data[data.length - 5].obv;
    if (obv5 != 0) {
      if (last.obv > obv5 && last.close > data[data.length - 5].close) {
        volumeScore += 3; // OBV confirms uptrend
      } else if (last.obv < obv5 && last.close < data[data.length - 5].close) {
        volumeScore -= 2; // OBV confirms downtrend
      }
    }
  }
  volumeScore = volumeScore.clamp(0.0, 15.0);

  // 5. 波动率评分 (0-15分) - 基于ATR
  double volatilityScore = 8;
  if (last.atr14 > 0 && last.close > 0) {
    final atrPct = last.atr14 / last.close * 100;
    if (atrPct < 2) {
      volatilityScore = 13; // Low volatility, stable
    } else if (atrPct < 3) {
      volatilityScore = 11;
    } else if (atrPct < 4) {
      volatilityScore = 8;
    } else if (atrPct < 5) {
      volatilityScore = 5;
    } else {
      volatilityScore = 2; // High volatility, risky
    }
  }

  // K线信号基础分 (0-100)
  final klineBaseScore = (signalScore + trendScore + momentumScore + volumeScore + volatilityScore).round().clamp(0, 100);

  // ========== 5. 实时行情评分 (0-100) ==========
  double realtimeScore = 50; // 中性基准
  if (quote != null && quote.price > 0) {
    // 涨跌幅权重
    final changePct = quote.changePct;
    if (changePct > 0 && changePct <= 3) {
      realtimeScore += 10;
    } else if (changePct > 3 && changePct <= 5) {
      realtimeScore += 5;
    } else if (changePct > 5) {
      realtimeScore -= 5;
    } else if (changePct < 0 && changePct >= -3) {
      realtimeScore -= 5;
    } else if (changePct < -3 && changePct >= -5) {
      realtimeScore += 5;
    } else if (changePct < -5) {
      realtimeScore += 8;
    }

    // 资金流向权重
    if (quote.mainNetFlow != 0) {
      if (quote.mainNetFlow > 0) {
        realtimeScore += (quote.mainNetFlowRate > 5 ? 8 : 5); // 主力净流入加分
      } else {
        realtimeScore -= (quote.mainNetFlowRate < -5 ? 8 : 5); // 主力净流出减分
      }
    }

    // 换手率权重
    if (quote.turnover > 0) {
      if (quote.turnover >= 1 && quote.turnover <= 5) {
        realtimeScore += 5; // 活跃但不过热
      } else if (quote.turnover > 10) {
        realtimeScore -= 5; // 过热风险
      } else if (quote.turnover < 0.5) {
        realtimeScore -= 3; // 流动性不足
      }
    }
  }
  realtimeScore = realtimeScore.clamp(0.0, 100.0);

  // ========== 共振评分 ==========
  int bullCount = 0;
  final maBull = last.ma5 > last.ma10 && last.ma10 > last.ma20;
  final maBear = last.ma5 < last.ma10 && last.ma10 < last.ma20;
  if (maBull) bullCount++;
  final macdBull = last.macdDif > last.macdDea && last.macdHist > 0;
  final macdBear = last.macdDif < last.macdDea && last.macdHist < 0;
  if (macdBull) bullCount++;
  final rsiBull = last.rsi6 > 60;
  final rsiBear = last.rsi6 < 40 && last.rsi6 > 0;
  if (rsiBull) bullCount++;
  final kdjBull = last.k > last.d && last.k < 80;
  final kdjBear = last.k < last.d && last.k > 20;
  if (kdjBull) bullCount++;
  final bollBull = last.bollMid > 0 && last.close > last.bollMid;
  final bollBear = last.bollMid > 0 && last.close < last.bollMid;
  if (bollBull) bullCount++;
  final avgVol5 = data.length >= 5 ? data.sublist(data.length - 5).map((d) => d.volume).reduce((a, b) => a + b) / 5 : 0.0;
  final volBull = last.volume > avgVol5 && last.close > last.open;
  final volBear = last.volume > avgVol5 && last.close < last.open;
  if (volBull) bullCount++;
  final hasBottomDivergence = signals.any((s) => s.signal.contains('底背离'));
  final hasTopDivergence = signals.any((s) => s.signal.contains('顶背离'));
  if (hasBottomDivergence) bullCount += 2;

  final confluenceBonus = bullCount / 8 * 100;

  // ========== 三维度加权总分 ==========
  // K线信号(55%) + 实时行情(25%) + 共振评分(20%)
  final totalScore = (klineBaseScore * 0.55 + realtimeScore * 0.25 + confluenceBonus * 0.20).round().clamp(0, 100);

  // ========== 5级推荐 ==========
  String recommendation;
  if (totalScore >= 80) {
    recommendation = '强烈买入';
  } else if (totalScore >= 65) {
    recommendation = '买入';
  } else if (totalScore >= 40) {
    recommendation = '观望';
  } else if (totalScore >= 25) {
    recommendation = '卖出';
  } else {
    recommendation = '强烈卖出';
  }

  // ========== 推荐理由 ==========
  final reasons = <String>[];
  if (buyCount > sellCount + 1) reasons.add('多个买入信号共振');
  if (sellCount > buyCount + 1) reasons.add('多个卖出信号共振');
  if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma5 > 0) reasons.add('均线多头排列');
  if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma5 > 0) reasons.add('均线空头排列');
  if (last.rsi6 > 70) reasons.add('RSI超买区域');
  if (last.rsi6 < 30 && last.rsi6 > 0) reasons.add('RSI超卖区域');
  if (last.volume > last.volMa5 * 1.5 && last.volMa5 > 0) reasons.add('成交量显著放大');
  if (last.close >= last.open && last.volume < last.volMa5 * 0.7 && last.volMa5 > 0) reasons.add('上涨缩量，动能不足');

  // 实时行情因素
  if (quote != null && quote.price > 0) {
    if (quote.changePct > 3) reasons.add('当日涨幅${quote.changePct.toStringAsFixed(1)}%，追高需谨慎');
    if (quote.changePct < -3) reasons.add('当日跌幅${quote.changePct.toStringAsFixed(1)}%，超跌关注反弹');
    if (quote.mainNetFlow > 0 && quote.mainNetFlowRate > 3) reasons.add('主力资金净流入${quote.mainNetFlowRate.toStringAsFixed(1)}%');
    if (quote.mainNetFlow < 0 && quote.mainNetFlowRate < -3) reasons.add('主力资金净流出${quote.mainNetFlowRate.abs().toStringAsFixed(1)}%');
    if (quote.turnover > 10) reasons.add('换手率${quote.turnover.toStringAsFixed(1)}%，交投过热');
  }

  // ========== 风险因子 ==========
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

  // ========== 风险等级 ==========
  String riskLevel;
  if (riskFactors.length >= 3 || riskFactors.any((f) => f.contains('超买') || f.contains('过热'))) {
    riskLevel = '高';
  } else if (riskFactors.isNotEmpty) {
    riskLevel = '中等';
  } else {
    riskLevel = '低';
  }

  // ========== 机会识别 ==========
  final opportunities = <Map<String, String>>[];
  for (final signal in buySignals.take(3)) {
    String risk = '中等';
    if (signal.signal.contains('RSI') || signal.signal.contains('超卖')) risk = '中高';
    if (signal.signal.contains('金叉')) risk = '中等';
    if (signal.signal.contains('放量')) risk = '中低';
    if (signal.signal.contains('底背离')) risk = '中等';
    if (signal.signal.contains('跌破下轨')) risk = '中高';
    opportunities.add({
      'name': signal.signal,
      'description': signal.description,
      'risk': risk,
    });
  }

  // ========== 操作建议 ==========
  final suggestions = <String>[];
  double recentLow = last.low;
  if (data.length >= 10) {
    final recent10 = data.sublist(data.length - 10);
    recentLow = recent10.map((k) => k.low).reduce((a, b) => a < b ? a : b);
  }
  final stopLossRef = last.ma20 > 0 ? last.ma20 : recentLow;

  if (recommendation == '强烈买入') {
    suggestions.add('多项技术指标强烈共振偏多，但需结合基本面和大盘环境综合判断');
    suggestions.add('可考虑分批建仓，首批仓位控制在30%以内，确认趋势后逐步加仓');
    suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
  } else if (recommendation == '买入') {
    if (buySignals.length >= 3 && totalScore >= 70) {
      suggestions.add('多项技术指标共振偏多，但需结合基本面和大盘环境综合判断');
      suggestions.add('可考虑分批建仓，首批仓位控制在20%以内，确认趋势后逐步加仓');
    } else {
      suggestions.add('技术面偏多，可轻仓关注，但不宜追高');
      suggestions.add('建议先试探性建仓10%，确认支撑有效后再考虑加仓');
    }
    suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
    if (quote != null && quote.pe > 0 && quote.pe < 15) {
      suggestions.add('动态市盈率${quote.pe.toStringAsFixed(1)}倍，估值较低，具有一定安全边际');
    }
  } else if (recommendation == '观望') {
    suggestions.add('技术面中性，多空信号均衡，建议继续观察');
    suggestions.add('保持现有仓位，等待方向明确后再做决策');
    if (quote != null && quote.pe > 50) {
      suggestions.add('当前估值偏高（PE=${quote.pe.toStringAsFixed(1)}），注意仓位控制');
    }
  } else if (recommendation == '卖出') {
    suggestions.add('技术面偏弱，建议适当减仓，降低风险敞口');
    suggestions.add('关注支撑位${recentLow.toStringAsFixed(2)}的防守情况，跌破则加速减仓');
    if (quote != null && quote.pe > 0 && quote.pb > 0 && quote.pb < 1) {
      suggestions.add('市净率${quote.pb.toStringAsFixed(2)}倍破净，可能存在安全边际，不宜恐慌性抛售');
    }
  } else {
    suggestions.add('技术面偏空信号较强，建议及时止损或止盈，规避风险');
    if (sellSignals.length >= 3) {
      suggestions.add('多项指标共振偏空，建议大幅减仓观望');
    } else {
      suggestions.add('建议分批减仓，避免一次性清仓');
    }
    suggestions.add('等待调整结束（如RSI回到50附近、MACD金叉）后再考虑入场');
  }

  // 基本面补充建议
  if (quote != null) {
    if (quote.pe > 0 && quote.pe < 15 && quote.pb > 0 && quote.pb < 1.5) {
      suggestions.add('基本面估值较低（PE=${quote.pe.toStringAsFixed(1)}, PB=${quote.pb.toStringAsFixed(2)}），具有中长期投资价值');
    }
  }

  // 免责声明
  suggestions.add('以上分析基于历史数据和技术指标，仅供参考，不构成投资建议，投资有风险，决策需谨慎');

  // ========== 多指标共振详情（7维度） ==========
  final confluenceDetails = <Map<String, dynamic>>[];
  confluenceDetails.add({'name': 'MA', 'bull': maBull, 'bear': maBear});
  confluenceDetails.add({'name': 'MACD', 'bull': macdBull, 'bear': macdBear});
  confluenceDetails.add({'name': 'RSI', 'bull': rsiBull, 'bear': rsiBear});
  confluenceDetails.add({'name': 'KDJ', 'bull': kdjBull, 'bear': kdjBear});
  confluenceDetails.add({'name': 'BOLL', 'bull': bollBull, 'bear': bollBear});
  confluenceDetails.add({'name': '量价', 'bull': volBull, 'bear': volBear});
  confluenceDetails.add({'name': '背离', 'bull': hasBottomDivergence, 'bear': hasTopDivergence, 'weighted': true});

  final tradeLevels = calcTradeLevels(data);

  return AnalysisResult(
    signals: signals,
    indicators: indicators,
    recommendation: recommendation,
    score: totalScore,
    riskLevel: riskLevel,
    riskFactors: riskFactors,
    suggestions: suggestions,
    tradeLevels: tradeLevels.isNotEmpty ? tradeLevels : null,
    confluenceScore: bullCount,
    confluenceDetails: confluenceDetails,
    reasons: reasons,
    opportunities: opportunities,
  );
}
