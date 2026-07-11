import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/position_valuation.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('PositionValuation', () {
    test('revalues floating PnL from the latest quote', () {
      final position = Position(
        code: '600000',
        name: 'Test',
        quantity: 1000,
        avgPrice: 10,
        latestPrice: 10.1,
        floatPnl: 100,
        pnlPct: 1,
      );
      final quote = QuoteData(
        code: 'sh600000',
        price: 11.2,
        preClose: 10.8,
      );

      final valuation = PositionValuation.fromQuote(position, quote);

      expect(valuation.currentPrice, 11.2);
      expect(valuation.marketValue, closeTo(11200, 0.001));
      expect(valuation.floatPnl, closeTo(1200, 0.001));
      expect(valuation.pnlPct, closeTo(12, 0.001));
      expect(valuation.todayPnl, closeTo(400, 0.001));
      expect(valuation.todayPnlPct, closeTo(3.7037, 0.001));

      final updated = valuation.applyTo(position);
      expect(updated.latestPrice, 11.2);
      expect(updated.floatPnl, closeTo(1200, 0.001));
      expect(updated.pnlPct, closeTo(12, 0.001));
      expect(updated.marketValue, closeTo(11200, 0.001));
      expect(updated.todayPnl, closeTo(400, 0.001));
      expect(updated.todayPnlPct, closeTo(3.7037, 0.001));
    });

    test('falls back to stored latest price when quote has no price', () {
      final position = Position(
        code: '000001',
        name: 'Test',
        quantity: 500,
        avgPrice: 8,
        latestPrice: 8.8,
      );

      final valuation = PositionValuation.fromQuote(
        position,
        QuoteData(code: 'sz000001'),
      );

      expect(valuation.currentPrice, 8.8);
      expect(valuation.floatPnl, closeTo(400, 0.001));
      expect(valuation.pnlPct, closeTo(10, 0.001));
      expect(valuation.todayPnl, 0);
      expect(valuation.todayPnlPct, 0);
    });
  });
}
