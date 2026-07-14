import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_market_data_provider.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('decision provider requests adjusted stock benchmark and raw stock',
      () async {
    final api = _FakeApiClient();
    final data = await DecisionMarketDataProvider(apiClient: api).load(
      code: '000001',
      benchmarkCode: '000300',
    );
    expect(api.adjustedCodes, ['000001', '000300']);
    expect(api.rawCodes, ['000001']);
    expect(data.adjustedStock.single.close, 10);
    expect(data.adjustedBenchmark.single.close, 100);
  });
}

class _FakeApiClient extends ApiClient {
  final adjustedCodes = <String>[];
  final rawCodes = <String>[];

  @override
  Future<List<HistoryKline>> getForwardAdjustedHistory(String code,
      {int days = 180}) async {
    adjustedCodes.add(code);
    return [
      HistoryKline(
        date: DateTime(2026, 7, 14),
        close: code == '000300' ? 100 : 10,
      ),
    ];
  }

  @override
  Future<List<HistoryKline>> getRawHistory(String code,
      {int days = 180}) async {
    rawCodes.add(code);
    return [HistoryKline(date: DateTime(2026, 7, 14), close: 10)];
  }
}
