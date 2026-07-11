import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/analysis/sentiment_thermometer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('SentimentThermometer', () {
    group('zhabanRate', () {
      test('empty pool returns neutral 0.5', () {
        final r = SentimentThermometer.compute(
          todayPool: [], yesterdayPool: [], todayQuotePct: {},
        );
        expect(r.zhabanRate, 0.5);
      });

      test('all zhaban returns 1.0', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', isZhaBan: true),
          LimitUpAnalysis(code: '002', name: 'B', isZhaBan: true),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.zhabanRate, 1.0);
      });

      test('half zhaban returns 0.5', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', isZhaBan: true),
          LimitUpAnalysis(code: '002', name: 'B', isZhaBan: false),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.zhabanRate, 0.5);
      });
    });

    group('continuationRate', () {
      test('yesterday empty returns 0.3', () {
        final r = SentimentThermometer.compute(
          todayPool: [LimitUpAnalysis(code: '001', name: 'A', consecutiveDays: 2)],
          yesterdayPool: [], todayQuotePct: {});
        expect(r.continuationRate, 0.3);
      });

      test('yesterday 10 first-board, today 5 second-board → 0.5', () {
        final yesterday = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'Y$i', consecutiveDays: 1));
        final today = List.generate(5, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'T$i', consecutiveDays: 2));
        today.addAll(List.generate(10, (i) =>
            LimitUpAnalysis(code: '01$i', name: 'F$i', consecutiveDays: 1)));
        final r = SentimentThermometer.compute(
          todayPool: today, yesterdayPool: yesterday, todayQuotePct: {});
        expect(r.continuationRate, 0.5);
      });

      test('全高度晋级率：1→2(50%), 2→3(60%) → 加权52.5%', () {
        final yesterday = <LimitUpAnalysis>[
          ...List.generate(10, (i) => LimitUpAnalysis(code: '00$i', name: 'Y1$i', consecutiveDays: 1)),
          ...List.generate(5, (i) => LimitUpAnalysis(code: '10$i', name: 'Y2$i', consecutiveDays: 2)),
        ];
        final today = <LimitUpAnalysis>[
          ...List.generate(5, (i) => LimitUpAnalysis(code: '00$i', name: 'T1$i', consecutiveDays: 2)),
          ...List.generate(3, (i) => LimitUpAnalysis(code: '10$i', name: 'T2$i', consecutiveDays: 3)),
        ];
        final r = SentimentThermometer.compute(
          todayPool: today, yesterdayPool: yesterday, todayQuotePct: {});
        // (0.5*10 + 0.6*5) / 15 = (5+3)/15 = 0.533
        expect(r.continuationRate, closeTo(0.533, 0.01));
      });
    });

    group('moneyMakingEffect', () {
      test('empty yesterday returns 0.0', () {
        final r = SentimentThermometer.compute(
          todayPool: [], yesterdayPool: [], todayQuotePct: {});
        expect(r.moneyMakingEffect, 0.0);
      });

      test('average of yesterday pct change', () {
        final yesterday = [
          LimitUpAnalysis(code: '001', name: 'A'),
          LimitUpAnalysis(code: '002', name: 'B'),
        ];
        final quotes = {'001': 3.0, '002': 5.0};
        final r = SentimentThermometer.compute(
          todayPool: [], yesterdayPool: yesterday, todayQuotePct: quotes);
        expect(r.moneyMakingEffect, 4.0);  // (3+5)/2
      });
    });

    group('temperature', () {
      test('all bad → low temperature', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', isZhaBan: true, consecutiveDays: 1),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.temperature, lessThan(30));
      });

      test('all good → high temperature', () {
        final today = List.generate(60, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'T$i', consecutiveDays: 5,
                isZhaBan: false, sealAmount: 20000));
        final yesterday = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'Y$i', consecutiveDays: 1));
        final quotes = {for (var i = 0; i < 10; i++) '00$i': 5.0};
        final r = SentimentThermometer.compute(
          todayPool: today, yesterdayPool: yesterday, todayQuotePct: quotes);
        expect(r.temperature, greaterThan(60));
      });
    });

    group('phase inference', () {
      test('startup: 30+ limitUp, height≤3, temp 30-55', () {
        final pool = List.generate(35, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', consecutiveDays: 2, isZhaBan: false));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.phase, EmotionPhase.startup);
      });

      test('climax: 50+ limitUp, height≥4, temp≥60', () {
        final pool = List.generate(60, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i',
                consecutiveDays: i < 5 ? 5 : 2, isZhaBan: false, sealAmount: 20000));
        final yesterday = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'Y$i', consecutiveDays: 1));
        final quotes = {for (var i = 0; i < 10; i++) '00$i': 5.0};
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: yesterday, todayQuotePct: quotes);
        expect(r.phase, EmotionPhase.climax);
      });

      test('freezing: <20 limitUp, height≤2, temp<30 + limitDown penalty', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', consecutiveDays: 1, isZhaBan: true),
          LimitUpAnalysis(code: '002', name: 'B', consecutiveDays: 1, isZhaBan: true),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {},
          limitDownCount: 80); // 大量跌停触发恐慌惩罚
        expect(r.phase, EmotionPhase.freezing);
        expect(r.temperature, lessThan(30));
      });

      test('state transition: climax → retreat when temp drops', () {
        final yesterdayResult = SentimentResult(
          temperature: 70, phase: EmotionPhase.climax,
          zhabanRate: 0.1, continuationRate: 0.6, sealSuccessRate: 0.9,
          moneyMakingEffect: 5, limitUpCount: 60, limitDownCount: 2,
          continuationHeight: 5, signals: [], timestamp: DateTime.now(),
        );
        // 今日温度降到 50
        final pool = List.generate(25, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', consecutiveDays: 2, isZhaBan: true));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {},
          yesterdayPhase: yesterdayResult.phase);
        expect(r.phase, EmotionPhase.retreat);
      });
    });

    group('signals', () {
      test('zhabanRate >= 0.7 generates warning', () {
        final pool = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', isZhaBan: true));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.signals.any((s) => s.contains('炸板潮')), isTrue);
      });

      test('zhabanRate < 0.15 generates strong seal signal', () {
        final pool = List.generate(20, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', isZhaBan: false, consecutiveDays: 2));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.signals.any((s) => s.contains('封板极强')), isTrue);
      });
    });
  });
}
