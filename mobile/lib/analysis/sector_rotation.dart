class SectorAnalysis { String name, code; double changePct, mainNetFlow, strengthScore; int limitUpCount, consecutiveStrongDays; bool isMainLine;
  SectorAnalysis({required this.name, required this.code, this.changePct=0, this.limitUpCount=0, this.mainNetFlow=0, this.consecutiveStrongDays=0, this.strengthScore=0, this.isMainLine=false}); }

class SectorRotationResult { List<SectorAnalysis> topSectors, mainLines; DateTime? updateTime;
  SectorRotationResult({required this.topSectors, required this.mainLines, this.updateTime}); }

class SectorData { String name, code; double changePct, mainNetFlow; int limitUpCount;
  SectorData({required this.name, required this.code, this.changePct=0, this.limitUpCount=0, this.mainNetFlow=0}); }

class SectorRotation {
  static SectorRotationResult analyze({required List<SectorData> sectorList, Map<String, List<double>>? historyData}) {
    if (sectorList.isEmpty) return SectorRotationResult(topSectors: [], mainLines: []);
    final analyses = <SectorAnalysis>[];
    for (final s in sectorList) {
      double ss = 0;
      if (s.changePct > 3) ss += 3.0; else if (s.changePct > 2) ss += 2.5; else if (s.changePct > 1) ss += 2.0; else if (s.changePct > 0) ss += 1.2; else if (s.changePct > -1) ss += 0.5;
      if (s.limitUpCount >= 10) ss += 4.0; else if (s.limitUpCount >= 5) ss += 3.0; else if (s.limitUpCount >= 3) ss += 2.0; else if (s.limitUpCount >= 1) ss += 1.0;
      if (s.mainNetFlow > 5) ss += 2.0; else if (s.mainNetFlow > 2) ss += 1.5; else if (s.mainNetFlow > 0) ss += 0.8; else if (s.mainNetFlow < -3) ss -= 0.5;
      int cd = 0;
      if (historyData != null && historyData.containsKey(s.code)) for (int i = (historyData[s.code]?.length ?? 0) - 1; i >= 0; i--) { if ((historyData[s.code]?[i] ?? 0) >= 5.0) cd++; else break; }
      if (cd >= 3) ss += 1.0; else if (cd >= 2) ss += 0.5;
      analyses.add(SectorAnalysis(name: s.name, code: s.code, changePct: s.changePct, limitUpCount: s.limitUpCount, mainNetFlow: s.mainNetFlow, consecutiveStrongDays: cd, strengthScore: ss, isMainLine: ss >= 5.5 && s.limitUpCount >= 1));
    }
    analyses.sort((a, b) => b.strengthScore.compareTo(a.strengthScore));
    final topSectors = analyses.take(5).toList();
    final mainLines = analyses.asMap().entries.where((e) => e.value.isMainLine || (e.key < 3 && e.value.strengthScore >= 4.5)).map((e) => e.value).toList();
    return SectorRotationResult(topSectors: topSectors, mainLines: mainLines, updateTime: DateTime.now());
  }

  static bool isInMainLine(String sector, List<SectorAnalysis> lines) => lines.any((s) => s.name == sector || s.code == sector);
  static double getMainLineBonus(String sector, List<SectorAnalysis> lines) {
    for (final l in lines) { if (l.name == sector || l.code == sector) return 1.0 + (l.strengthScore / 20.0).clamp(0.0, 0.3); }
    return 1.0;
  }
}
