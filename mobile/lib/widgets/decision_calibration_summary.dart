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
          _metric('方向化平均收益', summary.meanOrientedReturn),
          _metric('方向化中位收益', summary.medianOrientedReturn),
          _metric('方向化平均 Alpha', summary.meanOrientedAlpha),
          _metric('方向化中位 Alpha', summary.medianOrientedAlpha),
          _metric('MFE', summary.meanMfe),
          _metric('MAE', summary.meanMae),
          const Divider(color: Color(0xFF30363D), height: 16),
          _metric('原始平均收益', summary.meanReturn, subdued: true),
          _metric('原始平均 Alpha', summary.meanAlpha, subdued: true),
          Text('Brier: ${_calibrationValue(summary.calibration.brier)}'),
          Text('ECE: ${_calibrationValue(summary.calibration.ece)}'),
          Text(
            '已收集 ${summary.calibration.sampleCount}/30 条，'
            '${summary.calibration.signalDateCount}/10 个信号日',
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, double? value, {bool subdued = false}) => Row(
        children: [
          Text(
            label,
            style: subdued
                ? const TextStyle(color: Color(0xFF8B949E), fontSize: 12)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            value == null ? '--' : '${value.toStringAsFixed(2)}%',
            style: subdued
                ? const TextStyle(color: Color(0xFF8B949E), fontSize: 12)
                : null,
          ),
        ],
      );

  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  String _calibrationValue(double? value) =>
      value == null ? '样本不足' : value.toStringAsFixed(4);
}
