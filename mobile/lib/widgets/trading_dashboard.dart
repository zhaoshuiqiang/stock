import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import 'score_radar_chart.dart';
import 'score_breakdown_card.dart';
import 'position_context_card.dart';
import 'skeleton_loader.dart';
import 'score_trend_chart.dart';
import '../analysis/chip_distribution_analyzer.dart';
import 'short_term_decision_panel.dart';
import '../models/short_term_decision.dart';

/// 交易仪表盘：聚合短线交易关键决策信息
/// 替代传统多Tab翻页模式，一屏展示全部决策要点
class TradingDashboard extends StatelessWidget {
  final QuoteData? quote;
  final AnalysisResult? analysis;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final String lastUpdateTime;
  final List<Map<String, dynamic>>? scoreTrend;
  final ChipDistribution? chipDistribution;
  final Position? position;

  const TradingDashboard({
    super.key,
    this.quote,
    this.analysis,
    this.onRefresh,
    this.isRefreshing = false,
    this.lastUpdateTime = '',
    this.scoreTrend,
    this.chipDistribution,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    if (quote == null || analysis == null) {
      return _buildLoading();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuoteHeader(),
          const SizedBox(height: 8),
          if (analysis!.shortTermDecision != null)
            ShortTermDecisionPanel(
              decision: analysis!.shortTermDecision!,
              recommendation: analysis!.recommendationDecision ??
                  RecommendationDecision(
                    direction: analysis!.shortTermDecision!.direction,
                    level: RecommendationLevel.neutralWatch,
                    label: analysis!.recommendation,
                    legacyScore: analysis!.score.clamp(1.0, 10.0),
                    actionable: analysis!.score >= 6,
                  ),
            )
          else
            _buildScoreRow(),
          const SizedBox(height: 10),
          if (analysis!.dimensionScores != null) _buildScoreRadarCard(),
          const SizedBox(height: 10),
          if (analysis!.dimensionScores != null) ...[
            ScoreBreakdownCard.fromAnalysis(analysis!),
            const SizedBox(height: 10),
          ],
          if (position != null) ...[
            PositionContextCard(
              score: analysis!.score,
              currentPrice: quote?.price ?? position!.avgPrice,
              avgPrice: position!.avgPrice,
              quantity: position!.quantity,
              atr: (analysis!.tradeLevels?['atr'] as num?)?.toDouble() ?? 0,
              riskScore: analysis!.shortTermDecision?.riskScore ?? 50,
            ),
            const SizedBox(height: 10),
          ],
          _buildKeySignals(),
          if (analysis!.tradeLevels != null) ...[
            const SizedBox(height: 10),
            _buildTradeLevels(),
          ],
          // v3.23: 置信度8维拆解卡片
          if (analysis!.confidenceBreakdown != null &&
              analysis!.confidenceBreakdown!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildConfidenceBreakdownCard(),
          ],
          // v3.23: 方向5维证据分量
          if (analysis!.shortTermDecision != null &&
              analysis!.shortTermDecision!.directionComponents.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildDirectionComponentsCard(),
          ],
          if (analysis!.backtestSummary != null) ...[
            const SizedBox(height: 10),
            _buildBacktestCard(),
          ],
          const SizedBox(height: 10),
          _buildRiskRow(),
          if (analysis!.marketContext != null) ...[
            const SizedBox(height: 8),
            _buildMarketContextRow(),
          ],
          if (analysis!.momentumPersistence != null) ...[
            const SizedBox(height: 10),
            _buildMomentumPersistenceCard(),
          ],
          if (analysis!.nextDayPrediction != null) ...[
            const SizedBox(height: 10),
            _buildNextDayPredictionCard(),
          ],
          if (scoreTrend != null && scoreTrend!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildScoreTrendCard(),
          ],
          if (chipDistribution != null && chipDistribution!.isValid) ...[
            const SizedBox(height: 10),
            _buildChipCard(),
          ],
          if (analysis!.earlyWarningSignals != null &&
              analysis!.earlyWarningSignals!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildEarlyWarningSignalsCard(),
          ],
        ],
      ),
    );
  }

  // ─── 行情头部 ───────────────────────────────────────────

  Widget _buildQuoteHeader() {
    final q = quote!;
    final isUp = q.changePct >= 0;
    final color = isUp ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71);
    final sign = isUp ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          // 名称 + 代码
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      q.name,
                      style: const TextStyle(
                        color: Color(0xFFF0F6FC),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      q.code,
                      style: const TextStyle(
                          color: Color(0xFF8B949E), fontSize: 12),
                    ),
                    const Spacer(),
                    if (onRefresh != null)
                      GestureDetector(
                        onTap: isRefreshing ? null : onRefresh,
                        child: Icon(
                          Icons.refresh,
                          color: isRefreshing
                              ? const Color(0xFF58A6FF)
                              : const Color(0xFF8B949E),
                          size: 18,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      q.price.toStringAsFixed(2),
                      style: TextStyle(
                        color: color,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$sign${q.changePct.toStringAsFixed(2)}%',
                      style: TextStyle(color: color, fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$sign${q.change.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: color.withOpacity(0.8), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 评分行 ───────────────────────────────────────────

  Widget _buildScoreRow() {
    final a = analysis!;
    final scoreColor = a.score >= 8
        ? const Color(0xFF26a69a)
        : a.score >= 7
            ? const Color(0xFF4caf50)
            : a.score >= 6
                ? const Color(0xFF8bc34a)
                : a.score >= 5
                    ? const Color(0xFFffb74d)
                    : a.score >= 4
                        ? const Color(0xFFff9800)
                        : a.score >= 3
                            ? const Color(0xFFF44336)
                            : a.score >= 2
                                ? const Color(0xFFe57373)
                                : const Color(0xFFc62828);

    return Row(
      children: [
        _buildMetricChip('评分', '${a.score.toStringAsFixed(1)}/10', scoreColor),
        const SizedBox(width: 8),
        _buildMetricChip('推荐', a.recommendation, scoreColor),
        const SizedBox(width: 8),
        _buildMetricChip(
          '置信度',
          '${(a.confidenceScore * 100).toStringAsFixed(0)}%',
          const Color(0xFF58A6FF),
        ),
        const Spacer(),
        if (lastUpdateTime.isNotEmpty)
          Text(
            lastUpdateTime,
            style: const TextStyle(color: Color(0xFF484F58), fontSize: 10),
          ),
      ],
    );
  }

  // ─── 维度评分雷达图 (v3.19) ─────────────────────────────────

  Widget _buildScoreRadarCard() {
    final a = analysis!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 16, color: Color(0xFF58A6FF)),
              const SizedBox(width: 4),
              const Text(
                '评分维度拆解',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '综合 ${a.score.toStringAsFixed(1)}/10',
                style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: ScoreRadarChart(
              scores: a.dimensionScores!,
              totalScore: a.score,
              size: 220,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 关键信号 ───────────────────────────────────────────

  Widget _buildKeySignals() {
    final signals = analysis!.signals;
    final buys = signals.where((s) => s.type == 'buy').take(3).toList();
    final sells = signals.where((s) => s.type == 'sell').take(3).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on, size: 16, color: Color(0xFF58A6FF)),
              const SizedBox(width: 4),
              const Text(
                '交易信号',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '买${buySignals()} 卖${sellSignals()}',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (buys.isNotEmpty) ...[
            const Text('买入信号',
                style: TextStyle(color: Color(0xFFE74C3C), fontSize: 11)),
            ...buys.map((s) => _buildSignalRow(s, const Color(0xFFE74C3C))),
          ],
          if (sells.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('卖出信号',
                style: TextStyle(color: Color(0xFF2ECC71), fontSize: 11)),
            ...sells.map((s) => _buildSignalRow(s, const Color(0xFF2ECC71))),
          ],
        ],
      ),
    );
  }

  int buySignals() => analysis!.signals.where((s) => s.type == 'buy').length;
  int sellSignals() => analysis!.signals.where((s) => s.type == 'sell').length;

  Widget _buildSignalRow(SignalItem s, Color color) {
    final strengthBar = (s.strength / 100.0).clamp(0.0, 1.0);
    final durStr = s.duration == SignalDuration.shortTerm
        ? '短线'
        : s.duration == SignalDuration.mediumTerm
            ? '中线'
            : '长线';
    final confPct = s.confidence != null
        ? '${(s.confidence! * 100).toStringAsFixed(0)}%'
        : '--';

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      s.signal,
                      style: TextStyle(
                        color: color.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        durStr,
                        style: TextStyle(
                            color: color.withOpacity(0.8), fontSize: 9),
                      ),
                    ),
                  ],
                ),
                if (s.description.isNotEmpty)
                  Text(
                    s.description,
                    style:
                        const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(confPct,
                    style:
                        TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
                const SizedBox(height: 2),
                Container(
                  width: 50,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: strengthBar,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 交易价位 ───────────────────────────────────────────

  Widget _buildTradeLevels() {
    final tl = analysis!.tradeLevels!;
    final entryLow = tl['entry_low'] as double? ?? 0.0;
    final entryHigh = tl['entry_high'] as double? ?? 0.0;
    final stopLoss = tl['stop_loss'] as double? ?? 0.0;
    final rr = tl['risk_reward_ratio'] as double? ?? 0.0;
    final tp1 = tl['tp1'] as double?;
    final tp2 = tl['tp2'] as double?;
    final tp3 = tl['tp3'] as double?;
    final trailingActivation = tl['trailing_stop_activation'] as double?;
    final trailingDistance = tl['trailing_stop_distance'] as double?;
    final stopType = tl['stop_loss_type'] as String? ?? '固定止损';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, size: 16, color: Color(0xFF58A6FF)),
              SizedBox(width: 4),
              Text(
                '交易价位',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 入场区间
              Expanded(
                child: _buildPriceBlock(
                  '入场区间',
                  '${entryLow.toStringAsFixed(2)} - ${entryHigh.toStringAsFixed(2)}',
                  const Color(0xFF58A6FF),
                ),
              ),
              const SizedBox(width: 6),
              // 止损
              Expanded(
                child: _buildPriceBlock(
                  '止损 ($stopType)',
                  stopLoss.toStringAsFixed(2),
                  const Color(0xFF2ECC71),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (tp1 != null) ...[
                Expanded(
                  child: _buildPriceBlock(
                    '止盈1',
                    tp1.toStringAsFixed(2),
                    const Color(0xFFE74C3C),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (tp2 != null) ...[
                Expanded(
                  child: _buildPriceBlock(
                    '止盈2',
                    tp2.toStringAsFixed(2),
                    const Color(0xFFE74C3C),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: _buildPriceBlock(
                  '盈亏比',
                  rr >= 100 ? '极佳' : '1:${rr.toStringAsFixed(1)}',
                  rr >= 2.0
                      ? const Color(0xFFE74C3C)
                      : rr >= 1.0
                          ? const Color(0xFF58A6FF)
                          : const Color(0xFF8B949E),
                ),
              ),
            ],
          ),
          // v3.23: 止盈3 + 追踪止损
          if (tp3 != null || trailingActivation != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (tp3 != null)
                  Expanded(
                    child: _buildPriceBlock('止盈3', tp3.toStringAsFixed(2), const Color(0xFFE74C3C)),
                  ),
                if (tp3 != null && trailingActivation != null) const SizedBox(width: 6),
                if (trailingActivation != null)
                  Expanded(
                    child: _buildPriceBlock(
                      '追踪止损',
                      entryLow > 0
                          ? '涨${((trailingActivation - entryLow) / entryLow * 100).toStringAsFixed(1)}%启动'
                          : trailingActivation.toStringAsFixed(2),
                      const Color(0xFF58A6FF),
                    ),
                  ),
                if (trailingDistance != null) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildPriceBlock('追踪距离', trailingDistance.toStringAsFixed(2), const Color(0xFF58A6FF)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceBlock(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ─── 回测卡片 ───────────────────────────────────────────

  Widget _buildBacktestCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history, size: 16, color: Color(0xFF58A6FF)),
              SizedBox(width: 4),
              Text(
                '历史回测',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            analysis!.backtestSummary!,
            style: const TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 风险分析 ───────────────────────────────────────────

  Widget _buildRiskRow() {
    final factors = analysis!.riskFactors;
    final level = analysis!.riskLevel;
    final levelColor = level == '低'
        ? const Color(0xFF2ECC71)
        : level == '中等'
            ? const Color(0xFF58A6FF)
            : const Color(0xFFE74C3C);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber,
                  size: 16, color: Color(0xFF58A6FF)),
              const SizedBox(width: 4),
              const Text(
                '风险分析',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: levelColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '风险$level',
                  style: TextStyle(color: levelColor, fontSize: 12),
                ),
              ),
            ],
          ),
          if (factors.isNotEmpty) ...[
            const SizedBox(height: 6),
            if (factors.length <= 3)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: factors.map((f) => _buildRiskChip(f)).toList(),
              )
            else
              ...factors.take(3).map((f) => _buildRiskChip(f)),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
      ),
    );
  }

  // ─── 市场环境 ───────────────────────────────────────────

  Widget _buildMarketContextRow() {
    final mc = analysis!.marketContext!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, size: 14, color: Color(0xFF8B949E)),
          const SizedBox(width: 6),
          Text(
            '上证${mc.shIndexPct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: mc.shIndexPct >= 0
                  ? const Color(0xFFE74C3C)
                  : const Color(0xFF2ECC71),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '深证${mc.szIndexPct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: mc.szIndexPct >= 0
                  ? const Color(0xFFE74C3C)
                  : const Color(0xFF2ECC71),
              fontSize: 12,
            ),
          ),
          if (mc.upCount > 0) ...[
            const SizedBox(width: 10),
            Text(
              '涨${mc.upCount}跌${mc.downCount}',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 动量持续性分析 ───────────────────────────────────────────

  Widget _buildMomentumPersistenceCard() {
    final mp = analysis!.momentumPersistence!;
    final persistenceScore = (mp['persistence_score'] as double?) ?? 0.5;
    final adxTrendScore = (mp['adx_trend_score'] as double?) ?? 0.5;
    final volumeConfirmScore = (mp['volume_confirm_score'] as double?) ?? 0.5;
    final priceDeviationScore = (mp['price_deviation_score'] as double?) ?? 0.5;
    final description = mp['description'] as String? ?? '';

    final scoreColor = persistenceScore >= 0.7
        ? const Color(0xFFE74C3C)
        : persistenceScore >= 0.5
            ? const Color(0xFF58A6FF)
            : const Color(0xFF2ECC71);
    final scoreLabel = persistenceScore >= 0.7
        ? '强'
        : persistenceScore >= 0.5
            ? '中'
            : '弱';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 16, color: Color(0xFFE74C3C)),
              const SizedBox(width: 4),
              const Text(
                '动量持续性',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${scoreLabel}(${persistenceScore.toStringAsFixed(2)})',
                  style: TextStyle(color: scoreColor, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildFactorBar(
                    '趋势速率', adxTrendScore, const Color(0xFFE74C3C)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFactorBar(
                    '量能确认', volumeConfirmScore, const Color(0xFF58A6FF)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFactorBar(
                    '价格偏离', priceDeviationScore, const Color(0xFF2ECC71)),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFactorBar(String label, double score, Color color) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 24,
            color: const Color(0xFF21262D),
            child: FractionallySizedBox(
              widthFactor: score.clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: Container(color: color.withOpacity(0.6)),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
        ),
        Text(
          '${(score * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: color, fontSize: 10),
        ),
      ],
    );
  }

  // ─── 次日涨跌概率预测 ───────────────────────────────────────────

  Widget _buildNextDayPredictionCard() {
    final np = analysis!.nextDayPrediction!;
    final upProbability = (np['up_probability'] as double?) ?? 0.5;
    final downProbability = (np['down_probability'] as double?) ?? 0.5;
    final neutralProbability = (np['neutral_probability'] as double?) ?? 0.0;
    final sampleCount = (np['sample_count'] as int?) ?? 0;
    final description = np['description'] as String? ?? '';

    final predictionColor = upProbability > downProbability
        ? const Color(0xFFE74C3C)
        : upProbability < downProbability
            ? const Color(0xFF2ECC71)
            : const Color(0xFF8B949E);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: predictionColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  size: 16, color: Color(0xFF58A6FF)),
              const SizedBox(width: 4),
              const Text(
                '次日预测',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '样本: ${sampleCount}个',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE74C3C).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${(upProbability * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xFFE74C3C),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('上涨',
                          style: TextStyle(
                              color: Color(0xFF8B949E), fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2ECC71).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${(downProbability * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xFF2ECC71),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('下跌',
                          style: TextStyle(
                              color: Color(0xFF8B949E), fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B949E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${(neutralProbability * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xFF8B949E),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('震荡',
                          style: TextStyle(
                              color: Color(0xFF8B949E), fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 预警信号 ───────────────────────────────────────────

  Widget _buildEarlyWarningSignalsCard() {
    final signals = analysis!.earlyWarningSignals!;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, size: 16, color: Color(0xFFFF9800)),
              const SizedBox(width: 4),
              const Text(
                '预警信号',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${signals.length}个',
                style: const TextStyle(color: Color(0xFFFF9800), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...signals.map((s) => _buildEarlyWarningSignalRow(s)),
        ],
      ),
    );
  }

  Widget _buildEarlyWarningSignalRow(SignalItem s) {
    final isBuy = s.type == 'buy';
    final color = isBuy ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71);

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(
            isBuy ? Icons.trending_up : Icons.trending_down,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.signal,
              style: TextStyle(color: color, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (s.description.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              s.description,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ─── 评分历史趋势 (v3.13) ────────────────────────────────

  Widget _buildChipCard() {
    final c = chipDistribution!;
    final profitPct = c.profitRatio * 100;
    final trappedPct = c.trappedRatio * 100;
    const red = Color(0xFFE74C3C);
    const green = Color(0xFF2ECC71);
    String money(double v) => v.toStringAsFixed(2);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D), width: 0.8),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        initiallyExpanded: false,
        leading: const Icon(Icons.stacked_bar_chart,
            color: Color(0xFF58A6FF), size: 20),
        title: Row(
          children: [
            const Text('筹码分布',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('获利${profitPct.toStringAsFixed(0)}%',
                style: const TextStyle(
                    color: red, fontSize: 11, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('集中度${(c.concentration90 * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        children: [
          Row(
            children: const [
              Text('获利盘',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              Spacer(),
              Text('套牢盘',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: profitPct.round().clamp(1, 100),
                  child: Container(height: 12, color: red),
                ),
                Expanded(
                  flex: trappedPct.round().clamp(1, 100),
                  child: Container(height: 12, color: green),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${profitPct.toStringAsFixed(1)}%',
                  style: const TextStyle(color: red, fontSize: 11)),
              const Spacer(),
              Text('${trappedPct.toStringAsFixed(1)}%',
                  style: const TextStyle(color: green, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          _chipMetricRow('平均成本(近似主力)', money(c.averageCost),
              c.currentPrice >= c.averageCost ? red : green),
          _chipMetricRow('主峰价', money(c.peakPrice), Colors.white70),
          _chipMetricRow('90%成本区间',
              '${money(c.lowerCost90)} ~ ${money(c.upperCost90)}', Colors.white70),
          const SizedBox(height: 6),
          const Text(
            '说明: 基于K线换手衰减估算，纯K线无法区分主力/散户，平均成本为全体筹码近似',
            style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _chipMetricRow(String label, String value, Color valueColor) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildScoreTrendCard() {
    final avgScore = scoreTrend!
            .map((d) => (d['score'] as num).toDouble())
            .reduce((a, b) => a + b) /
        scoreTrend!.length;
    final firstScore = (scoreTrend!.first['score'] as num).toDouble();
    final lastScore = (scoreTrend!.last['score'] as num).toDouble();
    final trend = lastScore - firstScore;
    final trendIcon = trend > 0.5
        ? Icons.trending_up
        : trend < -0.5
            ? Icons.trending_down
            : Icons.trending_flat;
    final trendColor = trend > 0.5
        ? const Color(0xFFE74C3C)
        : trend < -0.5
            ? const Color(0xFF2ECC71)
            : Colors.grey;
    final trendLabel = trend > 0.5
        ? '上升'
        : trend < -0.5
            ? '下降'
            : '平稳';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D), width: 0.8),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        initiallyExpanded: false,
        leading:
            const Icon(Icons.show_chart, color: Color(0xFF58A6FF), size: 20),
        title: Row(
          children: [
            const Text('评分趋势',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('${scoreTrend!.length}条',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(width: 8),
            Icon(trendIcon, color: trendColor, size: 14),
            const SizedBox(width: 2),
            Text('$trendLabel',
                style: TextStyle(
                    color: trendColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('均${avgScore.toStringAsFixed(1)}分',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        children: [
          ScoreTrendChart(trendData: scoreTrend!),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(const Color(0xFFE74C3C), '≥7 强'),
              const SizedBox(width: 16),
              _legendDot(Colors.orange, '≥6 谨慎'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFF58A6FF), '≥4 中性'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFF2ECC71), '<4 弱'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }

  // ─── 加载状态 ───────────────────────────────────────────

  Widget _buildLoading() {
    // P4.3: skeleton placeholder approximating the dashboard while loading,
    // replacing the bare spinner for a smoother perceived load.
    return const SingleChildScrollView(
      child: SkeletonList(lines: 8),
    );
  }

  // ─── v3.23: 置信度8维拆解卡片 ────────────────────────

  Widget _buildConfidenceBreakdownCard() {
    final bd = analysis!.confidenceBreakdown!;
    final labels = {
      'signal_consistency': '信号一致性',
      'fundamental_support': '基本面支撑',
      'sentiment_confirm': '情绪确认',
      'market_confirm': '市场环境',
      'structure_confirm': '结构确认',
      'signal_freshness': '信号时效',
      'historical_winrate': '回测胜率',
      'prediction_support': '预测支持',
    };
    final entries = bd.entries.toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline, size: 16, color: Color(0xFF58A6FF)),
              SizedBox(width: 4),
              Text('置信度维度拆解', style: TextStyle(color: Color(0xFFF0F6FC), fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ...entries.map((e) {
            final label = labels[e.key] ?? e.key;
            final value = e.value;
            final color = value >= 0.7
                ? const Color(0xFF26a69a)
                : value >= 0.5
                    ? const Color(0xFF58A6FF)
                    : const Color(0xFFE74C3C);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: value.clamp(0.0, 1.0),
                        backgroundColor: const Color(0xFF21262D),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    child: Text('${(value * 100).toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 10), textAlign: TextAlign.right),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── v3.23: 方向5维证据分量 ─────────────────────────

  Widget _buildDirectionComponentsCard() {
    final components = analysis!.shortTermDecision!.directionComponents;
    final labels = {
      'trend': '趋势(25%)',
      'reversal_momentum': '反转动量(25%)',
      'volume_flow': '量价流(20%)',
      'relative_strength': '相对强度(15%)',
      'sector_momentum': '板块动量(10%)',
      'next_session': '次日预测(5%)',
    };
    final direction = analysis!.shortTermDecision!.direction;
    final dirColor = direction == RecommendationDirection.bullish
        ? const Color(0xFFE74C3C)
        : direction == RecommendationDirection.bearish
            ? const Color(0xFF2ECC71)
            : const Color(0xFF8B949E);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: dirColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compass_calibration, size: 16, color: dirColor),
              const SizedBox(width: 4),
              const Text('方向证据分量', style: TextStyle(color: Color(0xFFF0F6FC), fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '方向分: ${analysis!.shortTermDecision!.directionScore.toStringAsFixed(0)}',
                style: TextStyle(color: dirColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...components.entries.map((e) {
            final label = labels[e.key] ?? e.key;
            final value = e.value; // -1.0 to +1.0
            final barValue = (value + 1.0) / 2.0; // normalize to 0-1
            final compColor = value > 0.1
                ? const Color(0xFFE74C3C)
                : value < -0.1
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFF8B949E);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11))),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(height: 6, decoration: BoxDecoration(color: const Color(0xFF21262D), borderRadius: BorderRadius.circular(3))),
                        FractionallySizedBox(
                          widthFactor: barValue.clamp(0.0, 1.0),
                          alignment: Alignment.centerLeft,
                          child: Container(height: 6, decoration: BoxDecoration(color: compColor.withOpacity(0.6), borderRadius: BorderRadius.circular(3))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 36,
                    child: Text(
                      value >= 0 ? '+${(value * 100).toStringAsFixed(0)}' : '${(value * 100).toStringAsFixed(0)}',
                      style: TextStyle(color: compColor, fontSize: 10),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
