import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/opportunity_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('cached opportunity analysis passes market context and disables effects',
      () {
    final marketContext = MarketContext(
      shIndexPct: 1,
      szIndexPct: 0.8,
      indexChange: 0.9,
      marketTrend: 'up',
      upCount: 3000,
      downCount: 1200,
      avgChangePct: 0.7,
      updateTime: DateTime(2026, 7, 15),
    );
    MarketContext? receivedContext;
    bool? receivedSideEffects;
    final data = [
      HistoryKline(date: DateTime(2026, 7, 15), close: 10),
    ];

    final result = generateOpportunityAnalysisForTesting(
      calculated: data,
      quote: QuoteData(code: 'sh600001', price: 10),
      marketContext: marketContext,
      generator: (
        calculated,
        quote, {
        marketContext,
        enableAsyncSideEffects = true,
      }) {
        receivedContext = marketContext;
        receivedSideEffects = enableAsyncSideEffects;
        return AnalysisResult(score: 5, recommendation: 'test');
      },
    );

    expect(result.score, 5);
    expect(identical(receivedContext, marketContext), isTrue);
    expect(receivedSideEffects, isFalse);
  });
}
