import 'package:intl/intl.dart';

import '../analysis/archive_reliability_evaluator.dart';
import '../models/stock_models.dart';

String buildLegacyArchiveCsv({
  required List<ArchiveRecord> records,
  required QuoteData? Function(String code) quoteOf,
  required DateTime now,
}) {
  const headers = [
    '代码',
    '名称',
    '留档价格',
    '留档涨跌幅(%)',
    '评分',
    '推荐',
    '风险等级',
    '买入信号数',
    '卖出信号数',
    '活跃战法数',
    '共振评分',
    '留档时间',
    '现价',
    '现涨跌幅(%)',
    '价格变动(%)',
    '是否偏差',
    '可靠性',
    'topSignals',
  ];
  final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final lines = <String>[headers.map(_escape).join(',')];
  for (final record in records) {
    final quote = quoteOf(record.code);
    final currentPrice = quote?.price ?? 0;
    final priceChange = record.price > 0 && currentPrice > 0
        ? (currentPrice - record.price) / record.price * 100
        : 0.0;
    final direction = ArchiveReliabilityEvaluator.directionOf(record);
    ReliabilityLevel? level;
    if (currentPrice > 0 &&
        direction != ArchiveRecommendationDirection.unknown) {
      level = ArchiveReliabilityEvaluator.getReliabilityLevel(
        record,
        currentPrice,
        now: now,
      );
    }
    final deviation = level == ReliabilityLevel.deviation ||
        level == ReliabilityLevel.veryDeviation;
    final row = <Object?>[
      record.code,
      record.name,
      record.price.toStringAsFixed(4),
      record.changePct.toStringAsFixed(2),
      record.score,
      record.recommendation,
      record.riskLevel,
      record.buySignalCount,
      record.sellSignalCount,
      record.activeStrategyCount,
      record.confluenceScore,
      dateFormat.format(record.archivedAt),
      currentPrice > 0 ? currentPrice.toStringAsFixed(4) : null,
      // currentPrice > 0 隐含 quote != null，防御式写法避免 ! 操作符
      currentPrice > 0 ? (quote?.changePct ?? 0).toStringAsFixed(2) : null,
      currentPrice > 0 ? priceChange.toStringAsFixed(2) : null,
      currentPrice > 0 ? (deviation ? '是' : '否') : null,
      _label(level),
      record.topSignals,
    ];
    lines.add(row.map(_escape).join(','));
  }
  return '\ufeff${lines.join('\r\n')}';
}

String _label(ReliabilityLevel? level) => switch (level) {
      ReliabilityLevel.veryReasonable => '非常合理',
      ReliabilityLevel.reasonable => '合理',
      ReliabilityLevel.deviation => '偏差',
      ReliabilityLevel.veryDeviation => '非常偏差',
      null => '未知',
    };

String _escape(Object? value) {
  if (value == null) return '';
  final text = value.toString().replaceAll('\r', ' ').replaceAll('\n', ' ');
  return text.contains(',') || text.contains('"')
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}
