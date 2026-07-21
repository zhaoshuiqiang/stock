import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/realtime_scorer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('RealtimeScorer', () {
    test('null quote returns neutral score (5.0)', () {
      expect(RealtimeScorer.score(null), equals(5.0));
    });

    test('quote with price <= 0 returns neutral score (5.0)', () {
      final quote = QuoteData(code: '000001', name: '测试', price: 0);
      expect(RealtimeScorer.score(quote), equals(5.0));
    });

    test('strong rise gets high score (倒U型评分抑制追高)', () {
      final quote = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: 9.0,
        turnover: 3.0,
        mainNetFlow: 1000000,
        mainNetFlowRate: 12.0,
      );
      expect(RealtimeScorer.score(quote), closeTo(7.3, 0.01));
    });

    test('strong fall gets low score', () {
      final quote = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: -9.0,
        turnover: 15.0,
        mainNetFlow: -1000000,
        mainNetFlowRate: -12.0,
      );
      // base 5.0 - 2.5 (cp<-8) - 1.5 (rate<-6) - 0.2 (turnover 8-15) = 0.8
      expect(RealtimeScorer.score(quote), equals(0.8));
    });

    test('positive fund flow increases score', () {
      final quoteNoFlow = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: 1.0,
        mainNetFlow: 0,
        mainNetFlowRate: 0,
      );
      final quoteWithFlow = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: 1.0,
        mainNetFlow: 1000000,
        mainNetFlowRate: 6.0,
      );
      // v3.34: cp=1.0, cp>1为false→cp>0: +0.5, 5.0 + 0.5 = 5.5
      expect(RealtimeScorer.score(quoteNoFlow), equals(5.5));
      // v3.34: cp=1.0, cp>0:+0.5, rate=6>5:+1.0, 5.0+0.5+1.0=6.5
      expect(RealtimeScorer.score(quoteWithFlow), equals(6.5));
      expect(
        RealtimeScorer.score(quoteWithFlow) > RealtimeScorer.score(quoteNoFlow),
        isTrue,
      );
    });

    test('score is always within 0-10 range even with extreme values', () {
      // Extreme positive
      final extremePositive = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: 20.0,
        turnover: 3.0,
        mainNetFlow: 1000000,
        mainNetFlowRate: 50.0,
      );
      final scorePositive = RealtimeScorer.score(extremePositive);
      expect(scorePositive, greaterThanOrEqualTo(0.0));
      expect(scorePositive, lessThanOrEqualTo(10.0));

      // Extreme negative
      final extremeNegative = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: -20.0,
        turnover: 15.0,
        mainNetFlow: -1000000,
        mainNetFlowRate: -50.0,
      );
      final scoreNegative = RealtimeScorer.score(extremeNegative);
      expect(scoreNegative, greaterThanOrEqualTo(0.0));
      expect(scoreNegative, lessThanOrEqualTo(10.0));
    });

    test('moderate rise with moderate values', () {
      final quote = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: 3.0,
        turnover: 2.0,
        mainNetFlow: 500000,
        mainNetFlowRate: 3.0,
      );
      expect(RealtimeScorer.score(quote), closeTo(7.3, 0.01));
    });

    test('zero turnover does not affect score', () {
      final quote = QuoteData(
        code: '000001',
        name: '测试',
        price: 10.0,
        changePct: 1.0,
        turnover: 0,
      );
      // v3.34: cp=1.0, cp>1为false→cp>0:+0.5, 5.0+0.5=5.5
      expect(RealtimeScorer.score(quote), equals(5.5));
    });

    test('chase zone (3-9%) not rewarded above mild rise (v4.6)', () {
      QuoteData q(double cp) =>
          QuoteData(code: '000001', name: 'T', price: 10.0, changePct: cp);
      // mild rise (2%) should score strictly higher than the 3~9% chase zone
      expect(RealtimeScorer.score(q(2.0)),
          greaterThan(RealtimeScorer.score(q(4.0))));
      expect(RealtimeScorer.score(q(2.0)),
          greaterThan(RealtimeScorer.score(q(7.0))));
    });
  });
}
