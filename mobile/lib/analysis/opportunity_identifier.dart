import '../models/stock_models.dart';

class OpportunityIdentifier {
  static List<Map<String, String>> identify(List<SignalItem> buySignals) {
    final opportunities = <Map<String, String>>[];
    for (final signal in buySignals.take(3)) {
      String risk = '中等';
      if (signal.signal.contains('RSI') || signal.signal.contains('超卖')) risk = '中高';
      if (signal.signal.contains('金叉')) risk = '中等';
      if (signal.signal.contains('放量')) risk = '中低';
      if (signal.signal.contains('底背离')) risk = '中等';
      if (signal.signal.contains('跌破下轨')) risk = '中高';
      opportunities.add({
        'name': signal.signal,
        'description': signal.description,
        'risk': risk,
      });
    }
    return opportunities;
  }
}
