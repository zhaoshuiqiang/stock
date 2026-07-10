import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/timeshare_parser.dart';
import 'package:stock_analyzer/core/stock_code_utils.dart';

void main() {
  group('EastMoney timeshare helpers', () {
    test('normalizes raw and prefixed A-share codes to EastMoney secid', () {
      expect(StockCodeUtils.toEastMoneySecId('002384'), equals('0.002384'));
      expect(StockCodeUtils.toEastMoneySecId('sz002384'), equals('0.002384'));
      expect(StockCodeUtils.toEastMoneySecId('SZ002384'), equals('0.002384'));
      expect(StockCodeUtils.toEastMoneySecId('600519'), equals('1.600519'));
      expect(StockCodeUtils.toEastMoneySecId('sh600519'), equals('1.600519'));
      expect(StockCodeUtils.toEastMoneySecId('830799'), equals('0.830799'));
      expect(StockCodeUtils.toEastMoneySecId('hk00700'), equals('hk00700'));
    });

    test(
        'parses EastMoney trend line using close volume amount and vwap fields',
        () {
      final point = TimeshareParser.parseEastMoneyTrendLine(
        '2026-07-10 14:27,248.87,248.60,248.87,248.50,2901,72153789.00,264.632',
      );

      expect(point, isNotNull);
      expect(point!.offset, equals(207));
      expect(point.price, closeTo(248.60, 0.001));
      expect(point.volume, closeTo(2901, 0.001));
      expect(point.amount, closeTo(72153789.00, 0.001));
      expect(point.vwap, closeTo(264.632, 0.001));
    });
  });
}
