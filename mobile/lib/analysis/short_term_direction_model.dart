import 'dart:math';

import '../models/short_term_decision.dart';
import '../models/short_term_direction.dart';
import '../models/stock_models.dart';
import 'directional_evidence_builder.dart';
import 'market_structure_analyzer.dart';

/// 短线方向模块（Batch 4 基线）
///
/// 复用 [DirectionalEvidenceBuilder] 已算好的 5 维单位分量
/// (trend 0.30 / reversal 0.25 / volumeFlow 0.20 / relStrength 0.15 / nextSession 0.10)，
/// 在其之上新增：
///  - 概率映射（|score| → [0.5,0.9]），输出可排序的 directionProbability；
///  - 去动量偏置（4.4）：已大涨+高乖离样本下调追高权重，而非加赏；
///  - 市场状态门控（4.4）：用修好的 avgChangePct 计算市场偏置参与融合；
///  - 可解释证据（supportingEvidence）供 UI 展示。
///
/// 校准（walk-forward 逻辑回归/提升）为第二步，待 decision_outcomes 积累后切换。
class ShortTermDirectionModel {
  static const String modelVersion = 'direction-v1';

  /// 分量中文标签，用于证据展示
  static const Map<String, String> _componentLabels = <String, String>{
    trendComponentKey: '趋势',
    reversalMomentumComponentKey: '反转动量',
    volumeFlowComponentKey: '量价',
    relativeStrengthComponentKey: '相对强度',
    nextSessionComponentKey: '次session',
  };

  static DirectionForecast evaluate({
    required Map<String, double> components,
    required MarketContext? marketContext,
    MarketStructureResult? marketStructure,
    required List<HistoryKline> data,
    int horizonDays = 3,
  }) {
    final weights = DirectionalEvidenceBuilder.componentWeights;
    var stockEvidence = 0.0;
    for (final entry in weights.entries) {
      stockEvidence += (components[entry.key] ?? 0) * entry.value;
    }
    stockEvidence = stockEvidence.clamp(-1.0, 1.0);

    // 4.4 去动量偏置：已大涨 + 高乖离时下调追高权重
    var momentumPenalized = false;
    if (data.isNotEmpty) {
      final last = data.last;
      final surged = last.changePct >= 8 ||
          (last.bias6.isFinite && last.bias6 >= 8) ||
          (last.rsi6 > 0 && last.rsi6 >= 80);
      if (stockEvidence > 0.25 && surged) {
        stockEvidence *= 0.6;
        momentumPenalized = true;
      }
    }

    // 4.4 市场状态门控：用修好的 avgChangePct 计算市场偏置（±1）
    var marketBias = 0.0;
    var avgChangePct = 0.0;
    if (marketContext != null && marketContext.avgChangePct.isFinite) {
      avgChangePct = marketContext.avgChangePct;
      marketBias = (avgChangePct / 3.0).clamp(-1.0, 1.0);
    }

    final rawScore =
        (stockEvidence * 0.8 + marketBias * 0.2).clamp(-1.0, 1.0);

    final direction = rawScore >= 0.2
        ? RecommendationDirection.bullish
        : rawScore <= -0.2
            ? RecommendationDirection.bearish
            : RecommendationDirection.neutral;

    // 概率映射：|score| → logistic → 限制在 [0.5, 0.9]，避免虚假确定性
    final p = 1 / (1 + exp(-rawScore.abs() * 4));
    final probability = (0.5 + (p - 0.5) * 0.8).clamp(0.5, 0.9);

    // 可解释证据
    final evidence = <String>[];
    components.forEach((key, value) {
      if (value.abs() >= 0.2) {
        final dir = value > 0 ? '偏多' : '偏空';
        final label = _componentLabels[key] ?? key;
        evidence.add('$label$dir(${(value * 100).round()})');
      }
    });
    if (momentumPenalized) evidence.add('已大涨+高乖离，追高权重下调');
    if (marketBias.abs() >= 0.2) {
      final biasLabel = marketBias > 0 ? '多' : '空';
      evidence.add('市场偏$biasLabel(${avgChangePct.toStringAsFixed(2)}%)');
    }
    if (evidence.isEmpty) evidence.add('信号稀疏，方向不明确');

    return DirectionForecast(
      direction: direction,
      probability: probability,
      horizonDays: horizonDays,
      componentScores: Map<String, double>.from(components),
      supportingEvidence: evidence,
      marketRegime: marketStructure?.structure.name ?? '',
      momentumPenalized: momentumPenalized,
      rawScore: rawScore,
      modelVersion: modelVersion,
    );
  }
}
