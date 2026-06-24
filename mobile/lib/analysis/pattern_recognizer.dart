import 'dart:math';
import '../models/stock_models.dart';

/// Signal emitted when a chart pattern is detected.
class PatternSignal {
  final String patternName;
  final String direction;
  final double confidence;
  final int barsAgo;
  final String description;
  final double? breakoutPrice;
  final double? targetPrice;

  const PatternSignal({
    required this.patternName,
    required this.direction,
    required this.confidence,
    required this.barsAgo,
    required this.description,
    this.breakoutPrice,
    this.targetPrice,
  });
}

/// Classic chart pattern recognizer.
///
/// Detects 3 core patterns from K-line data:
/// - Double Bottom (双底) — bullish reversal
/// - Head and Shoulders Bottom (头肩底) — bullish reversal
/// - Triangle Breakout (三角突破) — continuation or reversal
class PatternRecognizer {
  PatternRecognizer._();

  /// Minimum confidence threshold for returning a signal.
  static const double minConfidence = 0.45;

  /// Run all pattern detectors and return results sorted by confidence desc.
  static List<PatternSignal> detectAll(List<HistoryKline> data) {
    if (data.length < 20) return [];

    final results = <PatternSignal>[];

    final db = _detectDoubleBottom(data);
    if (db != null) results.add(db);

    final hs = _detectHeadShouldersBottom(data);
    if (hs != null) results.add(hs);

    final tb = _detectTriangleBreakout(data);
    if (tb != null) results.add(tb);

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results;
  }

  // ---------------------------------------------------------------------------
  // Double Bottom (双底)
  // ---------------------------------------------------------------------------

  /// Detects a double-bottom pattern in the most recent 20-60 bars.
  ///
  /// Steps:
  /// 1. Find all local minima (low lower than neighbours within ±2 bars).
  /// 2. Identify the two deepest local minima that are separated by ≥5 bars
  ///    and whose lows are within 3% of each other.
  /// 3. Require current price to be above the midpoint between the two dips.
  /// 4. Score confidence by dip similarity, separation, and volume on the
  ///    second dip.
  static PatternSignal? _detectDoubleBottom(List<HistoryKline> data) {
    final n = data.length;
    final windowStart = max(0, n - 60);
    final windowData = data.sublist(windowStart);

    if (windowData.length < 20) return null;

    // 1. Find local minima (look-ahead/back ±2)
    final minima = <int>[];
    for (int i = 2; i < windowData.length - 2; i++) {
      final low = windowData[i].low;
      final isMinima = windowData[i - 2].low > low &&
          windowData[i - 1].low > low &&
          windowData[i + 1].low > low &&
          windowData[i + 2].low > low;
      if (isMinima) {
        minima.add(i);
      }
    }

    if (minima.length < 2) return null;

    // 2. Find the best pair of minima
    int bestI = -1, bestJ = -1;
    double bestSimilarity = double.infinity;

    for (int a = 0; a < minima.length - 1; a++) {
      for (int b = a + 1; b < minima.length; b++) {
        final i = minima[a];
        final j = minima[b];
        final separation = j - i;
        if (separation < 5) continue;

        final lowI = windowData[i].low;
        final lowJ = windowData[j].low;
        final avgLow = (lowI + lowJ) / 2;
        if (avgLow <= 0) continue;
        final diffPct = (lowJ - lowI).abs() / avgLow;

        // Must be within 3%
        if (diffPct > 0.03) continue;

        if (diffPct < bestSimilarity) {
          bestSimilarity = diffPct;
          bestI = i;
          bestJ = j;
        }
      }
    }

    if (bestI < 0 || bestJ < 0) return null;

    final lowFirst = windowData[bestI].low;
    final lowSecond = windowData[bestJ].low;
    final lowestDip = min(lowFirst, lowSecond);

    // Midpoint between dips (peaks between)
    final midHigh = _highestBetween(windowData, bestI, bestJ);
    if (midHigh <= 0) return null;

    final breakoutPrice = midHigh;
    final currentClose = data.last.close;

    // Must have broken above the midpoint
    if (currentClose <= breakoutPrice) return null;

    // Target
    final targetPrice = breakoutPrice + (breakoutPrice - lowestDip);

    // Confidence scoring
    final dipSimilarityScore = 1.0 - bestSimilarity / 0.03;
    final separation = bestJ - bestI;
    final separationScore = _rangeScore(separation.toDouble(), 10, 30);
    final volSecondDip = windowData[bestJ].volume;
    final avgVol = _averageVolume(windowData);
    final volumeScore = avgVol > 0 ? min(volSecondDip / (avgVol * 1.5), 1.0) : 0.5;

    var confidence = dipSimilarityScore * 0.35 + separationScore * 0.30 + volumeScore * 0.35;
    confidence = confidence.clamp(0.0, 1.0);

    if (confidence < minConfidence) return null;

    final barsAgo = n - 1 - (windowStart + bestJ);

    return PatternSignal(
      patternName: '双底',
      direction: 'bullish',
      confidence: confidence,
      barsAgo: barsAgo,
      description: '检测到双底形态(W底)，突破颈线确认看涨信号',
      breakoutPrice: breakoutPrice,
      targetPrice: targetPrice,
    );
  }

  // ---------------------------------------------------------------------------
  // Head and Shoulders Bottom (头肩底)
  // ---------------------------------------------------------------------------

  /// Detects a head-and-shoulders bottom pattern in the most recent 30-80 bars.
  ///
  /// Steps:
  /// 1. Find all significant local minima.
  /// 2. Search for a left-shoulder → head (deepest) → right-shoulder sequence.
  ///    Head must be deeper than both shoulders; shoulders within 5% of each
  ///    other.
  /// 3. Neckline connects the two peaks between shoulder-head and head-shoulder.
  /// 4. Current price > neckline for confirmation.
  static PatternSignal? _detectHeadShouldersBottom(List<HistoryKline> data) {
    final n = data.length;
    final windowStart = max(0, n - 80);
    final windowData = data.sublist(windowStart);

    if (windowData.length < 30) return null;

    // 1. Find local minima (look-ahead/back ±2)
    final minima = <int>[];
    for (int i = 2; i < windowData.length - 2; i++) {
      final low = windowData[i].low;
      final isMinima = windowData[i - 2].low > low &&
          windowData[i - 1].low > low &&
          windowData[i + 1].low > low &&
          windowData[i + 2].low > low;
      if (isMinima) minima.add(i);
    }

    if (minima.length < 3) return null;

    // 2. Search for head-and-shoulders sequence among minima
    for (int left = 0; left < minima.length - 2; left++) {
      final lsIdx = minima[left];
      final lsLow = windowData[lsIdx].low;

      for (int head = left + 1; head < minima.length - 1; head++) {
        final hIdx = minima[head];
        final hLow = windowData[hIdx].low;

        // Head must be deeper than left shoulder
        if (hLow >= lsLow) continue;

        for (int right = head + 1; right < minima.length; right++) {
          final rsIdx = minima[right];
          final rsLow = windowData[rsIdx].low;

          // Head must be deeper than right shoulder
          if (hLow >= rsLow) continue;

          // Shoulders within 5% of each other
          final avgShoulder = (lsLow + rsLow) / 2;
          if (avgShoulder <= 0) continue;
          final shoulderDiff = (lsLow - rsLow).abs() / avgShoulder;
          if (shoulderDiff > 0.05) continue;

          // Minimum separation
          if (hIdx - lsIdx < 4 || rsIdx - hIdx < 4) continue;

          // 3. Neckline: peaks between LS-H and H-RS
          final peak1 = _highestBetween(windowData, lsIdx, hIdx);
          final peak2 = _highestBetween(windowData, hIdx, rsIdx);
          if (peak1 <= 0 || peak2 <= 0) continue;

          // Neckline connects the two peaks (take average if sloping)
          final neckline = (peak1 + peak2) / 2;

          // Current price must be above neckline
          final currentClose = data.last.close;
          if (currentClose <= neckline) continue;

          // Target
          final targetPrice = neckline + (neckline - hLow);

          // Confidence scoring
          final shoulderSymScore = 1.0 - shoulderDiff / 0.05;
          final headDepth = (avgShoulder - hLow) / avgShoulder;
          final headDepthScore = min(headDepth / 0.08, 1.0); // 8% head depth = full marks
          final confirmationScore = (currentClose - neckline) / (neckline * 0.03);
          final confirmed = min(confirmationScore, 1.0);

          // Volume increase on right shoulder
          final volRS = windowData[rsIdx].volume;
          final avgVol = _averageVolume(windowData);
          final volumeScore = avgVol > 0 ? min(volRS / (avgVol * 1.5), 1.0) : 0.5;

          var confidence = shoulderSymScore * 0.25 +
              headDepthScore * 0.25 +
              confirmed * 0.25 +
              volumeScore * 0.25;
          confidence = confidence.clamp(0.0, 1.0);

          if (confidence < minConfidence) continue;

          final barsAgo = n - 1 - (windowStart + rsIdx);

          return PatternSignal(
            patternName: '头肩底',
            direction: 'bullish',
            confidence: confidence,
            barsAgo: barsAgo,
            description: '检测到头肩底形态，突破颈线确认看涨反转信号',
            breakoutPrice: neckline,
            targetPrice: targetPrice,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Triangle Breakout (三角突破)
  // ---------------------------------------------------------------------------

  /// Detects a triangle breakout in the most recent 30-60 bars.
  ///
  /// Steps:
  /// 1. Fit a descending trendline to recent swing highs.
  /// 2. Fit an ascending trendline to recent swing lows.
  /// 3. Require triangle width ≥15 bars.
  /// 4. Detect breakout direction: price above upper TL = bullish, below lower TL
  ///    = bearish.
  /// 5. Volume should increase on breakout.
  static PatternSignal? _detectTriangleBreakout(List<HistoryKline> data) {
    final n = data.length;
    final windowStart = max(0, n - 60);
    final windowData = data.sublist(windowStart);

    if (windowData.length < 30) return null;

    // Find swing highs
    final swingHighs = <_Point>[];
    for (int i = 3; i < windowData.length - 3; i++) {
      final high = windowData[i].high;
      final isSwingHigh = windowData[i - 3].high < high &&
          windowData[i - 2].high < high &&
          windowData[i - 1].high < high &&
          windowData[i + 1].high < high &&
          windowData[i + 2].high < high &&
          windowData[i + 3].high < high;
      if (isSwingHigh) swingHighs.add(_Point(i.toDouble(), high));
    }

    // Find swing lows
    final swingLows = <_Point>[];
    for (int i = 3; i < windowData.length - 3; i++) {
      final low = windowData[i].low;
      final isSwingLow = windowData[i - 3].low > low &&
          windowData[i - 2].low > low &&
          windowData[i - 1].low > low &&
          windowData[i + 1].low > low &&
          windowData[i + 2].low > low &&
          windowData[i + 3].low > low;
      if (isSwingLow) swingLows.add(_Point(i.toDouble(), low));
    }

    if (swingHighs.length < 3 || swingLows.length < 3) return null;

    // Use most recent swing points
    final recentHighs = swingHighs.sublist(max(0, swingHighs.length - 12));
    final recentLows = swingLows.sublist(max(0, swingLows.length - 12));

    if (recentHighs.length < 3 || recentLows.length < 3) return null;

    // Fit descending trendline to swing highs (linear regression)
    final upperTL = _linearRegression(recentHighs);
    // Fit ascending trendline to swing lows
    final lowerTL = _linearRegression(recentLows);

    if (upperTL == null || lowerTL == null) return null;

    // Triangle must be converging: upper TL slope < 0, lower TL slope > 0
    if (upperTL.slope >= 0 || lowerTL.slope <= 0) return null;

    // Triangle width ≥ 15 bars
    final lastBarX = (windowData.length - 1).toDouble();
    final upperEnd = upperTL.intercept + upperTL.slope * lastBarX;
    final lowerEnd = lowerTL.intercept + lowerTL.slope * lastBarX;
    final triangleHeight = (upperEnd - lowerEnd).abs();
    final startUpper = upperTL.intercept + upperTL.slope * recentHighs.first.x;
    final startLower = lowerTL.intercept + lowerTL.slope * recentLows.first.x;
    final startHeight = (startUpper - startLower).abs();

    // Check convergence (start height should be bigger than end height)
    if (startHeight <= triangleHeight * 1.2) return null;

    final currentClose = data.last.close;
    final currentBar = (windowData.length - 1).toDouble();
    final upperLinePrice = upperTL.intercept + upperTL.slope * currentBar;
    final lowerLinePrice = lowerTL.intercept + lowerTL.slope * currentBar;

    // Detect breakout
    String? direction;
    double? breakoutLinePrice;
    String description;
    double? targetPrice;

    if (currentClose > upperLinePrice) {
      // Bullish breakout above upper trendline
      direction = 'bullish';
      breakoutLinePrice = upperLinePrice;
      targetPrice = upperLinePrice + startHeight;
      description = '三角收敛后向上突破，看涨信号';
    } else if (currentClose < lowerLinePrice) {
      // Bearish breakout below lower trendline
      direction = 'bearish';
      breakoutLinePrice = lowerLinePrice;
      targetPrice = lowerLinePrice - startHeight;
      description = '三角收敛后向下突破，看跌信号';
    } else {
      return null; // No breakout yet
    }

    // Volume confirmation
    final recentVol = _recentAvgVolume(windowData, 3);
    final midVol = _midAvgVolume(windowData, 10, 20);
    final volumeConfirm = midVol > 0 ? recentVol / midVol : 1.0;

    if (volumeConfirm < 0.8) return null; // Volume must be close to or above average

    // Confidence scoring
    final widthScore = _rangeScore(windowData.length.toDouble(), 15, 40);
    final convergenceScore = min(startHeight / (triangleHeight + 0.001) / 3.0, 1.0);
    final volumeScore = min(volumeConfirm / 1.5, 1.0);
    final breakoutStrength = direction == 'bullish'
        ? min((currentClose - upperLinePrice).abs() / (upperLinePrice * 0.02), 1.0)
        : min((lowerLinePrice - currentClose).abs() / (lowerLinePrice * 0.02), 1.0);

    var confidence = widthScore * 0.20 +
        convergenceScore * 0.30 +
        volumeScore * 0.25 +
        breakoutStrength * 0.25;
    confidence = confidence.clamp(0.0, 1.0);

    if (confidence < minConfidence) return null;

    // barsAgo: use 0 since breakout is "now"
    return PatternSignal(
      patternName: '三角突破',
      direction: direction,
      confidence: confidence,
      barsAgo: 0,
      description: description,
      breakoutPrice: breakoutLinePrice,
      targetPrice: targetPrice,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Finds the highest high within (start, end) exclusive.
  static double _highestBetween(
      List<HistoryKline> data, int start, int end) {
    double highest = double.negativeInfinity;
    for (int i = start + 1; i < end; i++) {
      if (data[i].high > highest) highest = data[i].high;
    }
    return highest == double.negativeInfinity ? 0 : highest;
  }

  /// Average volume across the provided window.
  static double _averageVolume(List<HistoryKline> data) {
    if (data.isEmpty) return 0;
    double sum = 0;
    for (final bar in data) {
      sum += bar.volume;
    }
    return sum / data.length;
  }

  /// Average volume of the most recent [count] bars.
  static double _recentAvgVolume(List<HistoryKline> data, int count) {
    if (data.length < count) return _averageVolume(data);
    final recent = data.sublist(data.length - count);
    return _averageVolume(recent);
  }

  /// Average volume from [start] to [end] bars before the end.
  static double _midAvgVolume(
      List<HistoryKline> data, int start, int end) {
    final actualStart = max(0, data.length - end);
    final actualEnd = max(0, data.length - start);
    if (actualEnd <= actualStart) return _averageVolume(data);
    return _averageVolume(data.sublist(actualStart, actualEnd));
  }

  /// Gives 1.0 at the ideal range midpoint, tapering to 0.0 outside.
  static double _rangeScore(double value, double minIdeal, double maxIdeal) {
    if (value >= minIdeal && value <= maxIdeal) return 1.0;
    if (value >= maxIdeal) return max(0.0, 1.0 - (value - maxIdeal) / maxIdeal);
    return max(0.0, value / minIdeal);
  }

  /// Simple linear regression returning slope and intercept.
  /// Returns null if the fit fails.
  static _LinearFit? _linearRegression(List<_Point> points) {
    if (points.length < 2) return null;
    final n = points.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
      sumXY += p.x * p.y;
      sumX2 += p.x * p.x;
    }
    final denominator = n * sumX2 - sumX * sumX;
    if (denominator == 0) return null;
    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;
    return _LinearFit(slope, intercept);
  }
}

/// Internal 2D point for regression.
class _Point {
  final double x;
  final double y;
  const _Point(this.x, this.y);
}

/// Internal linear fit result.
class _LinearFit {
  final double slope;
  final double intercept;
  const _LinearFit(this.slope, this.intercept);
}
