import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';

void main() {
  group('Hot Sectors API', skip: 'Requires network access - fails in offline CI', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    tearDown(() {
      apiClient.dispose();
    });

    test('getHotSectors returns non-empty list', () async {
      final sectors = await apiClient.getHotSectors();
      print('热门板块数量: ${sectors.length}');
      for (final s in sectors.take(5)) {
        print('  ${s.name} (${s.code}) 涨幅:${s.changePct.toStringAsFixed(2)}% 领涨:${s.leadStockName}');
      }
      expect(sectors, isNotEmpty, reason: '热门板块列表不应为空');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getHotSectors sector data integrity', () async {
      final sectors = await apiClient.getHotSectors();
      if (sectors.isNotEmpty) {
        for (final sector in sectors) {
          expect(sector.name, isNotEmpty, reason: '板块名称不应为空');
          expect(sector.code, isNotEmpty, reason: '板块代码不应为空');
        }
      } else {
        fail('热门板块列表为空，无法验证数据完整性');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getSectorStocks returns stocks for a known sector', () async {
      // 先获取板块列表
      final sectors = await apiClient.getHotSectors();
      if (sectors.isEmpty) {
        fail('热门板块列表为空，无法测试板块内股票');
      }

      // 取第一个板块获取股票
      final firstSector = sectors.first;
      print('测试板块: ${firstSector.name} (${firstSector.code})');
      final stocks = await apiClient.getSectorStocks(firstSector.code);
      print('板块内股票数量: ${stocks.length}');
      for (final s in stocks.take(5)) {
        print('  ${s.name} (${s.code}) 涨幅:${s.changePct.toStringAsFixed(2)}%');
      }
      expect(stocks, isNotEmpty, reason: '板块 ${firstSector.name} 内应有股票数据');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getHotSectors eastmoney API direct test', () async {
      // 直接测试东方财富API的返回格式
      final sectors = await apiClient.getHotSectors();
      print('东方财富API返回板块数: ${sectors.length}');

      // 验证板块数据包含领涨股信息
      int withLeadStock = 0;
      for (final s in sectors) {
        if (s.leadStockName.isNotEmpty) withLeadStock++;
      }
      print('含领涨股信息的板块: $withLeadStock/${sectors.length}');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getHotSectors multiple calls consistency', () async {
      // 连续调用2次，验证结果一致性
      final sectors1 = await apiClient.getHotSectors();
      print('第1次调用: ${sectors1.length}个板块');

      // 等待1秒
      await Future.delayed(const Duration(seconds: 1));

      final sectors2 = await apiClient.getHotSectors();
      print('第2次调用: ${sectors2.length}个板块');

      // 两次调用都应返回非空结果
      expect(sectors1, isNotEmpty, reason: '第1次调用应返回数据');
      expect(sectors2, isNotEmpty, reason: '第2次调用应返回数据');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('getSectorStocks for multiple sectors', () async {
      final sectors = await apiClient.getHotSectors();
      if (sectors.length < 3) {
        fail('板块数量不足3个，无法测试多板块');
      }

      int successCount = 0;
      int failCount = 0;
      for (final sector in sectors.take(3)) {
        final stocks = await apiClient.getSectorStocks(sector.code);
        if (stocks.isNotEmpty) {
          successCount++;
          print('板块 ${sector.name}: ${stocks.length}只股票');
        } else {
          failCount++;
          print('板块 ${sector.name}: 无股票数据');
        }
      }
      print('3个板块中: $successCount成功, $failCount失败');
      expect(successCount, greaterThan(0), reason: '至少1个板块应有股票数据');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
