import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/evidence_confidence_calculator.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('uses the specified confidence component weights', () {
    expect(EvidenceConfidenceCalculator.weights, {
      'component_agreement': 0.25,
      'data_coverage': 0.20,
      'freshness': 0.15,
      'history_stability': 0.10,
      'fundamental_support': 0.10,
      'sentiment_confirm': 0.08,
      'market_environment': 0.07,
      'backtest_winrate': 0.05,
    });
  });

  test('independent agreement, coverage, and freshness raise confidence', () {
    final now = DateTime(2026, 7, 15);
    final weak = EvidenceConfidenceCalculator.calculate(
      directionComponents: const {
        'trend': 0.7,
        'reversal_momentum': -0.7,
        'volume_flow': 0,
        'relative_strength': 0,
        'next_session': 0,
      },
      directionalSignals: const [],
      dataQualityFlags: const ['market_context_missing'],
      now: now,
    );
    final strong = EvidenceConfidenceCalculator.calculate(
      directionComponents: const {
        'trend': 0.7,
        'reversal_momentum': 0.6,
        'volume_flow': 0.5,
        'relative_strength': 0.4,
        'next_session': 0.3,
      },
      directionalSignals: [
        _signal(now.subtract(const Duration(hours: 12))),
        _signal(now.subtract(const Duration(days: 1)), indicator: 'MA'),
      ],
      dataQualityFlags: const [],
      now: now,
    );

    expect(strong.componentAgreement, greaterThan(weak.componentAgreement));
    expect(strong.dataCoverage, greaterThan(weak.dataCoverage));
    expect(strong.freshness, greaterThan(weak.freshness));
    expect(strong.score, greaterThan(weak.score));
  });

  test('missing market data lowers confidence', () {
    final complete = EvidenceConfidenceCalculator.calculate(
      directionComponents: const {'trend': 0.5, 'volume_flow': 0.4},
      directionalSignals: const [],
      dataQualityFlags: const [],
    );
    final missing = EvidenceConfidenceCalculator.calculate(
      directionComponents: const {'trend': 0.5, 'volume_flow': 0.4},
      directionalSignals: const [],
      dataQualityFlags: const ['market_context_missing'],
    );

    expect(missing.dataCoverage, lessThan(complete.dataCoverage));
    expect(missing.score, lessThan(complete.score));
  });

  test('defaults immature history stability to exactly 50', () {
    final result = EvidenceConfidenceCalculator.calculate(
      directionComponents: const {},
      directionalSignals: const [],
      dataQualityFlags: const [],
    );

    expect(result.historyStability, 50);
    expect(result.components.containsKey('probability'), isFalse);
    expect(result.score, inInclusiveRange(0, 100));
  });

  test('clamps custom history stability and total score', () {
    final result = EvidenceConfidenceCalculator.calculate(
      directionComponents: const {'trend': 10, 'volume_flow': 10},
      directionalSignals: [_signal(DateTime(2030), confidence: 4)],
      dataQualityFlags: const [],
      historicalStability: 500,
    );

    expect(result.historyStability, 100);
    for (final value in [...result.components.values, result.score]) {
      expect(value, inInclusiveRange(0, 100));
    }
  });
}

SignalItem _signal(
  DateTime freshTime, {
  String indicator = 'RSI',
  double confidence = 0.8,
}) {
  return SignalItem(
    type: 'buy',
    indicator: indicator,
    signal: 'test',
    strength: 3,
    duration: SignalDuration.shortTerm,
    confidence: confidence,
    freshTime: freshTime,
  );
}
