import '../models/stock_models.dart';
import 'market_structure_analyzer.dart';

class StructureTransition {
  final MarketStructure from;
  final MarketStructure to;
  final double confidence;
  final DateTime detectedAt;
  final String description;
  final List<String> evidence;

  const StructureTransition({
    required this.from,
    required this.to,
    required this.confidence,
    required this.detectedAt,
    required this.description,
    required this.evidence,
  });
}

class StructureTransitionDetector {
  static final Map<String, MarketStructureResult> _previousStructure = {};

  static StructureTransition? detect(
    String code,
    List<HistoryKline> data,
    MarketStructureResult current,
  ) {
    final previous = _previousStructure[code];
    _previousStructure[code] = current;

    if (previous == null) return null;
    if (current.structure == previous.structure) return null;
    if (data.length < 20) return null;

    final evidence = <String>[];
    double confidence = 0.5;

    if (_isAdxDirectionConsistent(current, previous)) {
      confidence += 0.2;
      evidence.add('ADX方向一致');
    }

    if (_isVolumePriceConfirming(data, current.type)) {
      confidence += 0.15;
      evidence.add('量价配合确认');
    }

    if (_isMaAlignmentConfirming(data, current.type)) {
      confidence += 0.15;
      evidence.add('均线排列确认');
    }

    return StructureTransition(
      from: previous.type,
      to: current.type,
      confidence: confidence.clamp(0.3, 0.95),
      detectedAt: DateTime.now(),
      description: '${_structureLabel(previous.type)}→${_structureLabel(current.type)}',
      evidence: evidence,
    );
  }

  static bool _isAdxDirectionConsistent(
    MarketStructureResult current,
    MarketStructureResult previous,
  ) {
    final toBullish = current.structure == MarketStructure.bullTrend ||
        current.structure == MarketStructure.accumulation;
    final toBearish = current.structure == MarketStructure.bearTrend ||
        current.structure == MarketStructure.distribution;

    if (toBullish && current.adxValue > previous.adxValue) return true;
    if (toBearish && current.adxValue > previous.adxValue) return true;
    if (current.structure == MarketStructure.consolidation &&
        current.adxValue < previous.adxValue) return true;
    return false;
  }

  static bool _isVolumePriceConfirming(
    List<HistoryKline> data,
    MarketStructure targetType,
  ) {
    if (data.length < 5) return false;
    final last = data.last;
    final prev = data[data.length - 2];

    final isUp = last.close > last.open;
    final volIncreasing = last.volume > prev.volume;

    final toBullish = targetType == MarketStructure.bullTrend ||
        targetType == MarketStructure.accumulation;
    if (toBullish && isUp && volIncreasing) return true;

    final toBearish = targetType == MarketStructure.bearTrend ||
        targetType == MarketStructure.distribution;
    if (toBearish && !isUp && volIncreasing) return true;

    return false;
  }

  static bool _isMaAlignmentConfirming(
    List<HistoryKline> data,
    MarketStructure targetType,
  ) {
    if (data.isEmpty) return false;
    final last = data.last;
    if (last.ma5 <= 0 || last.ma10 <= 0) return false;

    final bullishAlign = last.ma5 > last.ma10;
    final toBullish = targetType == MarketStructure.bullTrend ||
        targetType == MarketStructure.accumulation;
    if (toBullish && bullishAlign) return true;

    final toBearish = targetType == MarketStructure.bearTrend ||
        targetType == MarketStructure.distribution;
    if (toBearish && !bullishAlign) return true;

    return false;
  }

  static String _structureLabel(MarketStructure type) {
    return switch (type) {
      MarketStructure.bullTrend => '牛市',
      MarketStructure.bearTrend => '熊市',
      MarketStructure.consolidation => '震荡',
      MarketStructure.accumulation => '吸筹',
      MarketStructure.distribution => '派发',
    };
  }

  static void clearCache() {
    _previousStructure.clear();
  }
}
