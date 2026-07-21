import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/ai_layer.dart';

/// Better Loop F2: deterministic coverage for the AI layer's fallback path and
/// output contracts. The live network path (ChatCompletionLayer) creates its
/// own http.Client with no injection seam, so these tests exercise the safe,
/// offline behavior that must never regress: the NullAILayer fallback, provider
/// resolution, the singleton provider, and the result value objects.
void main() {
  group('AIProvider', () {
    test('fromString maps known provider names', () {
      expect(AIProvider.fromString('zhipu'), AIProvider.zhipu);
      expect(AIProvider.fromString('openrouter'), AIProvider.openrouter);
      expect(AIProvider.fromString('cliproxyapi'), AIProvider.cliproxyapi);
    });

    test('fromString falls back to zhipu for unknown/empty names', () {
      expect(AIProvider.fromString('does-not-exist'), AIProvider.zhipu);
      expect(AIProvider.fromString(''), AIProvider.zhipu);
    });

    test('every provider exposes a usable endpoint/model/label', () {
      for (final p in AIProvider.values) {
        expect(p.label.trim(), isNotEmpty);
        expect(p.defaultModel.trim(), isNotEmpty);
        expect(
          p.endpoint,
          anyOf(startsWith('http://'), startsWith('https://')),
        );
      }
    });
  });

  group('result value objects', () {
    test('AIChatResult.withError sets error and leaves answer empty', () {
      final r = AIChatResult.withError('Q', 'boom');
      expect(r.question, 'Q');
      expect(r.answer, isEmpty);
      expect(r.error, 'boom');
    });

    test('DebateResult.empty has no error and an empty synthesis', () {
      final r = DebateResult.empty();
      expect(r.error, isNull);
      expect(r.synthesis.conclusion, isEmpty);
      expect(r.synthesis.reasons, isEmpty);
      expect(r.synthesis.riskFactors, isEmpty);
    });

    test('DebateResult.withError carries the error message', () {
      expect(DebateResult.withError('bad').error, 'bad');
    });

    test('AISentimentResult.empty is a neutral zero result', () {
      final r = AISentimentResult.empty();
      expect(r.score, 0);
      expect(r.positiveCount, 0);
      expect(r.negativeCount, 0);
      expect(r.neutralCount, 0);
      expect(r.keyFactors, isEmpty);
    });
  });

  group('NullAILayer fallback', () {
    final layer = AILayer.nullLayer();

    test('is unavailable and reports a valid provider', () {
      expect(layer.isAvailable, isFalse);
      expect(AIProvider.values.contains(layer.provider), isTrue);
    });

    test('analyzeSentiment returns an empty neutral result', () async {
      final r = await layer.analyzeSentiment(['title-a', 'title-b']);
      expect(r.score, 0);
      expect(r.keyFactors, isEmpty);
    });

    test('runDebate returns an empty debate', () async {
      final r = await layer.runDebate(
        stockCode: '600000',
        stockName: 'X',
        technicalData: const {},
        newsTitles: const [],
        historicalReflections: const [],
      );
      expect(r.synthesis.conclusion, isEmpty);
      expect(r.bullCase, isNull);
      expect(r.bearCase, isNull);
    });

    test('generateReflection returns an empty string', () async {
      final r = await layer.generateReflection(
        stockCode: '600000',
        stockName: 'X',
        signalPrice: 1.0,
        signalDate: DateTime(2026, 1, 1),
        realizedReturn: 0.0,
        alphaVsMarket: 0.0,
        originalRecommendation: 'hold',
      );
      expect(r, isEmpty);
    });

    test('template/custom/portfolio calls return an errored chat result',
        () async {
      final t = await layer.analyzeByTemplate(
        template: AnalysisTemplate.shortTerm,
        stockCode: '1',
        stockName: 'X',
        technicalData: const {},
        newsTitles: const [],
      );
      expect(t.answer, isEmpty);
      expect(t.error, isNotNull);
      expect(t.error, isNotEmpty);

      final c = await layer.askCustomQuestion(
        question: 'why',
        stockCode: '1',
        stockName: 'X',
        technicalData: const {},
        newsTitles: const [],
      );
      expect(c.answer, isEmpty);
      expect(c.error, isNotNull);

      final p = await layer.analyzePortfolio(
        positions: const [],
        totalCost: 0,
        totalMarketValue: 0,
        totalPnlPct: 0,
      );
      expect(p.answer, isEmpty);
      expect(p.error, isNotNull);
    });
  });

  group('AILayerProvider singleton', () {
    tearDown(AILayerProvider.reset);

    test('defaults to a NullAILayer when unset', () {
      AILayerProvider.reset();
      expect(AILayerProvider.instance, isA<NullAILayer>());
      expect(AILayerProvider.instance.isAvailable, isFalse);
    });

    test('set installs a custom layer; reset restores the null layer', () {
      final custom = AILayer.nullLayer();
      AILayerProvider.set(custom);
      expect(identical(AILayerProvider.instance, custom), isTrue);
      AILayerProvider.reset();
      expect(AILayerProvider.instance, isA<NullAILayer>());
    });
  });
}
