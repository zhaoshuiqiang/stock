import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/position_risk_advisor.dart';

void main() {
  group('DynamicStopLoss.trailingStop', () {
    test('uses initial percentage floor when price has not advanced', () {
      final stop = DynamicStopLoss.trailingStop(
        entryPrice: 100,
        highestSincePurchase: 100,
        atr: 1,
        atrMultiplier: 2,
        initialStopPct: 0.08,
      );
      // floor = 92; trailing = 100 - 2 = 98 -> higher is 98.
      expect(stop, closeTo(98.0, 1e-9));
    });

    test('ratchets up as the peak rises', () {
      final low = DynamicStopLoss.trailingStop(
          entryPrice: 100, highestSincePurchase: 105, atr: 2);
      final high = DynamicStopLoss.trailingStop(
          entryPrice: 100, highestSincePurchase: 120, atr: 2);
      expect(high, greaterThan(low));
    });

    test('never drops below the initial percentage floor', () {
      final stop = DynamicStopLoss.trailingStop(
        entryPrice: 100,
        highestSincePurchase: 100,
        atr: 10, // wide ATR would push trailing to 80
        atrMultiplier: 2,
        initialStopPct: 0.08,
      );
      expect(stop, closeTo(92.0, 1e-9)); // floor wins
    });

    test('never placed above the peak reference', () {
      final stop = DynamicStopLoss.trailingStop(
          entryPrice: 100, highestSincePurchase: 100, atr: 0);
      expect(stop, lessThanOrEqualTo(100.0));
    });
  });

  group('RiskMonetizer.estimate', () {
    test('maps risk 0 -> 5% and risk 100 -> 25%', () {
      final low = RiskMonetizer.estimate(riskScore: 0, positionValue: 10000);
      final high = RiskMonetizer.estimate(riskScore: 100, positionValue: 10000);
      expect(low.drawdownPct, closeTo(0.05, 1e-9));
      expect(low.amount, closeTo(500, 1e-6));
      expect(high.drawdownPct, closeTo(0.25, 1e-9));
      expect(high.amount, closeTo(2500, 1e-6));
    });

    test('higher risk yields larger drawdown amount', () {
      final a = RiskMonetizer.estimate(riskScore: 30, positionValue: 50000);
      final b = RiskMonetizer.estimate(riskScore: 70, positionValue: 50000);
      expect(b.amount, greaterThan(a.amount));
    });
  });

  group('PositionContextAdvisor.advise', () {
    test('stop triggered when price at or below stop', () {
      final a = PositionContextAdvisor.advise(
          score: 9, currentPrice: 9.5, stopPrice: 10);
      expect(a, PositionAction.stopTriggered);
      expect(PositionContextAdvisor.label(a), '触发止损');
    });

    test('score bands map to add/hold/reduce/exit', () {
      expect(
          PositionContextAdvisor.advise(
              score: 8, currentPrice: 12, stopPrice: 10),
          PositionAction.addPosition);
      expect(
          PositionContextAdvisor.advise(
              score: 5, currentPrice: 12, stopPrice: 10),
          PositionAction.hold);
      expect(
          PositionContextAdvisor.advise(
              score: 3, currentPrice: 12, stopPrice: 10),
          PositionAction.reduce);
      expect(
          PositionContextAdvisor.advise(
              score: 1, currentPrice: 12, stopPrice: 10),
          PositionAction.exit);
    });
  });
}
