# Next Session Prediction POC Report

## Scope

This report covers the first implementation pass of the next-session prediction POC.

Implemented:

- Local feature extraction from daily K-line data.
- Similar-history next-session predictor.
- Bayesian shrinkage for small sample counts.
- Chase-risk caps for large-rise, long-upper-shadow, and volume-stall patterns.
- Walk-forward backtest framework.
- Production gate evaluator.
- Signal-engine integration as risk display and downgrade gate.

Not available in this repository:

- A bundled offline, multi-stock historical K-line dataset suitable for market-wide validation.
- A saved real-market POC run proving stable out-of-sample edge.

## Current Gate Decision

The predictor is **not approved for recommendation upgrades**.

It is currently approved only for:

- Independent next-session prediction display.
- Risk warning text.
- Recommendation downgrade when high pullback risk is detected.

It must not:

- Upgrade a recommendation from neutral to buy.
- Increase score solely because next-session probability is high.
- Replace the existing comprehensive score.
- Be presented as deterministic next-day direction.

## Production Rules Implemented

- `generateAnalysis()` writes next-session output into `AnalysisResult.nextDayPrediction['next_session']`.
- Dimension scores include `次交易预测`.
- High pullback-risk scenarios can cap aggressive buy recommendations.
- High pullback-risk scenarios add a top suggestion: do not chase, wait for pullback confirmation.
- Existing recommendation scoring remains the primary strength score.

## Required Future Validation

Before allowing recommendation upgrades, run walk-forward validation on broad historical data and require:

- High-confidence bullish bucket beats baseline next-close hit rate by at least 5 percentage points.
- High-confidence bullish bucket remains positive after 0.2% transaction-cost assumption.
- Probability buckets are directionally monotonic.
- High-risk bucket has materially worse realized returns than neutral bucket.

Until those criteria pass on real historical data, next-session prediction stays risk-only.
