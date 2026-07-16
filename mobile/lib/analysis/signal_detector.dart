import '../models/stock_models.dart';
import 'signal_evidence_classifier.dart';

/// åå±ä¿¡å·æ£æµå¨
/// è´è´£æ£æµç­æãä¸­æãé¿æçä¿¡å·
class SignalDetector {
  /// æ£æµææåå±ä¿¡å·
  static List<SignalItem> detectLayeredSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 20) return [];

    final last = data[data.length - 1];
    final prev = data[data.length - 2];

    // æ¶éææåºç¡ä¿¡å·
    final baseSignals = <SignalItem>[];
    baseSignals.addAll(_detectShortTermSignals(data, last, prev));
    baseSignals.addAll(_detectMediumTermSignals(data, last, prev));
    baseSignals.addAll(_detectLongTermSignals(data, last, prev));

    // å±æ¯åªè®°å½åæ¹åç¬ç«ç»ä»¶è¦çï¼ä¸åæåä¸ææ éå¤æ¬¡æ°æ¬é«ç½®ä¿¡åº¦ã
    final signals = SignalConfluenceAnnotator.annotate(baseSignals);

    signals.sort((a, b) => b.strength.compareTo(a.strength));
    return signals;
  }

  /// ç­æä¿¡å·æ£æµï¼2-5å¤©ï¼
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

  /// KDJéå/æ­»åæ£æµ
  static List<SignalItem> _detectKDJSignals(
      HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.k > last.d && prev.k <= prev.d) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'KDJéå',
        description: 'Kçº¿ä¸ç©¿Dçº¿ï¼å½¢æéåï¼ç­çº¿ä¹°å¥ä¿¡å·',
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
        signal: 'KDJæ­»å',
        description: 'Kçº¿ä¸ç©¿Dçº¿ï¼ç­çº¿è½¬å¼±ä¿¡å·',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateKDJConfidence(last, prev, signalType: 'sell'),
        signalCount: 1,
      ));
    }
    return signals;
  }

  /// RSIè¶ååå/è¶ä¹°åè½æ£æµ
  static List<SignalItem> _detectRSISignals(
      HistoryKline last, HistoryKline prev) {
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
        confidence: _calculateRSIConfidence(prev.rsi6, isBuy: true),
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
        confidence: _calculateRSIConfidence(prev.rsi6, isBuy: false),
        signalCount: 1,
      ));
    } else if (prev.rsi6 >= 70 && last.rsi6 < 70) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'RSI',
        signal: 'RSIè¶ä¹°åè½',
        description: 'RSIä»è¶ä¹°åºï¼>70ï¼åè½è·ç ´70ï¼ç­çº¿åè°ä¿¡å·',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    }
    return signals;
  }

  /// MA5éå/æ­»åæ£æµ
  static List<SignalItem> _detectMASignals(
      List<HistoryKline> data, HistoryKline last) {
    final signals = <SignalItem>[];
    if (data.length < 2) return signals;
    final prev = data[data.length - 2];
    if (last.ma5 > last.ma10 && prev.ma5 <= prev.ma10) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MA',
        signal: 'MA5ä¸ç©¿MA10',
        description: 'ç­æåçº¿åä¸çªç ´ä¸­æåçº¿ï¼å¿«éä¹°å¥ä¿¡å·',
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
        signal: 'MA5ä¸ç©¿MA10',
        description: 'ç­æåçº¿åä¸è·ç ´ä¸­æåçº¿ï¼å¿«éååºä¿¡å·',
        strength: 80,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: _calculateMAConfidence(last, prev, data),
        signalCount: 2,
      ));
    }
    return signals;
  }

  /// MACDéå/æ­»åæ£æµ
  static List<SignalItem> _detectMACDSignals(
      HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    double confidence = 0.75;
    if (last.macdDif > 0 && last.macdDea > 0) confidence += 0.05;
    // v3.19: macdHist ä¸ºä»·æ ¼åä½ï¼å >1 éå¼å¯¹é«ä»·è¡è¿ä¸¥ãä½ä»·è¡è¿æ¾ã
    // æ¹ä¸ºç¸å¯¹æ¶çä»·(>0.5%)å½ä¸åï¼ä½¿ä¸åä»·ä½è¡ç¥¨å£å¾ä¸è´ã
    if (last.close > 0 && last.macdHist.abs() / last.close > 0.005) {
      confidence += 0.05;
    }
    confidence = confidence.clamp(0.6, 0.9);

    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDea) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACDéå',
        description: 'DIFä¸ç©¿DEAå½¢æéåï¼ä¸­çº¿ä¹°å¥ä¿¡å·',
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
        signal: 'MACDæ­»å',
        description: 'DIFä¸ç©¿DEAå½¢ææ­»åï¼ä¸­çº¿ååºä¿¡å·',
        strength: 85,
        timestamp: last.date,
        duration: SignalDuration.mediumTerm,
        confidence: confidence,
        signalCount: 2,
      ));
    }
    return signals;
  }

  /// æäº¤éå¼å¨æ£æµ
  static List<SignalItem> _detectVolumeSignals(
      HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.volMa5 > 0) {
      final volRatio = last.volume / last.volMa5;
      if (volRatio > 2 && last.close > prev.close) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'éä»·',
          signal: 'æ¾éä¸æ¶¨',
          description: 'æäº¤éæ¾å¤§è³åé2åä»¥ä¸ï¼ç­çº¿ä¹°å¥ä¿¡å·',
          strength: 75,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      } else if (volRatio < 0.5 && last.close > prev.close) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'éä»·',
          signal: 'ç¼©éä¸æ¶¨',
          description: 'æäº¤éèç¼©è³åé50%ä»¥ä¸ï¼ä¸æ¶¨ç¼ºä¹éè½æ¯æï¼è¿½é«é£é©è¾å¤§',
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

  /// WRè¶ä¹°è¶åæ£æµ
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
          confidence: _calculateWRConfidence(last.wr14!, isBuy: true),
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
          confidence: _calculateWRConfidence(last.wr14!, isBuy: false),
          signalCount: 1,
        ));
      }
    }
    return signals;
  }

  /// ä¸­æä¿¡å·æ£æµï¼5-20å¤©ï¼
  static List<SignalItem> _detectMediumTermSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    // 1. MACDé¡¶åºèç¦»
    signals.addAll(_detectMACDDivergence(data, last, prev));

    // 2. MA10/MA20éå/æ­»åï¼ä¸­æè¶å¿ï¼
    if (last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma10 > last.ma20 && prev.ma10 <= prev.ma20) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: 'MA10ä¸ç©¿MA20',
          description: 'ä¸­æåçº¿åä¸çªç ´ï¼ä¸­æè¶å¿è½¬å¼º',
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
          signal: 'MA10ä¸ç©¿MA20',
          description: 'ä¸­æåçº¿åä¸è·ç ´ï¼ä¸­æè¶å¿è½¬å¼±',
          strength: 80,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      }
    }

    // 3. å¸æå¸¦çªç ´/æ¯æ
    if (last.bollUpper > 0) {
      // v3.19: è¶å¿å¤å®ââADX æªå°±ç»ª(==0ï¼éå¸¸å æ°æ®ä¸è¶³ 29 æ ¹)æ¶æ¹ç¨åçº¿æåååºï¼
      // é¿åç­åå²ä¸ isTrending æä¸º false å¯¼è´çç³»ç»æ§"çªç ´ä¸è½¨å¤å"åç©ºåå·®ã
      bool? bollTrend; // true=åä¸è¶å¿, false=åä¸è¶å¿, null=æªç¥
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
        bollTrend = null; // ADX å¨ (0,25] ä¸å¯é ï¼è§ä¸ºæªç¥
      }

      if (last.close > last.bollUpper && prev.close <= prev.bollUpper) {
        // è¶å¿è¡æä¸­çªç ´ä¸è½¨ä¸ºå¼ºå¿ä¿¡å·ï¼éè¡/æªç¥è¶å¿ä¸­ä¸ä½ä¸ºæ¹åæ§ä¿¡å·ååº
        if (bollTrend != null) {
          final isTrending = bollTrend;
          signals.add(SignalItem(
            type: isTrending ? 'buy' : 'sell',
            indicator: 'BOLL',
            signal: isTrending ? 'è¶å¿çªç ´ä¸è½¨' : 'çªç ´ä¸è½¨',
            description: isTrending
                ? 'è¡ä»·çªç ´å¸æå¸¦ä¸è½¨ä¸è¶å¿æç¡®(ADX=${last.adx14.toStringAsFixed(1)})ï¼å¼ºå¿çªç ´'
                : 'è¡ä»·çªç ´å¸æå¸¦ä¸è½¨ï¼è¶ä¹°ç¶æ',
            strength: isTrending ? 75 : 70,
            timestamp: last.date,
            duration: SignalDuration.mediumTerm,
            confidence: isTrending ? 0.7 : 0.65,
            signalCount: 1,
          ));
        }
      } else if (last.bollLower > 0 &&
          last.close < last.bollLower &&
          prev.close >= prev.bollLower) {
        // P1-5ä¿®å¤ï¼éåä¸è½¨é»è¾ï¼è¶å¿è¡æä¸­ç ´ä¸è½¨ä¸ºçè·å»¶ç»­ï¼éè¡è¡æä¸­ä¸ºè¶å
        // v3.19: ä¸ä¸æ¹ç»ä¸ä½¿ç¨ bollTrendï¼ADX æªå°±ç»ªæ¶åçº¿æåååºï¼ï¼æªç¥è¶å¿ä¸ååºæ¹åä¿¡å·
        if (bollTrend != null) {
          final isTrendingDown = !bollTrend;
          signals.add(SignalItem(
            type: isTrendingDown ? 'sell' : 'buy',
            indicator: 'BOLL',
            signal: isTrendingDown ? 'è¶å¿è·ç ´ä¸è½¨' : 'è·ç ´ä¸è½¨',
            description: isTrendingDown
                ? 'è¡ä»·è·ç ´å¸æå¸¦ä¸è½¨ä¸ä¸è·è¶å¿æç¡®(ADX=${last.adx14.toStringAsFixed(1)})ï¼çè·å»¶ç»­'
                : 'è¡ä»·è·ç ´å¸æå¸¦ä¸è½¨ï¼è¶åç¶æ',
            strength: isTrendingDown ? 75 : 70,
            timestamp: last.date,
            duration: SignalDuration.mediumTerm,
            confidence: isTrendingDown ? 0.7 : 0.65,
            signalCount: 1,
          ));
        }
      }
    }

    // 4. OBVè¶å¿ç¡®è®¤
    if (data.length >= 5 && last.obv != 0) {
      final obv5 = data[data.length - 5].obv;
      if (last.obv > obv5 && last.close > data[data.length - 5].close) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'OBV',
          signal: 'OBVæ¾éä¸æ¶¨',
          description: 'è½éæ½®ææ ç¡®è®¤ä¸æ¶¨è¶å¿',
          strength: 65,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 2,
        ));
      }
    }

    // CCIçªç ´æ£æµ
    if (last.cci14 != null && prev.cci14 != null) {
      if (prev.cci14! < -100 && last.cci14! >= -100) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'CCI',
          signal: 'CCIè¶ååå',
          description: 'CCIä»è¶ååº(<-100)ååï¼ç­æåå¼¹ä¿¡å·',
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
          signal: 'CCIè¶ä¹°åè½',
          description: 'CCIä»è¶ä¹°åº(>100)åè½ï¼ç­æåè°ä¿¡å·',
          strength: 65,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 1,
        ));
      }
    }

    // æäº¤éè¶å¿åæ
    signals.addAll(_detectVolumeTrends(data, last));

    return signals;
  }

  /// é¿æä¿¡å·æ£æµï¼20-60å¤©ï¼
  static List<SignalItem> _detectLongTermSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    // 1. åçº¿å¤å¤´/ç©ºå¤´æåï¼é¿æè¶å¿ï¼
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0 && last.ma60 > 0) {
      if (last.ma5 > last.ma10 &&
          last.ma10 > last.ma20 &&
          last.ma20 > last.ma60) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: 'åçº¿å¤å¤´æå',
          description: 'MA5>MA10>MA20>MA60ï¼é¿æä¸åè¶å¿',
          strength: 90,
          timestamp: last.date,
          duration: SignalDuration.longTerm,
          confidence: 0.85,
          signalCount: 3,
        ));
      } else if (last.ma5 < last.ma10 &&
          last.ma10 < last.ma20 &&
          last.ma20 < last.ma60) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MA',
          signal: 'åçº¿ç©ºå¤´æå',
          description: 'MA5<MA10<MA20<MA60ï¼é¿æä¸éè¶å¿',
          strength: 90,
          timestamp: last.date,
          duration: SignalDuration.longTerm,
          confidence: 0.85,
          signalCount: 3,
        ));
      }
    }

    // 2. MACDé¶è½´ä¸æ¹éåï¼å¼ºå¿å¤å¤´ï¼
    if (last.macdDif > last.macdDea &&
        prev.macdDif <= prev.macdDea &&
        last.macdDif > 0) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACDé¶è½´ä¸æ¹éå',
        description: 'MACDå¨é¶è½´ä¸æ¹å½¢æéåï¼å¤å¤´è¶å¿å¼ºå²',
        strength: 90,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.85,
        signalCount: 2,
      ));
    }

    // P1-6: MACDé¶è½´ä¸æ¹æ­»åï¼å¼ºå¿ç©ºå¤´ï¼â ä¸é¶è½´ä¸æ¹éåå¯¹ç§°
    if (last.macdDif < last.macdDea &&
        prev.macdDif >= prev.macdDea &&
        last.macdDif < 0) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'MACD',
        signal: 'MACDé¶è½´ä¸æ¹æ­»å',
        description: 'MACDå¨é¶è½´ä¸æ¹å½¢ææ­»åï¼ç©ºå¤´è¶å¿å¼ºå²',
        strength: 90,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.85,
        signalCount: 2,
      ));
    }

    // 3. è¶å¿å¼ºåº¦ç¡®è®¤ï¼ADXï¼â P0-1ä¿®å¤ï¼éè¦æ¹åç¡®è®¤
    // v2.38.0: å°è¶å¿å¼ºåº¦å¼ºå²ä¿¡å·typeä»neutralæ¹ä¸ºbuy/sellï¼ç¡®ä¿ä¿¡å·åç±»åç¡®
    if (last.adx14 > 25 && last.plusDi14 > last.minusDi14) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'ADX',
        signal: 'è¶å¿å¼ºåº¦å¼ºå²',
        description: 'ADX>25ï¼å¤å¤´è¶å¿æç¡®ï¼å¯é¡ºå¿èä¸º',
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
        signal: 'è¶å¿å¼ºåº¦å¼ºå²',
        description: 'ADX>25ï¼ç©ºå¤´è¶å¿æç¡®ï¼å»ºè®®åé¿',
        strength: 75,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        // v3.22: éä½ç©ºå¤´è¶å¿ä¿¡å·ç½®ä¿¡åº¦(0.80â0.55)ï¼ADXæ¯æ»åé¿å¨æææ ï¼
        // å¯¹æ¬¡æ¥ç­çº¿é¢æµåå¼±ï¼ä¸Aè¡ä¸è·è¶å¿ç»å¸¸å¿«éåè½¬ã
        confidence: 0.55,
        signalCount: 1,
      ));
    } else if (last.adx14 > 0 && last.adx14 < 20) {
      signals.add(SignalItem(
        type: 'neutral',
        indicator: 'ADX',
        signal: 'çæ´è¶å¿',
        description: 'ADX<20ï¼è¶å¿ä¸æç¡®ï¼å»ºè®®è§æ',
        strength: 40,
        timestamp: last.date,
        duration: SignalDuration.longTerm,
        confidence: 0.6,
        signalCount: 1,
      ));
    }

    return signals;
  }

  // è¾å©æ¹æ³ï¼è®¡ç®KDJç½®ä¿¡åº¦
  /// v3.22: KDJæ­»åç½®ä¿¡åº¦éä½(base 0.70â0.55 for sell)ï¼å¼ºå¿è¡æä¸­KDJæ­»åé¢ç¹å¤±æã
  /// éåä¿æåæbase=0.70ï¼ä¸å½±åçå¤ä¿¡å·åç¡®çã
  static double _calculateKDJConfidence(HistoryKline last, HistoryKline prev,
      {String signalType = 'buy'}) {
    if (signalType == 'buy') {
      if (last.k < 20) return 0.80;
      if (last.k < 30) return 0.70;
      if (last.k < 50) return 0.55;
      return 0.40;
    } else {
      if (last.k > 80) return 0.70;
      if (last.k > 50) return 0.55;
      return 0.40;
    }
  }

  static double _calculateRSIConfidence(double rsiValue, {required bool isBuy}) {
    if (isBuy) {
      if (rsiValue <= 15) return 0.85;
      if (rsiValue <= 20) return 0.75;
      if (rsiValue <= 25) return 0.65;
      return 0.55;
    } else {
      if (rsiValue >= 85) return 0.85;
      if (rsiValue >= 80) return 0.75;
      if (rsiValue >= 75) return 0.65;
      return 0.55;
    }
  }

  static double _calculateWRConfidence(double wrValue, {required bool isBuy}) {
    if (isBuy) {
      if (wrValue > 95) return 0.70;
      if (wrValue > 85) return 0.60;
      return 0.45;
    } else {
      if (wrValue < 5) return 0.70;
      if (wrValue < 15) return 0.60;
      return 0.45;
    }
  }
    return base.clamp(0.45, 0.9);
  }

  /// MACDé¡¶åºèç¦»æ£æµï¼ä¸­æä¿¡å·ï¼
  static List<SignalItem> _detectMACDDivergence(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (data.length < 30) return signals;

    // å¯»æ¾å±é¨é«ç¹åä½ç¹
    final searchRange = data.sublist(data.length - 30);
    final highPeaks = _findLocalPeaks(searchRange, findHighs: true);
    final lowPeaks = _findLocalPeaks(searchRange, findHighs: false);

    // é¡¶èç¦»ï¼è¡ä»·åæ°é«ä½DIFä¸åæ°é«
    if (highPeaks.length >= 2) {
      final p1 = highPeaks[highPeaks.length - 2];
      final p2 = highPeaks[highPeaks.length - 1];
      if (searchRange[p2].high > searchRange[p1].high &&
          searchRange[p2].macdDif < searchRange[p1].macdDif) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'MACD',
          signal: 'MACDé¡¶èç¦»',
          description: 'è¡ä»·åæ°é«ä½DIFæªåæ°é«ï¼ä¸æ¶¨å¨è½è¡°ç«­',
          strength: 85,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.8,
          signalCount: 2,
        ));
      }
    }

    // åºèç¦»ï¼è¡ä»·åæ°ä½ä½DIFä¸åæ°ä½
    if (lowPeaks.length >= 2) {
      final p1 = lowPeaks[lowPeaks.length - 2];
      final p2 = lowPeaks[lowPeaks.length - 1];
      if (searchRange[p2].low < searchRange[p1].low &&
          searchRange[p2].macdDif > searchRange[p1].macdDif) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'MACD',
          signal: 'MACDåºèç¦»',
          description: 'è¡ä»·åæ°ä½ä½DIFæªåæ°ä½ï¼ä¸è·å¨è½åå¼±',
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

  /// å¯»æ¾å±é¨å³°å¼
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

  // è¾å©æ¹æ³ï¼è®¡ç®MAç½®ä¿¡åº¦
  static double _calculateMAConfidence(
      HistoryKline last, HistoryKline prev, List<HistoryKline> data) {
    double base = 0.75;
    if (last.close > last.ma10 && last.volume > last.volMa5 * 1.2)
      base += 0.05; // éä»·éå
    return base.clamp(0.7, 0.9);
  }

  /// è·³ç©ºç¼ºå£æ£æµ
  static List<SignalItem> _detectGapSignals(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (prev.high <= 0 || prev.low <= 0 || last.open <= 0) return signals;

    final gapUpSize = (last.low - prev.high) / prev.high * 100;
    final gapDownSize = (prev.low - last.high) / prev.low * 100;

    // åä¸è·³ç©ºï¼ä¸­ç¼ºå£ä»¥ä¸>2%æçæä¿¡å·ï¼
    if (gapUpSize > 2) {
      final level = gapUpSize > 5 ? 'å¤§' : 'ä¸­';
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'ç¼ºå£',
        signal: 'åä¸è·³ç©ºçªç ´',
        description: '${level}ç¼ºå£${gapUpSize.toStringAsFixed(1)}%ï¼è·³ç©ºé«å¼çªç ´ï¼ç­çº¿å¼ºå¿ä¿¡å·',
        strength: gapUpSize > 5 ? 85 : 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.75,
        signalCount: 1,
      ));
    }

    // åä¸è·³ç©ºï¼ä¸­ç¼ºå£ä»¥ä¸>2%æçæä¿¡å·ï¼
    if (gapDownSize > 2) {
      final level = gapDownSize > 5 ? 'å¤§' : 'ä¸­';
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'ç¼ºå£',
        signal: 'åä¸è·³ç©ºç ´ä½',
        description:
            '${level}ç¼ºå£${gapDownSize.toStringAsFixed(1)}%ï¼è·³ç©ºä½å¼ç ´ä½ï¼ç­çº¿å¼±å¿ä¿¡å·',
        strength: gapDownSize > 5 ? 85 : 75,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.75,
        signalCount: 1,
      ));
    }

    return signals;
  }

  /// Kçº¿å½¢æè¯å«
  static List<SignalItem> _detectCandlestickPatterns(
      List<HistoryKline> data, HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.open <= 0 || prev.open <= 0) return signals;

    final body = (last.close - last.open).abs();
    final bodyPct = body / last.open * 100;
    final upperShadow =
        last.high - (last.close > last.open ? last.close : last.open);
    final lowerShadow =
        (last.close > last.open ? last.open : last.close) - last.low;
    final isBullish = last.close > last.open;
    final isBearish = last.close < last.open;
    final prevBullish = prev.close > prev.open;
    final prevBearish = prev.close < prev.open;

    // å¤æ­è¶å¿ï¼è¿5æ¥æ¶¨è·ï¼
    bool inDowntrend = false;
    bool inUptrend = false;
    if (data.length >= 6) {
      final price5ago = data[data.length - 6].close;
      if (price5ago > 0) {
        final change5d = (last.close / price5ago - 1) * 100;
        inDowntrend =
            change5d < -3 || (last.ma10 > 0 && last.close < last.ma10);
        inUptrend = change5d > 3 || (last.ma10 > 0 && last.close > last.ma10);
      }
    }

    // é¤å­çº¿ï¼åºé¨åè½¬ï¼- å°å®ä½ãé¿ä¸å½±çº¿ãä¸è·è¶å¿ä¸­
    if (bodyPct < 1.0 &&
        lowerShadow > body * 2 &&
        upperShadow < body * 0.5 &&
        inDowntrend) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'Kçº¿å½¢æ',
        signal: 'åºé¨é¤å­çº¿',
        description: 'å°å®ä½+é¿ä¸å½±çº¿ï¼ä¸è·è¶å¿ä¸­åºç°ï¼åºé¨åè½¬ä¿¡å·',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    }

    // åé¢çº¿ï¼é¡¶é¨åè½¬ï¼- å°å®ä½ãé¿ä¸å½±çº¿ãä¸æ¶¨è¶å¿ä¸­
    if (bodyPct < 1.0 &&
        lowerShadow > body * 2 &&
        upperShadow < body * 0.5 &&
        inUptrend) {
      signals.add(SignalItem(
        type: 'sell',
        indicator: 'Kçº¿å½¢æ',
        signal: 'é¡¶é¨åé¢çº¿',
        description: 'å°å®ä½+é¿ä¸å½±çº¿ï¼ä¸æ¶¨è¶å¿ä¸­åºç°ï¼é¡¶é¨åè½¬ä¿¡å·',
        strength: 70,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.7,
        signalCount: 1,
      ));
    }

    // ä¹äºçé¡¶ï¼é¡¶é¨åè½¬ï¼- åé³åé´ãé«å¼ä½èµ°
    if (prevBullish && isBearish) {
      if (last.open > prev.high && last.close < (prev.open + prev.close) / 2) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'Kçº¿å½¢æ',
          signal: 'ä¹äºçé¡¶',
          description: 'åæ¥é³çº¿åä»æ¥é«å¼ä½èµ°æ¶é´ï¼æ¶çä½äºåæ¥å®ä½ä¸­ç¹ï¼é¡¶é¨åè½¬ä¿¡å·',
          strength: 75,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      }
    }

    // åºéå½¢æï¼åºé¨åè½¬ï¼- åé´åé³ãä½å¼é«èµ°
    if (prevBearish && isBullish) {
      if (last.open < prev.low && last.close > (prev.open + prev.close) / 2) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'Kçº¿å½¢æ',
          signal: 'åºéå½¢æ',
          description: 'åæ¥é´çº¿åä»æ¥ä½å¼é«èµ°æ¶é³ï¼æ¶çé«äºåæ¥å®ä½ä¸­ç¹ï¼åºé¨åè½¬ä¿¡å·',
          strength: 75,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.75,
          signalCount: 2,
        ));
      }
    }

    // ââï¿½ï¿½ å¤æ¥å½¢æè¯å«ï¼3-5æ¥ï¼ ââââââââââââââââââââââââââââââ

    // é³åé´ï¼çæ¶¨åæ²¡ï¼- å½åé³çº¿å®ä½å®å¨åæ²¡åé´çº¿å®ä½
    if (isBullish && prevBearish) {
      final prevBody = prev.open - prev.close;
      if (body > prevBody &&
          last.open <= prev.close &&
          last.close >= prev.open) {
        final strength = body > prevBody * 1.5 ? 80 : 75;
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'Kçº¿å½¢æ',
          signal: 'é³åé´',
          description: 'å½åé³çº¿å®ä½å®å¨åæ²¡åæ¥é´çº¿å®ä½ï¼çæ¶¨åè½¬ä¿¡å·',
          strength: strength,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.78,
          signalCount: 2,
        ));
      }
    }

    // é´åé³ï¼çè·åæ²¡ï¼- å½åé´çº¿å®ä½å®å¨åæ²¡åé³çº¿å®ä½
    if (isBearish && prevBullish) {
      final prevBody = prev.close - prev.open;
      if (body > prevBody &&
          last.open >= prev.close &&
          last.close <= prev.open) {
        final strength = body > prevBody * 1.5 ? 80 : 75;
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'Kçº¿å½¢æ',
          signal: 'é´åé³',
          description: 'å½åé´çº¿å®ä½å®å¨åæ²¡åæ¥é³çº¿å®ä½ï¼çè·åè½¬ä¿¡å·',
          strength: strength,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.78,
          signalCount: 2,
        ));
      }
    }

    // åå­æï¼å¤ç©ºåè¡¡ï¼- å®ä½æå°ï¼ä¸ä¸å½±çº¿å¯¹ç§°
    if (bodyPct < 0.3) {
      final shadowRatio = upperShadow > 0 ? lowerShadow / upperShadow : 999;
      final isDoji = shadowRatio > 0.7 && shadowRatio < 1.4;
      if (isDoji) {
        // é«ä½åå­æ = è§é¡¶ä¿¡å·
        if (inUptrend && last.close > last.ma10) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: 'Kçº¿å½¢æ',
            signal: 'é«ä½åå­æ',
            description: 'ä¸æ¶¨è¶å¿ä¸­åºç°åå­æï¼å¤ç©ºåæ­§å å¤§ï¼è­¦æåè°',
            strength: 65,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.65,
            signalCount: 1,
          ));
        }
        // ä½ä½åå­æ = è§åºä¿¡å·
        if (inDowntrend && last.close < last.ma10) {
          signals.add(SignalItem(
            type: 'buy',
            indicator: 'Kçº¿å½¢æ',
            signal: 'ä½ä½åå­æ',
            description: 'ä¸è·è¶å¿ä¸­åºç°åå­æï¼åçè¡°ç«­ï¼å³æ³¨åå¼¹',
            strength: 65,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.65,
            signalCount: 1,
          ));
        }
      }
    }

    // ä¸é³å¼æ³°ï¼Three White Soldiersï¼- è¿ç»­3æ¥é³çº¿ä¸æ¶¨
    // å¯ææï¼Morning Starï¼åé»ææï¼Evening Starï¼- 3æ¥åè½¬å½¢æ
    if (data.length >= 3) {
      final pp = data[data.length - 3]; // ååæ¥

      // ä¸é³å¼æ³°ï¼è¿ç»­3æ¥é³çº¿ãå®ä½éå¢ãæ¶çåè¿ææ°é«
      if (isBullish && prevBullish && pp.close > pp.open) {
        final ppBody = pp.close - pp.open;
        final prevBody = prev.close - prev.open;
        if (prevBody > ppBody * 0.7 &&
            body > prevBody * 0.5 &&
            last.close > prev.close &&
            prev.close > pp.close) {
          // ç¡®è®¤è¶å¿åä¸
          final inTrend =
              last.ma5 > 0 && last.close > last.ma5 && last.ma5 > last.ma10;
          signals.add(SignalItem(
            type: 'buy',
            indicator: 'Kçº¿å½¢æ',
            signal: 'ä¸é³å¼æ³°',
            description: 'è¿ç»­3æ¥é³çº¿éå¢ä¸æ¶¨ï¼è¶å¿å¼ºå¿${inTrend ? '' : "ï¼ä½åçº¿éç¡®è®¤"}',
            strength: inTrend ? 85 : 75,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: inTrend ? 0.82 : 0.72,
            signalCount: 3,
          ));
        }
      }

      // ä¸åªä¹é¸¦ï¼è¿ç»­3æ¥é´çº¿ä¸è·ãæ¶çåè¿ææ°ä½
      if (isBearish && prevBearish && pp.close < pp.open) {
        final ppBody = pp.open - pp.close;
        final prevBody = prev.open - prev.close;
        if (prevBody > ppBody * 0.7 &&
            body > prevBody * 0.5 &&
            last.close < prev.close &&
            prev.close < pp.close) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: 'Kçº¿å½¢æ',
            signal: 'ä¸åªä¹é¸¦',
            description: 'è¿ç»­3æ¥é´çº¿éå¢ä¸è·ï¼è¶å¿å¼±å¿',
            strength: 80,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.78,
            signalCount: 3,
          ));
        }
      }

      // å¯ææï¼Morning Starï¼- é´çº¿ + å°å®ä½(æçº¿) + é³çº¿çªç ´é´çº¿å®ä½ä¸­ç¹
      if (pp.close < pp.open && isBullish) {
        final ppBody = pp.open - pp.close;
        final prevBodySmall = (prev.close - prev.open).abs() / prev.open * 100;
        if (prevBodySmall < 0.8 &&
            body > ppBody * 0.6 &&
            last.close > (pp.open + pp.close) / 2) {
          signals.add(SignalItem(
            type: 'buy',
            indicator: 'Kçº¿å½¢æ',
            signal: 'å¯ææ',
            description: '3æ¥åè½¬å½¢æï¼é´âæâé³ï¼é³çº¿æ¶ççªç ´é´çº¿å®ä½ä¸­ç¹ï¼åºé¨åè½¬ä¿¡å·',
            strength: 80,
            timestamp: last.date,
            duration: SignalDuration.shortTerm,
            confidence: 0.78,
            signalCount: 3,
          ));
        }
      }

      // é»ææï¼Evening Starï¼- é³çº¿ + å°å®ä½(æçº¿) + é´çº¿è·å¥é³çº¿å®ä½
      if (pp.close > pp.open && isBearish) {
        final ppBody = pp.close - pp.open;
        final prevBodySmall = (prev.close - prev.open).abs() / prev.open * 100;
        if (prevBodySmall < 0.8 &&
            body > ppBody * 0.6 &&
            last.close < (pp.open + pp.close) / 2) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: 'Kçº¿å½¢æ',
            signal: 'é»ææ',
            description: '3æ¥åè½¬å½¢æï¼é³âæâé´ï¼é´çº¿æ¶çè·ç ´é³çº¿å®ä½ä¸­ç¹ï¼é¡¶é¨åè½¬ä¿¡å·',
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

  /// æäº¤éè¶å¿åæ
  static List<SignalItem> _detectVolumeTrends(
      List<HistoryKline> data, HistoryKline last) {
    final signals = <SignalItem>[];
    if (data.length < 20 || last.volMa5 <= 0) return signals;

    final recent10 = data.sublist(data.length - 10);
    final recent3 = data.sublist(data.length - 3);
    final recent5 = data.sublist(data.length - 5);

    final priceChange10d =
        (last.close / data[data.length - 11].close - 1) * 100;

    // å¸ç­¹å½¢æï¼10æ¥ä¸è·>5% + åæéè½éå(æé¤è¿3æ¥) + è¿3æ¥ä¼ç¨³æ¾é
    if (priceChange10d < -5) {
      // æ£æ¥ç¬¬-4å°-7å¤©éè½éåï¼æé¤è¿3å¤©çä¼ç¨³æ¾éé¶æ®µï¼
      bool volDeclining = recent10.length >= 7;
      for (int i = 4; i < 8 && i < recent10.length - 1; i++) {
        if (recent10[recent10.length - i].volume >=
            recent10[recent10.length - i - 1].volume) {
          volDeclining = false;
          break;
        }
      }
      final avgVol3 = recent3.map((d) => d.volume).reduce((a, b) => a + b) / 3;
      final avgVol5 = recent5.map((d) => d.volume).reduce((a, b) => a + b) / 5;
      final priceStable =
          (last.close / data[data.length - 4].close - 1).abs() < 2;

      if (volDeclining && avgVol3 > avgVol5 * 1.2 && priceStable) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'éä»·è¶å¿',
          signal: 'ä¸»åå¸ç­¹è¿¹è±¡',
          description:
              'ä¸è·${priceChange10d.toStringAsFixed(1)}%åéè½èç¼©éåï¼è¿3æ¥ä¼ç¨³ä¸éè½æ¾å¤§ï¼ä¸»åå¯è½å¨å¸ç­¹',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 2,
        ));
      }
    }

    // æ´¾åå½¢æï¼10æ¥ä¸æ¶¨>5% + éè½éå + è¿3æ¥ç¼©é
    if (priceChange10d > 5) {
      bool volDeclining = true;
      for (int i = 1; i < 5; i++) {
        if (recent10[recent10.length - i].volume >=
            recent10[recent10.length - i - 1].volume) {
          volDeclining = false;
          break;
        }
      }
      final avgVol3 = recent3.map((d) => d.volume).reduce((a, b) => a + b) / 3;
      if (volDeclining && avgVol3 < last.volMa5 * 0.7) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'éä»·è¶å¿',
          signal: 'ä¸»åæ´¾åè¿¹è±¡',
          description:
              'ä¸æ¶¨${priceChange10d.toStringAsFixed(1)}%ä½éè½æç»­èç¼©ï¼è¿3æ¥ç¼©éè³åé70%ä»¥ä¸ï¼ä¸»åå¯è½å¨æ´¾å',
          strength: 70,
          timestamp: last.date,
          duration: SignalDuration.mediumTerm,
          confidence: 0.7,
          signalCount: 2,
        ));
      }
    }

    // å°éè§åºï¼æäº¤éåè¿20æ¥æä½ + ä»·æ ¼å¨MA20éè¿æä¸æ¹
    final minVol20 = data
        .sublist(data.length - 20)
        .map((d) => d.volume)
        .reduce((a, b) => a < b ? a : b);
    if (last.volume <= minVol20 &&
        last.ma20 > 0 &&
        last.close <= last.ma20 * 1.02) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'éä»·è¶å¿',
        signal: 'å°éè§åº',
        description:
            'æäº¤éåè¿20æ¥æ°ä½ï¼ä»·æ ¼å¨MA20(${last.ma20.toStringAsFixed(2)})éè¿ï¼åçæ¯ç«­',
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

  static List<SignalItem> _detectMACDCrossWarning(
      HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];
    if (last.macdDea == 0) return signals;

    final difDistance =
        (last.macdDea - last.macdDif).abs() / last.macdDea.abs();
    final difTrend = last.macdDif - prev.macdDif;
    final deaTrend = last.macdDea - prev.macdDea;

    if (difDistance < 0.08 && difTrend > 0 && deaTrend <= 0) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'MACDéåé¢è­¦',
        description: 'DIFå¿«éæ¥è¿DEAï¼å³å°å½¢æéåï¼æåå³æ³¨',
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
        signal: 'MACDæ­»åé¢è­¦',
        description: 'DIFå¿«éæ¥è¿DEAï¼å³å°å½¢ææ­»åï¼æåè­¦æ',
        strength: 55,
        timestamp: last.date,
        duration: SignalDuration.shortTerm,
        confidence: 0.6,
        signalCount: 1,
      ));
    }

    return signals;
  }

  static List<SignalItem> _detectKDJCrossWarning(
      HistoryKline last, HistoryKline prev) {
    final signals = <SignalItem>[];

    final kDistance = (last.d - last.k).abs() /
        (last.d.abs() + last.k.abs()).clamp(1.0, double.infinity);
    final kTrend = last.k - prev.k;

    if (kDistance < 0.15 && kTrend > 0 && last.k < 50) {
      signals.add(SignalItem(
        type: 'buy',
        indicator: 'KDJ',
        signal: 'KDJéåé¢è­¦',
        description: 'Kçº¿å¿«éæ¥è¿Dçº¿ï¼å³å°å½¢æéåï¼æåå³æ³¨',
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
        signal: 'KDJæ­»åé¢è­¦',
        description: 'Kçº¿å¿«éæ¥è¿Dçº¿ï¼å³å°å½¢ææ­»åï¼æåè­¦æ',
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
          signal: 'MACDé¡¶èç¦»é¢è­¦',
          description: 'ä»·æ ¼æ¥è¿åé«ä½MACDæªåæ°é«ï¼ä¸æ¶¨å¨è½åå¼±',
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
          signal: 'MACDåºèç¦»é¢è­¦',
          description: 'ä»·æ ¼æ¥è¿åä½ä½MACDæªåæ°ä½ï¼ä¸è·å¨è½åå¼±',
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
