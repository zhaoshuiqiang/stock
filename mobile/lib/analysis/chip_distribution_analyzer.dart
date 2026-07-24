import '../models/stock_models.dart';

/// A single price level in the reconstructed chip (cost) distribution.
class ChipLevel {
  final double price;
  final double ratio; // share of float held at this price, normalized to sum 1

  const ChipLevel({required this.price, required this.ratio});
}

/// Result of the chip-distribution reconstruction.
///
/// [averageCost] is the ratio-weighted mean holding cost - a proxy for the
/// "main-force average cost" (pure K-line data cannot separate main-force from
/// retail, so this is the whole-float average / peak, labeled as such in UI).
/// [profitRatio] is the fraction of chips whose cost is at or below the current
/// price; [trappedRatio] is the fraction above it.
class ChipDistribution {
  final List<ChipLevel> levels;
  final double averageCost;
  final double profitRatio;
  final double trappedRatio;
  final double lowerCost90;
  final double upperCost90;
  final double concentration90;
  final double peakPrice;
  final double currentPrice;

  const ChipDistribution({
    required this.levels,
    required this.averageCost,
    required this.profitRatio,
    required this.trappedRatio,
    required this.lowerCost90,
    required this.upperCost90,
    required this.concentration90,
    required this.peakPrice,
    required this.currentPrice,
  });

  bool get isValid => levels.isNotEmpty;
}

/// Reconstructs a chip (cost) distribution from daily K-line using the classic
/// turnover-decay + triangular-diffusion model (TDX / EastMoney style):
///
/// For each day (oldest -> newest): decay all existing chips by the day's
/// turnover fraction g (older holders who sold), then add that day's volume as
/// new chips spread triangularly across [low, high] peaked at the typical
/// price. Recent, high-volume days dominate; the result is normalized to a
/// probability distribution over price.
///
/// Per-day turnover is derived as `volume(lots) * 100 / circulatingShares` when
/// [circulatingShares] is known; otherwise a fixed fallback diffusion is used
/// so the geometric recency-decay still applies.
class ChipDistributionAnalyzer {
  static const double _fallbackTurnover = 0.06;

  static ChipDistribution? analyze(
    List<HistoryKline> data, {
    required double currentPrice,
    double circulatingShares = 0,
    int priceBins = 120,
  }) {
    if (data.isEmpty || !currentPrice.isFinite || currentPrice <= 0) {
      return null;
    }

    var minP = double.infinity;
    var maxP = -double.infinity;
    for (final k in data) {
      final lo = k.low > 0 ? k.low : k.close;
      final hi = k.high > 0 ? k.high : k.close;
      if (lo > 0 && lo < minP) minP = lo;
      if (hi > maxP) maxP = hi;
    }
    if (!minP.isFinite || !maxP.isFinite || maxP <= 0) return null;
    // Include the current price so profit/trapped is meaningful at the edges.
    if (currentPrice < minP) minP = currentPrice;
    if (currentPrice > maxP) maxP = currentPrice;
    if (maxP <= minP) maxP = minP + (minP.abs() * 0.01 + 0.01);

    final bins = priceBins.clamp(10, 400);
    final width = (maxP - minP) / bins;
    final chips = List<double>.filled(bins, 0.0);

    for (final k in data) {
      final vol = k.volume;
      if (vol <= 0) continue;
      final g = circulatingShares > 0
          ? (vol * 100.0 / circulatingShares).clamp(0.001, 1.0)
          : _fallbackTurnover;
      for (var b = 0; b < bins; b++) {
        chips[b] *= (1.0 - g);
      }
      final lo = k.low > 0 ? k.low : k.close;
      final hi = k.high > 0 ? k.high : k.close;
      final tp = (hi + lo + k.close) / 3.0;
      _addTriangular(chips, minP, width, bins, lo, hi, tp, vol);
    }

    final total = chips.fold<double>(0.0, (a, b) => a + b);
    if (total <= 0) return null;

    final levels = <ChipLevel>[];
    var profit = 0.0;
    var weightedCost = 0.0;
    var peakRatio = -1.0;
    var peakPrice = currentPrice;
    for (var b = 0; b < bins; b++) {
      final ratio = chips[b] / total;
      final priceMid = minP + (b + 0.5) * width;
      levels.add(ChipLevel(price: priceMid, ratio: ratio));
      weightedCost += priceMid * ratio;
      if (priceMid <= currentPrice) profit += ratio;
      if (ratio > peakRatio) {
        peakRatio = ratio;
        peakPrice = priceMid;
      }
    }

    final range = _percentileRange(levels, 0.90);
    final lo90 = range[0];
    final hi90 = range[1];
    final concentration =
        (hi90 + lo90) > 0 ? (hi90 - lo90) / (hi90 + lo90) : 0.0;

    return ChipDistribution(
      levels: levels,
      averageCost: weightedCost,
      profitRatio: profit.clamp(0.0, 1.0),
      trappedRatio: (1.0 - profit).clamp(0.0, 1.0),
      lowerCost90: lo90,
      upperCost90: hi90,
      concentration90: concentration,
      peakPrice: peakPrice,
      currentPrice: currentPrice,
    );
  }

  static void _addTriangular(
    List<double> chips,
    double minP,
    double width,
    int bins,
    double lo,
    double hi,
    double typical,
    double mass,
  ) {
    if (width <= 0) return;
    if (hi <= lo) {
      final b = (((lo - minP) / width).floor()).clamp(0, bins - 1);
      chips[b] += mass;
      return;
    }
    final tp = typical.clamp(lo, hi);
    final startB = (((lo - minP) / width).floor()).clamp(0, bins - 1);
    final endB = (((hi - minP) / width).floor()).clamp(0, bins - 1);
    final weights = <int, double>{};
    var wsum = 0.0;
    for (var b = startB; b <= endB; b++) {
      final pc = minP + (b + 0.5) * width;
      double w;
      if (pc <= tp) {
        w = tp > lo ? (pc - lo) / (tp - lo) : 1.0;
      } else {
        w = hi > tp ? (hi - pc) / (hi - tp) : 1.0;
      }
      if (w < 0) w = 0;
      weights[b] = w;
      wsum += w;
    }
    if (wsum <= 0) {
      final b = (((tp - minP) / width).floor()).clamp(0, bins - 1);
      chips[b] += mass;
      return;
    }
    weights.forEach((b, w) {
      chips[b] += mass * (w / wsum);
    });
  }

  /// Returns [lowPrice, highPrice] bounding the central [p] fraction of chips
  /// (e.g. p=0.90 => the 5th..95th percentile cost band).
  static List<double> _percentileRange(List<ChipLevel> levels, double p) {
    final lowQ = (1 - p) / 2;
    final hiQ = 1 - (1 - p) / 2;
    var cum = 0.0;
    var lo = levels.first.price;
    var hi = levels.last.price;
    var loSet = false;
    for (final level in levels) {
      cum += level.ratio;
      if (!loSet && cum >= lowQ) {
        lo = level.price;
        loSet = true;
      }
      if (cum >= hiQ) {
        hi = level.price;
        break;
      }
    }
    return [lo, hi];
  }
}
