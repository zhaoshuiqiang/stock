import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/opportunity_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/services/watchlist_export_csv.dart';

/// Watchlist multi-select export: verifies the CSV builder shape.
/// (ASCII-only assertions; the builder itself emits Chinese headers.)
void main() {
  group('buildWatchlistExportCsv', () {
    final now = DateTime(2026, 7, 23, 10, 0, 0);

    OpportunityResult opp() => OpportunityResult(
          code: 'sh600000',
          name: 'AlphaCo',
          price: 10.0,
          changePct: 2.5,
          score: 7.0,
          recommendation: 'BUY',
          riskLevel: 'LOW',
          buySignalCount: 3,
          sellSignalCount: 1,
          activeStrategyCount: 2,
          confluenceScore: 6,
          tradeLevels: const {
            'entry_low': 9.8,
            'entry_high': 10.2,
            'stop_loss': 9.3,
            'tp1': 10.8,
            'tp2': 11.5,
            'tp3': 12.0,
            'risk_reward_ratio': 2.5,
          },
          topSignals: const ['MA-bull', 'MACD-cross'],
        );

    List<WatchlistExportItem> sample() => [
          // analyzed stock (opp + quote)
          WatchlistExportItem(
            code: 'sh600000',
            name: 'AlphaCo',
            quote: QuoteData(code: 'sh600000', name: 'AlphaCo', price: 10.0),
            opp: opp(),
          ),
          // watch-only stock (no analysis) -> analysis columns blank
          WatchlistExportItem(
            code: 'sh000001',
            name: 'BetaCo',
            quote: QuoteData(code: 'sh000001', name: 'BetaCo', price: 5.5),
            opp: null,
          ),
        ];

    test('emits UTF-8 BOM + CRLF and a fixed 26-column schema', () {
      final csv = buildWatchlistExportCsv(items: sample(), now: now);
      expect(csv.startsWith('\ufeff'), isTrue);
      expect(csv.contains('\r\n'), isTrue);
      final rows = csv.substring(1).split('\r\n');
      expect(rows.length, 3); // header + 2 data rows
      expect(rows.first.split(',').length, 26);
      expect(rows[1].split(',').length, 26);
      expect(rows[2].split(',').length, 26);
    });

    test('analyzed row carries score, signals and trade levels', () {
      final csv = buildWatchlistExportCsv(items: sample(), now: now);
      final row = csv.substring(1).split('\r\n')[1];
      expect(row.contains('sh600000'), isTrue);
      expect(row.contains('7.0'), isTrue); // score
      expect(row.contains('BUY'), isTrue); // recommendation
      expect(row.contains('2.50'), isTrue); // risk_reward_ratio formatted
      expect(row.contains('MA-bull  MACD-cross'), isTrue); // topSignals joined
    });

    test('watch-only row keeps schema with blank analysis columns', () {
      final csv = buildWatchlistExportCsv(items: sample(), now: now);
      final row = csv.substring(1).split('\r\n')[2];
      final cells = row.split(',');
      expect(cells[0], 'sh000001');
      expect(cells[4], ''); // score column blank when no analysis
      expect(cells[24], ''); // topSignals blank
    });

    test('empty item list still emits just the header row', () {
      final csv = buildWatchlistExportCsv(items: const [], now: now);
      final rows = csv.substring(1).split('\r\n');
      expect(rows.length, 1);
      expect(rows.first.split(',').length, 26);
    });
  });
}
