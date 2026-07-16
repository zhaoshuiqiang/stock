import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/trading_date_utils.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('classifies capture phases at A-share session boundaries', () {
    expect(
      TradingDateUtils.signalPhase(DateTime(2026, 7, 16, 8, 45)),
      DecisionSignalPhase.preMarket,
    );
    expect(
      TradingDateUtils.signalPhase(DateTime(2026, 7, 16, 9, 30)),
      DecisionSignalPhase.intraday,
    );
    expect(
      TradingDateUtils.signalPhase(DateTime(2026, 7, 16, 15)),
      DecisionSignalPhase.afterClose,
    );
    expect(
      TradingDateUtils.signalPhase(DateTime(2026, 7, 18, 10)),
      DecisionSignalPhase.nonTrading,
    );
  });

  test('previous weekday skips a weekend', () {
    expect(
      TradingDateUtils.previousWeekday(DateTime(2026, 7, 20)),
      DateTime(2026, 7, 17),
    );
  });
}
