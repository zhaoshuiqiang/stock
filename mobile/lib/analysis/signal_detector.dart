import '../models/stock_models.dart';
import 'signal_evidence_classifier.dart';

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

    // 共振只记录同方向独立组件覆盖，不再按同一指标重复次数抬高置信度。
    final signals = SignalConfluenceAnnotator.annotate(baseSignals);

    signals.sort((a, b) => b.strength.compareTo(a.strength));
    return signals;
  }

  /// 短期信号检测（2-5天）
  static List<SignalItem> _detectShortTermSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    signals.addAll(_detectKDJSignals(last, prev));
    signals.addAll(_detectRSISignals(last, prev));
    signals.addAll(_detectMASignals(data, last));
    signals.addAll(_detectMACDSignals(last, prev));
    signals.addAll(_detectVolumeSignals(last, prev));
    signals.addAll(_detectWRSignals(last));
    signals.addAll(_detectGapSignals(data, last, prev));
    signals.addAll(_detectCandlestickPatterns(data, last, prev));
    return signals;
  }

  /// KDJ金叉/死叉检测
  static List<SignalItem> _detectKDJSignals(HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.k > last.d && prev.k <= prev.d) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'KDJ金叉',
        description: 'K线上穿D线，形成金叉，短线买入信号',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateKDJConfidence(last, prev, signalType: 'buy'),
        signalCount: 1,
      ));
    } else if (last.k < last.d && prev.k >= prev.d && prev.k > 50) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'KDJ',
        signal: 'KDJ死叉',
        description: 'K线下穿D线，短线转弱信号',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateKDJConfidence(last, prev, signalType: 'sell'),
        signalCount: 1,
      ));
    }
    return signals;
  }

  /// RSI超卖回升/超买回落检测
  static List<SignalItem> _detectRSISignals(HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
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
    return signals;
  }

  /// MA5金叉/死叉检测
  static List<SignalItem> _detectMASignals(List<HistoryKline> data, HistoryKline last) {
    final signals = <SignalItem>[];
    if (data.length < 2) return signals;
    final prev = data[data.length - 2];
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
    return signals;
  }

  /// MACD金叉/死叉检测
  static List<SignalItem> _detectMACDSignals(HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    double confidence = 0.75;
    if (last.macdDif > 0 && last.macdDea > 0) confidence += 0.05;
    // v3.19: macdHist 为价格单位，原 >1 阈值对高价股过严、低价股过松。
    // 改为相对收盘价(>0.5%)归一化，使不同价位股票口径一致。
    if (last.close > 0 && last.macdHist.abs() / last.close > 0.005) {
      confidence += 0.05;
    }
    confidence = confidence.clamp(0.6, 0.9);

    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDea) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACD金叉',
        description: 'DIF上穿DEA形成金叉，中线买入信号',
        strength: 85,
        timestamp: last.date,
        duration: SignalDuration.mediumTerm,
        confidence: confidence,
        signalCount: 2,
      ));
    } else if (last.macdDif < last.macdDea && prev.macdDif >= prev.macdDea) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACD死叉',
        description: 'DIF下穿DEA形成死叉，中线卖出信号',
        strength: 85,
        timestamp: last.date,
        duration: SignalDuration.mediumTerm,
        confidence: confidence,
        signalCount: 2,
      ));
    }
    return signals;
  }

  /// 成交量异动检测
  static List<SignalItem> _detectVolumeSignals(HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
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
          type: 'sell',
          indicator: '量价',
          signal: '缩量上涨',
          description: '成交量萎缩至均量50%以下，上涨缺乏量能支撑，追高风险较大',
          strength: 45,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.5,
          signalCount: 1,
        ));
      }
    }
    return signals;
  }

  /// WR超买超卖检测
  static List<SignalItem> _detectWRSignals(HistoryKline last) {
    final signals = <SignalItem>[];
    if (last.wr14 != null) {
      if (last.wr14! > 80) {
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
      } else if (last.wr14! < 20) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'WR',
          signal: 'WR超买',
          description: '威廉指标进入超买区(<20)，短期超涨，注意回调',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          // v3.22: 降低WR超买置信度(0.70→0.50)，A股趋势市中超买可持续很久，
          // 仅凭超买判断回调胜率较低。
          confidence: 0.50,
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
      // v3.19: 趋势判定——ADX 未就绪(==0，通常因数据不足 29 根)时改用均线排列兜底，
      // 避免短历史下 isTrending 恒为 false 导致的系统性"突破上轨判卖"偏空偏差。
      bool? bollTrend; // true=向上趋势, false=向下趋势, null=未知
      if (last.adx14 > 25) {
        bollTrend = last.plusDi14 > last.minusDi14;
      } else if (last.adx14 == 0) {
        if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
          bollTrend = true;
        } else if (last.ma5 < last.ma10 && last.ma10 < last.ma20) {
          bollTrend = false;
        } else {
          bollTrend = null;
        }
      } else {
        bollTrend = null; // ADX 在 (0,25] 不可靠，视为未知
      }

      if (last.close > last.bollUpper && prev.close <= prev.bollUpper) {
        // 趋势行情中突破上轨为强势信号，震荡/未知趋势中不作为方向性信号发出
        if (bollTrend != null) {
          final isTrending = bollTrend;
          signals.add(SignalItem(
            type: isTrending ? 'buy' : 'sell',
            indicator: 'BOLL',
            signal: isTrending ? '趋势突破上轨' : '突破上轨',
            description: isTrending
                ? '股价突破布林带上轨且趋势明确(ADX=${last.adx14.toStringAsFixed(1)})，强势突破'
                : '股价突破布林带上轨，超买状态',
            strength: isTrending ? 75 : 70,
            timestamp: last.date,
            duration: SignalDuration.mediumTerm,
            confidence: isTrending ? 0.7 : 0.65,
            signalCount: 1,
          ));
        }
      } else if (last.bollLower > 0 && last.close < last.bollLower && prev.close >= prev.bollLower) {
        // P1-5修复：镜像上轨逻辑，趋势行情中破下轨为看跌延续，震荡行情中为超卖
        // v3.19: 与上方统一使用 bollTrend（ADX 未就绪时均线排列兜底），未知趋势不发出方向信号
        if (bollTrend != null) {
          final isTrendingDown = !bollTrend;
          signals.add(SignalItem(
            type: isTrendingDown ? 'sell' : 'buy',
            indicator: 'BOLL',
            signal: isTrendingDown ? '趋势跌破下轨' : '跌破下轨',
            description: isTrendingDown
                ? '股价跌破布林带下轨且下跌趋势明确(ADX=${last.adx14.toStringAsFixed(1)})，看跌延续'
                : '股价跌破布林带下轨，超卖状态',
            strength: isTrendingDown ? 75 : 70,
            timestamp: last.date,
            duration: SignalDuration.mediumTerm,
            confidence: isTrendingDown ? 0.7 : 0.65,
            signalCount: 1,
          ));
        }
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

    // 成交量趋势分析
    signals.addAll(_detectVolumeTrends(data, last));

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
    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDea && last.macdDif > 0) {
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

    // P1-6: MACD零轴下方死叉（强势空头）— 与零轴上方金叉对称
    if (last.macdDif < last.macdDea && prev.macdDif >= prev.macdDea && last.macdDif < 0) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACD零轴下方死叉',
        description: 'MACD在零轴下方形成死叉，空头趋势强劲',
        strength: 90,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.85,
        signalCount: 2,
      ));
    }

    // 3. 趋势强度确认（ADX）— P0-1修复：需要方向确认
    // v2.38.0: 将趋势强度强劲信号type从neutral改为buy/sell，确保信号分类准确
    if (last.adx14 > 25 && last.plusDi14 > last.minusDi14) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'ADX',
        signal: '趋势强度强劲',
        description: 'ADX>25，多头趋势明确，可顺势而为',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.8,
        signalCount: 1,
      ));
    } else if (last.adx14 > 25 && last.minusDi14 > last.plusDi14) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'ADX',
        signal: '趋势强度强劲',
        description: 'ADX>25，空头趋势明确，建议回避',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        // v3.22: 降低空头趋势信号置信度(0.80→0.55)，ADX是滞后长周期指标，
        // 对次日短线预测力弱，且A股下跌趋势经常快速反转。
        confidence: 0.55,
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

  // 辅助方法：计算KDJ置信度
  /// v3.22: KDJ死叉置信度降低(base 0.70→0.55 for sell)，强势行情中KDJ死叉频繁失效。
  /// 金叉保持原有base=0.70，不影响看多信号准确率。
  static double _calculateKDJConfidence(HistoryKline last, HistoryKline prev, {String signalType = 'buy'}) {
    double base = signalType == 'buy' ? 0.70 : 0.55;
    if (signalType == 'buy') {
      if (last.j < 20) base += 0.05; // 超卖区金叉更可靠
      if (last.j > 80) base -= 0.05; // 超买区金叉不可靠
    } else {
      if (last.j > 80) base += 0.05; // 超买区死叉稍可靠
      if (last.j < 20) base -= 0.05; // 超卖区死叉不可靠
    }
    return base.clamp(0.45, 0.9);
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

  // 辅助方法：计算MA置信度
  static double _calculateMAConfidence(HistoryKline last, HistoryKline prev, List<HistoryKline> data) {
    double base = 0.75;
    if (last.close > last.ma10 && last.volume > last.volMa5 * 1.2) base += 0.05;  // 量价配合
    return base.clamp(0.7, 0.9);
  }

  /// 跳空缺口检测
  static List<SignalItem> _detectGapSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (prev.high <= 0 || prev.low <= 0 || last.open <= 0) return signals;

    final gapUpSize = (last.low - prev.high) / prev.high * 100;
    final gapDownSize = (prev.low - last.high) / prev.low * 100;

    // 向上跳空（中缺口以上>2%才生成信号）
    if (gapUpSize > 2) {
      final level = gapUpSize > 5 ? '大' : '中';
      signals.add(SignalItem(
        type: 'buy',
        indicator: '缺口',
        signal: '向上跳空突破',
        description: '${level}缺口${gapUpSize.toStringAsFixed(1)}%，跳空高开突破，短线强势信号',
        strength: gapUpSize > 5 ? 85 : 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.75,
        signalCount: 1,
      ));
    }

    // 向下跳空（中缺口以上>2%才生成信号）
    if (gapDownSize > 2) {
      final level = gapDownSize > 5 ? '大' : '中';
      signals.add(SignalItem(
        type: 'sell',
        indicator: '缺口',
        signal: '向下跳空破位',
        description: '${level}缺口${gapDownSize.toStringAsFixed(1)}%，跳空低开破位，短线弱势信号',
        strength: gapDownSize > 5 ? 85 : 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.75,
        signalCount: 1,
      ));
    }

    return signals;
  }

  /// K线形态识别
  static List<SignalItem> _detectCandlestickPatterns(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.open <= 0 || prev.open <= 0) return signals;

    final body = (last.close - last.open).abs();
    final bodyPct = body / last.open * 100;
    final upperShadow = last.high - (last.close > last.open ? last.close : last.open);
    final lowerShadow = (last.close > last.open ? last.open : last.close) - last.low;
    final isBullish = last.close > last.open;
    final isBearish = last.close < last.open;
    final prevBullish = prev.close > prev.open;
    final prevBearish = prev.close < prev.open;

    // 判断趋势（近5日涨跌）
    bool inDowntrend = false;
    bool inUptrend = false;
    if (data.length >= 6) {
      final price5ago = data[data.length - 6].close;
      if (price5ago > 0) {
        final change5d = (last.close / price5ago - 1) * 100;
        inDowntrend = change5d < -3 || (last.ma10 > 0 && last.close < last.ma10);
        inUptrend = change5d > 3 || (last.ma10 > 0 && last.close > last.ma10);
      }
    }

    // 锤子线（底部反转）- 小实体、长下影线、下跌趋势中
    if (bodyPct < 1.0 && lowerShadow > body * 2 && upperShadow < body * 0.5 && inDowntrend) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'K线形态',
        signal: '底部锤子线',
        description: '小实体+长下影线，下跌趋势中出现，底部反转信号',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    }

    // 吊颈线（顶部反转）- 小实体、长下影线、上涨趋势中
    if (bodyPct < 1.0 && lowerShadow > body * 2 && upperShadow < body * 0.5 && inUptrend) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'K线形态',
        signal: '顶部吊颈线',
        description: '小实体+长下影线，上涨趋势中出现，顶部反转信号',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    }

    // 乌云盖顶（顶部反转）- 前阳后阴、高开低走
    if (prevBullish && isBearish) {
      if (last.open > prev.high && last.close < (prev.open + prev.close) / 2) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'K线形态',
          signal: '乌云盖顶',
          description: '前日阳线后今日高开低走收阴，收盘低于前日实体中点，顶部反转信号',
          strength: 75,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      }
    }

    // 刺透形态（底部反转）- 前阴后阳、低开高走
    if (prevBearish && isBullish) {
      if (last.open < prev.low && last.close > (prev.open + prev.close) / 2) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'K线形态',
          signal: '刺透形态',
          description: '前日阴线后今日低开高走收阳，收盘高于前日实体中点，底部反转信号',
          strength: 75,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      }
    }

    // ──�� 多日形态识别（3-5日） ──────────────────────────────

    // 阳包阴（看涨吞没）- 当前阳线实体完全吞没前阴线实体
    if (isBullish && prevBearish) {
      final prevBody = prev.open - prev.close;
      if (body > prevBody && last.open <= prev.close && last.close >= prev.open) {
        final strength = body > prevBody * 1.5 ? 80 : 75;
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'K线形态',
          signal: '阳包阴',
          description: '当前阳线实体完全吞没前日阴线实体，看涨反转信号',
          strength: strength,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.78,
          signalCount: 2,
        ));
      }
    }

    // 阴包阳（看跌吞没）- 当前阴线实体完全吞没前阳线实体
    if (isBearish && prevBullish) {
      final prevBody = prev.close - prev.open;
      if (body > prevBody && last.open >= prev.close && last.close <= prev.open) {
        final strength = body > prevBody * 1.5 ? 80 : 75;
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'K线形态',
          signal: '阴包阳',
          description: '当前阴线实体完全吞没前日阳线实体，看跌反转信号',
          strength: strength,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.78,
          signalCount: 2,
        ));
      }
    }

    // 十字星（多空均衡）- 实体极小，上下影线对称
    if (bodyPct < 0.3) {
      final shadowRatio = upperShadow > 0 ? lowerShadow / upperShadow : 999;
      final isDoji = shadowRatio > 0.7 && shadowRatio < 1.4;
      if (isDoji) {
        // 高位十字星 = 见顶信号
        if (inUptrend && last.close > last.ma10) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: 'K线形态',
            signal: '高位十字星',
            description: '上涨趋势中出现十字星，多空分歧加大，警惕回调',
            strength: 65,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.65,
            signalCount: 1,
          ));
        }
        // 低位十字星 = 见底信号
        if (inDowntrend && last.close < last.ma10) {
          signals.add(SignalItem(
            type: 'buy',
            indicator: 'K线形态',
            signal: '低位十字星',
            description: '下跌趋势中出现十字星，卖盘衰竭，关注反弹',
            strength: 65,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.65,
            signalCount: 1,
          ));
        }
      }
    }

    // 三阳开泰（Three White Soldiers）- 连续3日阳线上涨
    // 启明星（Morning Star）和黄昏星（Evening Star）- 3日反转形态
    if (data.length >= 3) {
      final pp = data[data.length - 3]; // 前前日

      // 三阳开泰：连续3日阳线、实体递增、收盘创近期新高
      if (isBullish && prevBullish && pp.close > pp.open) {
        final ppBody = pp.close - pp.open;
        final prevBody = prev.close - prev.open;
        if (prevBody > ppBody * 0.7 && body > prevBody * 0.5 &&
            last.close > prev.close && prev.close > pp.close) {
          // 确认趋势向上
          final inTrend = last.ma5 > 0 && last.close > last.ma5 && last.ma5 > last.ma10;
          signals.add(SignalItem(
            type: 'buy',
            indicator: 'K线形态',
            signal: '三阳开泰',
            description: '连续3日阳线递增上涨，趋势强势${inTrend ? '' : "，但均线需确认"}',
            strength: inTrend ? 85 : 75,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: inTrend ? 0.82 : 0.72,
            signalCount: 3,
          ));
        }
      }

      // 三只乌鸦：连续3日阴线下跌、收盘创近期新低
      if (isBearish && prevBearish && pp.close < pp.open) {
        final ppBody = pp.open - pp.close;
        final prevBody = prev.open - prev.close;
        if (prevBody > ppBody * 0.7 && body > prevBody * 0.5 &&
            last.close < prev.close && prev.close < pp.close) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: 'K线形态',
            signal: '三只乌鸦',
            description: '连续3日阴线递增下跌，趋势弱势',
            strength: 80,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.78,
            signalCount: 3,
          ));
        }
      }

      // 启明星（Morning Star）- 阴线 + 小实体(星线) + 阳线突破阴线实体中点
      if (pp.close < pp.open && isBullish) {
        final ppBody = pp.open - pp.close;
        final prevBodySmall = (prev.close - prev.open).abs() / prev.open * 100;
        if (prevBodySmall < 0.8 && body > ppBody * 0.6 &&
            last.close > (pp.open + pp.close) / 2) {
          signals.add(SignalItem(
            type: 'buy',
            indicator: 'K线形态',
            signal: '启明星',
            description: '3日反转形态：阴→星→阳，阳线收盘突破阴线实体中点，底部反转信号',
            strength: 80,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.78,
            signalCount: 3,
          ));
        }
      }

      // 黄昏星（Evening Star）- 阳线 + 小实体(星线) + 阴线跌入阳线实体
      if (pp.close > pp.open && isBearish) {
        final ppBody = pp.close - pp.open;
        final prevBodySmall = (prev.close - prev.open).abs() / prev.open * 100;
        if (prevBodySmall < 0.8 && body > ppBody * 0.6 &&
            last.close < (pp.open + pp.close) / 2) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: 'K线形态',
            signal: '黄昏星',
            description: '3日反转形态：阳→星→阴，阴线收盘跌破阳线实体中点，顶部反转信号',
            strength: 80,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.78,
            signalCount: 3,
          ));
        }
      }
    }

    return signals;
  }

  /// 成交量趋势分析
  static List<SignalItem> _detectVolumeTrends(List<HistoryKline> data, HistoryKline last) {
    final signals = <SignalItem>[];
    if (data.length < 20 || last.volMa5 <= 0) return signals;

    final recent10 = data.sublist(data.length - 10);
    final recent3 = data.sublist(data.length - 3);
    final recent5 = data.sublist(data.length - 5);

    final priceChange10d = (last.close / data[data.length - 11].close - 1) * 100;

    // 吸筹形态：10日下跌>5% + 前期量能递减(排除近3日) + 近3日企稳放量
    if (priceChange10d < -5) {
      // 检查第-4到-7天量能递减（排除近3天的企稳放量阶段）
      bool volDeclining = recent10.length >= 7;
      for (int i = 4; i < 8 && i < recent10.length - 1; i++) {
        if (recent10[recent10.length - i].volume >= recent10[recent10.length - i - 1].volume) {
          volDeclining = false;
          break;
        }
      }
      final avgVol3 = recent3.map((d) => d.volume).reduce((a, b) => a + b) / 3;
      final avgVol5 = recent5.map((d) => d.volume).reduce((a, b) => a + b) / 5;
      final priceStable = (last.close / data[data.length - 4].close - 1).abs() < 2;

      if (volDeclining && avgVol3 > avgVol5 * 1.2 && priceStable) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: '量价趋势',
          signal: '主力吸筹迹象',
          description: '下跌${priceChange10d.toStringAsFixed(1)}%后量能萎缩递减，近3日企稳且量能放大，主力可能在吸筹',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 2,
        ));
      }
    }

    // 派发形态：10日上涨>5% + 量能递减 + 近3日缩量
    if (priceChange10d > 5) {
      bool volDeclining = true;
      for (int i = 1; i < 5; i++) {
        if (recent10[recent10.length - i].volume >= recent10[recent10.length - i - 1].volume) {
          volDeclining = false;
          break;
        }
      }
      final avgVol3 = recent3.map((d) => d.volume).reduce((a, b) => a + b) / 3;
      if (volDeclining && avgVol3 < last.volMa5 * 0.7) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: '量价趋势',
          signal: '主力派发迹象',
          description: '上涨${priceChange10d.toStringAsFixed(1)}%但量能持续萎缩，近3日缩量至均量70%以下，主力可能在派发',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 2,
        ));
      }
    }

    // 地量见底：成交量创近20日最低 + 价格在MA20附近或下方
    final minVol20 = data.sublist(data.length - 20).map((d) => d.volume).reduce((a, b) => a < b ? a : b);
    if (last.volume <= minVol20 && last.ma20 > 0 && last.close <= last.ma20 * 1.02) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: '量价趋势',
        signal: '地量见底',
        description: '成交量创近20日新低，价格在MA20(${last.ma20.toStringAsFixed(2)})附近，卖盘枯竭',
        strength: 65,
        timestamp: last.date,
        duration: SignalDuration.mediumTerm,
        confidence: 0.65,
        signalCount: 1,
      ));
    }

    return signals;
  }

  static List<SignalItem> detectEarlyWarningSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 10) return [];

    final last = data[data.length - 1];
    final prev = data[data.length - 2];
    final signals = <SignalItem>[];

    signals.addAll(_detectMACDCrossWarning(last, prev));
    signals.addAll(_detectKDJCrossWarning(last, prev));
    signals.addAll(_detectMACDDivergenceWarning(data, last, prev));

    return signals;
  }

  static List<SignalItem> _detectMACDCrossWarning(HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.macdDea == 0) return signals;

    final difDistance = (last.macdDea - last.macdDif).abs() / last.macdDea.abs();
    final difTrend = last.macdDif - prev.macdDif;
    final deaTrend = last.macdDea - prev.macdDea;

    if (difDistance < 0.08 && difTrend > 0 && deaTrend <= 0) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACD金叉预警',
        description: 'DIF快速接近DEA，即将形成金叉，提前关注',
        strength: 55,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.6,
        signalCount: 1,
      ));
    } else if (difDistance < 0.08 && difTrend < 0 && deaTrend >= 0) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACD死叉预警',
        description: 'DIF快速接近DEA，即将形成死叉，提前警惕',
        strength: 55,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.6,
        signalCount: 1,
      ));
    }

    return signals;
  }

  static List<SignalItem> _detectKDJCrossWarning(HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    final kDistance = (last.d - last.k).abs() / (last.d.abs() + last.k.abs()).clamp(1.0, double.infinity);
    final kTrend = last.k - prev.k;

    if (kDistance < 0.15 && kTrend > 0 && last.k < 50) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'KDJ金叉预警',
        description: 'K线快速接近D线，即将形成金叉，提前关注',
        strength: 50,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.55,
        signalCount: 1,
      ));
    } else if (kDistance < 0.15 && kTrend < 0 && last.k > 50) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'KDJ',
        signal: 'KDJ死叉预警',
        description: 'K线快速接近D线，即将形成死叉，提前警惕',
        strength: 50,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.55,
        signalCount: 1,
      ));
    }

    return signals;
  }

  static List<SignalItem> _detectMACDDivergenceWarning(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (data.length < 20) return signals;

    final searchRange = data.sublist(data.length - 20);
    final highPeaks = _findLocalPeaks(searchRange, findHighs: true);
    final lowPeaks = _findLocalPeaks(searchRange, findHighs: false);

    if (highPeaks.length >= 1) {
      final p1 = highPeaks[highPeaks.length - 1];
      if (searchRange[p1].high > searchRange.last.high * 0.98 &&
          searchRange[p1].macdDif < searchRange.last.macdDif &&
          last.macdHist > prev.macdHist) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MACD',
          signal: 'MACD顶背离预警',
          description: '价格接近前高但MACD未创新高，上涨动能减弱',
          strength: 55,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.6,
          signalCount: 1,
        ));
      }
    }

    if (lowPeaks.length >= 1) {
      final p1 = lowPeaks[lowPeaks.length - 1];
      if (searchRange[p1].low < searchRange.last.low * 1.02 &&
          searchRange[p1].macdDif > searchRange.last.macdDif &&
          last.macdHist < prev.macdHist) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MACD',
          signal: 'MACD底背离预警',
          description: '价格接近前低但MACD未创新低，下跌动能减弱',
          strength: 55,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.6,
          signalCount: 1,
        ));
      }
    }

    return signals;
  }
}
