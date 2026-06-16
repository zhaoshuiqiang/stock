# signal_engine 上帝函数重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 signal_engine.dart 中1000+行的 `generateAnalysis` 上帝函数拆分为职责单一的模块，保持对外接口不变。

**Architecture:** 采用"提取类"策略，将 generateAnalysis 中的各段逻辑提取为独立的静态类，generateAnalysis 退化为薄编排器。每个新类放在 `mobile/lib/analysis/` 目录下的独立文件中，通过 import 引入。保持所有现有调用方无需修改。

**Tech Stack:** Dart, Flutter, flutter_test

---

## File Structure

| 操作 | 文件 | 职责 |
|---|---|---|
| Create | `mobile/lib/analysis/signal_layer.dart` | 信号检测与合并 |
| Create | `mobile/lib/analysis/technical_scorer.dart` | 5维技术面评分 |
| Create | `mobile/lib/analysis/realtime_scorer.dart` | 实时行情评分 |
| Create | `mobile/lib/analysis/confluence_scorer.dart` | 跨指标共振评分 |
| Create | `mobile/lib/analysis/comprehensive_scorer.dart` | 综合评分（动态权重+市场调节） |
| Create | `mobile/lib/analysis/risk_analyzer.dart` | 风险因子收集+等级判定 |
| Create | `mobile/lib/analysis/opportunity_identifier.dart` | 机会识别 |
| Create | `mobile/lib/analysis/suggestion_generator.dart` | 操作建议生成 |
| Create | `mobile/lib/analysis/confidence_calculator.dart` | 置信度计算+对抗验证调整 |
| Modify | `mobile/lib/analysis/signal_engine.dart` | 薄编排器，委托给各模块 |
| Create | `mobile/test/signal_layer_test.dart` | SignalLayer 单元测试 |
| Create | `mobile/test/technical_scorer_test.dart` | TechnicalScorer 单元测试 |
| Create | `mobile/test/realtime_scorer_test.dart` | RealtimeScorer 单元测试 |
| Create | `mobile/test/confluence_scorer_test.dart` | ConfluenceScorer 单元测试 |
| Create | `mobile/test/risk_analyzer_test.dart` | RiskAnalyzer 单元测试 |
| Create | `mobile/test/confidence_calculator_test.dart` | ConfidenceCalculator 单元测试 |

---

### Task 1: 创建 SignalLayer — 信号检测与合并

**Files:**
- Create: `mobile/lib/analysis/signal_layer.dart`
- Create: `mobile/test/signal_layer_test.dart`

- [ ] **Step 1: 创建 SignalLayer 类**

创建 `mobile/lib/analysis/signal_layer.dart`，将 signal_engine.dart 中的 `detectSignals`、`_detectVolumePriceDivergence`、`_detectBollSqueezeBreakout` 和 generateAnalysis 中的信号合并逻辑提取出来：

```dart
import '../models/stock_models.dart';
import 'signal_detector.dart';

/// 信号层：负责技术信号的检测和合并
class SignalLayer {
  /// 检测并合并所有信号
  static List<SignalItem> detectAllSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 2) return [];

    // 1. 使用 SignalDetector 检测分层信号
    List<SignalItem> signals;
    try {
      signals = SignalDetector.detectLayeredSignals(data);
    } catch (_) {
      signals = [];
    }

    // 2. 添加特有信号（量价背离、布林收口）
    try {
      final uniqueSignals = detectUniqueSignals(data);
      final existingNames = signals.map((s) => s.signal).toSet();
      for (final s in uniqueSignals) {
        if (!existingNames.contains(s.signal)) {
          signals.add(s);
        }
      }
    } catch (_) {}

    return signals;
  }

  /// 检测 SignalDetector 未覆盖的特有信号
  static List<SignalItem> detectUniqueSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 2) return [];

    final signals = <SignalItem>[];
    signals.addAll(_detectVolumePriceDivergence(data));
    signals.addAll(_detectBollSqueezeBreakout(data));

    signals.sort((a, b) => b.strength.compareTo(a.strength));
    return signals;
  }

  /// 量价背离检测
  static List<SignalItem> _detectVolumePriceDivergence(List<HistoryKline> data) {
    final signals = <SignalItem>[];
    if (data.length < 15) return signals;

    final last = data[data.length - 1];
    final avg10Vol = data.sublist(data.length - 10).map((d) => d.volume).reduce((a, b) => a + b) / 10;
    final avg3Vol = data.sublist(data.length - 3).map((d) => d.volume).reduce((a, b) => a + b) / 3;

    if (avg3Vol > avg10Vol * 1.5) {
      final priceChange3d = (last.close / data[data.length - 4].close - 1) * 100;
      if (priceChange3d.abs() < 2) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: '量价',
          signal: '放量滞涨',
          description: '近3日均量是10日均量的${(avg3Vol / avg10Vol).toStringAsFixed(1)}倍，但涨幅仅${priceChange3d.toStringAsFixed(1)}%，主力可能在出货',
          strength: 75,
          timestamp: last.date,
        ));
      }
    }

    if (data.length >= 6) {
      final priceChange5d = (last.close / data[data.length - 6].close - 1) * 100;
      if (priceChange5d > 3) {
        var volDeclining = true;
        for (int i = data.length - 1; i > data.length - 5; i--) {
          if (data[i].volume >= data[i - 1].volume) {
            volDeclining = false;
            break;
          }
        }
        if (volDeclining) {
          signals.add(SignalItem(
            type: 'sell',
            indicator: '量价',
            signal: '缩量上涨',
            description: '近5日涨幅${priceChange5d.toStringAsFixed(1)}%但量能持续萎缩，上涨动力不足',
            strength: 70,
            timestamp: last.date,
          ));
        }
      }
    }

    if (data.length >= 13) {
      final priceChange10d = (last.close / data[data.length - 11].close - 1) * 100;
      if (priceChange10d < -10) {
        final recent3Change = (last.close / data[data.length - 4].close - 1) * 100;
        if (recent3Change.abs() < 1 && avg3Vol < avg10Vol * 0.5) {
          signals.add(SignalItem(
            type: 'buy',
            indicator: '量价',
            signal: '缩量止跌',
            description: '前期跌幅${priceChange10d.toStringAsFixed(1)}%后量能萎缩至均量的${(avg3Vol / avg10Vol * 100).toStringAsFixed(0)}%，价格企稳，抛压减弱',
            strength: 65,
            timestamp: last.date,
          ));
        }
      }
    }

    return signals;
  }

  /// 布林带收口突破检测
  static List<SignalItem> _detectBollSqueezeBreakout(List<HistoryKline> data) {
    final signals = <SignalItem>[];
    if (data.length < 25) return signals;

    final last = data[data.length - 1];
    if (last.bollMid == 0) return signals;

    final bandwidths = <double>[];
    for (int i = data.length - 20; i < data.length; i++) {
      final d = data[i];
      if (d.bollMid > 0) {
        bandwidths.add((d.bollUpper - d.bollLower) / d.bollMid * 100);
      }
    }
    if (bandwidths.length < 10) return signals;

    final currentBw = bandwidths.last;
    final minBw = bandwidths.reduce((a, b) => a < b ? a : b);

    var contracting = true;
    for (int i = bandwidths.length - 1; i > bandwidths.length - 6 && i > 0; i--) {
      if (bandwidths[i] >= bandwidths[i - 1]) {
        contracting = false;
        break;
      }
    }

    if (currentBw <= minBw * 1.1 && contracting) {
      signals.add(SignalItem(
        type: 'neutral',
        indicator: 'BOLL',
        signal: '布林带收口蓄势',
        description: '布林带宽度收窄至${currentBw.toStringAsFixed(1)}%，连续5日递减，即将选择方向突破但方向待确认',
        strength: 60,
        timestamp: last.date,
      ));

      final avgVol = data.sublist(data.length - 10).map((d) => d.volume).reduce((a, b) => a + b) / 10;
      if (last.close > last.bollUpper && last.volume > avgVol * 1.5) {
        signals.add(SignalItem(
          type: 'buy',
          indicator: 'BOLL',
          signal: '布林带放量突破上轨',
          description: '收口后放量突破布林带上轨(${last.bollUpper.toStringAsFixed(2)})，向上突破确认',
          strength: 80,
          timestamp: last.date,
        ));
      } else if (last.close < last.bollLower) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'BOLL',
          signal: '布林带跌破下轨',
          description: '收口后跌破布林带下轨(${last.bollLower.toStringAsFixed(2)})，向下突破',
          strength: 80,
          timestamp: last.date,
        ));
      }
    }

    return signals;
  }
}
```

- [ ] **Step 2: 创建 SignalLayer 测试**

创建 `mobile/test/signal_layer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_layer.dart';

List<HistoryKline> _pricesToKlines(List<double> prices) {
  return List.generate(prices.length, (i) {
    final price = prices[i];
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price * 0.99, high: price * 1.02, low: price * 0.98, close: price,
      volume: 10000.0 + (i % 5) * 2000, amount: 10000 * price,
    );
  });
}

List<HistoryKline> _baseData({int count = 40}) {
  final prices = List.generate(count, (i) => 15.0 + (i % 10) * 0.5);
  return calcAllIndicators(_pricesToKlines(prices));
}

void main() {
  group('SignalLayer', () {
    test('detectAllSignals returns empty for empty data', () {
      expect(SignalLayer.detectAllSignals([]), isEmpty);
    });

    test('detectAllSignals returns empty for insufficient data', () {
      final data = [HistoryKline(date: DateTime(2024, 1, 1), close: 10.0)];
      expect(SignalLayer.detectAllSignals(data), isEmpty);
    });

    test('detectAllSignals merges layered and unique signals without duplicates', () {
      final data = _baseData();
      final signals = SignalLayer.detectAllSignals(data);
      // Verify no duplicate signal names
      final names = signals.map((s) => s.signal).toList();
      expect(names.toSet().length, equals(names.length), reason: 'No duplicate signals');
    });

    test('detectUniqueSignals returns BOLL signals for squeeze pattern', () {
      var data = _baseData();
      final n = data.length;
      // Force BOLL squeeze conditions
      for (int i = n - 6; i < n; i++) {
        data[i] = data[i].copyWith(
          bollUpper: 16.0 - (n - i) * 0.1,
          bollMid: 15.0,
          bollLower: 14.0 + (n - i) * 0.1,
        );
      }
      final signals = SignalLayer.detectUniqueSignals(data);
      final bollSignals = signals.where((s) => s.indicator == 'BOLL').toList();
      expect(bollSignals, isNotEmpty, reason: 'Should detect BOLL squeeze signal');
    });

    test('detectUniqueSignals detects volume-price divergence', () {
      var data = _baseData();
      final n = data.length;
      // Force high volume with flat price (放量滞涨)
      for (int i = n - 3; i < n; i++) {
        data[i] = data[i].copyWith(volume: 50000.0);
      }
      for (int i = n - 10; i < n - 3; i++) {
        data[i] = data[i].copyWith(volume: 10000.0);
      }
      final signals = SignalLayer.detectUniqueSignals(data);
      final volSignals = signals.where((s) => s.signal == '放量滞涨').toList();
      expect(volSignals, isNotEmpty, reason: 'Should detect volume-price divergence');
    });
  });
}
```

- [ ] **Step 3: 运行测试验证**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/signal_layer_test.dart`
Expected: PASS

---

### Task 2: 创建 TechnicalScorer — 5维技术面评分

**Files:**
- Create: `mobile/lib/analysis/technical_scorer.dart`
- Create: `mobile/test/technical_scorer_test.dart`

- [ ] **Step 1: 创建 TechnicalScorer 类**

创建 `mobile/lib/analysis/technical_scorer.dart`，提取 generateAnalysis 中的5维技术面评分逻辑（信号评分、趋势评分、动量评分、量价评分、波动率评分）和 `_calculateWeightedSignalStrength` 辅助方法：

```dart
import '../models/stock_models.dart';

/// 技术面5维评分结果
class TechnicalScoreResult {
  final double signalScore;    // 0-3
  final double trendScore;     // 0-2
  final double momentumScore;  // 0-2
  final double volumeScore;    // 0-1.5
  final double volatilityScore;// 0-1.5
  final double totalScore;     // 0-10

  TechnicalScoreResult({
    required this.signalScore,
    required this.trendScore,
    required this.momentumScore,
    required this.volumeScore,
    required this.volatilityScore,
    required this.totalScore,
  });
}

/// 技术面评分器：5维评分（信号、趋势、动量、量价、波动率）
class TechnicalScorer {
  /// 计算技术面5维评分
  static TechnicalScoreResult score(
    List<HistoryKline> data,
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
  ) {
    final last = data[data.length - 1];

    final signalScore = _scoreSignal(buySignals, sellSignals, last.adx14);
    final trendScore = _scoreTrend(last);
    final momentumScore = _scoreMomentum(last);
    final volumeScore = _scoreVolume(data, last);
    final volatilityScore = _scoreVolatility(last);

    final totalScore = (signalScore + trendScore + momentumScore + volumeScore + volatilityScore).clamp(0.0, 10.0);

    return TechnicalScoreResult(
      signalScore: signalScore,
      trendScore: trendScore,
      momentumScore: momentumScore,
      volumeScore: volumeScore,
      volatilityScore: volatilityScore,
      totalScore: totalScore,
    );
  }

  /// 1. 信号评分 (0-3分)
  static double _scoreSignal(List<SignalItem> buySignals, List<SignalItem> sellSignals, double adx) {
    final weightedStrength = _calculateWeightedSignalStrength(buySignals, sellSignals, adx);
    final buyStrength = weightedStrength.$1;
    final sellStrength = weightedStrength.$2;
    final totalStrength = buyStrength + sellStrength;
    final maxTotal = totalStrength > 0 ? (totalStrength * 0.6).clamp(30.0, 150.0) : 150.0;
    double signalRaw = (buyStrength - sellStrength) / maxTotal * 3;
    signalRaw = signalRaw.clamp(-3.0, 3.0);
    return (signalRaw + 3.0) / 2.0;
  }

  /// 2. 趋势强度评分 (0-2分)
  static double _scoreTrend(HistoryKline last) {
    double trendScore = 0;
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20) {
        trendScore = 1.8;
      } else if (last.ma5 > last.ma10) {
        trendScore = 1.1;
      } else if (last.ma5 > last.ma20) {
        trendScore = 0.7;
      } else {
        trendScore = 0.3;
      }
    }
    if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
      if (last.ma5 < last.ma10 && last.ma10 < last.ma20) {
        trendScore = 0;
      }
    }
    if (last.adx14 > 25) {
      trendScore += 0.5;
    } else if (last.adx14 > 0 && last.adx14 < 20) {
      trendScore -= 0.3;
    }
    return trendScore.clamp(0.0, 2.0);
  }

  /// 3. 动量评分 (0-2分)
  static double _scoreMomentum(HistoryKline last) {
    double momentumScore = 1.0;
    if (last.rsi6 > 0) {
      final isTrending = last.adx14 > 25;
      final isRanging = last.adx14 > 0 && last.adx14 < 20;
      if (isTrending) {
        if (last.rsi6 >= 60) momentumScore = 1.8;
        else if (last.rsi6 >= 50) momentumScore = 1.3;
        else if (last.rsi6 >= 40) momentumScore = 0.8;
        else momentumScore = 0.3;
      } else if (isRanging) {
        if (last.rsi6 < 30) momentumScore = 1.6;
        else if (last.rsi6 < 40) momentumScore = 1.3;
        else if (last.rsi6 <= 60) momentumScore = 1.0;
        else if (last.rsi6 <= 70) momentumScore = 0.7;
        else momentumScore = 0.3;
      } else {
        if (last.rsi6 < 30) momentumScore = 1.4;
        else if (last.rsi6 < 40) momentumScore = 1.2;
        else if (last.rsi6 < 60) momentumScore = 1.0;
        else if (last.rsi6 < 70) momentumScore = 0.8;
        else momentumScore = 0.5;
      }
    }
    if (last.bias6.abs() > 5) momentumScore -= 0.4;
    else if (last.bias6.abs() > 3) momentumScore -= 0.2;
    return momentumScore.clamp(0.0, 2.0);
  }

  /// 4. 量价确认评分 (0-1.5分)
  static double _scoreVolume(List<HistoryKline> data, HistoryKline last) {
    double volumeScore = 0.8;
    if (last.volMa5 > 0) {
      final volRatio = last.volume / last.volMa5;
      if (last.close >= last.open) {
        if (volRatio > 1.5) volumeScore = 1.4;
        else if (volRatio > 1.0) volumeScore = 1.1;
        else volumeScore = 0.6;
      } else {
        if (volRatio > 1.5) volumeScore = 0.2;
        else if (volRatio > 1.0) volumeScore = 0.5;
        else volumeScore = 0.8;
      }
    }
    if (data.length >= 5 && last.obv != 0) {
      final obv5 = data[data.length - 5].obv;
      if (obv5 != 0) {
        if (last.obv > obv5 && last.close > data[data.length - 5].close) volumeScore += 0.3;
        else if (last.obv < obv5 && last.close < data[data.length - 5].close) volumeScore -= 0.2;
      }
    }
    return volumeScore.clamp(0.0, 1.5);
  }

  /// 5. 波动率评分 (0-1.5分)
  static double _scoreVolatility(HistoryKline last) {
    double volatilityScore = 0.8;
    if (last.atr14 > 0 && last.close > 0) {
      final atrPct = last.atr14 / last.close * 100;
      if (atrPct < 1) volatilityScore = 0.3;
      else if (atrPct < 2) volatilityScore = 0.7;
      else if (atrPct < 3) volatilityScore = 1.1;
      else if (atrPct < 5) volatilityScore = 1.3;
      else if (atrPct < 8) volatilityScore = 0.8;
      else volatilityScore = 0.3;
    }
    return volatilityScore;
  }

  /// ADX趋势/盘整权重调整
  static (double, double) _calculateWeightedSignalStrength(
    List<SignalItem> buySignals,
    List<SignalItem> sellSignals,
    double adx,
  ) {
    double buyStrength = 0;
    double sellStrength = 0;
    for (final s in buySignals) {
      double strength = s.strength.toDouble();
      if (adx > 25) {
        if (s.indicator == 'MA' || s.indicator == 'MACD' || s.signal.contains('排列') || s.signal.contains('金叉') || s.signal.contains('死叉')) {
          strength *= 1.2;
        }
      } else if (adx > 0 && adx < 20) {
        if (s.indicator == 'RSI' || s.indicator == 'KDJ' || s.signal.contains('超买') || s.signal.contains('超卖')) {
          strength *= 1.2;
        }
      }
      buyStrength += strength;
    }
    for (final s in sellSignals) {
      double strength = s.strength.toDouble();
      if (adx > 25) {
        if (s.indicator == 'MA' || s.indicator == 'MACD' || s.signal.contains('排列') || s.signal.contains('金叉') || s.signal.contains('死叉')) {
          strength *= 1.2;
        }
      } else if (adx > 0 && adx < 20) {
        if (s.indicator == 'RSI' || s.indicator == 'KDJ' || s.signal.contains('超买') || s.signal.contains('超卖')) {
          strength *= 1.2;
        }
      }
      sellStrength += strength;
    }
    return (buyStrength, sellStrength);
  }
}
```

- [ ] **Step 2: 创建 TechnicalScorer 测试**

创建 `mobile/test/technical_scorer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/technical_scorer.dart';

List<HistoryKline> _uptrendData({int count = 60}) {
  double price = 10.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 1.02;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: price * 1.01, low: open * 0.99, close: price,
      volume: 10000.0 + (i % 5) * 2000, amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

List<HistoryKline> _downtrendData({int count = 60}) {
  double price = 30.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 0.98;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: open * 1.01, low: price * 0.99, close: price,
      volume: 10000.0 + (i % 5) * 2000, amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('TechnicalScorer', () {
    test('Uptrend produces higher total score than downtrend', () {
      final upData = _uptrendData();
      final downData = _downtrendData();
      final upResult = TechnicalScorer.score(upData, [], []);
      final downResult = TechnicalScorer.score(downData, [], []);
      expect(upResult.totalScore, greaterThan(downResult.totalScore));
    });

    test('All sub-scores are within valid ranges', () {
      final data = _uptrendData();
      final result = TechnicalScorer.score(data, [], []);
      expect(result.signalScore, inInclusiveRange(0.0, 3.0));
      expect(result.trendScore, inInclusiveRange(0.0, 2.0));
      expect(result.momentumScore, inInclusiveRange(0.0, 2.0));
      expect(result.volumeScore, inInclusiveRange(0.0, 1.5));
      expect(result.volatilityScore, inInclusiveRange(0.0, 1.5));
      expect(result.totalScore, inInclusiveRange(0.0, 10.0));
    });

    test('Trend score is higher for MA bullish alignment', () {
      var data = _uptrendData(count: 80);
      final n = data.length;
      // Force MA bullish alignment
      data[n - 1] = data[n - 1].copyWith(ma5: 20.0, ma10: 18.0, ma20: 16.0, adx14: 30.0);
      final result = TechnicalScorer.score(data, [], []);
      expect(result.trendScore, greaterThanOrEqualTo(1.8));
    });

    test('Momentum score penalizes extreme BIAS', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(bias6: 8.0);
      final result = TechnicalScorer.score(data, [], []);
      // With extreme BIAS, momentum should be reduced
      expect(result.momentumScore, lessThan(2.0));
    });

    test('Buy signals increase signal score', () {
      final data = _uptrendData();
      final buySignals = [SignalItem(type: 'buy', indicator: 'MA', signal: '金叉', strength: 85)];
      final resultNoSignals = TechnicalScorer.score(data, [], []);
      final resultWithSignals = TechnicalScorer.score(data, buySignals, []);
      expect(resultWithSignals.signalScore, greaterThan(resultNoSignals.signalScore));
    });
  });
}
```

- [ ] **Step 3: 运行测试验证**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/technical_scorer_test.dart`
Expected: PASS

---

### Task 3: 创建 RealtimeScorer — 实时行情评分

**Files:**
- Create: `mobile/lib/analysis/realtime_scorer.dart`
- Create: `mobile/test/realtime_scorer_test.dart`

- [ ] **Step 1: 创建 RealtimeScorer 类**

创建 `mobile/lib/analysis/realtime_scorer.dart`，提取 generateAnalysis 中的实时行情评分逻辑：

```dart
import '../models/stock_models.dart';

/// 实时行情评分器
class RealtimeScorer {
  /// 计算实时行情评分 (0-10)
  static double score(QuoteData? quote) {
    double realtimeScore = 5.0;
    if (quote == null || quote.price <= 0) return realtimeScore.clamp(0.0, 10.0);

    final changePct = quote.changePct;
    if (changePct > 8) realtimeScore += 2.5;
    else if (changePct > 5) realtimeScore += 2.0;
    else if (changePct > 2) realtimeScore += 2.0;
    else if (changePct > 0) realtimeScore += 1.0;
    else if (changePct >= -2) realtimeScore -= 0.5;
    else if (changePct >= -5) realtimeScore -= 1.5;
    else if (changePct >= -8) realtimeScore -= 2.0;
    else realtimeScore -= 2.5;

    if (quote.mainNetFlow != 0) {
      final rate = quote.mainNetFlowRate;
      if (rate > 10) realtimeScore += 1.5;
      else if (rate > 5) realtimeScore += 1.0;
      else if (rate > 0) realtimeScore += 0.5;
      else if (rate > -5) realtimeScore -= 0.5;
      else if (rate > -10) realtimeScore -= 1.0;
      else realtimeScore -= 1.5;
    }

    if (quote.turnover > 0) {
      if (quote.turnover >= 1 && quote.turnover <= 5) realtimeScore += 0.5;
      else if (quote.turnover > 10) realtimeScore -= 0.5;
      else if (quote.turnover < 0.5) realtimeScore -= 0.3;
    }

    return realtimeScore.clamp(0.0, 10.0);
  }
}
```

- [ ] **Step 2: 创建 RealtimeScorer 测试**

创建 `mobile/test/realtime_scorer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/realtime_scorer.dart';

void main() {
  group('RealtimeScorer', () {
    test('Null quote returns neutral score', () {
      expect(RealtimeScorer.score(null), equals(5.0));
    });

    test('Strong rise gets high score', () {
      final quote = QuoteData(code: 'sh600000', name: '测试', price: 15.0, changePct: 6.0);
      final score = RealtimeScorer.score(quote);
      expect(score, greaterThan(5.0));
    });

    test('Strong fall gets low score', () {
      final quote = QuoteData(code: 'sh600000', name: '测试', price: 15.0, changePct: -6.0);
      final score = RealtimeScorer.score(quote);
      expect(score, lessThan(5.0));
    });

    test('Positive fund flow increases score', () {
      final quoteNoFlow = QuoteData(code: 'sh600000', name: '测试', price: 15.0, changePct: 0);
      final quoteWithFlow = QuoteData(code: 'sh600000', name: '测试', price: 15.0, changePct: 0, mainNetFlow: 1000000, mainNetFlowRate: 8.0);
      expect(RealtimeScorer.score(quoteWithFlow), greaterThan(RealtimeScorer.score(quoteNoFlow)));
    });

    test('Score is always within 0-10 range', () {
      final extremeUp = QuoteData(code: 'sh600000', name: '测试', price: 15.0, changePct: 20.0, mainNetFlowRate: 20.0, turnover: 3.0);
      final extremeDown = QuoteData(code: 'sh600000', name: '测试', price: 15.0, changePct: -20.0, mainNetFlowRate: -20.0);
      expect(RealtimeScorer.score(extremeUp), inInclusiveRange(0.0, 10.0));
      expect(RealtimeScorer.score(extremeDown), inInclusiveRange(0.0, 10.0));
    });
  });
}
```

- [ ] **Step 3: 运行测试验证**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/realtime_scorer_test.dart`
Expected: PASS

---

### Task 4: 创建 ConfluenceScorer — 跨指标共振评分

**Files:**
- Create: `mobile/lib/analysis/confluence_scorer.dart`
- Create: `mobile/test/confluence_scorer_test.dart`

- [ ] **Step 1: 创建 ConfluenceScorer 类**

创建 `mobile/lib/analysis/confluence_scorer.dart`，提取 generateAnalysis 中的10维共振评分逻辑：

```dart
import '../models/stock_models.dart';

/// 共振评分结果
class ConfluenceResult {
  final double score;                          // 0-10
  final int bullCount;                         // 偏多指标数
  final int bearCount;                         // 偏空指标数
  final List<Map<String, dynamic>> details;    // 10维度详情

  ConfluenceResult({
    required this.score,
    required this.bullCount,
    required this.bearCount,
    required this.details,
  });
}

/// 跨指标共振评分器：10维度指标多空分析
class ConfluenceScorer {
  /// 计算共振评分
  static ConfluenceResult score(HistoryKline last, List<SignalItem> signals) {
    final maBull = last.ma5 > last.ma10 && last.ma10 > last.ma20;
    final maBear = last.ma5 < last.ma10 && last.ma10 < last.ma20;
    final macdBull = last.macdDif > last.macdDea && last.macdHist > 0;
    final macdBear = last.macdDif < last.macdDea && last.macdHist < 0;
    final rsiBull = last.rsi6 > 60;
    final rsiBear = last.rsi6 < 40 && last.rsi6 > 0;
    final kdjBull = last.k > last.d && last.k < 80;
    final kdjBear = last.k < last.d && last.k > 20;
    final bollBull = last.bollMid > 0 && last.close > last.bollMid;
    final bollBear = last.bollMid > 0 && last.close < last.bollMid;
    final volBull = last.volMa5 > 0 && last.volume > last.volMa5 && last.close > last.open;
    final volBear = last.volMa5 > 0 && last.volume > last.volMa5 && last.close < last.open;
    final wrBull = last.wr14 != null && last.wr14! > 80;
    final wrBear = last.wr14 != null && last.wr14! < 20;
    final cciBull = last.cci14 != null && last.cci14! > 100;
    final cciBear = last.cci14 != null && last.cci14! < -100;
    final hasGapUp = signals.any((s) => s.signal.contains('向上跳空'));
    final hasGapDown = signals.any((s) => s.signal.contains('向下跳空'));
    final hasBottomDivergence = signals.any((s) => s.signal.contains('底背离'));
    final hasTopDivergence = signals.any((s) => s.signal.contains('顶背离'));

    final bullIndicators = <String>[];
    final bearIndicators = <String>[];
    if (maBull) bullIndicators.add('MA');
    if (maBear) bearIndicators.add('MA');
    if (macdBull) bullIndicators.add('MACD');
    if (macdBear) bearIndicators.add('MACD');
    if (rsiBull) bullIndicators.add('RSI');
    if (rsiBear) bearIndicators.add('RSI');
    if (kdjBull) bullIndicators.add('KDJ');
    if (kdjBear) bearIndicators.add('KDJ');
    if (bollBull) bullIndicators.add('BOLL');
    if (bollBear) bearIndicators.add('BOLL');
    if (volBull) bullIndicators.add('VOL');
    if (volBear) bearIndicators.add('VOL');
    if (wrBull) bullIndicators.add('WR');
    if (wrBear) bearIndicators.add('WR');
    if (cciBull) bullIndicators.add('CCI');
    if (cciBear) bearIndicators.add('CCI');
    if (hasGapUp) bullIndicators.add('GAP');
    if (hasGapDown) bearIndicators.add('GAP');
    if (hasBottomDivergence) { bullIndicators.add('DIVER_1'); bullIndicators.add('DIVER_2'); }
    if (hasTopDivergence) { bearIndicators.add('DIVER_1'); bearIndicators.add('DIVER_2'); }

    final bullDistinct = bullIndicators.toSet().length;
    final bearDistinct = bearIndicators.toSet().length;
    final bullConfluence = (bullDistinct * 0.8).clamp(0.0, 4.0);
    final bearConfluence = (bearDistinct * 0.8).clamp(0.0, 4.0);
    final confluenceScore = (5.0 + bullConfluence - bearConfluence).clamp(0.0, 10.0);

    final confluenceDetails = <Map<String, dynamic>>[];
    confluenceDetails.add({'name': 'MA', 'bull': maBull, 'bear': maBear});
    confluenceDetails.add({'name': 'MACD', 'bull': macdBull, 'bear': macdBear});
    confluenceDetails.add({'name': 'RSI', 'bull': rsiBull, 'bear': rsiBear});
    confluenceDetails.add({'name': 'KDJ', 'bull': kdjBull, 'bear': kdjBear});
    confluenceDetails.add({'name': 'BOLL', 'bull': bollBull, 'bear': bollBear});
    confluenceDetails.add({'name': '量价', 'bull': volBull, 'bear': volBear});
    confluenceDetails.add({'name': 'WR', 'bull': wrBull, 'bear': wrBear});
    confluenceDetails.add({'name': 'CCI', 'bull': cciBull, 'bear': cciBear});
    confluenceDetails.add({'name': '缺口', 'bull': hasGapUp, 'bear': hasGapDown});
    confluenceDetails.add({'name': '背离', 'bull': hasBottomDivergence, 'bear': hasTopDivergence, 'weighted': true});

    return ConfluenceResult(
      score: confluenceScore,
      bullCount: bullDistinct,
      bearCount: bearDistinct,
      details: confluenceDetails,
    );
  }
}
```

- [ ] **Step 2: 创建 ConfluenceScorer 测试**

创建 `mobile/test/confluence_scorer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/confluence_scorer.dart';

void main() {
  group('ConfluenceScorer', () {
    test('Returns valid score range', () {
      final kline = HistoryKline(date: DateTime(2024, 1, 1), close: 15.0, ma5: 16.0, ma10: 15.0, ma20: 14.0);
      final result = ConfluenceScorer.score(kline, []);
      expect(result.score, inInclusiveRange(0.0, 10.0));
    });

    test('Bullish alignment produces higher score', () {
      final bullish = HistoryKline(
        date: DateTime(2024, 1, 1), close: 15.0,
        ma5: 16.0, ma10: 15.0, ma20: 14.0,
        macdDif: 0.5, macdDea: 0.3, macdHist: 0.2,
        rsi6: 65.0, k: 60.0, d: 40.0,
        bollMid: 14.0, volume: 15000.0, volMa5: 10000.0, open: 14.5,
      );
      final bearish = HistoryKline(
        date: DateTime(2024, 1, 1), close: 15.0,
        ma5: 14.0, ma10: 15.0, ma20: 16.0,
        macdDif: -0.5, macdDea: -0.3, macdHist: -0.2,
        rsi6: 30.0, k: 30.0, d: 50.0,
        bollMid: 16.0, volume: 15000.0, volMa5: 10000.0, open: 15.5,
      );
      final bullResult = ConfluenceScorer.score(bullish, []);
      final bearResult = ConfluenceScorer.score(bearish, []);
      expect(bullResult.score, greaterThan(bearResult.score));
    });

    test('Details contain 10 dimensions', () {
      final kline = HistoryKline(date: DateTime(2024, 1, 1), close: 15.0);
      final result = ConfluenceScorer.score(kline, []);
      expect(result.details.length, equals(10));
    });
  });
}
```

- [ ] **Step 3: 运行测试验证**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/confluence_scorer_test.dart`
Expected: PASS

---

### Task 5: 创建 ComprehensiveScorer — 综合评分

**Files:**
- Create: `mobile/lib/analysis/comprehensive_scorer.dart`

- [ ] **Step 1: 创建 ComprehensiveScorer 类**

创建 `mobile/lib/analysis/comprehensive_scorer.dart`，提取 generateAnalysis 中的动态权重分配和综合评分逻辑：

```dart
import '../models/stock_models.dart';
import 'fundamental_analyzer.dart';
import 'news_sentiment_analyzer.dart';

/// 综合评分结果
class ComprehensiveScoreResult {
  final int totalScore;           // 1-10
  final String recommendation;    // 推荐等级
  final FundamentalScore? fundamentalScore;
  final NewsSentiment? newsSentiment;

  ComprehensiveScoreResult({
    required this.totalScore,
    required this.recommendation,
    this.fundamentalScore,
    this.newsSentiment,
  });
}

/// 综合评分器：动态权重分配 + 市场调节 + 推荐等级映射
class ComprehensiveScorer {
  /// 计算综合评分
  static ComprehensiveScoreResult combine({
    required double technicalScore,
    required double realtimeScore,
    required double confluenceScore,
    required QuoteData? quote,
    required MarketContext? marketContext,
    required List<dynamic>? newsList,
  }) {
    // 基本面评分
    FundamentalScore? fundamentalScore;
    double fundamentalScoreValue = 5.0;
    if (quote != null && quote.price > 0) {
      fundamentalScore = FundamentalAnalyzer.analyze(quote);
      fundamentalScoreValue = fundamentalScore.totalScore;
    }

    // 新闻情绪评分
    NewsSentiment? newsSentiment;
    double sentimentScoreValue = 5.0;
    if (newsList != null && newsList.isNotEmpty) {
      newsSentiment = NewsSentimentAnalyzer.analyze(newsList);
      sentimentScoreValue = (newsSentiment.score + 10) / 2;
    }

    // 动态权重分配
    double techW = 0.38, fundW = 0.10, sentW = 0.12, realW = 0.22, confW = 0.18;
    final hasFund = fundamentalScore != null;
    final hasSent = newsSentiment != null;
    if (!hasFund && !hasSent) {
      techW = 0.45; realW = 0.30; confW = 0.25; fundW = 0; sentW = 0;
    } else if (!hasFund) {
      techW = 0.42; realW = 0.25; confW = 0.20; sentW = 0.13; fundW = 0;
    } else if (!hasSent) {
      techW = 0.42; realW = 0.25; confW = 0.20; fundW = 0.13; sentW = 0;
    }

    final rawScore = (technicalScore * techW +
        fundamentalScoreValue * fundW +
        sentimentScoreValue * sentW +
        realtimeScore * realW +
        confluenceScore * confW).clamp(0.0, 10.0);

    // 市场环境调节
    double marketAdjustment = 1.0;
    if (marketContext != null) {
      marketAdjustment = marketContext.getMarketAdjustmentFactor();
    }
    final adjustedScore = (rawScore * marketAdjustment).clamp(0.0, 10.0);

    // 映射到10级整分
    final totalScore = (adjustedScore / 10.0 * 9 + 1).round().clamp(1, 10);

    // 推荐等级
    final recommendation = _determineRecommendation(totalScore);

    return ComprehensiveScoreResult(
      totalScore: totalScore,
      recommendation: recommendation,
      fundamentalScore: fundamentalScore,
      newsSentiment: newsSentiment,
    );
  }

  static String _determineRecommendation(int totalScore) {
    if (totalScore >= 9) return '强烈买入';
    if (totalScore >= 8) return '买入';
    if (totalScore >= 7) return '谨慎买入';
    if (totalScore >= 6) return '偏多观望';
    if (totalScore >= 5) return '偏空观望';
    if (totalScore >= 4) return '谨慎卖出';
    if (totalScore >= 3) return '卖出';
    return '强烈卖出';
  }
}
```

- [ ] **Step 2: 运行已有测试验证无回归**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/scoring_logic_test.dart`
Expected: PASS (此步骤仅创建文件，尚未修改 signal_engine.dart)

---

### Task 6: 创建 RiskAnalyzer — 风险因子收集

**Files:**
- Create: `mobile/lib/analysis/risk_analyzer.dart`
- Create: `mobile/test/risk_analyzer_test.dart`

- [ ] **Step 1: 创建 RiskAnalyzer 类**

创建 `mobile/lib/analysis/risk_analyzer.dart`，提取 `_collectRiskFactors` 和风险等级判定逻辑：

```dart
import '../models/stock_models.dart';

/// 风险分析结果
class RiskAnalysisResult {
  final List<String> riskFactors;
  final String riskLevel;

  RiskAnalysisResult({required this.riskFactors, required this.riskLevel});
}

/// 风险分析器：收集风险因子并判定风险等级
class RiskAnalyzer {
  /// 分析风险因子并判定风险等级
  static RiskAnalysisResult analyze(List<HistoryKline> data, HistoryKline last, QuoteData? quote) {
    final riskFactors = _collectRiskFactors(data, last, quote);
    final riskLevel = _determineLevel(riskFactors);
    return RiskAnalysisResult(riskFactors: riskFactors, riskLevel: riskLevel);
  }

  static List<String> _collectRiskFactors(List<HistoryKline> data, HistoryKline last, QuoteData? quote) {
    final riskFactors = <String>[];

    if (last.rsi6 > 70) riskFactors.add('RSI超买(${last.rsi6.toStringAsFixed(1)})，回调风险');
    if (last.rsi6 < 30 && last.rsi6 > 0) riskFactors.add('RSI超卖(${last.rsi6.toStringAsFixed(1)})，可能继续探底');
    if (last.close > last.bollUpper && last.bollUpper > 0) riskFactors.add('价格突破布林上轨，短期过热');
    if (last.close < last.bollLower && last.bollLower > 0) riskFactors.add('价格跌破布林下轨，波动加剧');
    if (last.close < last.ma20 && last.ma20 > 0) riskFactors.add('价格低于20日均线，趋势偏弱');

    if (last.close < last.open && last.volume > last.volMa5 * 1.5 && last.volMa5 > 0) {
      riskFactors.add('放量下跌，抛压较大');
    }
    if (last.close >= last.open && last.volume < last.volMa5 * 0.7 && last.volMa5 > 0) {
      riskFactors.add('上涨缩量，量价背离');
    }

    if (last.ma5 > 0 && last.ma10 > 0 && last.ma5 < last.ma10 && data.length >= 2) {
      final prev = data[data.length - 2];
      if (prev.ma5 >= prev.ma10) {
        riskFactors.add('MA5下穿MA10死叉，短期趋势转弱');
      }
    }

    if (last.amplitude > 5) {
      riskFactors.add('当日振幅较大(${last.amplitude.toStringAsFixed(1)}%)，短期波动剧烈');
    }

    if (data.length >= 6) {
      final close5ago = data[data.length - 6].close;
      if (close5ago > 0) {
        final change5d = (last.close / close5ago - 1) * 100;
        if (change5d.abs() > 15) {
          riskFactors.add('近5日涨跌幅${change5d.toStringAsFixed(1)}%，短期波动剧烈');
        }
      }
    }
    if (data.length >= 21) {
      final close20ago = data[data.length - 21].close;
      if (close20ago > 0) {
        final change20d = (last.close / close20ago - 1) * 100;
        if (change20d > 30) {
          riskFactors.add('近20日涨幅${change20d.toStringAsFixed(1)}%，回调风险增加');
        } else if (change20d < -30) {
          riskFactors.add('近20日跌幅${change20d.toStringAsFixed(1)}%，跌幅较大');
        }
      }
    }

    if (last.j > 100) riskFactors.add('KDJ超买风险(J=${last.j.toStringAsFixed(1)})');
    if (last.j < 0) riskFactors.add('KDJ超卖风险(J=${last.j.toStringAsFixed(1)})');

    if (quote != null) {
      if (quote.pe > 60) riskFactors.add('市盈率偏高(${quote.pe.toStringAsFixed(1)})，估值风险');
      if (quote.turnover > 15) {
        riskFactors.add('换手率${quote.turnover.toStringAsFixed(1)}%，投机氛围浓厚');
      } else if (quote.turnover < 1 && quote.turnover > 0) {
        riskFactors.add('换手率仅${quote.turnover.toStringAsFixed(1)}%，流动性不足');
      }
      if (quote.changePct > 5) {
        riskFactors.add('当日涨幅${quote.changePct.toStringAsFixed(2)}%，追高需谨慎');
      } else if (quote.changePct < -5) {
        riskFactors.add('当日跌幅${quote.changePct.toStringAsFixed(2)}%，跌幅较大');
      }
    }

    if (last.atr14 > 0 && last.close > 0) {
      final atrPct = last.atr14 / last.close * 100;
      if (atrPct > 5) {
        riskFactors.add('ATR波动率${atrPct.toStringAsFixed(1)}%，短期波动剧烈');
      }
    }

    if (last.bias6 > 5) {
      riskFactors.add('BIAS6乖离率${last.bias6.toStringAsFixed(1)}%，偏离均线过大，回归风险');
    } else if (last.bias6 < -5) {
      riskFactors.add('BIAS6乖离率${last.bias6.toStringAsFixed(1)}%，严重偏离均线，关注反弹');
    }

    if (data.length >= 5 && last.obv != 0) {
      final obv5 = data[data.length - 5].obv;
      if (obv5 != 0 && last.close > data[data.length - 5].close && last.obv < obv5) {
        riskFactors.add('OBV量价背离：价格上涨但量能趋势下降，上涨持续性存疑');
      }
    }

    return riskFactors;
  }

  static String _determineLevel(List<String> riskFactors) {
    if (riskFactors.length >= 3 || riskFactors.any((f) => f.contains('超买') || f.contains('过热'))) {
      return '高';
    } else if (riskFactors.isNotEmpty) {
      return '中等';
    } else {
      return '低';
    }
  }
}
```

- [ ] **Step 2: 创建 RiskAnalyzer 测试**

创建 `mobile/test/risk_analyzer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/risk_analyzer.dart';

List<HistoryKline> _uptrendData({int count = 60}) {
  double price = 10.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 1.02;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: price * 1.01, low: open * 0.99, close: price,
      volume: 10000.0 + (i % 5) * 2000, amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('RiskAnalyzer', () {
    test('Detects RSI overbought risk', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(rsi6: 75.0);
      final result = RiskAnalyzer.analyze(data, data.last, null);
      expect(result.riskFactors.any((f) => f.contains('RSI超买')), true);
    });

    test('Detects ATR volatility risk', () {
      var data = _uptrendData();
      final n = data.length;
      final last = data[n - 1];
      data[n - 1] = data[n - 1].copyWith(atr14: last.close * 0.06);
      final result = RiskAnalyzer.analyze(data, data.last, null);
      expect(result.riskFactors.any((f) => f.contains('ATR波动率')), true);
    });

    test('Detects BIAS extreme risk', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(bias6: 7.0);
      final result = RiskAnalyzer.analyze(data, data.last, null);
      expect(result.riskFactors.any((f) => f.contains('BIAS6')), true);
    });

    test('High risk level with 3+ factors', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(rsi6: 75.0, bias6: 7.0);
      final quote = QuoteData(code: 'sh600000', name: '测试', price: 15.0, pe: 80.0);
      final result = RiskAnalyzer.analyze(data, data.last, quote);
      expect(result.riskLevel, equals('高'));
    });

    test('Low risk level with no factors', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(rsi6: 50.0, bias6: 1.0, atr14: data.last.close * 0.02);
      final result = RiskAnalyzer.analyze(data, data.last, null);
      // May still have some factors, but risk should be manageable
      expect(result.riskLevel, anyOf(equals('低'), equals('中等')));
    });
  });
}
```

- [ ] **Step 3: 运行测试验证**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/risk_analyzer_test.dart`
Expected: PASS

---

### Task 7: 创建 OpportunityIdentifier + SuggestionGenerator + ConfidenceCalculator

**Files:**
- Create: `mobile/lib/analysis/opportunity_identifier.dart`
- Create: `mobile/lib/analysis/suggestion_generator.dart`
- Create: `mobile/lib/analysis/confidence_calculator.dart`
- Create: `mobile/test/confidence_calculator_test.dart`

- [ ] **Step 1: 创建 OpportunityIdentifier**

创建 `mobile/lib/analysis/opportunity_identifier.dart`：

```dart
import '../models/stock_models.dart';

/// 机会识别器：从买入信号中提取交易机会
class OpportunityIdentifier {
  /// 识别交易机会
  static List<Map<String, String>> identify(List<SignalItem> buySignals) {
    final opportunities = <Map<String, String>>[];
    for (final signal in buySignals.take(3)) {
      String risk = '中等';
      if (signal.signal.contains('RSI') || signal.signal.contains('超卖')) risk = '中高';
      if (signal.signal.contains('金叉')) risk = '中等';
      if (signal.signal.contains('放量')) risk = '中低';
      if (signal.signal.contains('底背离')) risk = '中等';
      if (signal.signal.contains('跌破下轨')) risk = '中高';
      opportunities.add({
        'name': signal.signal,
        'description': signal.description,
        'risk': risk,
      });
    }
    return opportunities;
  }
}
```

- [ ] **Step 2: 创建 SuggestionGenerator**

创建 `mobile/lib/analysis/suggestion_generator.dart`，提取 `_generateSuggestions` 逻辑：

```dart
import '../models/stock_models.dart';
import 'position_manager.dart';

/// 操作建议生成器
class SuggestionGenerator {
  /// 生成操作建议
  static List<String> generate({
    required String recommendation,
    required List<HistoryKline> data,
    required HistoryKline last,
    required QuoteData? quote,
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    required int totalScore,
  }) {
    final suggestions = <String>[];
    double recentLow = last.low;
    if (data.length >= 10) {
      final recent10 = data.sublist(data.length - 10);
      recentLow = recent10.map((k) => k.low).reduce((a, b) => a < b ? a : b);
    }
    final stopLossRef = last.ma20 > 0 ? last.ma20 : recentLow;

    if (recommendation == '强烈买入') {
      suggestions.add('多项技术指标强烈共振偏多，但需结合基本面和大盘环境综合判断');
      suggestions.add('可考虑分批建仓，首批仓位控制在30%以内，确认趋势后逐步加仓');
      suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
    } else if (recommendation == '买入') {
      if (buySignals.length >= 3 && totalScore >= 8) {
        suggestions.add('多项技术指标共振偏多，但需结合基本面和大盘环境综合判断');
        suggestions.add('可考虑分批建仓，首批仓位控制在20%以内，确认趋势后逐步加仓');
      } else {
        suggestions.add('技术面偏多，可轻仓关注，但不宜追高');
        suggestions.add('建议先试探性建仓10%，确认支撑有效后再考虑加仓');
      }
      suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
      if (quote != null && quote.pe > 0 && quote.pe < 15) {
        suggestions.add('动态市盈率${quote.pe.toStringAsFixed(1)}倍，估值较低，具有一定安全边际');
      }
    } else if (recommendation == '谨慎买入') {
      suggestions.add('技术面偏多但不确定性较大，建议谨慎操作');
      suggestions.add('可试探性轻仓买入，仓位控制在10%以内，确认趋势后再加仓');
      suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
    } else if (recommendation == '偏多观望') {
      suggestions.add('技术面略偏多，但信号不够强烈，建议轻仓观察');
      suggestions.add('关注关键阻力位突破情况，突破后可考虑加仓');
      if (quote != null && quote.pe > 50) {
        suggestions.add('当前估值偏高（PE=${quote.pe.toStringAsFixed(1)}），注意仓位控制');
      }
    } else if (recommendation == '偏空观望') {
      suggestions.add('技术面略偏空，建议谨慎观望，控制仓位');
      suggestions.add('等待企稳信号出现后再考虑入场');
      if (quote != null && quote.pe > 50) {
        suggestions.add('当前估值偏高（PE=${quote.pe.toStringAsFixed(1)}），注意仓位控制');
      }
    } else if (recommendation == '谨慎卖出') {
      suggestions.add('技术面偏空但尚不极端，建议适当减仓，降低风险敞口');
      suggestions.add('关注支撑位${recentLow.toStringAsFixed(2)}的防守情况，跌破则加速减仓');
    } else if (recommendation == '卖出') {
      suggestions.add('技术面偏弱，建议适当减仓，降低风险敞口');
      suggestions.add('关注支撑位${recentLow.toStringAsFixed(2)}的防守情况，跌破则加速减仓');
      if (quote != null && quote.pe > 0 && quote.pb > 0 && quote.pb < 1) {
        suggestions.add('市净率${quote.pb.toStringAsFixed(2)}倍破净，可能存在安全边际，不宜恐慌性抛售');
      }
    } else {
      suggestions.add('技术面偏空信号较强，建议及时止损或止盈，规避风险');
      if (sellSignals.length >= 3) {
        suggestions.add('多项指标共振偏空，建议大幅减仓观望');
      } else {
        suggestions.add('建议分批减仓，避免一次性清仓');
      }
      suggestions.add('等待调整结束（如RSI回到50附近、MACD金叉）后再考虑入场');
    }

    if (quote != null) {
      if (quote.pe > 0 && quote.pe < 15 && quote.pb > 0 && quote.pb < 1.5) {
        suggestions.add('基本面估值较低（PE=${quote.pe.toStringAsFixed(1)}, PB=${quote.pb.toStringAsFixed(2)}），具有中长期投资价值');
      }
    }

    suggestions.add('以上分析基于历史数据和技术指标，仅供参考，不构成投资建议，投资有风险，决策需谨慎');

    // 仓位建议
    try {
      final positionManager = PositionManager.calculatePosition(last);
      suggestions.add(PositionManager.getPositionAdvice(positionManager));
    } catch (_) {}

    return suggestions;
  }
}
```

- [ ] **Step 3: 创建 ConfidenceCalculator**

创建 `mobile/lib/analysis/confidence_calculator.dart`，提取置信度计算和对抗验证调整逻辑：

```dart
import '../models/stock_models.dart';
import 'signal_validator.dart';

/// 置信度计算器：5维置信度 + 对抗验证调整
class ConfidenceCalculator {
  /// 计算综合置信度
  static double calculate({
    required List<SignalItem> signals,
    required int totalScore,
    required FundamentalScore? fundamentalScore,
    required NewsSentiment? newsSentiment,
    required MarketContext? marketContext,
    required QuoteData? quote,
    required HistoryKline last,
  }) {
    final buySignals = signals.where((s) => s.type == 'buy').toList();
    final sellSignals = signals.where((s) => s.type == 'sell').toList();
    final buyCount = buySignals.length;
    final sellCount = sellSignals.length;
    final signalCount = buyCount + sellCount;

    // 1. 信号一致性(30%)
    double signalConsistency = 0.5;
    if (signalCount > 0) {
      signalConsistency = 0.3 + (buyCount - sellCount).abs() / signalCount * 0.7;
    }

    // 2. 基本面支撑(25%)
    double fundamentalSupport = 0.5;
    if (fundamentalScore != null) {
      if (totalScore >= 7 && fundamentalScore.totalScore >= 6) {
        fundamentalSupport = (0.7 + (fundamentalScore.totalScore - 6) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore <= 4 && fundamentalScore.totalScore <= 4) {
        fundamentalSupport = (0.7 + (4 - fundamentalScore.totalScore) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore >= 7 && fundamentalScore.totalScore < 4) {
        fundamentalSupport = 0.3;
      } else if (totalScore <= 4 && fundamentalScore.totalScore > 6) {
        fundamentalSupport = 0.3;
      }
    }

    // 3. 情绪面确认(20%)
    double sentimentConfirm = 0.5;
    if (newsSentiment != null) {
      if (totalScore >= 7 && newsSentiment.score > 2) {
        sentimentConfirm = 0.7 + (newsSentiment.score - 2) * 0.03;
      } else if (totalScore <= 4 && newsSentiment.score < -2) {
        sentimentConfirm = 0.7 + (-2 - newsSentiment.score) * 0.03;
      } else if (totalScore >= 7 && newsSentiment.score < -2) {
        sentimentConfirm = 0.3;
      } else if (totalScore <= 4 && newsSentiment.score > 2) {
        sentimentConfirm = 0.3;
      }
    }

    // 4. 市场环境(15%)
    double marketConfirm = 0.5;
    if (marketContext != null) {
      if (totalScore >= 7 && marketContext.avgChangePct > 0.5) {
        marketConfirm = 0.7;
      } else if (totalScore <= 4 && marketContext.avgChangePct < -0.5) {
        marketConfirm = 0.7;
      } else if (totalScore >= 7 && marketContext.avgChangePct < -1) {
        marketConfirm = 0.3;
      } else if (totalScore <= 4 && marketContext.avgChangePct > 1) {
        marketConfirm = 0.3;
      }
    }

    // 5. 信号新鲜度(10%)
    double signalFreshness = 0.5;
    final recentBuySignals = buySignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    final recentSellSignals = sellSignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    if (recentBuySignals + recentSellSignals > 0) {
      signalFreshness = 0.3 + (recentBuySignals + recentSellSignals) / (signalCount > 0 ? signalCount : 1) * 0.7;
    }

    var confidenceScore = (signalConsistency * 0.30 +
        fundamentalSupport * 0.25 +
        sentimentConfirm * 0.20 +
        marketConfirm * 0.15 +
        signalFreshness * 0.10).clamp(0.3, 0.95);

    // 对抗验证调整
    try {
      final validatedSignals = SignalValidator.validate(signals, quote, last);
      double validationAdjustment = 0.0;
      for (final vs in validatedSignals) {
        if (vs.adjustedConfidence < 0.4) {
          validationAdjustment -= 0.05;
        } else if (vs.adjustedConfidence < 0.5) {
          validationAdjustment -= 0.02;
        }
      }
      confidenceScore = (confidenceScore + validationAdjustment).clamp(0.2, 0.95);
    } catch (_) {}

    return confidenceScore;
  }

  /// 获取置信度分解
  static Map<String, double> breakdown({
    required List<SignalItem> signals,
    required int totalScore,
    required FundamentalScore? fundamentalScore,
    required NewsSentiment? newsSentiment,
    required MarketContext? marketContext,
  }) {
    final buySignals = signals.where((s) => s.type == 'buy').toList();
    final sellSignals = signals.where((s) => s.type == 'sell').toList();
    final buyCount = buySignals.length;
    final sellCount = sellSignals.length;
    final signalCount = buyCount + sellCount;

    double signalConsistency = 0.5;
    if (signalCount > 0) {
      signalConsistency = 0.3 + (buyCount - sellCount).abs() / signalCount * 0.7;
    }

    double fundamentalSupport = 0.5;
    if (fundamentalScore != null) {
      if (totalScore >= 7 && fundamentalScore.totalScore >= 6) {
        fundamentalSupport = (0.7 + (fundamentalScore.totalScore - 6) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore <= 4 && fundamentalScore.totalScore <= 4) {
        fundamentalSupport = (0.7 + (4 - fundamentalScore.totalScore) * 0.1).clamp(0.0, 1.0);
      } else if (totalScore >= 7 && fundamentalScore.totalScore < 4) {
        fundamentalSupport = 0.3;
      } else if (totalScore <= 4 && fundamentalScore.totalScore > 6) {
        fundamentalSupport = 0.3;
      }
    }

    double sentimentConfirm = 0.5;
    if (newsSentiment != null) {
      if (totalScore >= 7 && newsSentiment.score > 2) {
        sentimentConfirm = 0.7 + (newsSentiment.score - 2) * 0.03;
      } else if (totalScore <= 4 && newsSentiment.score < -2) {
        sentimentConfirm = 0.7 + (-2 - newsSentiment.score) * 0.03;
      } else if (totalScore >= 7 && newsSentiment.score < -2) {
        sentimentConfirm = 0.3;
      } else if (totalScore <= 4 && newsSentiment.score > 2) {
        sentimentConfirm = 0.3;
      }
    }

    double marketConfirm = 0.5;
    if (marketContext != null) {
      if (totalScore >= 7 && marketContext.avgChangePct > 0.5) {
        marketConfirm = 0.7;
      } else if (totalScore <= 4 && marketContext.avgChangePct < -0.5) {
        marketConfirm = 0.7;
      } else if (totalScore >= 7 && marketContext.avgChangePct < -1) {
        marketConfirm = 0.3;
      } else if (totalScore <= 4 && marketContext.avgChangePct > 1) {
        marketConfirm = 0.3;
      }
    }

    double signalFreshness = 0.5;
    final recentBuySignals = buySignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    final recentSellSignals = sellSignals.where((s) =>
      s.duration == SignalDuration.shortTerm || s.duration == SignalDuration.mediumTerm
    ).length;
    if (recentBuySignals + recentSellSignals > 0) {
      signalFreshness = 0.3 + (recentBuySignals + recentSellSignals) / (signalCount > 0 ? signalCount : 1) * 0.7;
    }

    return {
      'signal_consistency': signalConsistency,
      'fundamental_support': fundamentalSupport,
      'sentiment_confirm': sentimentConfirm,
      'market_confirm': marketConfirm,
      'signal_freshness': signalFreshness,
    };
  }
}
```

- [ ] **Step 4: 创建 ConfidenceCalculator 测试**

创建 `mobile/test/confidence_calculator_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/confidence_calculator.dart';

void main() {
  group('ConfidenceCalculator', () {
    test('Returns valid confidence range', () {
      final data = List.generate(60, (i) {
        final price = 10.0 + i * 0.2;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: price - 0.1, high: price + 0.2, low: price - 0.2, close: price,
          volume: 10000.0, amount: 10000 * price,
        );
      });
      final calcData = calcAllIndicators(data);
      final confidence = ConfidenceCalculator.calculate(
        signals: [],
        totalScore: 5,
        fundamentalScore: null,
        newsSentiment: null,
        marketContext: null,
        quote: null,
        last: calcData.last,
      );
      expect(confidence, inInclusiveRange(0.2, 0.95));
    });

    test('Breakdown contains all 5 dimensions', () {
      final breakdown = ConfidenceCalculator.breakdown(
        signals: [],
        totalScore: 5,
        fundamentalScore: null,
        newsSentiment: null,
        marketContext: null,
      );
      expect(breakdown.keys, containsAll(['signal_consistency', 'fundamental_support', 'sentiment_confirm', 'market_confirm', 'signal_freshness']));
    });
  });
}
```

- [ ] **Step 5: 运行测试验证**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/confidence_calculator_test.dart`
Expected: PASS

---

### Task 8: 重构 signal_engine.dart — 薄编排器

**Files:**
- Modify: `mobile/lib/analysis/signal_engine.dart`

- [ ] **Step 1: 重写 signal_engine.dart**

将 `generateAnalysis` 重构为薄编排器，委托给各模块。保留 `detectSignals` 和 `calcTradeLevels` 作为向后兼容的公共API：

```dart
import '../models/stock_models.dart';
import 'indicators.dart';
import 'signal_detector.dart';
import 'signal_layer.dart';
import 'technical_scorer.dart';
import 'realtime_scorer.dart';
import 'confluence_scorer.dart';
import 'comprehensive_scorer.dart';
import 'risk_analyzer.dart';
import 'opportunity_identifier.dart';
import 'suggestion_generator.dart';
import 'confidence_calculator.dart';
import 'strategy_builder.dart';
import 'backtest_engine.dart';
import 'signal_validator.dart';

/// 向后兼容：检测特有信号
List<SignalItem> detectSignals(List<HistoryKline> data) {
  return SignalLayer.detectUniqueSignals(data);
}

/// 计算交易价位
Map<String, dynamic> calcTradeLevels(List<HistoryKline> data) {
  if (data.isEmpty) return {};

  final last = data[data.length - 1];
  final price = last.close;

  final supportLevels = calcSupportResistance(data);
  final supports = supportLevels['support'] as List<double>? ?? [];
  final resistances = supportLevels['resistance'] as List<double>? ?? [];

  final nearestSupport = supports.isNotEmpty ? supports.first : null;
  final nearestResistance = resistances.isNotEmpty ? resistances.first : null;

  final entryLow = nearestSupport ?? price * 0.98;
  final entryHigh = price * 1.01;
  final target = nearestResistance ?? price * 1.1;
  final stopLoss = last.ma60 > 0
      ? ([entryLow * 0.98, last.ma60 * 0.97].reduce((a, b) => a > b ? a : b))
      : entryLow * 0.98;

  final entryMid = (entryLow + entryHigh) / 2;
  final reward = target - entryMid;
  final risk = entryMid - stopLoss;
  final riskRewardRatio = risk > 0 ? reward / risk : 0.0;

  final support = nearestSupport ?? 0;
  final support2 = supports.length > 1 ? supports[1] : 0.0;
  final resistance = nearestResistance ?? 0;
  final resistance2 = resistances.length > 1 ? resistances[1] : 0.0;

  final tradeLevels = <String, dynamic>{
    'entry_low': entryLow,
    'entry_high': entryHigh,
    'target': target,
    'stop_loss': stopLoss,
    'risk_reward_ratio': riskRewardRatio,
    'has_support': nearestSupport != null,
    'has_resistance': nearestResistance != null,
  };

  // 支撑压力位质量评估
  if (data.length >= 30) {
    final supportsList = [support, support2].where((s) => s > 0).toList();
    final resistancesList = [resistance, resistance2].where((r) => r > 0).toList();
    for (int i = 0; i < supportsList.length; i++) {
      final quality = SRQualityEvaluator.evaluateSupport(data, supportsList[i]);
      tradeLevels.addAll({
        'support_${i + 1}_quality': quality.quality,
        'support_${i + 1}_test_count': quality.testCount,
        'support_${i + 1}_reliability': quality.reliability,
      });
    }
    for (int i = 0; i < resistancesList.length; i++) {
      final quality = SRQualityEvaluator.evaluateResistance(data, resistancesList[i]);
      tradeLevels.addAll({
        'resistance_${i + 1}_quality': quality.quality,
        'resistance_${i + 1}_test_count': quality.testCount,
        'resistance_${i + 1}_reliability': quality.reliability,
      });
    }
  }
  return tradeLevels;
}

/// 生成分析结果（薄编排器）
AnalysisResult generateAnalysis(
  List<HistoryKline> data,
  QuoteData? quote, {
  MarketContext? marketContext,
  List<dynamic>? newsList,
}) {
  if (data.isEmpty) {
    return AnalysisResult(
      signals: [],
      indicators: {},
      recommendation: '观望',
      score: 5,
      riskLevel: '中等',
      riskFactors: ['数据不足'],
      suggestions: ['等待更多数据'],
      reasons: ['数据不足，无法生成有效建议'],
      opportunities: [],
      confidenceScore: 0.3,
    );
  }

  final last = data[data.length - 1];

  // 1. 信号检测
  final signals = SignalLayer.detectAllSignals(data);
  final indicators = getIndicatorSummary(data);

  final buySignals = signals.where((s) => s.type == 'buy').toList();
  final sellSignals = signals.where((s) => s.type == 'sell').toList();

  // 2. 技术面评分
  final techResult = TechnicalScorer.score(data, buySignals, sellSignals);

  // 3. 实时行情评分
  final realtimeScore = RealtimeScorer.score(quote);

  // 4. 共振评分
  final confluenceResult = ConfluenceScorer.score(last, signals);

  // 5. 综合评分
  final compResult = ComprehensiveScorer.combine(
    technicalScore: techResult.totalScore,
    realtimeScore: realtimeScore,
    confluenceScore: confluenceResult.score,
    quote: quote,
    marketContext: marketContext,
    newsList: newsList,
  );

  final totalScore = compResult.totalScore;
  final recommendation = compResult.recommendation;

  // 6. 推荐理由
  final reasons = _generateReasons(buySignals, sellSignals, last, quote);

  // 7. 风险分析
  final riskResult = RiskAnalyzer.analyze(data, last, quote);

  // 8. 机会识别
  final opportunities = OpportunityIdentifier.identify(buySignals);

  // 9. 操作建议
  final suggestions = SuggestionGenerator.generate(
    recommendation: recommendation,
    data: data,
    last: last,
    quote: quote,
    buySignals: buySignals,
    sellSignals: sellSignals,
    totalScore: totalScore,
  );

  // 10. 回测统计
  Map<String, BacktestResult> backtestResults = {};
  try {
    if (data.length >= 60) {
      backtestResults['MACD金叉'] = BacktestEngine.backtestMACDCross(data);
      backtestResults['MA金叉'] = BacktestEngine.backtestMACross(data);
      backtestResults['KDJ超卖'] = BacktestEngine.backtestKDJOversoldCross(data);
      backtestResults['RSI超卖'] = BacktestEngine.backtestRSIOversoldRecovery(data);
    }
  } catch (_) {
    backtestResults = {};
  }

  // 11. 分层策略
  List<TradingStrategy> shortTermStrategies = [];
  List<TradingStrategy> longTermStrategies = [];
  try {
    shortTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.shortTerm);
    longTermStrategies = StrategyBuilder.buildLayeredStrategies(data, signals, SignalDuration.longTerm);
  } catch (_) {}

  // 12. 置信度计算
  final confidenceScore = ConfidenceCalculator.calculate(
    signals: signals,
    totalScore: totalScore,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
    quote: quote,
    last: last,
  );
  final confidenceBreakdown = ConfidenceCalculator.breakdown(
    signals: signals,
    totalScore: totalScore,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    marketContext: marketContext,
  );

  // 13. 对抗验证
  List<ValidatedSignal> validatedSignals = [];
  try {
    validatedSignals = SignalValidator.validate(signals, quote, last);
  } catch (_) {}

  // 14. 详细推荐理由
  final detailedReasons = <RecommendationReason>[];
  for (final signal in signals.take(5)) {
    if (signal.confidence != null) {
      detailedReasons.add(RecommendationReason(
        title: signal.signal,
        description: signal.description,
        confidence: signal.confidence!,
        duration: signal.duration == SignalDuration.shortTerm ? '短期' : signal.duration == SignalDuration.mediumTerm ? '中期' : '长期',
      ));
    }
  }
  if (marketContext != null) {
    detailedReasons.add(RecommendationReason(
      title: '市场环境',
      description: '上证${marketContext.shIndexPct.toStringAsFixed(2)}%，深证${marketContext.szIndexPct.toStringAsFixed(2)}%',
      confidence: 0.7,
      duration: '环境',
    ));
  }

  final tradeLevels = calcTradeLevels(data);

  return AnalysisResult(
    signals: signals,
    indicators: indicators,
    recommendation: recommendation,
    score: totalScore,
    riskLevel: riskResult.riskLevel,
    riskFactors: riskResult.riskFactors,
    suggestions: suggestions,
    tradeLevels: tradeLevels.isNotEmpty ? tradeLevels : null,
    confluenceScore: confluenceResult.bullCount,
    confluenceDetails: confluenceResult.details,
    reasons: reasons,
    opportunities: opportunities,
    shortTermStrategies: shortTermStrategies,
    longTermStrategies: longTermStrategies,
    marketContext: marketContext,
    confidenceScore: confidenceScore,
    detailedReasons: detailedReasons,
    backtestResults: backtestResults,
    fundamentalScore: compResult.fundamentalScore,
    newsSentiment: compResult.newsSentiment,
    validatedSignals: validatedSignals,
    confidenceBreakdown: confidenceBreakdown,
  );
}

/// 生成推荐理由
List<String> _generateReasons(
  List<SignalItem> buySignals,
  List<SignalItem> sellSignals,
  HistoryKline last,
  QuoteData? quote,
) {
  final reasons = <String>[];
  final buyCount = buySignals.length;
  final sellCount = sellSignals.length;

  if (buyCount > sellCount + 1) reasons.add('多个买入信号共振');
  if (sellCount > buyCount + 1) reasons.add('多个卖出信号共振');
  if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma5 > 0) reasons.add('均线多头排列');
  if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma5 > 0) reasons.add('均线空头排列');
  if (last.rsi6 > 70) reasons.add('RSI超买区域');
  if (last.rsi6 < 30 && last.rsi6 > 0) reasons.add('RSI超卖区域');
  if (last.volume > last.volMa5 * 1.5 && last.volMa5 > 0) reasons.add('成交量显著放大');
  if (last.close >= last.open && last.volume < last.volMa5 * 0.7 && last.volMa5 > 0) reasons.add('上涨缩量，动能不足');

  if (quote != null && quote.price > 0) {
    if (quote.changePct > 3) reasons.add('当日涨幅${quote.changePct.toStringAsFixed(1)}%，追高需谨慎');
    if (quote.changePct < -3) reasons.add('当日跌幅${quote.changePct.toStringAsFixed(1)}%，短线偏弱');
    if (quote.mainNetFlow > 0 && quote.mainNetFlowRate > 3) reasons.add('主力资金净流入${quote.mainNetFlowRate.toStringAsFixed(1)}%');
    if (quote.mainNetFlow < 0 && quote.mainNetFlowRate < -3) reasons.add('主力资金净流出${quote.mainNetFlowRate.abs().toStringAsFixed(1)}%');
    if (quote.turnover > 10) reasons.add('换手率${quote.turnover.toStringAsFixed(1)}%，交投过热');
  }

  return reasons;
}
```

- [ ] **Step 2: 运行全部已有测试验证无回归**

Run: `cd d:\MyProjects\stock\mobile && flutter test test/signal_engine_test.dart test/scoring_logic_test.dart test/strategy_engine_test.dart test/multi_dimension_test.dart`
Expected: ALL PASS

---

### Task 9: 清理 + 运行完整测试套件

**Files:**
- Delete: `mobile/lib/analysis/signal_engine.dart.bak`

- [ ] **Step 1: 删除备份文件**

删除 `mobile/lib/analysis/signal_engine.dart.bak`

- [ ] **Step 2: 运行完整测试套件**

Run: `cd d:\MyProjects\stock\mobile && flutter test`
Expected: ALL PASS

- [ ] **Step 3: 运行 Flutter 分析**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze`
Expected: No issues found

---

## Self-Review

### 1. Spec Coverage
- 信号检测与合并 → Task 1 (SignalLayer) ✓
- 多维评分计算 → Task 2 (TechnicalScorer) ✓
- 实时行情评分 → Task 3 (RealtimeScorer) ✓
- 跨指标共振评分 → Task 4 (ConfluenceScorer) ✓
- 综合评分计算 → Task 5 (ComprehensiveScorer) ✓
- 风险因子收集 → Task 6 (RiskAnalyzer) ✓
- 机会识别 → Task 7 (OpportunityIdentifier) ✓
- 操作建议生成 → Task 7 (SuggestionGenerator) ✓
- 置信度计算 → Task 7 (ConfidenceCalculator) ✓
- 重构 generateAnalysis → Task 8 ✓
- 回归测试 → Task 9 ✓

### 2. Placeholder Scan
- No TBD/TODO found ✓
- All code blocks contain actual implementation ✓
- All test commands specified ✓

### 3. Type Consistency
- `SignalLayer.detectAllSignals` returns `List<SignalItem>` → used in Task 8 ✓
- `TechnicalScorer.score` returns `TechnicalScoreResult` with `totalScore` field → used in Task 8 ✓
- `RealtimeScorer.score` returns `double` → used in Task 8 ✓
- `ConfluenceScorer.score` returns `ConfluenceResult` with `score`, `bullCount`, `details` → used in Task 8 ✓
- `ComprehensiveScorer.combine` returns `ComprehensiveScoreResult` with `totalScore`, `recommendation`, `fundamentalScore`, `newsSentiment` → used in Task 8 ✓
- `RiskAnalyzer.analyze` returns `RiskAnalysisResult` with `riskFactors`, `riskLevel` → used in Task 8 ✓
- `OpportunityIdentifier.identify` returns `List<Map<String, String>>` → used in Task 8 ✓
- `SuggestionGenerator.generate` returns `List<String>` → used in Task 8 ✓
- `ConfidenceCalculator.calculate` returns `double` → used in Task 8 ✓
- `ConfidenceCalculator.breakdown` returns `Map<String, double>` → used in Task 8 ✓
