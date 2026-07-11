import '../models/stock_models.dart';

class PositionValuation {
  final double currentPrice;
  final double marketValue;
  final double floatPnl;
  final double pnlPct;
  final double todayPnl;
  final double todayPnlPct;

  const PositionValuation({
    required this.currentPrice,
    required this.marketValue,
    required this.floatPnl,
    required this.pnlPct,
    required this.todayPnl,
    required this.todayPnlPct,
  });

  factory PositionValuation.fromQuote(Position position, QuoteData quote) {
    final currentPrice = quote.price > 0
        ? quote.price
        : (position.latestPrice > 0 ? position.latestPrice : position.avgPrice);
    final marketValue = position.quantity * currentPrice;
    final cost = position.quantity * position.avgPrice;
    final floatPnl = marketValue - cost;
    final pnlPct = cost > 0 ? floatPnl / cost * 100 : 0.0;

    final todayPnl = quote.preClose > 0
        ? position.quantity * (currentPrice - quote.preClose)
        : 0.0;
    final todayPnlPct = quote.preClose > 0
        ? (currentPrice - quote.preClose) / quote.preClose * 100
        : 0.0;

    return PositionValuation(
      currentPrice: currentPrice,
      marketValue: marketValue,
      floatPnl: floatPnl,
      pnlPct: pnlPct,
      todayPnl: todayPnl,
      todayPnlPct: todayPnlPct,
    );
  }

  Position applyTo(Position position) {
    return position.copyWith(
      latestPrice: currentPrice,
      marketValue: marketValue,
      floatPnl: floatPnl,
      pnlPct: pnlPct,
      todayPnl: todayPnl,
      todayPnlPct: todayPnlPct,
    );
  }
}
