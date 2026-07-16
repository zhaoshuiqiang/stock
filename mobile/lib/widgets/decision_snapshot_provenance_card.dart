import 'package:flutter/material.dart';

import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

class DecisionSnapshotProvenanceCard extends StatelessWidget {
  final DecisionSnapshotRecord snapshot;

  const DecisionSnapshotProvenanceCard({
    super.key,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final directionColor = switch (snapshot.direction) {
      RecommendationDirection.bullish => const Color(0xFFEF5350),
      RecommendationDirection.neutral => const Color(0xFFD29922),
      RecommendationDirection.bearish => const Color(0xFF26A69A),
    };
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  '决策证据链',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _tag(
                snapshot.actionable ? '可执行' : '不可执行',
                snapshot.actionable
                    ? const Color(0xFF3FB950)
                    : const Color(0xFFD29922),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '实际推荐 ${snapshot.recommendationLevel} · '
            '${snapshot.recommendationLabel}',
            style: TextStyle(
              color: directionColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('捕获 ${_dateTime(snapshot.signalTime)}'),
              Text('阶段 ${_phaseLabel(snapshot.signalPhase)}'),
              Text('证据日 ${_date(snapshot.evidenceTradeDate)}'),
              Text('信号日 ${_date(snapshot.signalTradeDate)}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${snapshot.source} · ${snapshot.modelVersion}'
            '${snapshot.appVersion.isEmpty ? '' : ' · App ${snapshot.appVersion}'}',
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
          ),
          if (snapshot.isRetrospective) ...[
            const SizedBox(height: 8),
            _tag('回溯补录', const Color(0xFFD29922)),
          ],
          const SizedBox(height: 10),
          _flagSection(
            '推荐门禁',
            snapshot.recommendationGates,
            emptyLabel: '无门禁',
            color: const Color(0xFFD29922),
          ),
          const SizedBox(height: 8),
          _flagSection(
            '数据质量',
            snapshot.dataQualityFlags,
            emptyLabel: '无质量标记',
            color: const Color(0xFF58A6FF),
          ),
        ],
      ),
    );
  }

  Widget _flagSection(
    String title,
    List<String> values, {
    required String emptyLabel,
    required Color color,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
          ),
          const SizedBox(height: 4),
          if (values.isEmpty)
            Text(
              emptyLabel,
              style: const TextStyle(color: Color(0xFF6E7681), fontSize: 12),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: values.map((value) => _tag(value, color)).toList(),
            ),
        ],
      );

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      );

  static String _phaseLabel(DecisionSignalPhase phase) => switch (phase) {
        DecisionSignalPhase.preMarket => '盘前',
        DecisionSignalPhase.intraday => '交易中',
        DecisionSignalPhase.afterClose => '盘后',
        DecisionSignalPhase.nonTrading => '非交易日',
        DecisionSignalPhase.unknown => '未知',
      };

  static String _date(DateTime? value) {
    if (value == null) return '--';
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _dateTime(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
