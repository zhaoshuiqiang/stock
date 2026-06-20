import '../models/stock_models.dart';
import 'strategy_builder.dart';
import 'market_structure_analyzer.dart';

class TradingStrategy {
  final String id;
  final String name;
  final String category;
  final String description;
  final String entryRule;
  final String exitRule;
  final String stopLossRule;
  bool isActive;
  final int signalStrength;
  final double? entryPrice;
  final double? targetPrice;
  final double? stopLossPrice;
  final String type;

  // 新增字段
  final String? strategyType;         // 'short' / 'long' / 'both'
  final int recommendedDuration;      // 推荐持有天数（1-90）
  final double maxDrawdown;           // 最大回撤控制（0.0-1.0）
  final int consecutiveLossLimit;     // 连续亏损自动停止次数
  final double minConfidence;         // 最小可信度要求（0.0-1.0）
  final double riskRewardRatio;       // 期望盈亏比（推荐值）
  final List<String> compatibleIndicators; // 兼容的指标列表

  TradingStrategy({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.entryRule,
    required this.exitRule,
    required this.stopLossRule,
    this.isActive = false,
    this.signalStrength = 0,
    this.entryPrice,
    this.targetPrice,
    this.stopLossPrice,
    this.type = 'buy',
    this.strategyType = 'both',
    this.recommendedDuration = 5,
    this.maxDrawdown = 0.05,
    this.consecutiveLossLimit = 3,
    this.minConfidence = 0.6,
    this.riskRewardRatio = 2.0,
    this.compatibleIndicators = const [],
  });

  factory TradingStrategy.fromJson(Map<String, dynamic> json) {
    return TradingStrategy(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      description: json['description'] ?? '',
      entryRule: json['entry_rule'] ?? '',
      exitRule: json['exit_rule'] ?? '',
      stopLossRule: json['stop_loss_rule'] ?? '',
      isActive: json['is_active'] != null ? json['is_active'] == 1 : false,
      signalStrength: json['signal_strength'] is int ? json['signal_strength'] : 0,
      entryPrice: json['entry_price'] is num ? (json['entry_price'] as num).toDouble() : null,
      targetPrice: json['target_price'] is num ? (json['target_price'] as num).toDouble() : null,
      stopLossPrice: json['stop_loss_price'] is num ? (json['stop_loss_price'] as num).toDouble() : null,
      type: json['type'] ?? 'buy',
      strategyType: json['strategy_type'] ?? 'both',
      recommendedDuration: json['recommended_duration'] is int ? json['recommended_duration'] : 5,
      maxDrawdown: json['max_drawdown'] is num ? (json['max_drawdown'] as num).toDouble() : 0.05,
      consecutiveLossLimit: json['consecutive_loss_limit'] is int ? json['consecutive_loss_limit'] : 3,
      minConfidence: json['min_confidence'] is num ? (json['min_confidence'] as num).toDouble() : 0.6,
      riskRewardRatio: json['risk_reward_ratio'] is num ? (json['risk_reward_ratio'] as num).toDouble() : 2.0,
      compatibleIndicators: json['compatible_indicators'] != null
          ? List<String>.from(json['compatible_indicators'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'description': description,
      'entry_rule': entryRule,
      'exit_rule': exitRule,
      'stop_loss_rule': stopLossRule,
      'is_active': isActive ? 1 : 0,
      'signal_strength': signalStrength,
      'entry_price': entryPrice,
      'target_price': targetPrice,
      'stop_loss_price': stopLossPrice,
      'type': type,
      'strategy_type': strategyType,
      'recommended_duration': recommendedDuration,
      'max_drawdown': maxDrawdown,
      'consecutive_loss_limit': consecutiveLossLimit,
      'min_confidence': minConfidence,
      'risk_reward_ratio': riskRewardRatio,
      'compatible_indicators': compatibleIndicators,
    };
  }
}

List<TradingStrategy> evaluateStrategies(List<HistoryKline> data, List<SignalItem> signals, {MarketStructureResult? marketStructure}) {
  if (data.length < 30) return [];

  // 委托 StrategyBuilder 构建完整策略库
  final strategies = StrategyBuilder.buildLayeredStrategies(data, signals, null);

  // Phase 1: 根据市场结构禁用不兼容策略
  if (marketStructure != null) {
    final incompatibleNames = getIncompatibleStrategies(marketStructure.structure);
    for (final strategy in strategies) {
      if (incompatibleNames.contains(strategy.name)) {
        // 将通过传入参数方式禁用
        strategy.isActive = false;
      }
    }
  }

  // 冲突检测：短线与长线策略方向矛盾时生成警告
  final activeShortStrategies = strategies.where((s) => s.isActive && s.strategyType == 'short').toList();
  final activeLongStrategies = strategies.where((s) => s.isActive && s.strategyType == 'long').toList();
  // 基于信号判断多空方向：买卖信号同时存在时视为冲突
  final buySignals = signals.where((s) => s.type == 'buy').length;
  final sellSignals = signals.where((s) => s.type == 'sell').length;

  if (activeShortStrategies.isNotEmpty && activeLongStrategies.isNotEmpty && buySignals > 0 && sellSignals > 0) {
    strategies.add(TradingStrategy(
      id: 'conflict_warning',
      name: '策略冲突警告',
      category: '警告',
      description: '同时存在${activeShortStrategies.length}个短线策略和${activeLongStrategies.length}个长线策略，且多空信号矛盾（买${buySignals}/卖${sellSignals}），建议观望',
      entryRule: '多空信号冲突，观望为主',
      exitRule: '等待信号统一',
      stopLossRule: '严格止损',
      isActive: true,
      signalStrength: 70,
      entryPrice: null,
      targetPrice: null,
      stopLossPrice: null,
      type: 'warning',
    ));
  }

  return strategies;
}
