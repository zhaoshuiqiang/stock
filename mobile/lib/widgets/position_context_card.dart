import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analysis/position_risk_advisor.dart';

/// P3.2 + P3.3 UI: position-context card for a HELD stock.
///
/// Renders a context-aware add/hold/reduce/exit suggestion, an ATR dynamic
/// trailing stop, and a monetized risk estimate (预估回撤金额). Hidden when the
/// stock is not currently held (quantity <= 0).
class PositionContextCard extends StatelessWidget {
  final double score;
  final double currentPrice;
  final double avgPrice;
  final int quantity;
  final double atr;
  final double riskScore;

  const PositionContextCard({
    super.key,
    required this.score,
    required this.currentPrice,
    required this.avgPrice,
    required this.quantity,
    required this.atr,
    required this.riskScore,
  });

  @override
  Widget build(BuildContext context) {
    if (quantity <= 0 || avgPrice <= 0 || currentPrice <= 0) {
      return const SizedBox.shrink();
    }
    final peak = math.max(currentPrice, avgPrice);
    final stop = DynamicStopLoss.trailingStop(
      entryPrice: avgPrice,
      highestSincePurchase: peak,
      atr: atr,
    );
    final action = PositionContextAdvisor.advise(
      score: score,
      currentPrice: currentPrice,
      stopPrice: stop,
    );
    final positionValue = quantity * currentPrice;
    final risk = RiskMonetizer.estimate(
      riskScore: riskScore,
      positionValue: positionValue,
    );
    final pnlPct = (currentPrice - avgPrice) / avgPrice * 100;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('持仓建议',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _actionColor(action).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(PositionContextAdvisor.label(action),
                    style: TextStyle(
                        color: _actionColor(action),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row('持仓成本', avgPrice.toStringAsFixed(2)),
          _row('浮动盈亏',
              '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
              color: pnlPct >= 0
                  ? const Color(0xFFef5350)
                  : const Color(0xFF26a69a)),
          _row('动态止损位', stop.toStringAsFixed(2),
              color: const Color(0xFFff9800)),
          _row('预估风险回撤',
              '${risk.amount.toStringAsFixed(0)} 元 (${(risk.drawdownPct * 100).toStringAsFixed(0)}%)',
              color: const Color(0xFFef5350)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: color ?? Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _actionColor(PositionAction action) {
    switch (action) {
      case PositionAction.addPosition:
        return const Color(0xFFef5350);
      case PositionAction.hold:
        return const Color(0xFFff9800);
      case PositionAction.reduce:
      case PositionAction.exit:
      case PositionAction.stopTriggered:
        return const Color(0xFF26a69a);
    }
  }
}
