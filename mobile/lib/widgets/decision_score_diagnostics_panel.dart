import 'package:flutter/material.dart';

import '../analysis/decision_score_diagnostics.dart';
import '../analysis/directional_evidence_builder.dart';
import '../models/short_term_decision.dart';

class DecisionScoreDiagnosticsPanel extends StatelessWidget {
  final DecisionScoreDiagnosticsResult diagnostics;

  const DecisionScoreDiagnosticsPanel({
    super.key,
    required this.diagnostics,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            title: '方向分布',
            child: _directionDistribution(),
          ),
          const SizedBox(height: 10),
          _section(
            title: '评分梯度',
            subtitle: '同方向分数越强，命中与方向化收益应逐档改善',
            child: _scoreGradient(),
          ),
          const SizedBox(height: 10),
          _section(
            title: '五维相关性',
            subtitle: '至少 30 条成熟样本、10 个信号日才展示 Spearman',
            child: _correlations(),
          ),
          const SizedBox(height: 10),
          _section(
            title: '调权准备度',
            subtitle: '仅提示是否具备设计下一版的样本条件，不自动改权重',
            child: _readiness(),
          ),
        ],
      );

  Widget _directionDistribution() {
    final distribution = diagnostics.distribution;
    final total = distribution.totalCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: total == 0
                ? const ColoredBox(color: Color(0xFF30363D))
                : Row(
                    children: [
                      if (distribution.bullishCount > 0)
                        Expanded(
                          flex: distribution.bullishCount,
                          child: const ColoredBox(color: Color(0xFFEF5350)),
                        ),
                      if (distribution.neutralCount > 0)
                        Expanded(
                          flex: distribution.neutralCount,
                          child: const ColoredBox(color: Color(0xFFD29922)),
                        ),
                      if (distribution.bearishCount > 0)
                        Expanded(
                          flex: distribution.bearishCount,
                          child: const ColoredBox(color: Color(0xFF26A69A)),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _legend('看多', distribution.bullishRatio, distribution.bullishCount,
                const Color(0xFFEF5350)),
            _legend('中性', distribution.neutralRatio, distribution.neutralCount,
                const Color(0xFFD29922)),
            _legend('看空', distribution.bearishRatio, distribution.bearishCount,
                const Color(0xFF26A69A)),
          ],
        ),
        if (distribution.isBiased) ...[
          const SizedBox(height: 8),
          Text(
            '方向分布明显偏斜：${_directionLabel(distribution.biasedDirection!)}占比超过 70%',
            style: const TextStyle(color: Color(0xFFD29922), fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _scoreGradient() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 38,
              dataRowMaxHeight: 46,
              horizontalMargin: 8,
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('档位')),
                DataColumn(label: Text('看多')),
                DataColumn(label: Text('看空')),
              ],
              rows: [
                for (final bucket in DecisionScoreBucket.values)
                  DataRow(cells: [
                    DataCell(Text(bucket.label)),
                    DataCell(_bucketCell(
                      diagnostics.bucket(
                        RecommendationDirection.bullish,
                        bucket,
                      ),
                    )),
                    DataCell(_bucketCell(
                      diagnostics.bucket(
                        RecommendationDirection.bearish,
                        bucket,
                      ),
                    )),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _monotonicityChip('看多', diagnostics.bullishMonotonicity),
              _monotonicityChip('看空', diagnostics.bearishMonotonicity),
            ],
          ),
        ],
      );

  Widget _correlations() {
    final items = <(String, DecisionCorrelationResult)>[
      ('总方向分', diagnostics.scoreCorrelation),
      for (final entry in diagnostics.componentCorrelations.entries)
        (_componentLabel(entry.key), entry.value),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Container(
              width: 142,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$1,
                      style: const TextStyle(
                          color: Color(0xFF8B949E), fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(
                    item.$2.coefficient == null
                        ? '待积累'
                        : item.$2.coefficient!.toStringAsFixed(3),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _correlationColor(item.$2.coefficient),
                    ),
                  ),
                  Text(
                    'n=${item.$2.sampleCount} · ${item.$2.signalDateCount}日',
                    style:
                        const TextStyle(color: Color(0xFF6E7681), fontSize: 10),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _readiness() {
    final readiness = diagnostics.readiness;
    final items = <(String, bool)>[
      ('四个强度桶各 100 条', readiness.bucketSamplesReady),
      ('至少 20 个信号日', readiness.signalDatesReady),
      ('1/3/5 日标签完整率 ≥95%', readiness.labelCompletenessReady),
      ('覆盖四类市场状态', readiness.marketRegimesReady),
      ('可按时间切分验证', readiness.timeSplitReady),
      ('相关性与单调性可用', readiness.diagnosticsReady),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: item.$2
                      ? const Color(0xFF3FB950)
                      : const Color(0xFF6E7681),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(item.$1, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          readiness.isReady ? '已具备下一版调权设计条件' : '继续积累，不自动调整生产权重',
          style: TextStyle(
            color: readiness.isReady
                ? const Color(0xFF3FB950)
                : const Color(0xFFD29922),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        Text(
          '标签完整率 ${(readiness.labelCompleteness * 100).toStringAsFixed(1)}% · '
          '${readiness.signalDateCount} 个信号日',
          style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10),
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    String? subtitle,
    required Widget child,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _legend(String label, double ratio, int count, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '$label ${(ratio * 100).toStringAsFixed(1)}% (n=$count)',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      );

  Widget _bucketCell(DecisionScoreBucketSummary item) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.effectiveHitRate == null
                ? '--'
                : '${(item.effectiveHitRate! * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            'n=${item.sampleCount} · '
            '${item.meanOrientedReturn?.toStringAsFixed(2) ?? '--'}%',
            style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10),
          ),
        ],
      );

  Widget _monotonicityChip(
    String label,
    DecisionMonotonicityResult result,
  ) {
    final color = result.isMonotonic == null
        ? const Color(0xFF6E7681)
        : result.isMonotonic!
            ? const Color(0xFF3FB950)
            : const Color(0xFFD29922);
    final status = result.isMonotonic == null
        ? '待积累'
        : result.isMonotonic!
            ? '单调'
            : '有反转';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label $status · ${result.eligiblePairCount}组',
          style: TextStyle(color: color, fontSize: 11)),
    );
  }

  static String _directionLabel(RecommendationDirection direction) =>
      switch (direction) {
        RecommendationDirection.bullish => '看多',
        RecommendationDirection.neutral => '中性',
        RecommendationDirection.bearish => '看空',
      };

  static String _componentLabel(String key) => switch (key) {
        trendComponentKey => '趋势',
        reversalMomentumComponentKey => '反转/动量',
        volumeFlowComponentKey => '量价/资金',
        relativeStrengthComponentKey => '相对强弱',
        nextSessionComponentKey => '次日预测',
        _ => key,
      };

  static Color _correlationColor(double? value) {
    if (value == null) return const Color(0xFF8B949E);
    if (value > 0) return const Color(0xFF3FB950);
    if (value < 0) return const Color(0xFFEF5350);
    return const Color(0xFF8B949E);
  }
}
