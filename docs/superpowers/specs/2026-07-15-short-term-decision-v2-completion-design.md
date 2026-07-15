# Short-Term Decision V2 Completion Design

## Goal

Complete the remaining Short-Term Decision V2 rollout without changing its
four-dimension scoring, calibration rules, or database schema. Release the
completed work as version `3.17.20260715`.

## Scope

1. Make ArchiveScreen's new-model mode functional end-to-end:
   - filter by direction, market regime, model version, and source;
   - reload the typed decision query when the horizon or filters change;
   - export decision CSV in new-model mode and preserve the legacy 18-column
     export in historical mode.
2. Complete the recommendation-statistics presentation with typed decision
   metrics: Wilson interval, return and Alpha distribution metrics, MFE/MAE,
   Brier/ECE availability, and primary-strategy results. Historical data and
   WeightOptimizer remain in an explicitly labelled historical mode.
3. Align decision wording across the old result-card and quantitative views:
   evidence confidence is not a probability; calibrated values name their
   horizon and effective-hit meaning.
4. Add regression coverage for archive mode/export behaviour, statistics,
   wording, and cross-surface consistency.
5. Update the three version locations, run verification, build the APK, and
   conduct a code review. Pushing is outside this task unless separately
   requested.

## Architecture

The database remains the source of typed `DecisionStatisticsRow` data.
ArchiveScreen owns only UI state: selected horizon, mode, and filter values.
It passes a `DecisionStatisticsFilter` into DatabaseService and maps the
filtered rows to the decision list and decision CSV exporter.

`DecisionCalibrationSummary` is a pure, typed widget. It receives a summary
and rows/buckets prepared by `DecisionStatistics`; it performs no database or
network calls. RecommendationStatsScreen uses it only for new-model mode.

Existing legacy services and UI remain isolated behind historical mode. No
legacy `recommendation_tracking` row is used as decision calibration input,
and `WeightOptimizer` is never surfaced as an active decision-model weight.

## Behaviour Rules

- New-model archive export uses `buildDecisionCsv` and a `decision_export_`
  filename; historical export keeps `buildLegacyArchiveCsv` and its existing
  `archive_export_` filename.
- Missing calibration estimates, pending outcomes, invalid outcomes, and
  unavailable execution values display as explicit status or absent data, not
  numeric zero.
- Direction, regime, source, and model-version filters apply only in
  new-model mode. Historical filters and reliability evaluation retain their
  present behaviour.
- The old pages may retain their existing score layout where required for
  compatibility, but any V2 values use the same four-dimension terminology as
  the trading dashboard.

## Testing And Release

Each production change begins with a focused failing test. Required coverage
includes filter forwarding, mode-specific exporting, statistics presentation,
and cross-surface vocabulary/data consistency. After focused suites pass, run
full Flutter tests and analysis. EastMoney live-network failures are reported
separately from deterministic failures. Then update version metadata to
`3.17.20260715`, build the release APK, and review the final diff for scope,
null safety, error handling, UI overflow, and legacy isolation.
