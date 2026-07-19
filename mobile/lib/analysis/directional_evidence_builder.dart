import 'market_regime_classifier.dart';
import 'market_structure_analyzer.dart';
import 'next_day_predictor.dart';
import 'next_session_prediction.dart';
import 'sector_momentum_calculator.dart';
import 'signal_evidence_classifier.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

const String trendComponentKey = 'trend';
const String reversalMomentumComponentKey = 'reversal_momentum';
const String volumeFlowComponentKey = 'volume_flow';
const String relativeStrengthComponentKey = 'relative_strength';
const String nextSessionComponentKey = 'next_session';
const String sectorMomentumComponentKey = 'sector_momentum';

const String oversoldReboundGuard = 'oversold_rebound_guard';
const String chaseGuard = 'chase_guard';
const String historyDataMissingFlag = 'history_data_missing';
const String quoteDataMissingFlag = 'quote_data_missing';
const String evidenceFamilyConflictFlag = 'evidence_family_conflict';

class DirectionalEvidenceInput {
  final List<HistoryKline> data;
  final List<SignalItem> buySignals;
  final List<SignalItem> sellSignals;
  final QuoteData? quote;
  final MarketContext? marketContext;
  final MarketStructureResult? marketStructure;
  final double? stockLastCompletedChangePct;
  final NextDayPredictionResult nextDayPrediction;
  final NextSessionPrediction nextSessionPrediction;
  final SectorMomentumResult? sectorMomentum;

  DirectionalEvidenceInput({
    required this.data,
    required this.buySignals,
    required this.sellSignals,
    this.quote,
    this.marketContext,
    this.marketStructure,
    this.stockLastCompletedChangePct,
    required this.nextDayPrediction,
    required this.nextSessionPrediction,
    this.sectorMomentum,
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

class _EvidenceObservation {
  final String component;
  final String family;
  final double signedValue;
  final String source;

  const _EvidenceObservation({
    required this.component,
    required this.family,
    required this.signedValue,
    required this.source,
  });
}

class _FamilyAccumulator {
  double? strongestPositive;
  double? strongestNegative;

  void add(double value) {
    if (value > 0 &&
        (strongestPositive == null || value > strongestPositive!)) {
      strongestPositive = value;
    } else if (value < 0 &&
        (strongestNegative == null || value < strongestNegative!)) {
      strongestNegative = value;
    }
  }

  bool get hasConflict =>
      strongestPositive != null && strongestNegative != null;

  double get value {
    if (hasConflict) {
      return (strongestPositive! + strongestNegative!) / 2;
    }
    return strongestPositive ?? strongestNegative ?? 0;
  }
}

class _AggregatedEvidence {
  final Map<String, double> components;
  final bool hasFamilyConflict;

  const _AggregatedEvidence({
    required this.components,
    required this.hasFamilyConflict,
  });
}

class DirectionalEvidenceBuilder {
  static const Map<String, double> componentWeights = <String, double>{
    trendComponentKey: 0.25,
    reversalMomentumComponentKey: 0.25,
    volumeFlowComponentKey: 0.20,
    relativeStrengthComponentKey: 0.15,
    nextSessionComponentKey: 0.05,
    sectorMomentumComponentKey: 0.10,
  };

  /// v4.3: optional data-driven override for [componentWeights], installed by
  /// DirectionalWeightOptimizer when ScoringConfig.useDynamicDirectionWeights is
  /// on. Null == use the static defaults (byte-identical to pre-v4.3 behavior).
  static Map<String, double>? _weightOverride;

  /// Weights actually used to fold evidence into the direction score.
  static Map<String, double> get effectiveWeights =>
      _weightOverride ?? componentWeights;

  /// Install (null clears) the dynamic weight override. Callers must pass a map
  /// with the same keys as [componentWeights]; normalization is the caller's job.
  static void applyWeightOverride(Map<String, double>? weights) {
    _weightOverride = weights;
  }

  static DirectionalEvidenceResult build(DirectionalEvidenceInput input) {
    final market = MarketRegimeClassifier.classify(input.marketContext);
    final dataQualityFlags = <String>[...market.dataQualityFlags];
    final guardReasons = <String>[];
    final signalOwnership = <String, String>{};

    if (input.quote == null ||
        !input.quote!.price.isFinite ||
        input.quote!.price <= 0) {
      dataQualityFlags.add(quoteDataMissingFlag);
    }

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

    final observations = <_EvidenceObservation>[
      ..._priceTrendEvidence(input.data),
      ..._marketStructureEvidence(input.marketStructure),
      ..._reversalMomentumEvidence(input.data.last),
      ..._volumeFlowEvidence(input.data.last, input.quote),
      _EvidenceObservation(
        component: relativeStrengthComponentKey,
        family: 'relative_strength',
        signedValue: _relativeStrength(
          input.stockLastCompletedChangePct,
          input.marketContext,
          market,
        ),
        source: 'numeric',
      ),
      ..._nextSessionEvidence(
        input.nextDayPrediction,
        input.nextSessionPrediction,
      ),
      _EvidenceObservation(
        component: sectorMomentumComponentKey,
        family: 'sector_momentum',
        signedValue: input.sectorMomentum?.score ?? 0,
        source: 'sector_momentum',
      ),
      ..._signalEvidence(
        input.buySignals,
        input.sellSignals,
        signalOwnership,
      ),
    ];
    final aggregated = _aggregateEvidence(observations);
    final components = aggregated.components;
    if (aggregated.hasFamilyConflict) {
      dataQualityFlags.add(evidenceFamilyConflictFlag);
    }
    final trend = components[trendComponentKey] ?? 0;
    final volumeFlow = components[volumeFlowComponentKey] ?? 0;

    final stockEvidence = 100 *
        effectiveWeights.entries.fold<double>(
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
        _consecutiveRiseDays(input.data) >= 3 &&
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
      dataQualityFlags: dataQualityFlags.toSet().toList(growable: false),
      signalComponentOwnership: signalOwnership,
    );
  }

  static Map<String, double> _emptyComponents() {
    return <String, double>{
      trendComponentKey: 0,
      reversalMomentumComponentKey: 0,
      volumeFlowComponentKey: 0,
      relativeStrengthComponentKey: 0,
      nextSessionComponentKey: 0,
      sectorMomentumComponentKey: 0,
    };
  }

  static List<_EvidenceObservation> _signalEvidence(
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
    Map<String, String> ownership,
  ) {
    final observations = <_EvidenceObservation>[];
    final seen = <int>{};

    void apply(SignalItem signal, double direction) {
      final identity = identityHashCode(signal);
      if (!seen.add(identity)) {
        return;
      }

      final classification = SignalEvidenceClassifier.classify(signal);
      final key = _signalKey(signal, identity);
      ownership[key] = classification.component;
      observations.add(_EvidenceObservation(
        component: classification.component,
        family: classification.family,
        signedValue: direction * _signalStrength(signal),
        source: 'signal',
      ));
    }

    for (final signal in buySignals) {
      apply(signal, 1);
    }
    for (final signal in sellSignals) {
      apply(signal, -1);
    }

    return observations;
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
    final confidence = (signal.confidence ?? 0.8).clamp(0.0, 1.0).toDouble();
    return _clampUnit((signal.strength / 100) * durationWeight * confidence);
  }

  static List<_EvidenceObservation> _priceTrendEvidence(
    List<HistoryKline> data,
  ) {
    final values = <_EvidenceObservation>[];
    final last = data.last;
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
        values.add(const _EvidenceObservation(
          component: trendComponentKey,
          family: 'ma',
          signedValue: 0.45,
          source: 'numeric',
        ));
      } else if (last.ma5 < last.ma10 && last.ma10 < last.ma20) {
        values.add(const _EvidenceObservation(
          component: trendComponentKey,
          family: 'ma',
          signedValue: -0.45,
          source: 'numeric',
        ));
      }
    }

    if (data.length >= 4) {
      final ref = data[data.length - 4].close;
      if (ref > 0 && last.close > 0) {
        final change3d = (last.close / ref - 1) * 100;
        if (change3d >= 3) {
          values.add(const _EvidenceObservation(
            component: trendComponentKey,
            family: 'price_momentum',
            signedValue: 0.20,
            source: 'numeric',
          ));
        } else if (change3d <= -3) {
          values.add(const _EvidenceObservation(
            component: trendComponentKey,
            family: 'price_momentum',
            signedValue: -0.20,
            source: 'numeric',
          ));
        }
      }
    }

    if (last.adx14 >= 25 && last.plusDi14 > last.minusDi14) {
      values.add(const _EvidenceObservation(
        component: trendComponentKey,
        family: 'adx',
        signedValue: 0.20,
        source: 'numeric',
      ));
    } else if (last.adx14 >= 25 && last.minusDi14 > last.plusDi14) {
      values.add(const _EvidenceObservation(
        component: trendComponentKey,
        family: 'adx',
        signedValue: -0.20,
        source: 'numeric',
      ));
    }

    return values;
  }

  static List<_EvidenceObservation> _marketStructureEvidence(
    MarketStructureResult? structure,
  ) {
    if (structure == null) return const <_EvidenceObservation>[];
    final value = switch (structure.structure) {
      MarketStructure.bullTrend => 0.35 * structure.confidence,
      MarketStructure.bearTrend => -0.35 * structure.confidence,
      MarketStructure.accumulation => 0.15 * structure.confidence,
      MarketStructure.distribution => -0.15 * structure.confidence,
      MarketStructure.consolidation => 0,
    };
    if (value == 0) return const <_EvidenceObservation>[];
    return <_EvidenceObservation>[
      _EvidenceObservation(
        component: trendComponentKey,
        family: 'market_structure',
        signedValue: value.toDouble(),
        source: 'numeric',
      ),
    ];
  }

  static List<_EvidenceObservation> _reversalMomentumEvidence(
    HistoryKline last,
  ) {
    final values = <_EvidenceObservation>[];
    if (last.rsi6 > 0) {
      if (last.rsi6 <= 30) {
        values.add(_numeric(reversalMomentumComponentKey, 'rsi', 0.30));
      } else if (last.rsi6 >= 70) {
        values.add(_numeric(reversalMomentumComponentKey, 'rsi', -0.30));
      }
    }

    final wr14 = last.wr14;
    if (wr14 != null && wr14 > 0) {
      if (wr14 >= 80) {
        values.add(_numeric(reversalMomentumComponentKey, 'wr', 0.20));
      } else if (wr14 <= 20) {
        values.add(_numeric(reversalMomentumComponentKey, 'wr', -0.20));
      }
    }

    if (last.k > 0 && last.d > 0) {
      if (last.k <= 25 && last.k > last.d) {
        values.add(_numeric(reversalMomentumComponentKey, 'kdj', 0.20));
      } else if (last.k >= 75 && last.k < last.d) {
        values.add(_numeric(reversalMomentumComponentKey, 'kdj', -0.20));
      }
    }

    if (last.bias6.isFinite) {
      if (last.bias6 <= -6) {
        values.add(_numeric(reversalMomentumComponentKey, 'bias', 0.15));
      } else if (last.bias6 >= 8) {
        values.add(_numeric(reversalMomentumComponentKey, 'bias', -0.15));
      }
    }

    return values;
  }

  static List<_EvidenceObservation> _volumeFlowEvidence(
    HistoryKline last,
    QuoteData? quote,
  ) {
    final values = <_EvidenceObservation>[];

    if (last.volMa5 > 0 && last.volume > 0) {
      final volumeRatio = last.volume / last.volMa5;
      if (last.close >= last.open && volumeRatio >= 1.4) {
        values.add(_numeric(volumeFlowComponentKey, 'volume_price', 0.55));
      } else if (last.close < last.open && volumeRatio >= 1.3) {
        values.add(_numeric(volumeFlowComponentKey, 'volume_price', -0.65));
      } else if (last.close >= last.open && volumeRatio < 0.7) {
        values.add(_numeric(volumeFlowComponentKey, 'volume_price', -0.20));
      }
    }

    if (quote != null) {
      if (quote.mainNetFlowRate >= 5) {
        values.add(_numeric(volumeFlowComponentKey, 'capital_flow', 0.35));
      } else if (quote.mainNetFlowRate <= -5) {
        values.add(_numeric(volumeFlowComponentKey, 'capital_flow', -0.35));
      }
      if (quote.volumeRatio >= 1.5 && quote.changePct > 0) {
        values.add(_numeric(volumeFlowComponentKey, 'volume_price', 0.20));
      } else if (quote.volumeRatio >= 1.5 && quote.changePct < 0) {
        values.add(_numeric(volumeFlowComponentKey, 'volume_price', -0.20));
      }
    }

    return values;
  }

  static double _relativeStrength(
    double? stockLastCompletedChangePct,
    MarketContext? context,
    MarketRegimeClassification classification,
  ) {
    if (stockLastCompletedChangePct == null ||
        !stockLastCompletedChangePct.isFinite ||
        context == null ||
        classification.dataQualityFlags.contains(marketContextMissingFlag) ||
        classification.dataQualityFlags.contains(marketContextInvalidFlag)) {
      return 0;
    }
    return _clampUnit(
      (stockLastCompletedChangePct - context.avgChangePct) / 5,
    );
  }

  static List<_EvidenceObservation> _nextSessionEvidence(
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
    final sessionEdge = _clampUnit(
      (nextCloseEdge * 0.40 + returnEdge * 0.35 + riskEdge * 0.25) * confidence,
    );
    return <_EvidenceObservation>[
      _numeric(nextSessionComponentKey, 'next_day_model', nextDayEdge),
      _numeric(nextSessionComponentKey, 'next_session_model', sessionEdge),
    ];
  }

  static _EvidenceObservation _numeric(
    String component,
    String family,
    double value,
  ) {
    return _EvidenceObservation(
      component: component,
      family: family,
      signedValue: _clampUnit(value),
      source: 'numeric',
    );
  }

  static _AggregatedEvidence _aggregateEvidence(
    List<_EvidenceObservation> observations,
  ) {
    final families = <String, Map<String, _FamilyAccumulator>>{};
    for (final observation in observations) {
      if (!observation.signedValue.isFinite) continue;
      families
          .putIfAbsent(
              observation.component, () => <String, _FamilyAccumulator>{})
          .putIfAbsent(observation.family, _FamilyAccumulator.new)
          .add(_clampUnit(observation.signedValue));
    }

    var hasConflict = false;
    final components = _emptyComponents();
    for (final component in components.keys) {
      final values =
          families[component]?.values.toList() ?? const <_FamilyAccumulator>[];
      if (values.isEmpty) continue;
      hasConflict = hasConflict || values.any((family) => family.hasConflict);
      components[component] = _clampUnit(
        values.fold<double>(0, (sum, family) => sum + family.value) /
            values.length,
      );
    }
    return _AggregatedEvidence(
      components: components,
      hasFamilyConflict: hasConflict,
    );
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

  static int _consecutiveRiseDays(List<HistoryKline> data) {
    if (data.length < 2) return 0;
    int count = 0;
    for (int i = data.length - 1; i >= 0; i--) {
      if (data[i].close > data[i].open && data[i].changePct > 0) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static double _clampUnit(double value) {
    return value.clamp(-1.0, 1.0).toDouble();
  }
}
