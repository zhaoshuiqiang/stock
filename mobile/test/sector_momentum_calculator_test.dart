import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/sector_momentum_calculator.dart';
import 'package:stock_analyzer/analysis/sector_rotation.dart';

void main() {
  SectorAnalysis _makeSector({
    String name = '半导体',
    String code = 'BK1036',
    double changePct = 2.0,
    double mainNetFlow = 3e8,
    double strengthScore = 6.0,
    int limitUpCount = 2,
    int consecutiveStrongDays = 1,
    bool isMainLine = true,
    String momentum = 'steady',
  }) {
    return SectorAnalysis(
      name: name,
      code: code,
      changePct: changePct,
      mainNetFlow: mainNetFlow,
      strengthScore: strengthScore,
      limitUpCount: limitUpCount,
      consecutiveStrongDays: consecutiveStrongDays,
      isMainLine: isMainLine,
      momentum: momentum,
    );
  }

  group('SectorMomentumCalculator', () {
    test('returns neutral when sectorName is null', () {
      final result = SectorMomentumCalculator.calculate(
        sectorName: null,
        sectorAnalysis: [_makeSector()],
        stockChangePct: 3.0,
      );
      expect(result.score, 0.0);
      expect(result.sectorName, '');
      expect(result.isInMainLine, false);
    });

    test('returns neutral when sectorAnalysis is empty', () {
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [],
        stockChangePct: 3.0,
      );
      expect(result.score, 0.0);
    });

    test('returns sectorName only when sector not found', () {
      final result = SectorMomentumCalculator.calculate(
        sectorName: '未知板块',
        sectorAnalysis: [_makeSector()],
        stockChangePct: 3.0,
      );
      expect(result.score, 0.0);
      expect(result.sectorName, '未知板块');
    });

    test('main line sector stock gets positive momentum', () {
      final sector = _makeSector(
        isMainLine: true,
        strengthScore: 8.0,
        changePct: 3.0,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 4.0,
      );
      expect(result.score, greaterThan(0));
      expect(result.isInMainLine, true);
      expect(result.mainLineBonus, greaterThan(1.0));
      expect(result.momentumLabel, contains('主线'));
    });

    test('non-main-line sector gets zero or negative momentum', () {
      final sector = _makeSector(
        isMainLine: false,
        strengthScore: 2.0,
        changePct: 0.5,
        momentum: 'steady',
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 0.5,
      );
      expect(result.score, closeTo(0.0, 0.01));
      expect(result.isInMainLine, false);
      expect(result.mainLineBonus, 1.0);
    });

    test('retreating sector gives negative momentum', () {
      final sector = _makeSector(
        isMainLine: false,
        changePct: -2.0,
        momentum: 'decelerating',
        mainNetFlow: -2e8,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: -1.5,
      );
      expect(result.score, lessThan(0));
      expect(result.isRetreating, true);
      expect(result.retreatDiscount, 0.85);
      expect(result.momentumLabel, contains('板块退潮'));
    });

    test('overheated main line limits bonus', () {
      final sector = _makeSector(
        isMainLine: true,
        strengthScore: 8.0,
        changePct: 9.0,
        limitUpCount: 8,
        consecutiveStrongDays: 4,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 5.0,
      );
      expect(result.isOverheated, true);
      expect(result.mainLineBonus, 1.0);
      expect(result.momentumLabel, contains('主线过热'));
    });

    test('accelerating sector gets positive momentum', () {
      final sector = _makeSector(
        isMainLine: false,
        momentum: 'accelerating',
        changePct: 3.0,
        mainNetFlow: 3e8,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 2.0,
      );
      expect(result.score, greaterThan(0));
      expect(result.momentumLabel, contains('板块加速'));
    });

    test('reversing sector gets slight positive momentum', () {
      final sector = _makeSector(
        isMainLine: false,
        momentum: 'reversing',
        changePct: -0.5,
        mainNetFlow: 2e8,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: -0.3,
      );
      expect(result.score, greaterThan(0));
      expect(result.momentumLabel, contains('板块反转'));
    });

    test('limit-up wave adds positive momentum when not overheated', () {
      final sector = _makeSector(
        isMainLine: false,
        limitUpCount: 4,
        consecutiveStrongDays: 1,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 2.0,
      );
      expect(result.momentumLabel, contains('板块涨停潮'));
      expect(result.score, greaterThan(0));
    });

    test('stock relative strength in main line sector affects score', () {
      final sector = _makeSector(
        isMainLine: true,
        strengthScore: 8.0,
        changePct: 3.0,
      );

      final resultLeader = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 5.0,
      );
      expect(resultLeader.momentumLabel, contains('板块龙头'));

      final resultFollower = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 0.5,
      );
      expect(resultFollower.momentumLabel, contains('板块跟风'));
    });

    test('decelerating sector with negative change gets penalty', () {
      final sector = _makeSector(
        isMainLine: false,
        momentum: 'decelerating',
        changePct: -2.0,
        mainNetFlow: 0,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: -1.0,
      );
      expect(result.momentumLabel, contains('板块减速'));
      expect(result.score, lessThan(-0.2));
    });

    test('score is clamped to [-1.0, 1.0]', () {
      final sector = _makeSector(
        isMainLine: true,
        strengthScore: 10.0,
        momentum: 'accelerating',
        changePct: 5.0,
        mainNetFlow: 5e8,
        limitUpCount: 5,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 8.0,
      );
      expect(result.score, lessThanOrEqualTo(1.0));
      expect(result.score, greaterThanOrEqualTo(-1.0));
    });

    test('matches sector by code', () {
      final sector = _makeSector(
        code: 'BK1036',
        isMainLine: true,
        strengthScore: 6.0,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: 'BK1036',
        sectorAnalysis: [sector],
        stockChangePct: 3.0,
      );
      expect(result.isInMainLine, true);
      expect(result.sectorName, 'BK1036');
    });

    test('retreat condition: decelerating with large outflow', () {
      final sector = _makeSector(
        isMainLine: false,
        momentum: 'decelerating',
        changePct: 0.5,
        mainNetFlow: -2e8,
      );
      final result = SectorMomentumCalculator.calculate(
        sectorName: '半导体',
        sectorAnalysis: [sector],
        stockChangePct: 0.3,
      );
      expect(result.isRetreating, true);
      expect(result.retreatDiscount, 0.85);
    });
  });
}
