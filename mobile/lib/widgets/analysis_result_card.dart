import 'package:flutter/material.dart';
import '../models/stock_models.dart';

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
        color: const Color(0xFF0f3460),
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

          const SizedBox(height: 16),

          // 详细理由时间轴
          if (analysis.detailedReasons.isNotEmpty)
            _buildDetailedReasons(context, textTheme),

          const SizedBox(height: 12),

          // 推荐等级和风险等级
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
  Widget _build10LevelScore(BuildContext context, TextTheme textTheme) {
    final score = analysis.score;
    final confidence = analysis.confidenceScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('10级评分', style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
            Text('$score/10', style: textTheme.titleLarge?.copyWith(color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: score / 10,
            backgroundColor: const Color(0xFF16213e),
            valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(score)),
          ),
        ),
        const SizedBox(height: 4),
        Text('推荐可信度：${(confidence * 100).toStringAsFixed(0)}%', style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
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
        Text('可信度评估', style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: confidence,
                  backgroundColor: const Color(0xFF16213e),
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
        Text('综合考虑：共振信号、基本面、市场环境等因素', style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      ],
    );
  }

  /// 详细理由时间轴
  Widget _buildDetailedReasons(BuildContext context, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('详细理由', style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 12),
        ...List.generate(analysis.detailedReasons.length, (index) {
          final reason = analysis.detailedReasons[index];
          return _buildReasonItem(context, textTheme, reason, index);
        }),
      ],
    );
  }

  /// 单个理由项
  Widget _buildReasonItem(BuildContext context, TextTheme textTheme, RecommendationReason reason, int index) {
    final color = _getConfidenceColor(reason.confidence);

    return Container(
      margin: EdgeInsets.only(bottom: index < analysis.detailedReasons.length - 1 ? 8 : 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.3),
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
              color: color.withOpacity(0.2),
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

  /// 获取评分颜色
  Color _getScoreColor(int score) {
    if (score >= 9) return const Color(0xFF26a69a); // 强烈买入
    if (score >= 8) return const Color(0xFF4caf50); // 买入
    if (score >= 7) return const Color(0xFF8bc34a); // 谨慎买入
    if (score >= 5) return const Color(0xFFffb74d); // 观望
    if (score >= 4) return const Color(0xFFF44336); // 谨慎卖出
    if (score >= 3) return const Color(0xFFe57373); // 卖出
    return const Color(0xFFc62828); // 强烈卖出
  }

  /// 获取置信度颜色
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return const Color(0xFF26a69a);
    if (confidence >= 0.7) return const Color(0xFF8bc34a);
    if (confidence >= 0.6) return const Color(0xFFffb74d);
    if (confidence >= 0.5) return const Color(0xFFF44336);
    return const Color(0xFFc62828);
  }

  /// 获取推荐颜色
  Color _getRecommendationColor() {
    if (analysis.score >= 9) return const Color(0xFF26a69a);
    if (analysis.score >= 8) return const Color(0xFF4caf50);
    if (analysis.score >= 7) return const Color(0xFF8bc34a);
    if (analysis.score >= 5) return const Color(0xFFffb74d);
    if (analysis.score >= 4) return const Color(0xFFF44336);
    if (analysis.score >= 3) return const Color(0xFFe57373);
    return const Color(0xFFc62828);
  }

  /// 获取风险等级颜色
  Color _getRiskLevelColor() {
    if (analysis.riskLevel == '低') return const Color(0xFF26a69a);
    if (analysis.riskLevel == '中') return const Color(0xFFffb74d);
    return const Color(0xFFe57373);
  }
}
