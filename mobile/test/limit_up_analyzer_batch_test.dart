import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';

void main() {
  group('LimitUpAnalysis.fromMap', () {
    test('round-trip toMap/fromMap preserves all fields', () {
      final original = LimitUpAnalysis(
        code: '600519', name: '贵州茅台', consecutiveDays: 3,
        quality: '优质', qualityScore: 8.5, boardType: '一字板',
        timeGrade: '竞价涨停', position: '龙头', sealRate: 8.5,
        premiumProb: 0.75,
        signals: const ['3连板，板块核心', '集合竞价即涨停', '封单充足'],
        sector: '白酒', zhabanCount: 0, isZhaBan: false,
        sealAmount: 23000, price: 1689.5, changePct: 10.0,
        firstLimitTime: DateTime(2026, 6, 27, 9, 25),
      );
      final m = original.toMap();
      final restored = LimitUpAnalysis.fromMap(m);
      // 断言所有字段（覆盖 round-trip 契约）
      expect(restored.code, original.code);
      expect(restored.name, original.name);
      expect(restored.consecutiveDays, original.consecutiveDays);
      expect(restored.quality, original.quality);
      expect(restored.qualityScore, original.qualityScore);
      expect(restored.timeGrade, original.timeGrade);
      expect(restored.sealRate, original.sealRate);
      expect(restored.boardType, original.boardType);
      expect(restored.position, original.position);
      expect(restored.premiumProb, original.premiumProb);
      expect(restored.signals, original.signals);
      expect(restored.sector, original.sector);
      expect(restored.zhabanCount, original.zhabanCount);
      expect(restored.isZhaBan, original.isZhaBan);
      expect(restored.sealAmount, original.sealAmount);
      expect(restored.price, original.price);
      expect(restored.changePct, original.changePct);
      expect(restored.firstLimitTime, original.firstLimitTime);
    });

    test('fromMap handles integer-valued doubles from SQLite', () {
      // SQLite 可能将 8.0 存为整数 8，fromMap 必须用 (as num).toDouble() 防御
      final m = <String, dynamic>{
        'code': '000001', 'name': '平安银行',
        'quality_score': 8, 'seal_rate': 3, 'premium_prob': 1,
        'seal_amount': 5000, 'price': 10, 'change_pct': 10,
        'first_limit_time': 1771234567890,
      };
      final restored = LimitUpAnalysis.fromMap(m);
      expect(restored.qualityScore, 8.0);
      expect(restored.sealRate, 3.0);
      expect(restored.premiumProb, 1.0);
      expect(restored.sealAmount, 5000.0);
      expect(restored.price, 10.0);
      expect(restored.changePct, 10.0);
      expect(restored.firstLimitTime, isNotNull);
    });

    test('fromMap handles null first_limit_time', () {
      final m = <String, dynamic>{
        'code': '000001', 'name': '平安银行',
        'first_limit_time': null,
      };
      final restored = LimitUpAnalysis.fromMap(m);
      expect(restored.firstLimitTime, isNull);
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
