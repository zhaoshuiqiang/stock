import 'package:flutter/material.dart';

import '../analysis/decision_statistics.dart';

class DecisionCalibrationSummary extends StatelessWidget {
  final DecisionStatisticsSummary summary;

  const DecisionCalibrationSummary({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final wilson = summary.rawHitWilson;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('校准与结果质量', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (wilson != null)
            Row(
              children: [
                const Text('Wilson 95%'),
                const SizedBox(width: 8),
                Text('${_percent(wilson.lower)} ~ ${_percent(wilson.upper)}'),
              ],
            ),
          _metric('平均收益', summary.meanReturn),
          _metric('中位收益', summary.medianReturn),
          _metric('平均 Alpha', summary.meanAlpha),
          _metric('中位 Alpha', summary.medianAlpha),
          _metric('MFE', summary.meanMfe),
          _metric('MAE', summary.meanMae),
          Text('Brier: ${_calibrationValue(summary.calibration.brier)}'),
          Text('ECE: ${_calibrationValue(summary.calibration.ece)}'),
          Text(
            '概率样本 ${summary.calibration.sampleCount}  '
            '信号日 ${summary.calibration.signalDateCount}',
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, double? value) => Row(
        children: [
          Text(label),
          const SizedBox(width: 8),
          Text(value == null ? '--' : '${value.toStringAsFixed(2)}%'),
        ],
      );

  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  String _calibrationValue(double? value) =>
      value == null ? '样本不足' : value.toStringAsFixed(4);
}
