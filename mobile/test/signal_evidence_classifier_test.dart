import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/signal_evidence_classifier.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('SignalEvidenceClassifier', () {
    test('classifies Chinese volume pattern divergence and gap vocabulary', () {
      expect(_classify('量价', '放量上涨').component, 'volume_flow');
      expect(_classify('量价', '放量上涨').family, 'volume_price');
      expect(_classify('K线形态', '启明星').component, 'reversal_momentum');
      expect(_classify('K线形态', '启明星').family, 'candlestick_reversal');
      expect(_classify('MACD', 'MACD顶背离').component, 'reversal_momentum');
      expect(_classify('MACD', 'MACD顶背离').family, 'macd_divergence');
      expect(_classify('缺口', '向上跳空突破').component, 'reversal_momentum');
      expect(_classify('缺口', '向上跳空突破').family, 'gap_reversal');
    });

    test('assigns trend indicators to stable independent families', () {
      expect(_classify('MA', '均线多头排列').family, 'ma');
      expect(_classify('ADX', '趋势强度强劲').family, 'adx');
      expect(_classify('MACD', 'MACD金叉').family, 'macd_trend');
      expect(_classify('BOLL', '趋势突破上轨').family, 'boll_trend');
    });

    test('does not route ordinary signals into reserved model components', () {
      final rsi = _classify('RSI', 'RSI超卖');
      final relativeText = _classify('形态', 'relative strength breakout');
      final nextText = _classify('形态', 'next session prediction');

      expect(rsi.component, 'reversal_momentum');
      expect(relativeText.component, isNot('relative_strength'));
      expect(nextText.component, isNot('next_session'));
    });
  });

  group('SignalConfluenceAnnotator', () {
    test('preserves confidence and counts independent directional components',
        () {
      final signals = <SignalItem>[
        _signal('buy', 'MA', confidence: 0.61),
        _signal('buy', 'ADX', confidence: 0.62),
        _signal('buy', 'RSI', confidence: 0.63),
        _signal('buy', '量价', confidence: 0.64),
        _signal('sell', 'MACD', confidence: 0.65),
      ];

      final annotated = SignalConfluenceAnnotator.annotate(signals);

      expect(annotated.take(4).map((signal) => signal.signalCount),
          everyElement(3));
      expect(annotated.last.signalCount, 1);
      expect(
        annotated.map((signal) => signal.confidence),
        orderedEquals(<double?>[0.61, 0.62, 0.63, 0.64, 0.65]),
      );
    });

    test('repeated indicators do not increase confidence or coverage', () {
      final signals = <SignalItem>[
        _signal('buy', 'MA', signal: 'MA5上穿MA10', confidence: 0.55),
        _signal('buy', 'MA', signal: '均线多头排列', confidence: 0.70),
      ];

      final annotated = SignalConfluenceAnnotator.annotate(signals);

      expect(annotated.map((signal) => signal.signalCount), everyElement(1));
      expect(annotated.first.confidence, 0.55);
      expect(annotated.last.confidence, 0.70);
    });
  });
}

SignalEvidenceClassification _classify(String indicator, String signal) =>
    SignalEvidenceClassifier.classify(
      _signal('buy', indicator, signal: signal),
    );

SignalItem _signal(
  String type,
  String indicator, {
  String signal = 'test',
  double confidence = 0.8,
}) =>
    SignalItem(
      type: type,
      indicator: indicator,
      signal: signal,
      strength: 60,
      confidence: confidence,
      duration: SignalDuration.shortTerm,
    );
