import '../models/stock_models.dart';
import 'indicators.dart';
import 'signal_detector.dart';
import 'position_manager.dart';
import 'strategy_builder.dart';
import 'strategy_engine.dart';

List<SignalItem> detectSignals(List<HistoryKline> data) {
  if (data.isEmpty || data.length < 2) return [];

  final signals = <SignalItem>[];

  // 仅保留 SignalDetector 未覆盖的特有信号
  signals.addAll(_detectVolumePriceDivergence(data));
  signals.addAll(_detectBollSqueezeBreakout(data));

  signals.sort((a, b) => b.strength.compareTo(a.strength));
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

AnalysisResult generateAnalysis(List<HistoryKline> data, QuoteData? quote, {MarketContext? marketContext}) {
  if (data.isEmpty) {
    return AnalysisResult(
      signals: [],
      indicators: {},
      recommendation: '观望',
      score: 5,
      riskLevel: '中等',
      riskFactors: ['数据不足'],
      suggestions: ['等待更多数据'],
      reasons: ['数据不足，无法生成有效建议'],
      opportunities: [],
      confidenceScore: 0.3,
    );
  }

  final last = data[data.length - 1];
  // 统一使用 SignalDetector 分层信号，合并特有信号
  List<SignalItem> signals;
  try {
    signals = SignalDetector.detectLayeredSignals(data);
  } catch (_) {
    signals = [];
  }
  // 添加特有信号（detectSignals 中的量价背离、布林收口）
  try {
    final uniqueSignals = detectSignals(data);
    final existingNames = signals.map((s) => s.signal).toSet();
    for (final s in uniqueSignals) {
      if (!existingNames.contains(s.signal)) {
        signals.add(s);
      }
    }
  } catch (_) {}
  final indicators = getIndicatorSummary(data);

  final buySignals = signals.where((s) => s.type == 'buy').toList();
  final sellSignals = signals.where((s) => s.type == 'sell').toList();

  // ========== 多维加权评分（10级制：1-10分） ==========

  // 1. 信号评分 (0-3分) - 按信号强度加权
  int buyCount = buySignals.length;
  int sellCount = sellSignals.length;

  // ADX趋势/盘整权重调整：在加权阶段分别调整信号强度
  final adx = last.adx14;
  double buyStrength = 0;
  double sellStrength = 0;
  for (final s in buySignals) {
    double strength = s.strength.toDouble();
    if (adx > 25) {
      if (s.indicator == 'MA' || s.indicator == 'MACD' || s.signal.contains('排列') || s.signal.contains('金叉') || s.signal.contains('死叉')) {
        strength *= 1.2;
      }
    } else if (adx > 0 && adx < 20) {
      if (s.indicator == 'RSI' || s.indicator == 'KDJ' || s.signal.contains('超买') || s.signal.contains('超卖')) {
        strength *= 1.2;
      }
    }
    buyStrength += strength;
  }
  for (final s in sellSignals) {
    double strength = s.strength.toDouble();
    if (adx > 25) {
      if (s.indicator == 'MA' || s.indicator == 'MACD' || s.signal.contains('排列') || s.signal.contains('金叉') || s.signal.contains('死叉')) {
        strength *= 1.2;
      }
    } else if (adx > 0 && adx < 20) {
      if (s.indicator == 'RSI' || s.indicator == 'KDJ' || s.signal.contains('超买') || s.signal.contains('超卖')) {
        strength *= 1.2;
      }
    }
    sellStrength += strength;
  }
  double maxTotal = 300.0;
  // 对称基础分：0 为中性，范围[-3, 3]，映射到[0, 3]
  double signalRaw = (buyStrength - sellStrength) / maxTotal * 3;
  signalRaw = signalRaw.clamp(-3.0, 3.0);
  double signalScore = (signalRaw + 3.0) / 2.0; // 映射到 [0, 3]

  // 2. 趋势强度评分 (0-2分) - 基于均线排列 + ADX趋势强度
  double trendScore = 0;
  if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
    if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
      trendScore = 1.8;
    } else if (last.ma5 > last.ma10) {
      trendScore = 1.1;
    } else if (last.ma5 > last.ma20) {
      trendScore = 0.7;
    } else {
      trendScore = 0.3;
    }
  }
  if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
    if (last.ma5 < last.ma10 && last.ma10 < last.ma20) {
      trendScore = 0;
    }
  }
  if (last.adx14 > 25) {
    trendScore += 0.5;
  } else if (last.adx14 > 0 && last.adx14 < 20) {
    trendScore -= 0.3;
  }
  trendScore = trendScore.clamp(0.0, 2.0);

  // 3. 动量评分 (0-2分) - 基于RSI + BIAS乖离率
  double momentumScore = 1.0;
  if (last.rsi6 > 0) {
    if (last.rsi6 < 30) {
      momentumScore = 1.6;
    } else if (last.rsi6 < 40) {
      momentumScore = 1.3;
    } else if (last.rsi6 < 60) {
      momentumScore = 1.0;
    } else if (last.rsi6 < 70) {
      momentumScore = 0.7;
    } else {
      momentumScore = 0.3;
    }
  }
  if (last.bias6.abs() > 5) {
    momentumScore -= 0.4;
  } else if (last.bias6.abs() > 3) {
    momentumScore -= 0.2;
  }
  momentumScore = momentumScore.clamp(0.0, 2.0);

  // 4. 量价确认评分 (0-1.5分) - 基于量比 + OBV趋势
  double volumeScore = 0.8;
  if (last.volMa5 > 0) {
    final volRatio = last.volume / last.volMa5;
    if (last.close >= last.open) {
      if (volRatio > 1.5) {
        volumeScore = 1.4;
      } else if (volRatio > 1.0) {
        volumeScore = 1.1;
      } else {
        volumeScore = 0.6;
      }
    } else {
      if (volRatio > 1.5) {
        volumeScore = 0.2;
      } else if (volRatio > 1.0) {
        volumeScore = 0.5;
      } else {
        volumeScore = 0.8;
      }
    }
  }
  if (data.length >= 5 && last.obv != 0) {
    final obv5 = data[data.length - 5].obv;
    if (obv5 != 0) {
      if (last.obv > obv5 && last.close > data[data.length - 5].close) {
        volumeScore += 0.3;
      } else if (last.obv < obv5 && last.close < data[data.length - 5].close) {
        volumeScore -= 0.2;
      }
    }
  }
  volumeScore = volumeScore.clamp(0.0, 1.5);

  // 5. 波动率评分 (0-1.5分) - 基于ATR
  double volatilityScore = 0.8;
  if (last.atr14 > 0 && last.close > 0) {
    final atrPct = last.atr14 / last.close * 100;
    if (atrPct < 2) {
      volatilityScore = 1.3;
    } else if (atrPct < 3) {
      volatilityScore = 1.1;
    } else if (atrPct < 4) {
      volatilityScore = 0.8;
    } else if (atrPct < 5) {
      volatilityScore = 0.5;
    } else {
      volatilityScore = 0.2;
    }
  }

  // K线信号基础分 (0-10)
  final klineBaseScore = (signalScore + trendScore + momentumScore + volumeScore + volatilityScore).clamp(0.0, 10.0);

  // ========== 实时行情评分 (0-10) ==========
  double realtimeScore = 5.0;
  if (quote != null && quote.price > 0) {
    final changePct = quote.changePct;
    // 8档对称涨跌幅评分
    if (changePct > 8) {
      realtimeScore -= 0.5;   // 追高风险大
    } else if (changePct > 5) {
      realtimeScore += 0.5;   // 注意追高风险
    } else if (changePct > 2) {
      realtimeScore += 1.0;   // 强势上涨
    } else if (changePct > 0) {
      realtimeScore += 0.5;   // 温和上涨
    } else if (changePct >= -2) {
      realtimeScore -= 0.5;   // 温和下跌
    } else if (changePct >= -5) {
      // 正常回调，不加不减
    } else if (changePct >= -8) {
      realtimeScore += 0.5;   // 超跌反弹机会
    } else {
      realtimeScore += 0.8;   // 大幅超跌
    }

    if (quote.mainNetFlow != 0) {
      final rate = quote.mainNetFlowRate;
      if (rate > 10) {
        realtimeScore += 1.0;
      } else if (rate > 5) {
        realtimeScore += 0.8;
      } else if (rate > 0) {
        realtimeScore += 0.4;
      } else if (rate > -5) {
        realtimeScore -= 0.4;
      } else if (rate > -10) {
        realtimeScore -= 0.8;
      } else {
        realtimeScore -= 1.0;
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

  // ========== 共振评分（双向：多空对称） ==========
  int bullCount = 0;
  int bearCount = 0;
  final maBull = last.ma5 > last.ma10 && last.ma10 > last.ma20;
  final maBear = last.ma5 < last.ma10 && last.ma10 < last.ma20;
  if (maBull) bullCount++;
  if (maBear) bearCount++;
  final macdBull = last.macdDif > last.macdDea && last.macdHist > 0;
  final macdBear = last.macdDif < last.macdDea && last.macdHist < 0;
  if (macdBull) bullCount++;
  if (macdBear) bearCount++;
  final rsiBull = last.rsi6 > 60;
  final rsiBear = last.rsi6 < 40 && last.rsi6 > 0;
  if (rsiBull) bullCount++;
  if (rsiBear) bearCount++;
  final kdjBull = last.k > last.d && last.k < 80;
  final kdjBear = last.k < last.d && last.k > 20;
  if (kdjBull) bullCount++;
  if (kdjBear) bearCount++;
  final bollBull = last.bollMid > 0 && last.close > last.bollMid;
  final bollBear = last.bollMid > 0 && last.close < last.bollMid;
  if (bollBull) bullCount++;
  if (bollBear) bearCount++;
  final volBull = last.volMa5 > 0 && last.volume > last.volMa5 && last.close > last.open;
  final volBear = last.volMa5 > 0 && last.volume > last.volMa5 && last.close < last.open;
  if (volBull) bullCount++;
  if (volBear) bearCount++;
  final wrBull = last.wr14 != null && last.wr14! > 80;
  final wrBear = last.wr14 != null && last.wr14! < 20;
  if (wrBull) bullCount++;
  if (wrBear) bearCount++;
  final cciBull = last.cci14 != null && last.cci14! > 100;
  final cciBear = last.cci14 != null && last.cci14! < -100;
  if (cciBull) bullCount++;
  if (cciBear) bearCount++;
  final hasBottomDivergence = signals.any((s) => s.signal.contains('底背离'));
  final hasTopDivergence = signals.any((s) => s.signal.contains('顶背离'));
  if (hasBottomDivergence) bullCount += 2;
  if (hasTopDivergence) bearCount += 2;

  // 双向共振：多空对称，范围[-8, 8]，映射到[0, 10]
  final confluenceBonus = (5.0 + (bullCount - bearCount) / 8 * 5).clamp(0.0, 10.0);

  // ========== 三维度加权总分（10级制 1-10） ==========
  // K线信号(55%) + 实时行情(25%) + 共振评分(20%)
  final rawScore = (klineBaseScore * 0.55 + realtimeScore * 0.25 + confluenceBonus * 0.20).clamp(0.0, 10.0);

  // 市场环境调节
  double marketAdjustment = 1.0;
  if (marketContext != null) {
    marketAdjustment = marketContext.getMarketAdjustmentFactor();
  }
  final adjustedScore = (rawScore * marketAdjustment).clamp(0.0, 10.0);

  // 映射到10级整分（1-10）
  final totalScore = (adjustedScore / 10.0 * 9 + 1).round().clamp(1, 10);

  // ========== 10级推荐（7档） ==========
  String recommendation;
  if (totalScore >= 9) {
    recommendation = '强烈买入';
  } else if (totalScore >= 8) {
    recommendation = '买入';
  } else if (totalScore >= 7) {
    recommendation = '谨慎买入';
  } else if (totalScore >= 5) {
    recommendation = '观望';
  } else if (totalScore >= 4) {
    recommendation = '谨慎卖出';
  } else if (totalScore >= 3) {
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
    if (buySignals.length >= 3 && totalScore >= 8) {
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

  // 仓位建议
  try {
    final positionManager = PositionManager.calculatePosition(last);
    suggestions.add(PositionManager.getPositionAdvice(positionManager));
  } catch (_) {
    // 仓位计算失败不影响主流程
  }

  // ========== 多指标共振详情（7维度） ==========
  final confluenceDetails = <Map<String, dynamic>>[];
  confluenceDetails.add({'name': 'MA', 'bull': maBull, 'bear': maBear});
  confluenceDetails.add({'name': 'MACD', 'bull': macdBull, 'bear': macdBear});
  confluenceDetails.add({'name': 'RSI', 'bull': rsiBull, 'bear': rsiBear});
  confluenceDetails.add({'name': 'KDJ', 'bull': kdjBull, 'bear': kdjBear});
  confluenceDetails.add({'name': 'BOLL', 'bull': bollBull, 'bear': bollBear});
  confluenceDetails.add({'name': '量价', 'bull': volBull, 'bear': volBear});
  confluenceDetails.add({'name': 'WR', 'bull': wrBull, 'bear': wrBear});
  confluenceDetails.add({'name': 'CCI', 'bull': cciBull, 'bear': cciBear});
  confluenceDetails.add({'name': '背离', 'bull': hasBottomDivergence, 'bear': hasTopDivergence, 'weighted': true});

  final tradeLevels = calcTradeLevels(data);

  // 构建分层策略
  List<TradingStrategy> shortTermStrategies = [];
  List<TradingStrategy> longTermStrategies = [];
  try {
    shortTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.shortTerm);
    longTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.longTerm);
  } catch (_) {
    // 策略构建失败时回退
  }

  // 推荐可信度计算
  double confidenceScore = 0.5;
  final signalCount = buyCount + sellCount;
  if (signalCount > 0) {
    final signalRatio = (buyCount - sellCount).abs() / signalCount;
    confidenceScore = 0.5 + signalRatio * 0.3;
  }
  if (quote != null && quote.pe > 0 && quote.pe < 50) confidenceScore += 0.05;
  if (quote != null && quote.pb > 0 && quote.pb < 5) confidenceScore += 0.05;
  if (marketContext != null && marketContext.avgChangePct > 0.5) confidenceScore += 0.03;
  if (marketContext != null && marketContext.avgChangePct < -0.5) confidenceScore -= 0.03;
  confidenceScore = confidenceScore.clamp(0.3, 0.95);

  // 详细推荐理由
  final detailedReasons = <RecommendationReason>[];
  for (final signal in signals.take(5)) {
    if (signal.confidence != null) {
      detailedReasons.add(RecommendationReason(
        title: signal.signal,
        description: signal.description,
        confidence: signal.confidence!,
        duration: signal.duration == SignalDuration.shortTerm ? '短期' : '长期',
      ));
    }
  }
  if (marketContext != null) {
    detailedReasons.add(RecommendationReason(
      title: '市场环境',
      description: '上证${marketContext.shIndexPct.toStringAsFixed(2)}%，深证${marketContext.szIndexPct.toStringAsFixed(2)}%',
      confidence: 0.7,
      duration: '环境',
    ));
  }

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
    shortTermStrategies: shortTermStrategies,
    longTermStrategies: longTermStrategies,
    marketContext: marketContext,
    confidenceScore: confidenceScore,
    detailedReasons: detailedReasons,
  );
}
