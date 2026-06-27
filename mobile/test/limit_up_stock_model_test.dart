import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';

void main() {
  group('LimitUpStock.fromEastMoney', () {
    test('parses full pool element', () {
      final json = {
        'c': '600519',
        'n': '贵州茅台',
        'lbc': 3,
        'fbt': 92500,
        'lbt': 145900,
        'fund': 230000000,
        'hs': 1.23,
        'zbc': 0,
        'hybk': '白酒',
        'ltsz': 21234567890,
        'tshare': 26543210000,
      };
      final s = LimitUpStock.fromEastMoney(json);
      expect(s.code, '600519');
      expect(s.name, '贵州茅台');
      expect(s.consecutiveDays, 3);
      expect(s.firstLimitTime, isNotNull);
      expect(s.firstLimitTime!.hour, 9);
      expect(s.firstLimitTime!.minute, 25);
      expect(s.sealAmount, closeTo(23000, 0.1));  // 元→万元
      expect(s.turnoverRate, 1.23);
      expect(s.isZhaBan, isFalse);
      expect(s.zhabanCount, 0);
      expect(s.sector, '白酒');
      expect(s.lastLimitTime, isNotNull);
      expect(s.lastLimitTime!.hour, 14);
      expect(s.lastLimitTime!.minute, 59);
      expect(s.totalValue, 26543210000);
      expect(s.circulationValue, 21234567890);
    });

    test('zbc > 0 marks as zhaban', () {
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': '平安银行', 'zbc': 2});
      expect(s.isZhaBan, isTrue);
      expect(s.zhabanCount, 2);
    });

    test('null fbt returns null firstLimitTime', () {
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': 'X', 'fbt': null});
      expect(s.firstLimitTime, isNull);
    });

    test('string time format "HH:mm:ss" parsed correctly', () {
      // This tests the string branch of _parseEastMoneyTime
      // Note: fromEastMoney currently only receives int from API, but the helper supports strings
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': 'X', 'fbt': '09:25:00'});
      expect(s.firstLimitTime, isNotNull);
      expect(s.firstLimitTime!.hour, 9);
      expect(s.firstLimitTime!.minute, 25);
    });

    test('missing fields use defaults', () {
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': 'X'});
      expect(s.consecutiveDays, 1);
      expect(s.sealAmount, 0);
      expect(s.isZhaBan, isFalse);
    });

    test('code padded to 6 digits', () {
      final s = LimitUpStock.fromEastMoney({'c': '1', 'n': 'X'});
      expect(s.code, '000001');
    });
  });
}
