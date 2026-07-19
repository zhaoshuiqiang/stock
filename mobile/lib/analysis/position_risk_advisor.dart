/// Position-aware advisory utilities (plan P3.2 + P3.3).
///
/// Pure functions (no I/O, no UI) so they are fully unit-testable and reusable
/// from the detail screen / dashboard. They turn a held position + the current
/// analysis into: a dynamic ATR trailing stop, a monetized risk estimate, and a
/// context-aware add/hold/reduce/exit suggestion.

/// Monetized risk estimate for a held position.
class RiskMoneyEstimate {
  /// Estimated adverse drawdown as a fraction (0..1) of position value.
  final double drawdownPct;

  /// Estimated adverse drawdown in currency (positionValue * drawdownPct).
  final double amount;

  const RiskMoneyEstimate({required this.drawdownPct, required this.amount});
}

/// P3.2: ATR-based dynamic trailing stop-loss.
class DynamicStopLoss {
  /// Trailing stop that ratchets UP as [highestSincePurchase] rises but never
  /// drops below the initial percentage stop off [entryPrice].
  ///
  /// - initial floor  = entryPrice * (1 - initialStopPct)
  /// - trailing level = highestSincePurchase - atrMultiplier * atr
  /// The stop is the higher of the two, and is never placed above the current
  /// reference (highestSincePurchase).
  static double trailingStop({
    required double entryPrice,
    required double highestSincePurchase,
    required double atr,
    double atrMultiplier = 2.0,
    double initialStopPct = 0.08,
  }) {
    if (entryPrice <= 0) return 0;
    final floor = entryPrice * (1 - initialStopPct.clamp(0.0, 0.9));
    final safeAtr = (atr.isFinite && atr > 0) ? atr : 0.0;
    final trailing = highestSincePurchase - atrMultiplier * safeAtr;
    final stop = trailing > floor ? trailing : floor;
    // Never above the peak reference.
    return stop > highestSincePurchase ? highestSincePurchase : stop;
  }
}

/// P3.3: convert a 0-100 risk score into an estimated worst-case drawdown for a
/// given position value. Higher risk -> larger expected adverse move.
class RiskMonetizer {
  /// Baseline drawdown at risk 0 and the additional span up to risk 100.
  static const double _baseDrawdown = 0.05; // 5%
  static const double _spanDrawdown = 0.20; // +20% -> up to 25% at risk 100

  static RiskMoneyEstimate estimate({
    required double riskScore,
    required double positionValue,
  }) {
    final r = riskScore.clamp(0.0, 100.0) / 100.0;
    final pct = _baseDrawdown + _spanDrawdown * r;
    final value = positionValue.isFinite && positionValue > 0
        ? positionValue
        : 0.0;
    return RiskMoneyEstimate(drawdownPct: pct, amount: value * pct);
  }
}

/// Position-context suggestion for a held stock.
enum PositionAction { addPosition, hold, reduce, exit, stopTriggered }

/// P3.2: context-aware suggestion combining the analysis score with the
/// current price relative to the dynamic stop.
class PositionContextAdvisor {
  static PositionAction advise({
    required double score,
    required double currentPrice,
    required double stopPrice,
  }) {
    if (stopPrice > 0 && currentPrice > 0 && currentPrice <= stopPrice) {
      return PositionAction.stopTriggered;
    }
    if (score >= 7) return PositionAction.addPosition;
    if (score >= 5) return PositionAction.hold;
    if (score >= 3) return PositionAction.reduce;
    return PositionAction.exit;
  }

  /// Chinese label for UI display.
  static String label(PositionAction action) {
    switch (action) {
      case PositionAction.addPosition:
        return '可加仓';
      case PositionAction.hold:
        return '持有';
      case PositionAction.reduce:
        return '减仓';
      case PositionAction.exit:
        return '清仓';
      case PositionAction.stopTriggered:
        return '触发止损';
    }
  }
}
