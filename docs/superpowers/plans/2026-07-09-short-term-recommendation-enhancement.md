# Short-Term Recommendation Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve 1-10 trading day recommendation accuracy by adding a dedicated short-term trading score and applying short-term risk caps without replacing the existing comprehensive score.

**Architecture:** Add a pure `ShortTermScorer` that derives a 0-10 tradeability score from short-term signals, volume-price quality, realtime flow, market context, limit-up risk, volatility, and recent price action. `signal_engine.dart` keeps the current comprehensive score as the broad quality score, then uses the short-term score as a recommendation cap/boost layer and exposes it in `AnalysisResult.dimensionScores` and reasons. `StrategyBuilder` will honor `preferredDuration` so short-term and long-term strategy lists are semantically correct.

**Tech Stack:** Flutter/Dart, pure client-side rule engine, existing `flutter test` suite.

---

### Task 1: Short-Term Scorer Tests

**Files:**
- Create: `mobile/test/short_term_scorer_test.dart`
- Create: `mobile/lib/analysis/short_term_scorer.dart`

- [ ] **Step 1: Write failing tests**

Add tests for four core behaviors:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/short_term_scorer.dart';
import 'package:stock/models/stock_models.dart';

void main() {
  group('ShortTermScorer', () {
    test('scores high for short-term momentum with volume and fund confirmation', () {
      final data = _klines(close: [10, 10.2, 10.5, 10.9, 11.2], volume: [1000, 1100, 1200, 1800, 2200]);
      final quote = _quote(changePct: 2.8, mainNetFlowRate: 6, turnover: 4, amplitude: 4);
      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('KDJ金叉', 'KDJ', 2), _signal('放量上涨', '量价', 2)],
        sellSignals: const [],
        quote: quote,
      );

      expect(result.score, greaterThanOrEqualTo(7));
      expect(result.actionLabel, equals('短线可参与'));
      expect(result.riskCaps, isEmpty);
    });

    test('caps recommendation when price is already limit-up or chase risk is high', () {
      final data = _klines(close: [10, 10.3, 10.7, 11.1, 12.2], volume: [1000, 1200, 1400, 1800, 2500]);
      final quote = _quote(changePct: 10.1, mainNetFlowRate: 8, turnover: 12, amplitude: 10);
      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('放量突破', '量价', 3)],
        sellSignals: const [],
        quote: quote,
      );

      expect(result.score, lessThanOrEqualTo(6));
      expect(result.maxRecommendationScore, lessThanOrEqualTo(6));
      expect(result.riskCaps.any((r) => r.contains('涨停') || r.contains('追高')), isTrue);
    });

    test('penalizes conflicting sell signals and recent weakness', () {
      final data = _klines(close: [10, 9.8, 9.4, 9.2, 9.0], volume: [1000, 1500, 1800, 2100, 2300]);
      final quote = _quote(changePct: -3.2, mainNetFlowRate: -5, turnover: 3, amplitude: 6);
      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('RSI超卖回升', 'RSI', 1)],
        sellSignals: [_signal('放量下跌', '量价', 3), _signal('MA死叉', 'MA', 2)],
        quote: quote,
      );

      expect(result.score, lessThanOrEqualTo(4));
      expect(result.actionLabel, equals('短线回避'));
    });

    test('uses valuation as risk cap not hard exclusion', () {
      final data = _klines(close: [10, 10.1, 10.3, 10.6, 10.9], volume: [1000, 1100, 1300, 1700, 1900]);
      final quote = _quote(changePct: 2.2, mainNetFlowRate: 5, turnover: 3, amplitude: 4, pe: -1);
      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('放量突破', '量价', 2)],
        sellSignals: const [],
        quote: quote,
      );

      expect(result.score, greaterThanOrEqualTo(5));
      expect(result.riskCaps.any((r) => r.contains('估值') || r.contains('亏损')), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `D:\flutter\bin\flutter.bat test test/short_term_scorer_test.dart`

Expected: fail because `short_term_scorer.dart` does not exist.

- [ ] **Step 3: Implement `ShortTermScorer`**

Create `ShortTermScoreResult` and `ShortTermScorer.score()` with deterministic scoring and risk caps.

- [ ] **Step 4: Run test to verify GREEN**

Run: `D:\flutter\bin\flutter.bat test test/short_term_scorer_test.dart`

Expected: all tests pass.

### Task 2: Strategy Duration Filtering

**Files:**
- Modify: `mobile/lib/analysis/strategy_builder.dart`
- Test: `mobile/test/strategy_builder_test.dart` or create focused `mobile/test/strategy_builder_duration_test.dart`

- [ ] **Step 1: Write failing tests**

Assert `buildLayeredStrategies(data, signals, SignalDuration.shortTerm)` returns only short/special defensive short strategies and no `strategyType == 'long'` strategies. Assert `SignalDuration.longTerm` returns long strategies and no pure short buy strategies.

- [ ] **Step 2: Run test to verify RED**

Run: `D:\flutter\bin\flutter.bat test test/strategy_builder_duration_test.dart`

Expected: fail because `preferredDuration` is ignored.

- [ ] **Step 3: Implement duration filtering**

Filter the deduplicated strategy list by `preferredDuration` before sorting. Keep `null` behavior unchanged for callers that want all strategies.

- [ ] **Step 4: Run test to verify GREEN**

Run: `D:\flutter\bin\flutter.bat test test/strategy_builder_duration_test.dart`

Expected: all tests pass.

### Task 3: Signal Engine Integration

**Files:**
- Modify: `mobile/lib/analysis/signal_engine.dart`
- Modify: `mobile/lib/models/stock_models.dart`
- Test: `mobile/test/signal_engine_short_term_test.dart`

- [ ] **Step 1: Write failing tests**

Create tests showing a high comprehensive setup with excessive chase risk is capped to at most `谨慎买入`, and a clean short-term setup includes `短线交易分` in `dimensionScores` and reasons.

- [ ] **Step 2: Run test to verify RED**

Run: `D:\flutter\bin\flutter.bat test test/signal_engine_short_term_test.dart`

Expected: fail because the short-term score is not integrated.

- [ ] **Step 3: Integrate scorer**

Call `ShortTermScorer.score()` after capital/realtime scores are available. Add `短线交易` to `dimensionScores`. Apply `maxRecommendationScore` as a cap to the production recommendation and total score, without changing ST stock cap behavior. Add short-term reason text and suggestions.

- [ ] **Step 4: Run test to verify GREEN**

Run: `D:\flutter\bin\flutter.bat test test/signal_engine_short_term_test.dart`

Expected: all tests pass.

### Task 4: Explore Candidate Policy

**Files:**
- Modify: `mobile/lib/analysis/explore_engine.dart`
- Test: `mobile/test/explore_engine_test.dart` or focused new test

- [ ] **Step 1: Write failing tests**

Assert `_passValuationFilter` does not hard-exclude亏损/高PE stocks when the short-term policy path is used.

- [ ] **Step 2: Run test to verify RED**

Run: `D:\flutter\bin\flutter.bat test test/explore_engine_test.dart`

Expected: fail if short-term policy is absent.

- [ ] **Step 3: Implement minimal policy**

Keep default valuation filter for broad exploration, but allow short-term mode to pass valuation and rely on `ShortTermScorer` risk caps.

- [ ] **Step 4: Run test to verify GREEN**

Run: `D:\flutter\bin\flutter.bat test test/explore_engine_test.dart`

Expected: all tests pass.

### Task 5: Verification

**Files:**
- No new production files unless tests reveal gaps.

- [ ] **Step 1: Run focused tests**

Run:

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/short_term_scorer_test.dart test/strategy_builder_duration_test.dart test/signal_engine_short_term_test.dart
```

- [ ] **Step 2: Run affected analysis**

Run:

```powershell
cd mobile
D:\flutter\bin\flutter.bat analyze lib/analysis/short_term_scorer.dart lib/analysis/signal_engine.dart lib/analysis/strategy_builder.dart lib/analysis/explore_engine.dart
```

- [ ] **Step 3: Run full tests if focused tests pass**

Run:

```powershell
cd mobile
D:\flutter\bin\flutter.bat test
```

Expected: full suite passes.
