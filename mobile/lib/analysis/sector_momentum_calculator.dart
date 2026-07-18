import 'sector_rotation.dart';
import 'sector_heat_detector.dart';

class SectorMomentumResult {
  final double score;
  final bool isInMainLine;
  final bool isRetreating;
  final bool isOverheated;
  final double mainLineBonus;
  final double retreatDiscount;
  final String momentumLabel;
  final String sectorName;

  const SectorMomentumResult({
    this.score = 0,
    this.isInMainLine = false,
    this.isRetreating = false,
    this.isOverheated = false,
    this.mainLineBonus = 1.0,
    this.retreatDiscount = 1.0,
    this.momentumLabel = '',
    this.sectorName = '',
  });
}

class SectorMomentumCalculator {
  const SectorMomentumCalculator._();

  static SectorMomentumResult calculate({
    required String? sectorName,
    required List<SectorAnalysis> sectorAnalysis,
    required double stockChangePct,
  }) {
    if (sectorName == null || sectorAnalysis.isEmpty) {
      return const SectorMomentumResult();
    }

    SectorAnalysis? mySector;
    for (final s in sectorAnalysis) {
      if (s.name == sectorName || s.code == sectorName) {
        mySector = s;
        break;
      }
    }
    if (mySector == null) {
      return SectorMomentumResult(sectorName: sectorName);
    }

    final isMainLine = mySector.isMainLine;
    final isOverheated = SectorHeatDetector.isOverheated(mySector);
    final isAccelerating = mySector.momentum == 'accelerating';
    final isDecelerating = mySector.momentum == 'decelerating';
    final isReversing = mySector.momentum == 'reversing';

    var score = 0.0;
    final labels = <String>[];

    if (isMainLine) {
      final bonus = SectorRotation.getMainLineBonus(sectorName, sectorAnalysis.where((s) => s.isMainLine).toList());
      if (isOverheated) {
        score += 0.15;
        labels.add('主线过热');
      } else {
        score += (bonus - 1.0) * 2.0;
        labels.add('主线');
      }
    }

    if (isAccelerating && !isOverheated) {
      score += 0.25;
      labels.add('板块加速');
    }
    if (isDecelerating && mySector.changePct < -1.0) {
      score -= 0.30;
      labels.add('板块减速');
    }
    if (isReversing) {
      score += 0.10;
      labels.add('板块反转');
    }

    if (mySector.limitUpCount >= 3 && !isOverheated) {
      score += 0.15;
      labels.add('板块涨停潮');
    }

    final isRetreating = mySector.changePct < -1.0 ||
        (isDecelerating && mySector.mainNetFlow < -1e8);
    if (isRetreating) {
      score -= 0.20;
      labels.add('板块退潮');
    }

    if (isMainLine && mySector.changePct > 0) {
      final relativeStrength = (stockChangePct / mySector.changePct).clamp(0.0, 2.0);
      if (relativeStrength > 0.8) {
        score += 0.10;
        labels.add('板块龙头');
      } else if (relativeStrength < 0.3) {
        score -= 0.10;
        labels.add('板块跟风');
      }
    }

    final mainLineBonus = isMainLine && !isOverheated
        ? SectorRotation.getMainLineBonus(sectorName, sectorAnalysis.where((s) => s.isMainLine).toList())
        : 1.0;
    final retreatDiscount = isRetreating ? 0.85 : 1.0;

    return SectorMomentumResult(
      score: score.clamp(-1.0, 1.0),
      isInMainLine: isMainLine,
      isRetreating: isRetreating,
      isOverheated: isOverheated,
      mainLineBonus: mainLineBonus,
      retreatDiscount: retreatDiscount,
      momentumLabel: labels.join('·'),
      sectorName: sectorName,
    );
  }
}
