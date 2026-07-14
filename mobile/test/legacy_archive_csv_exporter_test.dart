import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/services/legacy_archive_csv_exporter.dart';

void main() {
  test('legacy exporter keeps 18 columns BOM and CSV escaping', () {
    final record = ArchiveRecord(
      code: '000001',
      name: '测试,股"A',
      price: 10,
      changePct: 1,
      score: 7,
      recommendation: '谨慎买入',
      riskLevel: '中',
      buySignalCount: 2,
      sellSignalCount: 0,
      activeStrategyCount: 1,
      confluenceScore: 70,
      archivedAt: DateTime(2026, 7, 14, 15),
    );
    final csv = buildLegacyArchiveCsv(
      records: [record],
      quoteOf: (_) => QuoteData(code: '000001', price: 11, changePct: 2),
      now: DateTime(2026, 7, 15),
    );
    expect(csv.startsWith('\ufeff'), isTrue);
    expect(csv.split('\r\n').first.split(',').length, 18);
    expect(csv, contains('"\u6d4b\u8bd5,\u80a1""A"'));
    expect(csv, contains('10.00'));
  });
}
