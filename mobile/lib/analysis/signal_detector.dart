import '../models/stock_models.dart';

/// 分层信号检测器
/// 负责检测短期、中期、长期的信号
class SignalDetector {
  /// 检测所有分层信号
  static List<SignalItem> detectLayeredSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 20) return [];

    final last = data[data.length - 1];
    final prev = data[data.length - 2];

    // 收集所有基础信号
    final baseSignals = <SignalItem>[];
    baseSignals.addAll(_detectShortTermSignals(data, last, prev));
    baseSignals.addAll(_detectMediumTermSignals(data, last, prev));
    baseSignals.addAll(_detectLongTermSignals(data, last, prev));

    // 共振信号增强（替换为基础信号列表，避免重复）
    final signals = _detectConfluenceSignals(data, baseSignals);

    signals.sort((a, b) => b.strength.compareTo(a.strength));
    return signals;
  }

  /// 短期信号检测（2-5天）
  static List<SignalItem> _detectShortTermSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    // 1. KDJ金叉/死叉（短线快速反应）
    if (last.k > last.d && prev.k <= prev.d) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'KDJ金叉',
        description: 'K线上穿D线，形成金叉，短线买入信号',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateKDJConfidence(last, prev),
        signalCount: _countKDJConfidence(data),
      ));
    } else if (last.k < last.d && prev.k >= prev.d && prev.k > 70) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'KDJ',
        signal: 'KDJ死叉',
        description: 'K线下穿D线且K>70，短线见顶信号',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateKDJConfidence(last, prev),
        signalCount: _countKDJConfidence(data),
      ));
    }

    // 2. RSI超卖回升/超买回落
    if (prev.rsi6 <= 30 && last.rsi6 > 30) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'RSI',
        signal: 'RSI超卖回升',
        description: 'RSI从超卖区（<30）回升突破30，短线反弹信号',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    } else if (prev.rsi6 >= 70 && last.rsi6 < 70) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'RSI',
        signal: 'RSI超买回落',
        description: 'RSI从超买区（>70）回落跌破70，短线回调信号',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    }

    // 3. MA5金叉/死叉（快速趋势反转）
    if (last.ma5 > last.ma10 && prev.ma5 <= prev.ma10) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MA',
        signal: 'MA5上穿MA10',
        description: '短期均线向上突破中期均线，快速买入信号',
        strength: 80,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateMAConfidence(last, prev, data),
        signalCount: 2,
      ));
    } else if (last.ma5 < last.ma10 && prev.ma5 >= prev.ma10) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MA',
        signal: 'MA5下穿MA10',
        description: '短期均线向下跌破中期均线，快速卖出信号',
        strength: 80,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateMAConfidence(last, prev, data),
        signalCount: 2,
      ));
    }

    // 4. MACD金叉/死叉（趋势反转）
    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDif) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACD金叉',
        description: 'DIF上穿DEA形成金叉，中线买入信号',
        strength: 85,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateMACDConfidence(last, prev, data),
        signalCount: 2,
      ));
    } else if (last.macdDif < last.macdDea && prev.macdDif >= prev.macdDif) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACD死叉',
        description: 'DIF下穿DEA形成死叉，中线卖出信号',
        strength: 85,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateMACDConfidence(last, prev, data),
        signalCount: 2,
      ));
    }

    // 5. 成交量异动（放量/缩量）
    if (last.volMa5 > 0) {
      final volRatio = last.volume / last.volMa5;
      if (volRatio > 2 && last.close > prev.close) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: '量价',
          signal: '放量上涨',
          description: '成交量放大至均量2倍以上，短线买入信号',
          strength: 75,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      } else if (volRatio < 0.5 && last.close > prev.close) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: '量价',
          signal: '缩量上涨',
          description: '量能萎缩，市场观望情绪浓厚',
          strength: 45,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.5,
          signalCount: 1,
        ));
      }
    }

    // WR超买超卖检测
    if (last.wr14 != null && prev.wr14 != null) {
      if (last.wr14! > 80 && prev.wr14! <= 80) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'WR',
          signal: 'WR超卖',
          description: '威廉指标进入超卖区(>80)，短期超跌，关注反弹',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.7,
          signalCount: 1,
        ));
      } else if (last.wr14! < 20 && prev.wr14! >= 20) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'WR',
          signal: 'WR超买',
          description: '威廉指标进入超买区(<20)，短期超涨，注意回调',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.7,
          signalCount: 1,
        ));
      }
    }

    return signals;
  }

  /// 中期信号检测（5-20天）
  static List<SignalItem> _detectMediumTermSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    // 1. MACD顶底背离
    signals.addAll(_detectMACDDivergence(data, last, prev));

    // 2. MA10/MA20金叉/死叉（中期趋势）
    if (last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma10 > last.ma20 && prev.ma10 <= prev.ma20) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: 'MA10上穿MA20',
          description: '中期均线向上突破，中期趋势转强',
          strength: 80,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      } else if (last.ma10 < last.ma20 && prev.ma10 >= prev.ma20) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MA',
          signal: 'MA10下穿MA20',
          description: '中期均线向下跌破，中期趋势转弱',
          strength: 80,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      }
    }

    // 3. 布林带突破/支撑
    if (last.bollUpper > 0) {
      if (last.close > last.bollUpper && prev.close <= prev.bollUpper) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'BOLL',
          signal: '突破上轨',
          description: '股价突破布林带上轨，超买状态',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.65,
          signalCount: 1,
        ));
      } else if (last.close < last.bollLower && prev.close >= prev.bollLower) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'BOLL',
          signal: '跌破下轨',
          description: '股价跌破布林带下轨，超卖状态',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.65,
          signalCount: 1,
        ));
      }
    }

    // 4. OBV趋势确认
    if (data.length >= 5 && last.obv != 0) {
      final obv5 = data[data.length - 5].obv;
      if (last.obv > obv5 && last.close > data[data.length - 5].close) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'OBV',
          signal: 'OBV放量上涨',
          description: '能量潮指标确认上涨趋势',
          strength: 65,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 2,
        ));
      }
    }

    // CCI突破检测
    if (last.cci14 != null && prev.cci14 != null) {
      if (prev.cci14! < -100 && last.cci14! >= -100) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'CCI',
          signal: 'CCI超卖回升',
          description: 'CCI从超卖区(<-100)回升，短期反弹信号',
          strength: 65,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 1,
        ));
      } else if (prev.cci14! > 100 && last.cci14! <= 100) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'CCI',
          signal: 'CCI超买回落',
          description: 'CCI从超买区(>100)回落，短期回调信号',
          strength: 65,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 1,
        ));
      }
    }

    return signals;
  }

  /// 长期信号检测（20-60天）
  static List<SignalItem> _detectLongTermSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    // 1. 均线多头/空头排列（长期趋势）
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0 && last.ma60 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma20 > last.ma60) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: '均线多头排列',
          description: 'MA5>MA10>MA20>MA60，长期上升趋势',
          strength: 90,
          timestamp: last.date,
          duration: SignalDuration.longTerm,
          confidence: 0.85,
          signalCount: 3,
        ));
      } else if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma20 < last.ma60) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MA',
          signal: '均线空头排列',
          description: 'MA5<MA10<MA20<MA60，长期下降趋势',
          strength: 90,
          timestamp: last.date,
          duration: SignalDuration.longTerm,
          confidence: 0.85,
          signalCount: 3,
        ));
      }
    }

    // 2. MACD零轴上方金叉（强势多头）
    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDif && last.macdDif > 0) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACD零轴上方金叉',
        description: 'MACD在零轴上方形成金叉，多头趋势强劲',
        strength: 90,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.85,
        signalCount: 2,
      ));
    }

    // 3. 趋势强度确认（ADX）
    if (last.adx14 > 25) {
      signals.add(SignalItem(
        type: 'neutral',
        indicator: 'ADX',
        signal: '趋势强度强劲',
        description: 'ADX>25，趋势明确，可顺势而为',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.8,
        signalCount: 1,
      ));
    } else if (last.adx14 > 0 && last.adx14 < 20) {
      signals.add(SignalItem(
        type: 'neutral',
        indicator: 'ADX',
        signal: '盘整趋势',
        description: 'ADX<20，趋势不明确，建议观望',
        strength: 40,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.6,
        signalCount: 1,
      ));
    }

    return signals;
  }

  /// 共振信号增强
  static List<SignalItem> _detectConfluenceSignals(
      List<HistoryKline> data, List<SignalItem> signals) {
    // 统计各指标的共振信号数量
    final signalCounts = <String, int>{};
    for (final signal in signals) {
      if (signal.indicator.isNotEmpty) {
        signalCounts[signal.indicator] = (signalCounts[signal.indicator] ?? 0) + 1;
      }
    }

    // 对共振信号增强置信度
    final enhancedSignals = <SignalItem>[];
    for (final signal in signals) {
      if (signal.indicator.isNotEmpty) {
        final count = signalCounts[signal.indicator] ?? 1;
        if (count > 1) {
          // 共振信号，增加置信度
          enhancedSignals.add(signal.copyWith(
            signalCount: count,
            confidence: (signal.confidence ?? 0.5) + 0.1 * (count - 1).clamp(0, 2),
          ));
        } else {
          enhancedSignals.add(signal.copyWith(signalCount: 1));
        }
      } else {
        enhancedSignals.add(signal.copyWith(signalCount: 1));
      }
    }

    return enhancedSignals;
  }

  // 辅助方法：计算KDJ置信度
  static double _calculateKDJConfidence(HistoryKline last, HistoryKline prev) {
    double base = 0.7;
    if (last.j > 80) base += 0.05;  // J>80，可靠性更高
    if (last.j < 0) base += 0.05;  // J<0，超卖确认
    return base.clamp(0.6, 0.9);
  }

  /// MACD顶底背离检测（中期信号）
  static List<SignalItem> _detectMACDDivergence(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (data.length < 30) return signals;

    // 寻找局部高点和低点
    final searchRange = data.sublist(data.length - 30);
    final highPeaks = _findLocalPeaks(searchRange, findHighs: true);
    final lowPeaks = _findLocalPeaks(searchRange, findHighs: false);

    // 顶背离：股价创新高但DIF不创新高
    if (highPeaks.length >= 2) {
      final p1 = highPeaks[highPeaks.length - 2];
      final p2 = highPeaks[highPeaks.length - 1];
      if (searchRange[p2].high > searchRange[p1].high &&
          searchRange[p2].macdDif < searchRange[p1].macdDif) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MACD',
          signal: 'MACD顶背离',
          description: '股价创新高但DIF未创新高，上涨动能衰竭',
          strength: 85,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.8,
          signalCount: 2,
        ));
      }
    }

    // 底背离：股价创新低但DIF不创新低
    if (lowPeaks.length >= 2) {
      final p1 = lowPeaks[lowPeaks.length - 2];
      final p2 = lowPeaks[lowPeaks.length - 1];
      if (searchRange[p2].low < searchRange[p1].low &&
          searchRange[p2].macdDif > searchRange[p1].macdDif) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MACD',
          signal: 'MACD底背离',
          description: '股价创新低但DIF未创新低，下跌动能减弱',
          strength: 85,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.8,
          signalCount: 2,
        ));
      }
    }

    return signals;
  }

  /// 寻找局部峰值
  static List<int> _findLocalPeaks(List<HistoryKline> data,
      {required bool findHighs, int minSeparation = 5}) {
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

  // 辅助方法：统计KDJ信号数量
  static int _countKDJConfidence(List<HistoryKline> data) {
    int count = 0;
    for (int i = data.length - 5; i < data.length; i++) {
      if (i >= 0 && data[i].k > 0 && data[i].d > 0) {
        if (data[i].k > data[i].d && data[i-1].k <= data[i-1].d) count++;
        else if (data[i].k < data[i].d && data[i-1].k >= data[i-1].d) count++;
      }
    }
    return count;
  }

  // 辅助方法：计算MACD置信度
  static double _calculateMACDConfidence(HistoryKline last, HistoryKline prev, List<HistoryKline> data) {
    double base = 0.75;
    if (last.macdDif > 0 && last.macdDea > 0) base += 0.05;  // 零轴上方，可靠性更高
    if (last.macdHist.abs() > 1) base += 0.05;  // 柱子足够长
    return base.clamp(0.6, 0.9);
  }

  // 辅助方法：计算MA置信度
  static double _calculateMAConfidence(HistoryKline last, HistoryKline prev, List<HistoryKline> data) {
    double base = 0.75;
    if (last.close > last.ma10 && last.volume > last.volMa5 * 1.2) base += 0.05;  // 量价配合
    return base.clamp(0.7, 0.9);
  }
}
