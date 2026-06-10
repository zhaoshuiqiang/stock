import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';

void main() {
  group('K-line API', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    tearDown(() {
      apiClient.dispose();
    });

    test('getStockHistory returns K-line data for sh600519', () async {
      final klines = await apiClient.getStockHistory('sh600519', days: 30);
      print('K-line data count: ${klines.length}');
      if (klines.isNotEmpty) {
        final last = klines.last;
        print('Last kline: ${last.date} close=${last.close} vol=${last.volume}');
      }
      expect(klines, isNotEmpty, reason: 'K-line data should not be empty');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getStockHistory returns K-line data for sz000001', () async {
      final klines = await apiClient.getStockHistory('sz000001', days: 30);
      print('K-line data count: ${klines.length}');
      expect(klines, isNotEmpty, reason: 'K-line data should not be empty');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('getRealtimeQuote returns quote data', () async {
      final quote = await apiClient.getRealtimeQuote('sh600519');
      print('Quote: ${quote?.name} price=${quote?.price}');
      expect(quote, isNotNull, reason: 'Quote should not be null');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Multiple K-line requests', () async {
      final codes = ['sh600519', 'sz000001', 'sh601318'];
      int success = 0;
      int fail = 0;
      for (final code in codes) {
        final klines = await apiClient.getStockHistory(code, days: 30);
        if (klines.isNotEmpty) {
          success++;
          print('$code: ${klines.length} klines');
        } else {
          fail++;
          print('$code: NO DATA');
        }
      }
      print('Success: $success, Fail: $fail');
      expect(success, greaterThan(0), reason: 'At least 1 stock should have K-line data');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
