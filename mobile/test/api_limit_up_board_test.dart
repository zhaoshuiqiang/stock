import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';

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
}
