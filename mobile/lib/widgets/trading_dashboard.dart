import 'package:flutter/material.dart';
import '../models/stock_models.dart';

/// 交易仪表盘：聚合短线交易关键决策信息
/// 替代传统多Tab翻页模式，一屏展示全部决策要点
class TradingDashboard extends StatelessWidget {
  final QuoteData? quote;
  final AnalysisResult? analysis;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final String lastUpdateTime;

  const TradingDashboard({
    super.key,
    this.quote,
    this.analysis,
    this.onRefresh,
    this.isRefreshing = false,
    this.lastUpdateTime = '',
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
          _buildScoreRow(),
          const SizedBox(height: 10),
          _buildKeySignals(),
          if (analysis!.tradeLevels != null) ...[
            const SizedBox(height: 10),
            _buildTradeLevels(),
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
          if (_hasAIInsights) ...[
            const SizedBox(height: 10),
            _buildAIInsights(),
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
                      style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
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
                      style: TextStyle(color: color.withOpacity(0.8), fontSize: 12),
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
        _buildMetricChip('评分', '${a.score}/10', scoreColor),
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
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        durStr,
                        style: TextStyle(color: color.withOpacity(0.8), fontSize: 9),
                      ),
                    ),
                  ],
                ),
                if (s.description.isNotEmpty)
                  Text(
                    s.description,
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
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
                    style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
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
              const Icon(Icons.warning_amber, size: 16, color: Color(0xFF58A6FF)),
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
                children: factors
                    .map((f) => _buildRiskChip(f))
                    .toList(),
              )
            else
              ...factors
                  .take(3)
                  .map((f) => _buildRiskChip(f)),
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
              color: mc.shIndexPct >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '深证${mc.szIndexPct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: mc.szIndexPct >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
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

  // ─── AI分析见解 ───────────────────────────────────────────

  bool get _hasAIInsights {
    final reasons = analysis!.reasons;
    return reasons.any((r) => r.startsWith('AI'));
  }

  Widget _buildAIInsights() {
    final aiReasons = analysis!.reasons.where((r) => r.startsWith('AI')).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.smart_toy, size: 16, color: Color(0xFF58A6FF)),
              SizedBox(width: 4),
              Text(
                'AI分析',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...aiReasons.map((reason) {
            if (reason.startsWith('AI分析结论')) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  reason.replaceFirst('AI分析结论: ', ''),
                  style: const TextStyle(
                    color: Color(0xFF58A6FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              );
            } else if (reason.startsWith('AI理由')) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.arrow_right, size: 12, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        reason.replaceFirst('AI理由: ', ''),
                        style: const TextStyle(
                          color: Color(0xFF8B949E),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else if (reason.startsWith('AI风险提示')) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning, size: 12, color: Color(0xFFE74C3C)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        reason.replaceFirst('AI风险提示: ', ''),
                        style: const TextStyle(
                          color: Color(0xFFE74C3C),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                reason,
                style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 加载状态 ───────────────────────────────────────────

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(
          color: Color(0xFF58A6FF),
          strokeWidth: 2,
        ),
      ),
    );
  }
}
