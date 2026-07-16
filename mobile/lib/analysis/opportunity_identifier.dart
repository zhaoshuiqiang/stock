import 'dart:math';
import '../models/stock_models.dart';
import 'market_structure_analyzer.dart';

class OpportunityIdentifier {
  static const Map<String, Map<String, double>> _synergyMatrix = {
    'KDJ金叉': {
      '放量上涨': 15.0,
      'MACD金叉': 10.0,
      'MACD死叉': -20.0,
    },
    'RSI超卖回升': {
      'MACD底背离': 20.0,
      '布林带跌破下轨': 15.0,
      '缩量上涨': -10.0,
    },
    '放量上涨': {
      'MA5上穿MA10': 10.0,
      '布林带放量突破上轨': 15.0,
    },
    '向上跳空': {
      '放量上涨': 15.0,
      '缩量上涨': -15.0,
    },
    'MACD金叉': {
      'KDJ金叉': 10.0,
      'MA5上穿MA10': 8.0,
    },
    '缩量止跌': {
      'RSI超卖回升': 12.0,
      'KDJ金叉': 10.0,
    },
  };

  static List<Map<String, String>> identify(List<SignalItem> buySignals) {
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
    return opportunities;
  }

  static OpportunityScore evaluate({
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    required List<HistoryKline> klineData,
    required QuoteData? quote,
    required MarketStructureResult? marketStructure,
    required MarketContext? marketContext,
    required double? riskRewardRatio,
  }) {
    if (buySignals.isEmpty) {
      return const OpportunityScore(
        totalScore: 0, grade: OpportunityGrade.D,
        signalStrength: 0, capitalScore: 0, timingScore: 0,
        riskRewardScore: 0, liquidityScore: 0,
      );
    }

    final signalStr = _calcSignalStrength(buySignals);
    final capital = _calcCapitalScore(klineData, quote);
    final timing = _calcTimingScore(buySignals, marketStructure, marketContext);
    final rr = _calcRiskRewardScore(riskRewardRatio);
    final liquidity = _calcLiquidityScore(quote, klineData);
    final synergies = _detectSynergies(buySignals);
    final synergyBonus = synergies.fold(0.0, (sum, s) => sum + s.scoreDelta);

    final total = (signalStr + capital + timing + rr + liquidity + synergyBonus).clamp(0.0, 100.0);
    final grade = OpportunityScore.gradeFromScore(total);

    final primary = buySignals.first;
    final secondary = buySignals.length > 1 ? buySignals[1] : null;

    return OpportunityScore(
      totalScore: total,
      grade: grade,
      signalStrength: signalStr,
      capitalScore: capital,
      timingScore: timing,
      riskRewardScore: rr,
      liquidityScore: liquidity,
      synergies: synergies,
      primarySignal: primary.signal,
      secondarySignal: secondary?.signal,
      timeDecayFactor: _calcTimeDecay(buySignals),
    );
  }

  static double _calcSignalStrength(List<SignalItem> signals) {
    if (signals.isEmpty) return 0;
    final signalWeights = <String, double>{
      'KDJ': 1.0, 'RSI': 1.0, 'MA': 0.8, 'MACD': 0.8,
      '量价': 0.9, 'BOLL': 0.85, 'WR': 0.7, 'CCI': 0.7,
      '缺口': 0.7, 'composite': 0.9,
    };
    double total = 0;
    for (final s in signals.take(5)) {
      final weight = signalWeights[s.indicator] ?? 0.7;
      final decay = _signalTimeDecay(s);
      total += (s.strength / 100.0) * weight * decay * 6.0;
    }
    return total.clamp(0.0, 30.0);
  }

  static double _signalTimeDecay(SignalItem signal) {
    final ts = signal.freshTime ?? signal.timestamp;
    if (ts == null) return 1.0;
    final days = DateTime.now().difference(ts).inDays;
    if (days <= 0) return 1.0;
    if (days == 1) return 0.6;
    if (days == 2) return 0.3;
    return 0.1;
  }

  static double _calcTimeDecay(List<SignalItem> signals) {
    if (signals.isEmpty) return 1.0;
    final ts = signals.first.freshTime ?? signals.first.timestamp;
    if (ts == null) return 1.0;
    final hours = DateTime.now().difference(ts).inMinutes / 60.0;
    return (1.0 - hours * 0.02).clamp(0.5, 1.0);
  }

  static double _calcCapitalScore(List<HistoryKline> data, QuoteData? quote) {
    double score = 5.0;
    if (quote != null) {
      final rate = quote.mainNetFlowRate;
      if (rate > 5) score += 8.0;
      else if (rate > 2) score += 5.0;
      else if (rate > 0) score += 2.0;
      else if (rate < -6) score -= 8.0;
      else if (rate < -3) score -= 5.0;
    }
    if (data.length >= 5) {
      final recent5 = data.sublist(data.length - 5);
      int consecutiveInflow = 0;
      for (final k in recent5.reversed) {
        if (k.close > k.open && k.volume > (k.volMa5 > 0 ? k.volMa5 : k.volume)) {
          consecutiveInflow++;
        } else {
          break;
        }
      }
      if (consecutiveInflow >= 3) score += 5.0;
      else if (consecutiveInflow >= 2) score += 2.5;
    }
    if (data.length >= 10) {
      final last = data.last;
      final obv5ago = data[data.length - 5].obv;
      if (obv5ago != 0) {
        final obvChange = (last.obv - obv5ago) / obv5ago.abs();
        if (obvChange > 0.1) score += 3.0;
        else if (obvChange > 0.05) score += 1.5;
      }
    }
    return score.clamp(0.0, 25.0);
  }

  static double _calcTimingScore(
    List<SignalItem> signals,
    MarketStructureResult? structure,
    MarketContext? market,
  ) {
    double score = 5.0;
    final ts = signals.first.freshTime ?? signals.first.timestamp;
    if (ts != null) {
      final hours = DateTime.now().difference(ts).inHours;
      if (hours <= 2) score += 8.0;
      else if (hours <= 24) score += 5.0;
      else if (hours <= 48) score += 2.0;
    }
    if (structure != null) {
      final isBull = structure.structure == MarketStructure.bullTrend;
      final isConsolidation = structure.structure == MarketStructure.consolidation;
      final hasBuySignal = signals.any((s) => s.type == 'buy');
      if (isBull && hasBuySignal) score += 7.0;
      else if (isConsolidation && hasBuySignal) score += 4.0;
    }
    if (market != null) {
      final avgChange = market.avgChangePct;
      final isBullishSignal = signals.any((s) => s.type == 'buy');
      if (avgChange > 0 && isBullishSignal) score += 5.0;
      else if (avgChange < -1 && isBullishSignal) score += 1.0;
    }
    return score.clamp(0.0, 20.0);
  }

  static double _calcRiskRewardScore(double? ratio) {
    if (ratio == null || ratio <= 0) return 5.0;
    if (ratio >= 3.0) return 15.0;
    if (ratio >= 2.0) return 12.0;
    if (ratio >= 1.5) return 8.0;
    return 5.0;
  }

  static double _calcLiquidityScore(QuoteData? quote, List<HistoryKline> data) {
    double score = 3.0;
    if (quote != null) {
      final turnover = quote.turnover;
      if (turnover >= 2 && turnover <= 8) score += 4.0;
      else if (turnover >= 1 && turnover < 2) score += 2.0;
      else if (turnover > 15 || turnover < 0.5) score -= 2.0;

      final volRatio = quote.volumeRatio;
      if (volRatio > 1.5) score += 3.0;
      else if (volRatio >= 0.8) score += 1.5;
    }
    return score.clamp(0.0, 10.0);
  }

  static List<SignalSynergy> _detectSynergies(List<SignalItem> signals) {
    final result = <SignalSynergy>[];
    final names = signals.map((s) => s.signal).toList();
    for (int i = 0; i < names.length; i++) {
      for (int j = i + 1; j < names.length; j++) {
        final delta = _synergyMatrix[names[i]]?[names[j]] ??
            _synergyMatrix[names[j]]?[names[i]];
        if (delta != null) {
          result.add(SignalSynergy(
            signalA: names[i],
            signalB: names[j],
            isSynergistic: delta > 0,
            scoreDelta: delta,
          ));
        }
      }
    }
    return result;
  }
}
