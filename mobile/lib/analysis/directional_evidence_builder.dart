import 'market_regime_classifier.dart';
import 'market_structure_analyzer.dart';
import 'next_day_predictor.dart';
import 'next_session_prediction.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

const String trendComponentKey = 'trend';
const String reversalMomentumComponentKey = 'reversal_momentum';
const String volumeFlowComponentKey = 'volume_flow';
const String relativeStrengthComponentKey = 'relative_strength';
const String nextSessionComponentKey = 'next_session';

const String oversoldReboundGuard = 'oversold_rebound_guard';
const String chaseGuard = 'chase_guard';
const String historyDataMissingFlag = 'history_data_missing';

class DirectionalEvidenceInput {
  final List<HistoryKline> data;
  final List<SignalItem> buySignals;
  final List<SignalItem> sellSignals;
  final QuoteData? quote;
  final MarketContext? marketContext;
  final MarketStructureResult? marketStructure;
  final double? industryRelativeStrength;
  final NextDayPredictionResult nextDayPrediction;
  final NextSessionPrediction nextSessionPrediction;

  DirectionalEvidenceInput({
    required this.data,
    required this.buySignals,
    required this.sellSignals,
    this.quote,
    this.marketContext,
    this.marketStructure,
    this.industryRelativeStrength,
    required this.nextDayPrediction,
    required this.nextSessionPrediction,
  });
}

class DirectionalEvidenceResult {
  final Map<String, double> components;
  final double stockEvidence;
  final int marketBias;
  final double directionScore;
  final MarketRegime marketRegime;
  final List<String> guardReasons;
  final List<String> dataQualityFlags;
  final Map<String, String> signalComponentOwnership;

  DirectionalEvidenceResult({
    required Map<String, double> components,
    required this.stockEvidence,
    required this.marketBias,
    required this.directionScore,
    required this.marketRegime,
    List<String> guardReasons = const [],
    List<String> dataQualityFlags = const [],
    Map<String, String> signalComponentOwnership = const {},
  })  : components = Map<String, double>.unmodifiable(components),
        guardReasons = List<String>.unmodifiable(guardReasons),
        dataQualityFlags = List<String>.unmodifiable(dataQualityFlags),
        signalComponentOwnership =
            Map<String, String>.unmodifiable(signalComponentOwnership);
}

class DirectionalEvidenceBuilder {
  static const Map<String, double> componentWeights = <String, double>{
    trendComponentKey: 0.30,
    reversalMomentumComponentKey: 0.25,
    volumeFlowComponentKey: 0.20,
    relativeStrengthComponentKey: 0.15,
    nextSessionComponentKey: 0.10,
  };

  static DirectionalEvidenceResult build(DirectionalEvidenceInput input) {
    final market = MarketRegimeClassifier.classify(input.marketContext);
    final dataQualityFlags = <String>[...market.dataQualityFlags];
    final guardReasons = <String>[];
    final signalOwnership = <String, String>{};

    if (input.data.isEmpty) {
      dataQualityFlags.add(historyDataMissingFlag);
      return DirectionalEvidenceResult(
        components: _emptyComponents(),
        stockEvidence: 0,
        marketBias: market.marketBias,
        directionScore: (market.marketBias * 0.20).clamp(-100, 100).toDouble(),
        marketRegime: market.marketRegime,
        dataQualityFlags: dataQualityFlags,
        signalComponentOwnership: signalOwnership,
      );
    }

    final signalComponents = _signalComponents(
      input.buySignals,
      input.sellSignals,
      signalOwnership,
    );

    final trend = _combine(
      _priceTrend(input.data),
      _marketStructureTrend(input.marketStructure),
      signalComponents[trendComponentKey] ?? 0,
    );
    final reversalMomentum = _combine(
      _reversalMomentum(input.data.last),
      signalComponents[reversalMomentumComponentKey] ?? 0,
    );
    final volumeFlow = _combine(
      _volumeFlow(input.data.last, input.quote),
      signalComponents[volumeFlowComponentKey] ?? 0,
    );
    final relativeStrength = _combine(
      _relativeStrength(input.industryRelativeStrength),
      signalComponents[relativeStrengthComponentKey] ?? 0,
    );
    final nextSession = _combine(
      _nextSession(input.nextDayPrediction, input.nextSessionPrediction),
      signalComponents[nextSessionComponentKey] ?? 0,
    );

    final components = <String, double>{
      trendComponentKey: trend,
      reversalMomentumComponentKey: reversalMomentum,
      volumeFlowComponentKey: volumeFlow,
      relativeStrengthComponentKey: relativeStrength,
      nextSessionComponentKey: nextSession,
    };

    final stockEvidence = 100 *
        componentWeights.entries.fold<double>(
          0,
          (total, entry) => total + (components[entry.key] ?? 0) * entry.value,
        );

    var guardedDirectionScore =
        (stockEvidence * 0.80 + market.marketBias * 0.20)
            .clamp(-100, 100)
            .toDouble();

    if (_hasOversoldReboundSetup(input.data) &&
        guardedDirectionScore < -19 &&
        !(trend <= -0.45 && volumeFlow <= -0.45)) {
      guardedDirectionScore = -19;
      guardReasons.add(oversoldReboundGuard);
    }

    if (_hasChaseSetup(input.data.last, input.quote) &&
        guardedDirectionScore > 34 &&
        !(trend >= 0.45 && volumeFlow >= 0.45)) {
      guardedDirectionScore = 34;
      guardReasons.add(chaseGuard);
    }

    return DirectionalEvidenceResult(
      components: components,
      stockEvidence: stockEvidence,
      marketBias: market.marketBias,
      directionScore: guardedDirectionScore,
      marketRegime: market.marketRegime,
      guardReasons: guardReasons,
      dataQualityFlags: dataQualityFlags,
      signalComponentOwnership: signalOwnership,
    );
  }

  static Map<String, double> _emptyComponents() {
    return const <String, double>{
      trendComponentKey: 0,
      reversalMomentumComponentKey: 0,
      volumeFlowComponentKey: 0,
      relativeStrengthComponentKey: 0,
      nextSessionComponentKey: 0,
    };
  }

  static Map<String, double> _signalComponents(
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
    Map<String, String> ownership,
  ) {
    final componentValues = <String, List<double>>{
      trendComponentKey: <double>[],
      reversalMomentumComponentKey: <double>[],
      volumeFlowComponentKey: <double>[],
      relativeStrengthComponentKey: <double>[],
      nextSessionComponentKey: <double>[],
    };
    final seen = <int>{};

    void apply(SignalItem signal, double direction) {
      final identity = identityHashCode(signal);
      if (!seen.add(identity)) {
        return;
      }

      final component = _componentForSignal(signal);
      final key = _signalKey(signal, identity);
      ownership[key] = component;
      componentValues[component]!.add(direction * _signalStrength(signal));
    }

    for (final signal in buySignals) {
      apply(signal, 1);
    }
    for (final signal in sellSignals) {
      apply(signal, -1);
    }

    return componentValues.map<String, double>((key, values) {
      if (values.isEmpty) {
        return MapEntry<String, double>(key, 0);
      }
      final average = values.reduce((a, b) => a + b) / values.length;
      return MapEntry<String, double>(key, _clampUnit(average));
    });
  }

  static String _componentForSignal(SignalItem signal) {
    final text = '${signal.indicator} ${signal.signal} ${signal.description}'
        .toLowerCase();
    if (_containsAny(text, const <String>[
      'rsi',
      'kdj',
      'wr',
      'bias',
      'cci',
      'reversal',
      'oversold',
      'overbought',
    ])) {
      return reversalMomentumComponentKey;
    }
    if (_containsAny(text, const <String>[
      'volume',
      'vol',
      'obv',
      'flow',
      'fund',
      'turnover',
    ])) {
      return volumeFlowComponentKey;
    }
    if (_containsAny(text, const <String>[
      'relative',
      'industry',
      'sector',
      'rs',
    ])) {
      return relativeStrengthComponentKey;
    }
    if (_containsAny(text, const <String>[
      'next',
      'prediction',
      'session',
    ])) {
      return nextSessionComponentKey;
    }
    return trendComponentKey;
  }

  static bool _containsAny(String text, List<String> tokens) {
    return tokens.any(text.contains);
  }

  static String _signalKey(SignalItem signal, int identity) {
    return '$identity:${signal.type}:${signal.indicator}:${signal.signal}';
  }

  static double _signalStrength(SignalItem signal) {
    final durationWeight = switch (signal.duration) {
      SignalDuration.shortTerm => 1.0,
      SignalDuration.mediumTerm => 0.75,
      SignalDuration.longTerm => 0.45,
      null => 0.75,
    };
    final confidence = (signal.confidence?.clamp(0.4, 1.0) ?? 0.8).toDouble();
    return _clampUnit((signal.strength / 10) * durationWeight * confidence);
  }

  static double _priceTrend(List<HistoryKline> data) {
    var value = 0.0;
    final last = data.last;
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
        value += 0.45;
      } else if (last.ma5 < last.ma10 && last.ma10 < last.ma20) {
        value -= 0.45;
      }
    }

    if (data.length >= 4) {
      final ref = data[data.length - 4].close;
      if (ref > 0 && last.close > 0) {
        final change3d = (last.close / ref - 1) * 100;
        if (change3d >= 3) {
          value += 0.20;
        } else if (change3d <= -3) {
          value -= 0.20;
        }
      }
    }

    if (last.adx14 >= 25 && last.plusDi14 > last.minusDi14) {
      value += 0.20;
    } else if (last.adx14 >= 25 && last.minusDi14 > last.plusDi14) {
      value -= 0.20;
    }

    return _clampUnit(value);
  }

  static double _marketStructureTrend(MarketStructureResult? structure) {
    if (structure == null) return 0;
    return switch (structure.structure) {
      MarketStructure.bullTrend => 0.35 * structure.confidence,
      MarketStructure.bearTrend => -0.35 * structure.confidence,
      MarketStructure.accumulation => 0.15 * structure.confidence,
      MarketStructure.distribution => -0.15 * structure.confidence,
      MarketStructure.consolidation => 0,
    };
  }

  static double _reversalMomentum(HistoryKline last) {
    var value = 0.0;
    if (last.rsi6 > 0) {
      if (last.rsi6 <= 30) {
        value += 0.30;
      } else if (last.rsi6 >= 70) {
        value -= 0.30;
      }
    }

    final wr14 = last.wr14;
    if (wr14 != null && wr14 > 0) {
      if (wr14 >= 80) {
        value += 0.20;
      } else if (wr14 <= 20) {
        value -= 0.20;
      }
    }

    if (last.k > 0 && last.d > 0) {
      if (last.k <= 25 && last.k > last.d) {
        value += 0.20;
      } else if (last.k >= 75 && last.k < last.d) {
        value -= 0.20;
      }
    }

    if (last.bias6.isFinite) {
      if (last.bias6 <= -6) {
        value += 0.15;
      } else if (last.bias6 >= 8) {
        value -= 0.15;
      }
    }

    return _clampUnit(value);
  }

  static double _volumeFlow(HistoryKline last, QuoteData? quote) {
    var value = 0.0;

    if (last.volMa5 > 0 && last.volume > 0) {
      final volumeRatio = last.volume / last.volMa5;
      if (last.close >= last.open && volumeRatio >= 1.4) {
        value += 0.55;
      } else if (last.close < last.open && volumeRatio >= 1.3) {
        value -= 0.65;
      } else if (last.close >= last.open && volumeRatio < 0.7) {
        value -= 0.20;
      }
    }

    if (quote != null) {
      if (quote.mainNetFlowRate >= 5) {
        value += 0.35;
      } else if (quote.mainNetFlowRate <= -5) {
        value -= 0.35;
      }
      if (quote.volumeRatio >= 1.5 && quote.changePct > 0) {
        value += 0.20;
      } else if (quote.volumeRatio >= 1.5 && quote.changePct < 0) {
        value -= 0.20;
      }
    }

    return _clampUnit(value);
  }

  static double _relativeStrength(double? industryRelativeStrength) {
    if (industryRelativeStrength == null ||
        !industryRelativeStrength.isFinite) {
      return 0;
    }
    final normalized = industryRelativeStrength.abs() > 1
        ? industryRelativeStrength / 100
        : industryRelativeStrength;
    return _clampUnit(normalized);
  }

  static double _nextSession(
    NextDayPredictionResult nextDay,
    NextSessionPrediction nextSession,
  ) {
    final nextDayEdge = nextDay.upProbability - nextDay.downProbability;
    final nextCloseEdge = (nextSession.nextCloseUpProbability - 0.5) * 2;
    final returnEdge =
        (nextSession.expectedNextCloseReturn / 3).clamp(-1.0, 1.0).toDouble();
    final riskEdge = ((0.5 - nextSession.downsideRiskProbability) * 2)
        .clamp(-1.0, 1.0)
        .toDouble();
    final confidence = nextSession.confidence.clamp(0.0, 1.0).toDouble();

    return _clampUnit(
      nextDayEdge * 0.30 +
          nextCloseEdge * 0.30 * confidence +
          returnEdge * 0.25 * confidence +
          riskEdge * 0.15 * confidence,
    );
  }

  static double _combine(double first, [double second = 0, double third = 0]) {
    return _clampUnit(first + second + third);
  }

  /// 超跌反弹保护：检查是否处于深度超卖状态
  /// v3.3: WR14为null时使用bias6作为备选超卖确认指标，避免无WR14数据的股票绕过保护
  static bool _hasOversoldReboundSetup(List<HistoryKline> data) {
    if (data.length < 4) return false;
    final last = data.last;
    final ref = data[data.length - 4].close;
    if (ref <= 0 || last.close <= 0) return false;
    final change3d = (last.close / ref - 1) * 100;
    if (change3d > -5 || last.rsi6 > 30) return false;
    // WR14高值=超卖(>=80), bias6深度负值=-超卖(<=-8)
    // 优先使用WR14，无数据时使用bias6作为备选
    if (last.wr14 != null) return last.wr14! >= 80;
    return last.bias6 <= -8;
  }

  /// 追高保护：检查是否处于追高涨态
  /// v3.3: WR14为null时使用bias6作为备选超买确认指标
  static bool _hasChaseSetup(HistoryKline last, QuoteData? quote) {
    final dailyRise = last.changePct >= 8 || (quote?.changePct ?? 0) >= 8;
    if (!dailyRise) return false;
    if (last.rsi6 >= 70) return true;
    // WR14低值=超买(<=20), bias6高值=超买(>=8)
    if (last.wr14 != null) return last.wr14! <= 20;
    return last.bias6 >= 8;
  }

  static double _clampUnit(double value) {
    return value.clamp(-1.0, 1.0).toDouble();
  }
}
