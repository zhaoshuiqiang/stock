import 'package:flutter/material.dart';

import '../models/short_term_decision.dart';

class ShortTermDecisionPanel extends StatefulWidget {
  final ShortTermDecision decision;
  final RecommendationDecision recommendation;
  final int initialHorizon;

  const ShortTermDecisionPanel({
    super.key,
    required this.decision,
    required this.recommendation,
    this.initialHorizon = 1,
  });

  @override
  State<ShortTermDecisionPanel> createState() => _ShortTermDecisionPanelState();
}

class _ShortTermDecisionPanelState extends State<ShortTermDecisionPanel> {
  late int _horizon = widget.initialHorizon;

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final estimate = decision.calibrationByHorizon[_horizon];
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
          Row(children: [
            Expanded(
              child: Text(
                widget.recommendation.label,
                style: const TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${widget.recommendation.legacyScore}/10',
              style: const TextStyle(color: Color(0xFF8B949E)),
            ),
          ]),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _metric(Icons.explore, '方向强度',
                  decision.directionScore.toStringAsFixed(0)),
              _metric(Icons.assessment, '交易质量',
                  '${decision.tradeQualityScore.toStringAsFixed(0)}/100'),
              _metric(Icons.shield_outlined, '风险',
                  '${decision.riskScore.toStringAsFixed(0)}/100'),
              _metric(Icons.fact_check_outlined, '证据置信',
                  '${decision.evidenceConfidence.toStringAsFixed(0)}/100'),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1日')),
              ButtonSegment(value: 3, label: Text('3日')),
              ButtonSegment(value: 5, label: Text('5日')),
            ],
            selected: {_horizon},
            onSelectionChanged: (value) =>
                setState(() => _horizon = value.first),
            showSelectedIcon: false,
          ),
          if (estimate != null) ...[
            const SizedBox(height: 8),
            Text(
              '${estimate.isColdStart ? '校准小样本参考 ' : '校准有效命中率 '}${(estimate.probability * 100).toStringAsFixed(1)}%  '
              'n=${estimate.sampleCount}  '
              '[${(estimate.wilsonLower * 100).toStringAsFixed(1)}%, '
              '${(estimate.wilsonUpper * 100).toStringAsFixed(1)}%]',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              '暂无${_horizon}日校准数据（需积累历史决策记录，请先使用“全市场扫描”生成决策快照）',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Icon(icon, size: 17, color: const Color(0xFF58A6FF)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF8B949E), fontSize: 11)),
                Text(value,
                    maxLines: 1,
                    style: const TextStyle(
                        color: Color(0xFFF0F6FC),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ]),
      );
}
