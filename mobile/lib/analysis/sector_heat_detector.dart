import 'sector_rotation.dart';

class SectorHeatDetector {
  const SectorHeatDetector._();

  static bool isOverheated(SectorAnalysis sector) {
    if (sector.consecutiveStrongDays >= 3 && sector.limitUpCount >= 5) {
      return true;
    }
    if (sector.changePct > 8 && sector.limitUpCount >= 8) {
      return true;
    }
    return false;
  }

  static bool isOverheatedByName(String sectorName, List<SectorAnalysis> sectors) {
    for (final s in sectors) {
      if (s.name == sectorName) {
        return isOverheated(s);
      }
    }
    return false;
  }

  static double getHeatDiscount(String sectorName, List<SectorAnalysis> sectors) {
    if (isOverheatedByName(sectorName, sectors)) {
      return 0.85;
    }
    return 1.0;
  }
}