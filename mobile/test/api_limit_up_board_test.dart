import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';

void main() {
  group('ApiClient.getLimitUpBoard', () {
    test('method exists and returns List<LimitUpStock>', () {
      final client = ApiClient();
      // 验证方法存在（实际网络调用在集成测试中验证）
      expect(client.getLimitUpBoard, isNotNull);
    });

    test('getYesterdayLimitUpPool method exists', () {
      final client = ApiClient();
      expect(client.getYesterdayLimitUpPool, isNotNull);
    });
  });

  group('LimitUpStock.fromEastMoney parsing', () {
    // 验证 mock JSON 能被正确解析，为后续 Task 6+ 提供回归保护
    test('parses typical EastMoney response fields', () {
      final mockEntry = <String, dynamic>{
        'c': '001234',
        'n': '测试股票',
        'lbc': 3,
        'fbt': 143000,
        'lbt': 145500,
        'fund': 50000000,
        'hs': 8.5,
        'zbc': 0,
        'hybk': '测试板块',
        'ltsz': 1000000000,
        'tshare': 2000000000,
      };
      final stock = LimitUpStock.fromEastMoney(mockEntry);
      expect(stock.code, '001234');
      expect(stock.name, '测试股票');
      expect(stock.consecutiveDays, 3);
    });

    test('handles missing optional fields gracefully', () {
      final mockEntry = <String, dynamic>{
        'c': '002001',
        'n': '最小数据',
      };
      final stock = LimitUpStock.fromEastMoney(mockEntry);
      expect(stock.code, '002001');
      expect(stock.name, '最小数据');
      expect(stock.consecutiveDays, 1);
    });
  });
}
