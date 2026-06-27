import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/backtest_engine.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('K-line limit-up marks', () {
    test('LimitUpAnalysis toMap contains board_type for rendering', () {
      final a = LimitUpAnalysis(
        code: '600519',
        name: '茅台',
        consecutiveDays: 3,
        boardType: '一字板',
        timeGrade: '竞价涨停',
        premiumProb: 0.75,
      );
      final m = a.toMap();
      expect(m['board_type'], '一字板');
      expect(m['consecutive_days'], 3);
      expect(m['time_grade'], '竞价涨停');
      expect(m['premium_prob'], 0.75);
    });

    test('AnalysisResult.limitUpAnalysis field is nullable and holds value', () {
      final a = LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3);
      final r = AnalysisResult(limitUpAnalysis: a);
      expect(r.limitUpAnalysis, isNotNull);
      expect(r.limitUpAnalysis!.consecutiveDays, 3);
      // 默认为空时也能取到 null
      final empty = AnalysisResult();
      expect(empty.limitUpAnalysis, isNull);
    });

    test('KlineValidator.isLimitUp detects main board limit-up', () {
      final prev = HistoryKline(date: DateTime(2026, 6, 26), close: 10.0);
      final kline = HistoryKline(
        date: DateTime(2026, 6, 27),
        open: 10.5,
        high: 11.0,
        low: 10.5,
        close: 11.0,
      );
      expect(KlineValidator.isLimitUp(kline, prev, 0.095), isTrue);
    });

    test('KlineValidator.isLimitUp rejects non-limit-up day', () {
      final prev = HistoryKline(date: DateTime(2026, 6, 26), close: 10.0);
      final kline = HistoryKline(
        date: DateTime(2026, 6, 27),
        open: 10.1,
        high: 10.3,
        low: 10.0,
        close: 10.2,
      );
      expect(KlineValidator.isLimitUp(kline, prev, 0.095), isFalse);
    });

    test('KlineValidator.isYiZiBan detects one-line board', () {
      final prev = HistoryKline(date: DateTime(2026, 6, 26), close: 10.0);
      final kline = HistoryKline(
        date: DateTime(2026, 6, 27),
        open: 11.0,
        high: 11.0,
        low: 11.0,
        close: 11.0,
      );
      expect(KlineValidator.isYiZiBan(kline, prev, 0.095), isTrue);
    });

    test('KlineValidator.limitUpPrice computes expected threshold', () {
      expect(KlineValidator.limitUpPrice(10.0, 0.095), closeTo(10.95, 0.001));
      expect(KlineValidator.limitUpPrice(10.0, 0.20), closeTo(12.0, 0.001));
    });
  });
}
