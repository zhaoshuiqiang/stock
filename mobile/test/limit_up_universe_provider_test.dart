import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_universe_provider.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('LimitUpUniverseProvider', () {
    test('mergeAndDedup removes duplicate codes', () {
      final today = [
        LimitUpStock(code: '600519', name: '茅台', consecutiveDays: 3, sealAmount: 23000),
        LimitUpStock(code: '000001', name: '平安银行', consecutiveDays: 1),
      ];
      final fresh = [
        LimitUpStock(code: '600519', name: '茅台', consecutiveDays: 3, sealAmount: 25000),
        LimitUpStock(code: '000002', name: '万科A', consecutiveDays: 2),
      ];
      final merged = LimitUpUniverseProvider.mergeAndDedup(today, fresh);
      expect(merged, hasLength(3));
      final maotai = merged.firstWhere((s) => s.code == '600519');
      expect(maotai.sealAmount, 25000);  // fresh 覆盖 today
    });

    test('supplementQuotes fills price and changePct (with dot prefix)', () {
      final stocks = [
        LimitUpStock(code: '600519', name: '茅台'),
      ];
      final quotes = [
        QuoteData(code: 'sh.600519', name: '茅台', price: 1689.5, changePct: 10.0),
      ];
      final result = LimitUpUniverseProvider.supplementQuotes(stocks, quotes);
      expect(result.first.price, 1689.5);
      expect(result.first.changePct, 10.0);
    });

    test('supplementQuotes handles no-dot prefix (sh600519)', () {
      // ApiClient.addMarketPrefix returns 'sh600519' (no dot) — must also work
      final stocks = [
        LimitUpStock(code: '000001', name: '平安银行'),
      ];
      final quotes = [
        QuoteData(code: 'sz000001', name: '平安银行', price: 12.5, changePct: 3.2),
      ];
      final result = LimitUpUniverseProvider.supplementQuotes(stocks, quotes);
      expect(result.first.price, 12.5);
      expect(result.first.changePct, 3.2);
    });

    test('supplementQuotes leaves stock unchanged when no quote matches', () {
      final stocks = [
        LimitUpStock(code: '600519', name: '茅台', sealAmount: 5000),
      ];
      final quotes = <QuoteData>[];  // no quotes
      final result = LimitUpUniverseProvider.supplementQuotes(stocks, quotes);
      expect(result.first.code, '600519');
      expect(result.first.sealAmount, 5000);  // original preserved
      expect(result.first.price, 0);  // default unchanged
    });
  });
}
