import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';

void main() {
  group('LimitUpAnalysis.fromMap', () {
    test('round-trip toMap/fromMap', () {
      final a = LimitUpAnalysis(
        code: '600519', name: '贵州茅台', consecutiveDays: 3,
        qualityScore: 8.5, boardType: '一字板', timeGrade: '竞价涨停',
        sealRate: 8.5, premiumProb: 0.75, sector: '白酒',
        sealAmount: 23000, isZhaBan: false, price: 1689.5, changePct: 10.0,
      );
      final m = a.toMap();
      final restored = LimitUpAnalysis.fromMap(m);
      expect(restored.code, a.code);
      expect(restored.consecutiveDays, a.consecutiveDays);
      expect(restored.qualityScore, a.qualityScore);
      expect(restored.boardType, a.boardType);
      expect(restored.premiumProb, a.premiumProb);
    });
  });

  group('LimitUpAnalyzer.analyzeBatchList', () {
    test('returns List<LimitUpAnalysis> (activates dead code path)', () {
      final stocks = [
        LimitUpStock(code: '600519', name: '贵州茅台', consecutiveDays: 3,
            sealAmount: 23000, firstLimitTime: DateTime(2026, 6, 27, 9, 25)),
        LimitUpStock(code: '000001', name: '平安银行', consecutiveDays: 1,
            sealAmount: 5000, firstLimitTime: DateTime(2026, 6, 27, 14, 50)),
      ];
      final results = LimitUpAnalyzer.analyzeBatchList(stocks);
      expect(results, hasLength(2));
      expect(results.every((a) => a is LimitUpAnalysis), isTrue);
    });

    test('early limit time gets higher quality score than late', () {
      final early = LimitUpStock(code: '000001', name: 'A',
          firstLimitTime: DateTime(2026, 6, 27, 9, 25), sealAmount: 10000);
      final late = LimitUpStock(code: '000002', name: 'B',
          firstLimitTime: DateTime(2026, 6, 27, 14, 50), sealAmount: 10000);
      final r1 = LimitUpAnalyzer.analyzeBatchList([early]);
      final r2 = LimitUpAnalyzer.analyzeBatchList([late]);
      expect(r1.first.qualityScore, greaterThan(r2.first.qualityScore));
    });

    test('higher seal amount gets higher quality score', () {
      final strong = LimitUpStock(code: '000001', name: 'A', sealAmount: 50000);
      final weak = LimitUpStock(code: '000002', name: 'B', sealAmount: 500);
      final r1 = LimitUpAnalyzer.analyzeBatchList([strong]);
      final r2 = LimitUpAnalyzer.analyzeBatchList([weak]);
      expect(r1.first.qualityScore, greaterThanOrEqualTo(r2.first.qualityScore));
    });
  });
}
