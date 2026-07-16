import 'weight_calibrator.dart';

class WeightCalibrationCache {
  static WeightCalibrationResult? _latest;
  static DateTime? _lastCalibrated;

  static const _calibrationInterval = Duration(hours: 4);

  static WeightCalibrationResult? get latest {
    if (_lastCalibrated != null &&
        DateTime.now().difference(_lastCalibrated!) < _calibrationInterval) {
      return _latest;
    }
    return null;
  }

  static void update(WeightCalibrationResult result) {
    if (_latest != null && result.isValid) {
      final blended = _blendWithPrevious(_latest!, result);
      _latest = blended;
    } else {
      _latest = result;
    }
    _lastCalibrated = DateTime.now();
  }

  static WeightCalibrationResult _blendWithPrevious(
    WeightCalibrationResult old,
    WeightCalibrationResult current,
  ) {
    final blendedStrategy = <String, double>{};
    for (final entry in current.strategyAdjustments.entries) {
      final oldVal = old.strategyAdjustments[entry.key] ?? 1.0;
      blendedStrategy[entry.key] = oldVal * 0.7 + entry.value * 0.3;
    }

    final blendedRegime = <String, Map<String, double>>{};
    for (final regimeEntry in current.regimeAdjustments.entries) {
      final oldRegime = old.regimeAdjustments[regimeEntry.key] ?? {};
      final blended = <String, double>{};
      for (final stratEntry in regimeEntry.value.entries) {
        final oldVal = oldRegime[stratEntry.key] ?? 1.0;
        blended[stratEntry.key] = oldVal * 0.7 + stratEntry.value * 0.3;
      }
      blendedRegime[regimeEntry.key] = blended;
    }

    return WeightCalibrationResult(
      strategyAdjustments: blendedStrategy,
      regimeAdjustments: blendedRegime,
      calibratedAt: current.calibratedAt,
      sampleCount: current.sampleCount,
      isValid: current.isValid,
    );
  }

  static void clear() {
    _latest = null;
    _lastCalibrated = null;
  }
}
