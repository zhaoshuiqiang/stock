import 'package:flutter/material.dart';

import '../analysis/decision_statistics.dart';

class DecisionArchiveSummary extends StatelessWidget {
  final DecisionStatisticsSummary summary;
  final int horizon;
  final ValueChanged<int> onHorizonChanged;

  const DecisionArchiveSummary({
    super.key,
    required this.summary,
    required this.horizon,
    required this.onHorizonChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1日')),
              ButtonSegment(value: 3, label: Text('3日')),
              ButtonSegment(value: 5, label: Text('5日')),
            ],
            selected: {horizon},
            onSelectionChanged: (value) => onHorizonChanged(value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 10),
          Text('$horizon日结果', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metric(
                    '看多命中',
                    summary.bullishEffectiveHitRate,
                    'n=${summary.bullishSampleCount}',
                    width,
                  ),
                  _metric(
                    '看空命中',
                    summary.bearishEffectiveHitRate,
                    'n=${summary.bearishSampleCount}',
                    width,
                  ),
                  _metric(
                    '多空平衡',
                    summary.balancedEffectiveHitRate,
                    '多${summary.bullishSampleCount} / 空${summary.bearishSampleCount}',
                    width,
                  ),
                  _metric(
                    '中性稳定',
                    summary.neutralStabilityRate,
                    'n=${summary.neutralSampleCount}',
                    width,
                  ),
                  _metric(
                    'Alpha命中',
                    summary.alphaHitRate,
                    'n=${summary.alphaHitSampleCount}',
                    width,
                  ),
                  _metric('覆盖率', summary.coverage, null, width),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 6, children: [
            Text('已评估 ${summary.evaluatedCount}'),
            Text('待评估 ${summary.pendingCount}'),
            Text('到期未评估 ${summary.maturedPendingCount}'),
            Text('无效 ${summary.invalidCount}'),
          ]),
        ],
      );

  Widget _metric(
    String label,
    double? value,
    String? sampleLabel,
    double width,
  ) =>
      SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
              Text(
                value == null ? '--' : '${(value * 100).toStringAsFixed(1)}%',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (sampleLabel != null)
                Text(
                  sampleLabel,
                  style:
                      const TextStyle(color: Color(0xFF6E7681), fontSize: 10),
                ),
            ],
          ),
        ),
      );
}
