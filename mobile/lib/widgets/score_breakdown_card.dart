import 'package:flutter/material.dart';

import '../analysis/scoring_config.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

/// 评分明细卡片（P1.2 + P2.3）。
///
/// 展示"为什么是这个分/推荐"：5 维方向证据的逐项贡献，以及（当
/// [ScoringConfig.showCalibratedProbability] 开启且样本充足时）该决策 1/3/5 日的
/// 真实命中概率与 Wilson 区间。数据全部来自已算好的 [AnalysisResult]，不重算。
class ScoreBreakdownCard extends StatelessWidget {
  final double score;
  final String recommendation;
  final Map<String, double>? dimensionScores;
  final Map<int, CalibrationEstimate>? calibrationByHorizon;

  const ScoreBreakdownCard({
    super.key,
    required this.score,
    required this.recommendation,
    required this.dimensionScores,
    required this.calibrationByHorizon,
  });

  factory ScoreBreakdownCard.fromAnalysis(AnalysisResult a) {
    return ScoreBreakdownCard(
      score: a.score,
      recommendation: a.recommendation,
      dimensionScores: a.dimensionScores,
      calibrationByHorizon: a.shortTermDecision?.calibrationByHorizon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dims = dimensionScores;
    if (dims == null || dims.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('评分明细',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              Text('${score.toStringAsFixed(1)} 分 · $recommendation',
                  style: TextStyle(
                      color: _levelColor(recommendation),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('方向证据贡献（0-10）',
              style: TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 6),
          for (final e in dims.entries) _dimRow(e.key, e.value, theme),
          if (_calibrationVisible()) ...[
            const Divider(color: Color(0xFF30363D), height: 20),
            _buildCalibration(theme),
          ],
        ],
      ),
    );
  }

  bool _calibrationVisible() {
    if (!ScoringConfig.showCalibratedProbability) return false;
    final c = calibrationByHorizon;
    return c != null && c.isNotEmpty;
  }

  Widget _buildCalibration(ThemeData theme) {
    final c = calibrationByHorizon!;
    final horizons = <int>[1, 3, 5].where(c.containsKey).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('历史校准胜率（真实命中概率）',
            style: TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 6),
        for (final h in horizons) _calibrationRow(h, c[h]!, theme),
      ],
    );
  }

  Widget _calibrationRow(int horizon, CalibrationEstimate est, ThemeData theme) {
    final pct = (est.probability * 100).toStringAsFixed(0);
    final lo = (est.wilsonLower * 100).toStringAsFixed(0);
    final hi = (est.wilsonUpper * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('$horizon 日',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Text('$pct%',
              style: const TextStyle(
                  color: Color(0xFFff9800),
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text('[$lo% ~ $hi%]  n=${est.sampleCount}',
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _dimRow(String name, double value, ThemeData theme) {
    final factor = (value / 10.0).clamp(0.0, 1.0);
    final color = value >= 6
        ? const Color(0xFFef5350)
        : (value <= 4 ? const Color(0xFF26a69a) : Colors.grey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(name,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(value.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Color _levelColor(String level) {
    if (level.contains('买入')) return const Color(0xFFef5350);
    if (level.contains('卖出')) return const Color(0xFF26a69a);
    return Colors.grey;
  }
}
