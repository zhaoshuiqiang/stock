class SectorAnalysis {
  String name, code;
  double changePct, mainNetFlow, strengthScore;
  int limitUpCount, consecutiveStrongDays;
  bool isMainLine;
  double netInflowRate5Day;
  double netInflowRate20Day;
  int rank;
  int rank5Day;
  String momentum;

  SectorAnalysis({
    required this.name,
    required this.code,
    this.changePct = 0,
    this.limitUpCount = 0,
    this.mainNetFlow = 0,
    this.consecutiveStrongDays = 0,
    this.strengthScore = 0,
    this.isMainLine = false,
    this.netInflowRate5Day = 0,
    this.netInflowRate20Day = 0,
    this.rank = 0,
    this.rank5Day = 0,
    this.momentum = 'steady',
  });
}

class SectorRotationResult {
  List<SectorAnalysis> topSectors, mainLines;
  DateTime? updateTime;
  List<SectorRotationSignal> rotationSignals;

  SectorRotationResult({
    required this.topSectors,
    required this.mainLines,
    this.updateTime,
    this.rotationSignals = const [],
  });
}

class SectorData {
  String name, code;
  double changePct, mainNetFlow;
  int limitUpCount;

  SectorData({
    required this.name,
    required this.code,
    this.changePct = 0,
    this.limitUpCount = 0,
    this.mainNetFlow = 0,
  });
}

class SectorRotationSignal {
  final String fromSector;
  final String toSector;
  final double strength;
  final String type;

  const SectorRotationSignal({
    required this.fromSector,
    required this.toSector,
    required this.strength,
    required this.type,
  });
}

class StockSectorCorrelation {
  final String code;
  final String sectorCode;
  final double correlation;
  final double beta;
  final bool isLeading;

  const StockSectorCorrelation({
    required this.code,
    required this.sectorCode,
    required this.correlation,
    required this.beta,
    required this.isLeading,
  });
}

class SectorRotation {
  static SectorRotationResult analyze({
    required List<SectorData> sectorList,
    Map<String, List<double>>? historyData,
  }) {
    if (sectorList.isEmpty) {
      return SectorRotationResult(topSectors: [], mainLines: []);
    }

    final analyses = <SectorAnalysis>[];
    for (final s in sectorList) {
      double ss = 0;
      if (s.changePct > 3) ss += 3.0;
      else if (s.changePct > 2) ss += 2.5;
      else if (s.changePct > 1) ss += 2.0;
      else if (s.changePct > 0) ss += 1.2;
      else if (s.changePct > -1) ss += 0.5;

      if (s.limitUpCount >= 10) ss += 4.0;
      else if (s.limitUpCount >= 5) ss += 3.0;
      else if (s.limitUpCount >= 3) ss += 2.0;
      else if (s.limitUpCount >= 1) ss += 1.0;

      if (s.mainNetFlow > 5) ss += 2.0;
      else if (s.mainNetFlow > 2) ss += 1.5;
      else if (s.mainNetFlow > 0) ss += 0.8;
      else if (s.mainNetFlow < -3) ss -= 0.5;

      int cd = 0;
      if (historyData != null && historyData.containsKey(s.code)) {
        for (int i = (historyData[s.code]?.length ?? 0) - 1; i >= 0; i--) {
          if ((historyData[s.code]?[i] ?? 0) >= 5.0) cd++;
          else break;
        }
      }
      if (cd >= 3) ss += 1.0;
      else if (cd >= 2) ss += 0.5;

      String momentum = 'steady';
      if (s.changePct > 2 && s.mainNetFlow > 2) momentum = 'accelerating';
      else if (s.changePct > 0 && s.mainNetFlow < -1) momentum = 'decelerating';
      else if (s.changePct < -1 && s.mainNetFlow > 1) momentum = 'reversing';

      analyses.add(SectorAnalysis(
        name: s.name,
        code: s.code,
        changePct: s.changePct,
        limitUpCount: s.limitUpCount,
        mainNetFlow: s.mainNetFlow,
        consecutiveStrongDays: cd,
        strengthScore: ss,
        isMainLine: ss >= 5.0 && s.limitUpCount >= 1,
        momentum: momentum,
      ));
    }

    analyses.sort((a, b) => b.strengthScore.compareTo(a.strengthScore));

    for (int i = 0; i < analyses.length; i++) {
      analyses[i].rank = i + 1;
    }

    final topSectors = analyses.take(5).toList();
    final mainLines = analyses.asMap().entries.where((e) {
      if (e.value.isMainLine) return true;
      if (e.key < 2 && e.value.strengthScore >= 4.0) return true;
      return false;
    }).map((e) => e.value).toList();

    final rotationSignals = _detectRotationSignals(analyses);

    return SectorRotationResult(
      topSectors: topSectors,
      mainLines: mainLines,
      updateTime: DateTime.now(),
      rotationSignals: rotationSignals,
    );
  }

  static List<SectorRotationSignal> _detectRotationSignals(
      List<SectorAnalysis> analyses) {
    final signals = <SectorRotationSignal>[];
    if (analyses.length < 2) return signals;

    final strong = analyses.where((a) => a.strengthScore > 5).toList();
    final weak = analyses.where((a) => a.strengthScore < 2).toList();

    for (final s in strong.take(2)) {
      for (final w in weak.take(2)) {
        if (s.mainNetFlow > 2 && w.mainNetFlow < -2) {
          String type = 'sectorRotation';
          if (s.isMainLine && !w.isMainLine) type = 'mainLineSwitch';
          else if (s.changePct > 3 && w.changePct < -1) type = 'capitalFlight';
          else if (s.changePct < 2 && w.changePct > -0.5) type = 'sectorCatchUp';

          signals.add(SectorRotationSignal(
            fromSector: w.name,
            toSector: s.name,
            strength: (s.strengthScore - w.strengthScore).clamp(0.0, 10.0),
            type: type,
          ));
        }
      }
    }

    return signals;
  }

  static StockSectorCorrelation calcStockSectorCorrelation({
    required String code,
    required String sectorCode,
    required double stockChangePct,
    required double sectorChangePct,
    required double marketChangePct,
  }) {
    final stockAlpha = stockChangePct - marketChangePct;
    final sectorAlpha = sectorChangePct - marketChangePct;

    double correlation = 0.5;
    if (sectorAlpha != 0) {
      correlation = (stockAlpha / sectorAlpha).clamp(-1.0, 1.0);
    }

    double beta = 1.0;
    if (marketChangePct.abs() > 0.5) {
      beta = (stockChangePct / marketChangePct).clamp(0.0, 3.0);
    }

    final isLeading = stockAlpha > 2.0 && stockChangePct > sectorChangePct;

    return StockSectorCorrelation(
      code: code,
      sectorCode: sectorCode,
      correlation: correlation,
      beta: beta,
      isLeading: isLeading,
    );
  }

  static bool isInMainLine(String sector, List<SectorAnalysis> lines) =>
      lines.any((s) => s.name == sector || s.code == sector);

  static double getMainLineBonus(String sector, List<SectorAnalysis> lines) {
    for (final l in lines) {
      if (l.name == sector || l.code == sector) {
        return 1.0 + (l.strengthScore / 20.0).clamp(0.0, 0.3);
      }
    }
    return 1.0;
  }
}
