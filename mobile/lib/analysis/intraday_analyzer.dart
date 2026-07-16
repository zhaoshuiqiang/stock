import 'dart:math';
import '../models/stock_models.dart';

class IntradayAnalyzer {
  static IntradayProfile analyze(List<IntradayKline> klines) {
    if (klines.isEmpty) return IntradayProfile.unknown();
    if (klines.length < 6) return IntradayProfile.unknown();

    final pattern = _detectPattern(klines);
    final volDist = _analyzeVolumeDistribution(klines);
    final momentum = _calcMomentum(klines);
    final speed = _calcSpeed(klines);
    final signals = IntradaySignalDetector.detect(klines);
    final score = _calcIntradayScore(pattern, volDist, momentum, speed, signals);

    return IntradayProfile(
      pattern: pattern,
      volumeDistribution: volDist,
      momentumScore: momentum,
      speedScore: speed,
      signals: signals,
      intradayScore: score,
    );
  }

  static IntradayPattern _detectPattern(List<IntradayKline> klines) {
    final morning = klines.where((k) => k.time.hour < 12).toList();
    final afternoon = klines.where((k) => k.time.hour >= 13).toList();

    if (morning.isNotEmpty && afternoon.isNotEmpty) {
      if (_isEarlyHighThenFade(morning, afternoon)) {
        return IntradayPattern.earlyRallyAndFade;
      }
    }

    if (_isLowOpenAndRally(klines)) {
      return IntradayPattern.lowOpenAndRally;
    }

    if (afternoon.isNotEmpty) {
      if (_isSidewaysLateRally(afternoon, klines)) {
        return IntradayPattern.sidewaysLateRally;
      }
      if (_isSidewaysLateDrop(afternoon, klines)) {
        return IntradayPattern.sidewaysLateDrop;
      }
    }

    if (_isSteadyClimb(klines)) {
      return IntradayPattern.steadyClimb;
    }
    if (_isSteadyDecline(klines)) {
      return IntradayPattern.steadyDecline;
    }

    return IntradayPattern.volatile;
  }

  static bool _isEarlyHighThenFade(
      List<IntradayKline> morning, List<IntradayKline> afternoon) {
    if (morning.isEmpty || afternoon.isEmpty) return false;
    final morningHigh = morning.map((k) => k.high).reduce(max);
    final morningHighIdx = morning.indexWhere((k) => k.high == morningHigh);
    if (morningHighIdx > 6) return false;
    final afternoonClose = afternoon.last.close;
    return afternoonClose < morningHigh * 0.98;
  }

  static bool _isLowOpenAndRally(List<IntradayKline> klines) {
    if (klines.length < 6) return false;
    final first = klines.first;
    final last = klines.last;
    return first.close < first.open && last.close > first.open * 1.01;
  }

  static bool _isSidewaysLateRally(
      List<IntradayKline> afternoon, List<IntradayKline> klines) {
    final lateSession = afternoon.where((k) => k.time.hour == 14 && k.time.minute >= 30).toList();
    if (lateSession.isEmpty) return false;
    final lateHigh = lateSession.map((k) => k.high).reduce(max);
    final earlyHigh = klines.take(klines.length - lateSession.length)
        .map((k) => k.high)
        .fold(0.0, max);
    return lateHigh > earlyHigh * 1.01;
  }

  static bool _isSidewaysLateDrop(
      List<IntradayKline> afternoon, List<IntradayKline> klines) {
    final lateSession = afternoon.where((k) => k.time.hour == 14 && k.time.minute >= 30).toList();
    if (lateSession.isEmpty) return false;
    final lateLow = lateSession.map((k) => k.low).reduce(min);
    final earlyLow = klines.take(klines.length - lateSession.length)
        .map((k) => k.low)
        .fold(double.infinity, min);
    return lateLow < earlyLow * 0.99;
  }

  static bool _isSteadyClimb(List<IntradayKline> klines) {
    if (klines.length < 6) return false;
    int upCount = 0;
    for (int i = 1; i < klines.length; i++) {
      if (klines[i].close > klines[i - 1].close) upCount++;
    }
    return upCount > klines.length * 0.7 && klines.last.close > klines.first.open;
  }

  static bool _isSteadyDecline(List<IntradayKline> klines) {
    if (klines.length < 6) return false;
    int downCount = 0;
    for (int i = 1; i < klines.length; i++) {
      if (klines[i].close < klines[i - 1].close) downCount++;
    }
    return downCount > klines.length * 0.7 && klines.last.close < klines.first.open;
  }

  static double _analyzeVolumeDistribution(List<IntradayKline> klines) {
    if (klines.length < 6) return 0.5;
    final totalVolume = klines.map((k) => k.volume).fold(0.0, (a, b) => a + b);
    if (totalVolume <= 0) return 0.5;

    final morning30min = klines.take(6).map((k) => k.volume).fold(0.0, (a, b) => a + b);
    final last30min = klines.skip(klines.length - 6).map((k) => k.volume).fold(0.0, (a, b) => a + b);

    final morningRatio = morning30min / totalVolume;
    final lastRatio = last30min / totalVolume;

    double score = 0.5;
    if (morningRatio > 0.3) score += 0.2;
    if (lastRatio > 0.3 && klines.last.isUp) score += 0.15;
    if (lastRatio > 0.3 && klines.last.isDown) score -= 0.15;

    return score.clamp(0.0, 1.0);
  }

  static double _calcMomentum(List<IntradayKline> klines) {
    if (klines.length < 3) return 5.0;
    double score = 5.0;
    for (int i = 1; i < klines.length; i++) {
      final change = klines[i].changePct;
      if (change > 0.01) score += 0.5;
      else if (change < -0.01) score -= 0.5;
    }
    return score.clamp(0.0, 10.0);
  }

  static double _calcSpeed(List<IntradayKline> klines) {
    if (klines.length < 2) return 5.0;
    double score = 5.0;

    for (int i = 1; i < klines.length; i++) {
      final speed = (klines[i].close - klines[i - 1].close) / klines[i - 1].close;
      if (speed > 0.02 && klines[i].isUp) score += 1.0;
      if (speed < -0.02 && klines[i].isDown) score -= 1.0;
    }

    final maxPrice = klines.map((k) => k.high).reduce(max);
    final maxIndex = klines.indexWhere((k) => k.high == maxPrice);
    if (maxIndex < klines.length - 6 && klines.last.close < maxPrice * 0.97) {
      score -= 1.5;
    }

    return score.clamp(0.0, 10.0);
  }

  static double _calcIntradayScore(
    IntradayPattern pattern,
    double volDist,
    double momentum,
    double speed,
    List<IntradaySignal> signals,
  ) {
    double score = 5.0;

    switch (pattern) {
      case IntradayPattern.lowOpenAndRally:
      case IntradayPattern.steadyClimb:
        score += 1.5;
        break;
      case IntradayPattern.earlyRallyAndFade:
      case IntradayPattern.steadyDecline:
        score -= 1.5;
        break;
      case IntradayPattern.sidewaysLateRally:
        score += 0.8;
        break;
      case IntradayPattern.sidewaysLateDrop:
        score -= 0.8;
        break;
      default:
        break;
    }

    score += (momentum - 5.0) * 0.3;
    score += (speed - 5.0) * 0.2;

    final buySignals = signals.where((s) => s.type == 'buy').length;
    final sellSignals = signals.where((s) => s.type == 'sell').length;
    score += (buySignals - sellSignals) * 0.3;

    return score.clamp(0.0, 10.0);
  }
}

class IntradaySignalDetector {
  static List<IntradaySignal> detect(List<IntradayKline> klines) {
    if (klines.length < 6) return [];
    final signals = <IntradaySignal>[];

    _detectEarlyRallyAndFade(klines, signals);
    _detectLowOpenAndRally(klines, signals);
    _detectLateSessionRally(klines, signals);
    _detectLateSessionDrop(klines, signals);
    _detectVolumeIncreasingUp(klines, signals);
    _detectVolumeIncreasingDown(klines, signals);

    return signals;
  }

  static void _detectEarlyRallyAndFade(
      List<IntradayKline> klines, List<IntradaySignal> signals) {
    final morning = klines.where((k) => k.time.hour < 12).toList();
    final afternoon = klines.where((k) => k.time.hour >= 13).toList();
    if (morning.isEmpty || afternoon.isEmpty) return;

    final morningHigh = morning.map((k) => k.high).reduce(max);
    final morningHighTime = morning.firstWhere((k) => k.high == morningHigh).time;
    if (morningHighTime.hour >= 10) return;

    final drop = (morningHigh - afternoon.last.close) / morningHigh;
    if (drop > 0.02) {
      signals.add(IntradaySignal(
        type: 'sell',
        name: '早盘冲高回落',
        time: afternoon.last.time,
        confidence: 0.75,
        description: '10:00前最高，之后回落${(drop * 100).toStringAsFixed(1)}%',
      ));
    }
  }

  static void _detectLowOpenAndRally(
      List<IntradayKline> klines, List<IntradaySignal> signals) {
    if (klines.length < 6) return;
    final first = klines.first;
    final last = klines.last;
    if (first.close < first.open && last.close > first.open * 1.01) {
      signals.add(IntradaySignal(
        type: 'buy',
        name: '低开高走',
        time: last.time,
        confidence: 0.70,
        description: '低开后走高，收盘涨幅>${((last.close / first.open - 1) * 100).toStringAsFixed(1)}%',
      ));
    }
  }

  static void _detectLateSessionRally(
      List<IntradayKline> klines, List<IntradaySignal> signals) {
    final lateSession = klines.where((k) =>
        k.time.hour == 14 && k.time.minute >= 30).toList();
    if (lateSession.isEmpty) return;
    final rally = (lateSession.last.close - lateSession.first.open) / lateSession.first.open;
    final avgVol = klines.map((k) => k.volume).fold(0.0, (a, b) => a + b) / klines.length;
    final lateVol = lateSession.map((k) => k.volume).fold(0.0, (a, b) => a + b) / lateSession.length;
    if (rally > 0.01 && lateVol > avgVol * 1.2) {
      signals.add(IntradaySignal(
        type: 'buy',
        name: '尾盘抢筹',
        time: lateSession.last.time,
        confidence: 0.65,
        description: '14:30后放量拉升${(rally * 100).toStringAsFixed(1)}%',
      ));
    }
  }

  static void _detectLateSessionDrop(
      List<IntradayKline> klines, List<IntradaySignal> signals) {
    final lateSession = klines.where((k) =>
        k.time.hour == 14 && k.time.minute >= 30).toList();
    if (lateSession.isEmpty) return;
    final drop = (lateSession.first.open - lateSession.last.close) / lateSession.first.open;
    final avgVol = klines.map((k) => k.volume).fold(0.0, (a, b) => a + b) / klines.length;
    final lateVol = lateSession.map((k) => k.volume).fold(0.0, (a, b) => a + b) / lateSession.length;
    if (drop > 0.01 && lateVol > avgVol * 1.2) {
      signals.add(IntradaySignal(
        type: 'sell',
        name: '尾盘跳水',
        time: lateSession.last.time,
        confidence: 0.70,
        description: '14:30后放量下跌${(drop * 100).toStringAsFixed(1)}%',
      ));
    }
  }

  static void _detectVolumeIncreasingUp(
      List<IntradayKline> klines, List<IntradaySignal> signals) {
    if (klines.length < 3) return;
    for (int i = 2; i < klines.length; i++) {
      if (klines[i].volume > klines[i - 1].volume &&
          klines[i - 1].volume > klines[i - 2].volume &&
          klines[i].isUp && klines[i - 1].isUp) {
        signals.add(IntradaySignal(
          type: 'buy',
          name: '量能递增上涨',
          time: klines[i].time,
          confidence: 0.60,
          description: '连续放量上涨，资金持续进场',
        ));
        return;
      }
    }
  }

  static void _detectVolumeIncreasingDown(
      List<IntradayKline> klines, List<IntradaySignal> signals) {
    if (klines.length < 3) return;
    for (int i = 2; i < klines.length; i++) {
      if (klines[i].volume > klines[i - 1].volume &&
          klines[i - 1].volume > klines[i - 2].volume &&
          klines[i].isDown && klines[i - 1].isDown) {
        signals.add(IntradaySignal(
          type: 'sell',
          name: '量能递增下跌',
          time: klines[i].time,
          confidence: 0.60,
          description: '连续放量下跌，资金持续出逃',
        ));
        return;
      }
    }
  }
}
