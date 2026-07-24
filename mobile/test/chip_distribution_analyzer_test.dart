import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/chip_distribution_analyzer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

HistoryKline _k({
  required int day,
  required double high,
  required double low,
  required double close,
  required double volume,
}) {
  return HistoryKline(
    date: DateTime(2026, 7, day),
    open: close,
    high: high,
    low: low,
    close: close,
    volume: volume,
  );
}

void main() {
  group('ChipDistributionAnalyzer', () {
    test('returns null for empty data or invalid price', () {
      expect(
        ChipDistributionAnalyzer.analyze(const [], currentPrice: 10),
        isNull,
      );
      expect(
        ChipDistributionAnalyzer.analyze(
          [_k(day: 1, high: 10.2, low: 9.8, close: 10, volume: 1000)],
          currentPrice: 0,
        ),
        isNull,
      );
    });

    test('current price above all chips => nearly all profit, none trapped',
        () {
      final dist = ChipDistributionAnalyzer.analyze(
        [_k(day: 1, high: 10.2, low: 9.8, close: 10.0, volume: 1000)],
        currentPrice: 11.0,
        circulatingShares: 1000000,
      )!;
      expect(dist.isValid, isTrue);
      expect(dist.profitRatio, closeTo(1.0, 1e-6));
      expect(dist.trappedRatio, closeTo(0.0, 1e-6));
      // profit + trapped must always sum to 1
      expect(dist.profitRatio + dist.trappedRatio, closeTo(1.0, 1e-9));
      // levels form a normalized distribution
      final sum = dist.levels.fold<double>(0.0, (a, b) => a + b.ratio);
      expect(sum, closeTo(1.0, 1e-6));
      // average cost sits within the traded band
      expect(dist.averageCost, inInclusiveRange(9.8, 10.2));
    });

    test('current price below all chips => fully trapped', () {
      final dist = ChipDistributionAnalyzer.analyze(
        [_k(day: 1, high: 10.2, low: 9.8, close: 10.0, volume: 1000)],
        currentPrice: 9.0,
        circulatingShares: 1000000,
      )!;
      expect(dist.profitRatio, closeTo(0.0, 1e-6));
      expect(dist.trappedRatio, closeTo(1.0, 1e-6));
    });

    test('recent high-volume/high-turnover day pulls average cost toward it',
        () {
      final dist = ChipDistributionAnalyzer.analyze(
        [
          _k(day: 1, high: 10.1, low: 9.9, close: 10.0, volume: 1000),
          _k(day: 2, high: 12.1, low: 11.9, close: 12.0, volume: 5000),
        ],
        currentPrice: 12.0,
        circulatingShares: 1000000,
      )!;
      // day2 (price ~12) has 5x volume + higher turnover => cost skews up
      expect(dist.averageCost, greaterThan(11.0));
      expect(dist.averageCost, lessThanOrEqualTo(12.1));
      expect(dist.peakPrice, greaterThan(11.0));
    });

    test('90% cost band is ordered and within the traded range', () {
      final dist = ChipDistributionAnalyzer.analyze(
        [
          _k(day: 1, high: 10.5, low: 9.5, close: 10.0, volume: 2000),
          _k(day: 2, high: 11.0, low: 10.0, close: 10.5, volume: 3000),
          _k(day: 3, high: 10.8, low: 10.2, close: 10.6, volume: 2500),
        ],
        currentPrice: 10.6,
        circulatingShares: 800000,
      )!;
      expect(dist.lowerCost90, lessThanOrEqualTo(dist.upperCost90));
      expect(dist.lowerCost90, greaterThanOrEqualTo(9.5));
      expect(dist.upperCost90, lessThanOrEqualTo(11.0));
      expect(dist.concentration90, inInclusiveRange(0.0, 1.0));
      expect(dist.profitRatio + dist.trappedRatio, closeTo(1.0, 1e-9));
    });

    test('works without circulating shares (fallback diffusion)', () {
      final dist = ChipDistributionAnalyzer.analyze(
        [
          _k(day: 1, high: 10.1, low: 9.9, close: 10.0, volume: 1000),
          _k(day: 2, high: 10.3, low: 10.0, close: 10.2, volume: 1200),
        ],
        currentPrice: 10.2,
      )!;
      expect(dist.isValid, isTrue);
      final sum = dist.levels.fold<double>(0.0, (a, b) => a + b.ratio);
      expect(sum, closeTo(1.0, 1e-6));
      expect(dist.profitRatio + dist.trappedRatio, closeTo(1.0, 1e-9));
    });
  });
}
