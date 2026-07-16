import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/signal_evidence_classifier.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('confluence annotation separates opposite directions', () {
    final annotated = SignalConfluenceAnnotator.annotate(<SignalItem>[
      _signal(type: 'buy', indicator: 'MA', confidence: 0.5),
      _signal(type: 'buy', indicator: 'RSI', confidence: 0.6),
      _signal(type: 'sell', indicator: '量价', confidence: 0.7),
      _signal(type: 'sell', indicator: 'MACD', confidence: 0.8),
    ]);

    expect(
        annotated
            .where((signal) => signal.type == 'buy')
            .map((signal) => signal.signalCount),
        everyElement(2));
    expect(
        annotated
            .where((signal) => signal.type == 'sell')
            .map((signal) => signal.signalCount),
        everyElement(2));
    expect(annotated.map((signal) => signal.confidence),
        orderedEquals(<double?>[0.5, 0.6, 0.7, 0.8]));
  });

  test('annotated signal list remains growable for downstream enrichment', () {
    final annotated = SignalConfluenceAnnotator.annotate(<SignalItem>[
      _signal(type: 'buy', indicator: 'MA', confidence: 0.5),
    ]);

    expect(
      () => annotated.add(
        _signal(type: 'buy', indicator: 'RSI', confidence: 0.6),
      ),
      returnsNormally,
    );
  });
}

SignalItem _signal({
  required String type,
  required String indicator,
  required double confidence,
}) =>
    SignalItem(
      type: type,
      indicator: indicator,
      signal: 'test',
      strength: 60,
      confidence: confidence,
      duration: SignalDuration.shortTerm,
    );
