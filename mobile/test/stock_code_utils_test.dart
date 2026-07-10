import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/core/stock_code_utils.dart';

void main() {
  group('StockCodeUtils', () {
    test('normalizes raw A-share codes to market-prefixed lowercase codes', () {
      expect(StockCodeUtils.normalizeForArchive('600519'), equals('sh600519'));
      expect(StockCodeUtils.normalizeForArchive('000001'), equals('sz000001'));
      expect(StockCodeUtils.normalizeForArchive('300750'), equals('sz300750'));
      expect(StockCodeUtils.normalizeForArchive('830799'), equals('bj830799'));
    });

    test('normalizes existing market prefixes and preserves unknown codes', () {
      expect(
          StockCodeUtils.normalizeForArchive('SH600519'), equals('sh600519'));
      expect(
          StockCodeUtils.normalizeForArchive('sz000001'), equals('sz000001'));
      expect(
          StockCodeUtils.normalizeForArchive(' hk00700 '), equals('hk00700'));
      expect(StockCodeUtils.stripMarketPrefix('SZ000001'), equals('000001'));
    });
  });
}
