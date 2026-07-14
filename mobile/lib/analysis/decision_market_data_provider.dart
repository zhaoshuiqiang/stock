import '../api/api_client.dart';
import '../models/stock_models.dart';

class DecisionMarketData {
  final List<HistoryKline> adjustedStock;
  final List<HistoryKline>? rawStock;
  final List<HistoryKline> adjustedBenchmark;

  const DecisionMarketData({
    required this.adjustedStock,
    this.rawStock,
    required this.adjustedBenchmark,
  });
}

abstract class DecisionMarketDataSource {
  Future<DecisionMarketData> load({
    required String code,
    required String benchmarkCode,
    int days,
  });
}

class DecisionMarketDataProvider implements DecisionMarketDataSource {
  final ApiClient apiClient;

  DecisionMarketDataProvider({ApiClient? apiClient})
      : apiClient = apiClient ?? ApiClient();

  @override
  Future<DecisionMarketData> load({
    required String code,
    required String benchmarkCode,
    int days = 180,
  }) async {
    final results = await Future.wait([
      apiClient.getForwardAdjustedHistory(code, days: days),
      apiClient.getRawHistory(code, days: days),
      apiClient.getForwardAdjustedHistory(benchmarkCode, days: days),
    ]);
    return DecisionMarketData(
      adjustedStock: results[0],
      rawStock: results[1].isEmpty ? null : results[1],
      adjustedBenchmark: results[2],
    );
  }
}
