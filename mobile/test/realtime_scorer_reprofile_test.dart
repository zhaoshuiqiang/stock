import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/realtime_scorer.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// v4.10: short-term realtime inverted-U reprofile (ScoringConfig
/// .useShortTermRealtimeReprofile). Verifies (a) the flag is OFF by default and
/// the scorer stays byte-identical to the legacy inverted-U, and (b) when ON the
/// reward peak moves to the mild-pullback zone and the 3-5% chase zone is
/// penalized, while limit-up and panic bands behave as designed.
QuoteData q(double cp) =>
    QuoteData(code: '000001', name: 'T', price: 10.0, changePct: cp);

void main() {
  group('RealtimeScorer reprofile flag', () {
    tearDown(() => ScoringConfig.useShortTermRealtimeReprofile = false);

    test('defaults to OFF and stays byte-identical to the legacy inverted-U', () {
      expect(ScoringConfig.useShortTermRealtimeReprofile, isFalse);
      expect(RealtimeScorer.score(q(2.0)), equals(6.0)); // 5 + 1.0
      expect(RealtimeScorer.score(q(0.5)), equals(5.5)); // 5 + 0.5
      expect(RealtimeScorer.score(q(-1.0)), equals(5.5)); // 5 + 0.5
      expect(RealtimeScorer.score(q(4.0)), closeTo(5.3, 1e-9)); // 5 + 0.3
      expect(RealtimeScorer.score(q(7.0)), equals(5.0)); // 5 + 0.0
    });

    test('ON moves the reward peak to the mild-pullback zone', () {
      ScoringConfig.useShortTermRealtimeReprofile = true;
      final pullback = RealtimeScorer.score(q(-1.0)); // 5 + 1.0 = 6.0 (peak)
      final flat = RealtimeScorer.score(q(0.5)); // 5 + 0.6 = 5.6
      final mildUp = RealtimeScorer.score(q(2.0)); // 5 + 0.3 = 5.3

      expect(pullback, equals(6.0));
      expect(flat, closeTo(5.6, 1e-9));
      expect(mildUp, closeTo(5.3, 1e-9));
      expect(pullback, greaterThan(mildUp));
      expect(pullback, greaterThan(flat));
    });

    test('ON penalizes the 3-5% chase zone below neutral and below legacy', () {
      ScoringConfig.useShortTermRealtimeReprofile = true;
      final chaseOn = RealtimeScorer.score(q(4.0)); // 5 - 0.3 = 4.7
      expect(chaseOn, closeTo(4.7, 1e-9));
      expect(chaseOn, lessThan(5.0));

      ScoringConfig.useShortTermRealtimeReprofile = false;
      expect(chaseOn, lessThan(RealtimeScorer.score(q(4.0)))); // 4.7 < 5.3
    });

    test('ON keeps limit-up neutral and preserves panic penalties + clamp', () {
      ScoringConfig.useShortTermRealtimeReprofile = true;
      expect(RealtimeScorer.score(q(9.0)), equals(5.0)); // >8 stays neutral
      expect(RealtimeScorer.score(q(-9.0)), equals(2.5)); // 5 - 2.5 panic
      final extreme = RealtimeScorer.score(q(-30.0));
      expect(extreme, greaterThanOrEqualTo(0.0));
      expect(extreme, lessThanOrEqualTo(10.0));
    });
  });
}
