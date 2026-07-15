import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../models/short_term_decision.dart';
import '../validators/data_validator.dart';
import 'short_term_decision_panel.dart';

/// 分析结果卡片（10级评分）
class AnalysisResultCard extends StatelessWidget {
  final AnalysisResult analysis;

  const AnalysisResultCard({
    super.key,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 10级评分可视化
          _build10LevelScore(context, textTheme),

          const SizedBox(height: 16),

          // 推荐可信度仪表盘
          _buildConfidenceDashboard(context, textTheme),

          const SizedBox(height: 12),

          // 3.3 数据时效透明化：展示行情时间，陈旧则告警
          _buildDataFreshness(context, textTheme),

          const SizedBox(height: 12),

          // Batch 4 短线方向预测（方向 + 概率 + 持有期）
          if (analysis.directionForecast != null)
            _buildDirectionForecast(context, textTheme),

          const SizedBox(height: 16),

          if (analysis.shortTermDecision != null) ...[
            ShortTermDecisionPanel(
              decision: analysis.shortTermDecision!,
              recommendation: analysis.recommendationDecision ??
                  RecommendationDecision(
                    direction: analysis.shortTermDecision!.direction,
                    level: RecommendationLevel.neutralWatch,
                    label: analysis.recommendation,
                    legacyScore: analysis.score.clamp(1, 10),
                    actionable: analysis.score >= 6,
                  ),
            ),
            const SizedBox(height: 16),
          ],

          // 详细理由时间轴
          if (analysis.detailedReasons.isNotEmpty)
            _buildDetailedReasons(context, textTheme),

          const SizedBox(height: 12),

          // 推荐等级和风险等级
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getRecommendationColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  analysis.recommendation,
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getRiskLevelColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '风险等级：${analysis.riskLevel}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 10级评分可视化
  Map<String, dynamic>? get _nextSessionPrediction {
    final raw = analysis.nextDayPrediction?['next_session'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return analysis.nextDayPrediction;
  }

  Widget _buildNextSessionPrediction(
    BuildContext context,
    TextTheme textTheme,
  ) {
    final prediction = _nextSessionPrediction!;
    final openUp = _asDouble(prediction['next_open_up_probability']);
    final closeUp = _asDouble(prediction['next_close_up_probability']);
    final downside = _asDouble(prediction['downside_risk_probability']);
    final confidence = _asDouble(prediction['confidence']);
    final sampleCount = _asInt(prediction['sample_count']);
    final tags = _asStringList(prediction['scenario_tags']);
    final warnings = _asStringList(prediction['risk_warnings']);
    final color = downside >= 0.55
        ? const Color(0xFFef5350)
        : closeUp >= 0.6
            ? const Color(0xFF26a69a)
            : const Color(0xFFffb74d);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\u6b21\u4ea4\u6613\u9884\u6d4b',
                style: textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '\u6837\u672c $sampleCount | \u7f6e\u4fe1 ${_formatPercent(confidence)}',
                style: textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildPredictionChip(
                textTheme,
                '\u5f00\u76d8\u4e0a\u6da8 ${_formatPercent(openUp)}',
                const Color(0xFF8bc34a),
              ),
              _buildPredictionChip(
                textTheme,
                '\u6536\u76d8\u4e0a\u6da8 ${_formatPercent(closeUp)}',
                const Color(0xFF26a69a),
              ),
              _buildPredictionChip(
                textTheme,
                '\u4e0b\u8dcc\u98ce\u9669 ${_formatPercent(downside)}',
                const Color(0xFFef5350),
              ),
            ],
          ),
          if (tags.isNotEmpty || warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [...tags, ...warnings].take(4).join(' / '),
              style: textTheme.bodySmall?.copyWith(color: Colors.white60),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPredictionChip(
    TextTheme textTheme,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble().clamp(0.0, 1.0);
    return 0;
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return 0;
  }

  List<String> _asStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  String _formatPercent(double value) => '${(value * 100).round()}%';

  Widget _build10LevelScore(BuildContext context, TextTheme textTheme) {
    final score = analysis.score;
    final confidence = analysis.confidenceScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('10级评分',
                style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
            Text('$score/10',
                style: textTheme.titleLarge?.copyWith(color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: score / 10,
            backgroundColor: const Color(0xFF161B22),
            valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(score)),
          ),
        ),
        const SizedBox(height: 4),
        Text('推荐可信度：${(confidence * 100).toStringAsFixed(0)}%',
            style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
      ],
    );
  }

  /// 推荐可信度仪表盘
  Widget _buildConfidenceDashboard(BuildContext context, TextTheme textTheme) {
    final confidence = analysis.confidenceScore;
    final color = _getConfidenceColor(confidence);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('可信度评估',
            style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: confidence,
                  backgroundColor: const Color(0xFF161B22),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(confidence * 100).toStringAsFixed(0)}%',
              style: textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('综合考虑：共振信号、基本面、市场环境等因素',
            style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
        if (analysis.nextDayPrediction != null) ...[
          const SizedBox(height: 12),
          _buildNextSessionPrediction(context, textTheme),
        ],
      ],
    );
  }

  /// 详细理由时间轴
  Widget _buildDetailedReasons(BuildContext context, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('详细理由',
            style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 12),
        ...List.generate(analysis.detailedReasons.length, (index) {
          final reason = analysis.detailedReasons[index];
          return _buildReasonItem(context, textTheme, reason, index);
        }),
      ],
    );
  }

  /// 单个理由项
  Widget _buildReasonItem(BuildContext context, TextTheme textTheme,
      RecommendationReason reason, int index) {
    final color = _getConfidenceColor(reason.confidence);

    return Container(
      margin: EdgeInsets.only(
          bottom: index < analysis.detailedReasons.length - 1 ? 8 : 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${index + 1}. ${reason.title}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        reason.duration,
                        style: textTheme.bodySmall?.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reason.description,
                  style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(reason.confidence * 100).toStringAsFixed(0)}%',
              style: textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取评分颜色（与comprehensive_scorer推荐逻辑一致）
  Color _getScoreColor(int score) {
    if (score >= 8) return const Color(0xFF26a69a); // 强烈买入 (8-10)
    if (score >= 7) return const Color(0xFF4caf50); // 买入 (7)
    if (score >= 6) return const Color(0xFF8bc34a); // 谨慎买入 (6)
    if (score >= 5) return const Color(0xFFffb74d); // 偏多观望 (5)
    if (score >= 4) return const Color(0xFFff9800); // 偏空观望 (4)
    if (score >= 3) return const Color(0xFFF44336); // 谨慎卖出 (3)
    if (score >= 2) return const Color(0xFFe57373); // 卖出 (2)
    return const Color(0xFFc62828); // 强烈卖出 (1)
  }

  /// 获取置信度颜色
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return const Color(0xFF26a69a);
    if (confidence >= 0.7) return const Color(0xFF8bc34a);
    if (confidence >= 0.6) return const Color(0xFFffb74d);
    if (confidence >= 0.5) return const Color(0xFFF44336);
    return const Color(0xFFc62828);
  }

  /// 获取推荐颜色（与comprehensive_scorer推荐逻辑一致）
  Color _getRecommendationColor() {
    return _getScoreColor(analysis.score);
  }

  /// 获取风险等级颜色
  Color _getRiskLevelColor() {
    if (analysis.riskLevel == '低') return const Color(0xFF26a69a);
    if (analysis.riskLevel == '中') return const Color(0xFFffb74d);
    return const Color(0xFFe57373);
  }

  /// Batch 4 短线方向预测展示（方向 + 概率 + 持有期 + 可解释证据）
  Widget _buildDirectionForecast(BuildContext context, TextTheme textTheme) {
    final f = analysis.directionForecast!;
    final dirColor = switch (f.direction) {
      RecommendationDirection.bullish => const Color(0xFFef5350),
      RecommendationDirection.bearish => const Color(0xFF26a69a),
      RecommendationDirection.neutral => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dirColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dirColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '短线方向',
                style: textTheme.bodySmall
                    ?.copyWith(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 8),
              Text(
                '${f.directionLabel}',
                style: textTheme.titleMedium?.copyWith(
                  color: dirColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '概率 ${(f.probability * 100).toStringAsFixed(0)}%',
                style: textTheme.bodyMedium
                    ?.copyWith(color: dirColor, fontSize: 13),
              ),
              const SizedBox(width: 6),
              Text(
                '${f.horizonDays}日',
                style: textTheme.bodySmall
                    ?.copyWith(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          if (f.supportingEvidence.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              f.supportingEvidence.take(3).join(' · '),
              style: textTheme.bodySmall
                  ?.copyWith(color: Colors.white54, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (f.momentumPenalized)
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 3.3 数据时效透明化：展示行情更新时间，陈旧时给出告警
  Widget _buildDataFreshness(BuildContext context, TextTheme textTheme) {
    final quote = analysis.quote;
    if (quote == null) return const SizedBox.shrink();

    final updated = quote.updateTime;
    final stale = DataValidator.isStaleQuote(quote);
    final timeStr = updated != null
        ? '${updated.hour.toString().padLeft(2, '0')}:'
            '${updated.minute.toString().padLeft(2, '0')}'
        : '未知';
    final color = stale ? const Color(0xFFffb74d) : Colors.white54;

    return Row(
      children: [
        Icon(
          stale ? Icons.warning_amber_rounded : Icons.access_time,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '行情时间 $timeStr',
          style: textTheme.bodySmall?.copyWith(color: color, fontSize: 11),
        ),
        if (stale) ...[
          const SizedBox(width: 6),
          Text(
            '数据可能延迟',
            style: textTheme.bodySmall?.copyWith(
              color: const Color(0xFFffb74d),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
