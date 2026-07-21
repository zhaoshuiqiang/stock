import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/analysis/confluence_scorer.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/analysis/technical_scorer.dart';
import 'package:stock_analyzer/core/scoring_prefs.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// v4.11 B#1 short-term trend discount (ScoringConfig.useShortTermTrendDiscount).
/// Verifies the flag is OFF by default (legacy behavior), and when ON it
/// down-weights the MA-alignment / ADX trend reward (technical_scorer) and the
/// MA confluence weight (confluence_scorer), plus the persistence round-trip.

// Bull-aligned bar: ma5>ma10>ma20, adx>25, close>ma5, MA20 deviation ~7% (x0.92),
// intraday +5% (no crash penalty). Legacy trend = 1.4*0.92 + 0.5 = 1.788.
HistoryKline _bullBar() => HistoryKline(
      date: DateTime(2024, 1, 20),
      open: 10.0,
      high: 10.6,
      low: 9.9,
      close: 10.5,
      volume: 1500,
      ma5: 10.4,
      ma10: 10.1,
      ma20: 9.8,
      adx14: 30.0,
    );

// Confluence kline where ONLY the MA indicator is bullish, so the MA weight is
// not masked by the +/-5 clamp: score = 5.0 + MAweight.
HistoryKline _maOnlyBull() => HistoryKline(
      date: DateTime(2024, 1, 20),
      open: 10.0,
      high: 10.5,
      low: 9.8,
      close: 10.0,
      volume: 900,
      ma5: 10.4,
      ma10: 10.1,
      ma20: 9.8,
      volMa5: 1000,
      macdDif: 0.0,
      macdDea: 0.0,
      macdHist: 0.0,
      rsi6: 50.0,
      k: 50.0,
      d: 50.0,
      bollMid: 10.0,
      wr14: 50.0,
      cci14: 0.0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => ScoringConfig.useShortTermTrendDiscount = false);

  test('flag defaults to OFF', () {
    expect(ScoringConfig.useShortTermTrendDiscount, isFalse);
  });

  group('technical trend reward', () {
    test('OFF keeps the legacy MA-align + ADX trend reward (1.788)', () {
      final t =
          TechnicalScorer.score([_bullBar()], const [], const []).trendScore;
      expect(t, closeTo(1.788, 1e-9)); // 1.4*0.92 + 0.5
    });

    test('ON discounts the MA-align base and ADX bonus (1.22)', () {
      ScoringConfig.useShortTermTrendDiscount = true;
      final t =
          TechnicalScorer.score([_bullBar()], const [], const []).trendScore;
      expect(t, closeTo(1.22, 1e-9)); // 1.0*0.92 + 0.3
    });

    test('ON trend reward is strictly below OFF', () {
      final off =
          TechnicalScorer.score([_bullBar()], const [], const []).trendScore;
      ScoringConfig.useShortTermTrendDiscount = true;
      final on =
          TechnicalScorer.score([_bullBar()], const [], const []).trendScore;
      expect(on, lessThan(off));
    });
  });

  group('MA confluence weight', () {
    test('OFF gives MA weight 1.5 (score 6.5 for MA-only bull)', () {
      expect(ConfluenceScorer.score(_maOnlyBull(), const []).score,
          closeTo(6.5, 1e-9));
    });

    test('ON discounts MA weight to 1.0 (score 6.0)', () {
      ScoringConfig.useShortTermTrendDiscount = true;
      expect(ConfluenceScorer.score(_maOnlyBull(), const []).score,
          closeTo(6.0, 1e-9));
    });
  });

  group('persistence', () {
    test('applyScoringPrefs defaults the flag to false when unset', () async {
      SharedPreferences.setMockInitialValues({});
      ScoringConfig.useShortTermTrendDiscount = true; // dirty first
      applyScoringPrefs(await SharedPreferences.getInstance());
      expect(ScoringConfig.useShortTermTrendDiscount, isFalse);
    });

    test('applyScoringPrefs restores the persisted flag', () async {
      SharedPreferences.setMockInitialValues(
        {kPrefUseShortTermTrendDiscount: true},
      );
      applyScoringPrefs(await SharedPreferences.getInstance());
      expect(ScoringConfig.useShortTermTrendDiscount, isTrue);
    });
  });
}
