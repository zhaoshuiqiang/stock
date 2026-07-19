import '../models/stock_models.dart';
import 'directional_evidence_builder.dart';
import 'indicators.dart';
import 'recommendation_policy.dart';
import 'recommendation_thresholds.dart';
import 'scoring_config.dart';
import 'signal_engine.dart';

/// P4.1: inputs + entry point for offloading the CPU-heavy batch analysis to a
/// background isolate (via `compute`). Everything here must be isolate-safe:
/// no DB, no platform channels, no main-isolate singletons that require setup.
/// `generateAnalysis(enableAsyncSideEffects: false)` satisfies this — its only
/// singleton touch, `AILayerProvider.instance`, resolves to `NullAILayer()` in
/// a fresh isolate, so the AI branch is simply skipped.

/// One stock's RAW inputs (indicators are (re)computed inside the isolate).
class IsolateScanItem {
  final String code;
  final List<HistoryKline> klines;
  final QuoteData quote;
  const IsolateScanItem({
    required this.code,
    required this.klines,
    required this.quote,
  });
}

/// Immutable request bundle sent to the analysis isolate. Plain data only; the
/// scoring config (weights/thresholds) is captured explicitly below because a
/// `compute()` worker isolate does NOT share the main isolate's static state.
class IsolateScanRequest {
  final List<IsolateScanItem> items;
  final MarketContext? marketContext;

  /// Snapshot of the main-isolate scoring config so the worker reproduces
  /// identical scores. Restored into statics at the top of [runBatchAnalysis].
  final Map<String, double> activeWeights;
  final RecommendationThresholds activeThresholds;

  const IsolateScanRequest({
    required this.items,
    this.marketContext,
    required this.activeWeights,
    required this.activeThresholds,
  });
}

/// One analyzed result returned from the isolate (pure CPU output only).
class IsolateScanResult {
  final String code;
  final AnalysisResult analysis;
  final DateTime evidenceDate;
  const IsolateScanResult({
    required this.code,
    required this.analysis,
    required this.evidenceDate,
  });
}

/// Top-level `compute` entry: runs indicators + [generateAnalysis] for a whole
/// batch off the UI isolate. Items with insufficient data are skipped; per-item
/// failures are swallowed so one bad stock never aborts the batch.
List<IsolateScanResult> runBatchAnalysis(IsolateScanRequest request) {
  // A compute() worker starts with fresh static state, so restore the main
  // isolate's active scoring config here — otherwise dynamic weights, calibrated
  // thresholds and the risk profile would be silently ignored in the worker,
  // making flag-on isolate results diverge from the main-isolate path.
  DirectionalEvidenceBuilder.applyWeightOverride(request.activeWeights);
  RecommendationPolicy.applyThresholdOverride(request.activeThresholds);
  ScoringConfig.useCalibratedThresholds = true;
  ScoringConfig.riskProfile = RiskProfile.balanced;

  final results = <IsolateScanResult>[];
  for (final item in request.items) {
    try {
      if (item.klines.length < 20) continue;
      final indicators = calcAllIndicators(item.klines);
      if (indicators.isEmpty) continue;
      final analysis = generateAnalysis(
        indicators,
        item.quote,
        marketContext: request.marketContext,
        enableAsyncSideEffects: false,
      );
      results.add(IsolateScanResult(
        code: item.code,
        analysis: analysis,
        evidenceDate: indicators.last.date,
      ));
    } catch (_) {
      continue;
    }
  }
  return results;
}
