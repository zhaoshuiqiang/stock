import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import 'signal_detector.dart';

/// 信号层：合并分层信号与特有信号，提供统一的信号检测入口
class SignalLayer {
  /// 检测所有信号：先获取分层信号，再合并特有信号（去重）
  static List<SignalItem> detectAllSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 2) return [];

    // 获取分层信号
    List<SignalItem> signals;
    try {
      signals = SignalDetector.detectLayeredSignals(data);
    } catch (e) {
      debugPrint('SignalLayer.detectAllSignals: detectLayeredSignals failed: $e');
      signals = [];
    }

    // 合并特有信号（去重：同名信号保留strength更高的版本）
    try {
      final uniqueSignals = detectUniqueSignals(data);
      // P1-2修复：去重时比较strength，保留更强的版本
      final signalsByName = <String, SignalItem>{};
      for (final s in signals) {
        signalsByName[s.signal] = s;
      }
      for (final s in uniqueSignals) {
        final existing = signalsByName[s.signal];
        if (existing == null || s.strength > existing.strength) {
          signalsByName[s.signal] = s;
        }
      }
      // 重建列表：保留原始顺序 + 追加新信号
      final existingSet = signals.map((s) => s.signal).toSet();
      for (final s in uniqueSignals) {
        if (!existingSet.contains(s.signal) || signalsByName[s.signal] == s) {
          if (!existingSet.contains(s.signal)) {
            signals.add(s);
          } else {
            // 替换为更强版本
            final idx = signals.indexWhere((e) => e.signal == s.signal);
            if (idx >= 0) signals[idx] = s;
          }
        }
      }
    } catch (e) {
      debugPrint('SignalLayer.detectAllSignals: detectUniqueSignals failed: $e');
    }

    return signals;
  }

  /// 检测特有信号（SignalDetector 未覆盖的量价背离、布林收口等）
  static List<SignalItem> detectUniqueSignals(List<HistoryKline> data) {
    if (data.isEmpty || data.length < 2) return [];

    final signals = <SignalItem>[];

    signals.addAll(_detectVolumePriceDivergence(data));
    signals.addAll(_detectBollSqueezeBreakout(data));

    signals.sort((a, b) => b.strength.compareTo(a.strength));
    return signals;
  }

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
          duration: SignalDuration.shortTerm,
          confidence: 0.7,
          signalCount: 1,
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
            duration: SignalDuration.shortTerm,
            confidence: 0.7,
            signalCount: 1,
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
            duration: SignalDuration.shortTerm,
            confidence: 0.65,
            signalCount: 1,
          ));
        }
      }
    }

    return signals;
  }

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
        duration: SignalDuration.shortTerm,
        confidence: 0.6,
        signalCount: 1,
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
          duration: SignalDuration.shortTerm,
          confidence: 0.8,
          signalCount: 1,
        ));
      } else if (last.close < last.bollLower) {
        signals.add(SignalItem(
          type: 'sell',
          indicator: 'BOLL',
          signal: '布林带跌破下轨',
          description: '收口后跌破布林带下轨(${last.bollLower.toStringAsFixed(2)})，向下突破',
          strength: 80,
          timestamp: last.date,
          duration: SignalDuration.shortTerm,
          confidence: 0.8,
          signalCount: 1,
        ));
      }
    }

    return signals;
  }
}
