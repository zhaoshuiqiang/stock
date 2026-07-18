import 'dart:math' as math;

import '../models/stock_models.dart';
import 'next_session_prediction.dart';

class NextSessionFeatureExtractor {
  static NextSessionFeatures extract(List<HistoryKline> data, {int? index}) {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'must not be empty');
    }

    final i = index ?? data.length - 1;
    if (i < 0 || i >= data.length) {
      throw RangeError.index(i, data, 'index');
    }

    final current = data[i];
    final previous = i > 0 ? data[i - 1] : null;
    final changePct = _changePct(current, previous);
    final range = current.high - current.low;
    final closePosition = range > 0
        ? ((current.close - current.low) / range).clamp(0.0, 1.0)
        : 0.5;
    final upperShadow = range > 0
        ? (current.high - math.max(current.open, current.close)) / range
        : 0.0;
    final lowerShadow = range > 0
        ? (math.min(current.open, current.close) - current.low) / range
        : 0.0;
    final amplitudePct = previous != null && previous.close > 0
        ? range / previous.close * 100
        : current.amplitude;

    final return3 = _lookbackReturn(data, i, 3);
    final return5 = _lookbackReturn(data, i, 5);
    final return10 = _lookbackReturn(data, i, 10);
    final volumeRatio5 = _volumeRatio(data, i, 5);
    final volumeRatio10 = _volumeRatio(data, i, 10);

    final scenarioTags = <String>{};
    final riskWarnings = <String>{};

    if (changePct >= 6.5 && closePosition < 0.55 && upperShadow >= 0.35) {
      scenarioTags.add('高位回调风险');
      riskWarnings.add('不追高');
    }
    if (upperShadow >= 0.35 && closePosition < 0.55) {
      scenarioTags.add('长上影分歧');
    }
    if (changePct >= 2 && volumeRatio5 >= 2 && closePosition < 0.45) {
      scenarioTags.add('放量滞涨');
      riskWarnings.add('放量不强');
    }
    if (changePct >= 2 && volumeRatio5 > 0 && volumeRatio5 < 0.7) {
      scenarioTags.add('缩量上涨不追');
      riskWarnings.add('量能不足');
    }
    if (return5 <= -8 && lowerShadow >= 0.5 && closePosition >= 0.7) {
      scenarioTags.add('超跌反弹');
    }
    if (changePct >= 2 &&
        changePct <= 7 &&
        closePosition >= 0.75 &&
        volumeRatio5 >= 1 &&
        volumeRatio5 <= 2.5) {
      scenarioTags.add('强势延续');
    }
    if (return5 <= -5 && closePosition < 0.35) {
      scenarioTags.add('弱势延续');
      riskWarnings.add('趋势偏弱');
    }

    final volatility20 = _volatility20(data, i);

    final featureBins = _extractFeatureBins(data[i]);

    return NextSessionFeatures(
      changePct: changePct,
      amplitudePct: amplitudePct,
      closePosition: closePosition,
      upperShadowRatio: upperShadow.clamp(0.0, 1.0),
      lowerShadowRatio: lowerShadow.clamp(0.0, 1.0),
      return3: return3,
      return5: return5,
      return10: return10,
      consecutiveUpDays: _consecutiveDays(data, i, up: true),
      consecutiveDownDays: _consecutiveDays(data, i, up: false),
      distanceMa5: _distanceToMa(current.close, current.ma5),
      distanceMa10: _distanceToMa(current.close, current.ma10),
      distanceMa20: _distanceToMa(current.close, current.ma20),
      volumeRatio5: volumeRatio5,
      volumeRatio10: volumeRatio10,
      turnover: current.turnover,
      rsi6: current.rsi6,
      k: current.k,
      d: current.d,
      j: current.j,
      macdHist: current.macdHist,
      volatility20: volatility20,
      featureBins: featureBins,
      scenarioTags: scenarioTags.toList(growable: false),
      riskWarnings: riskWarnings.toList(growable: false),
    );
  }

  static double _volatility20(List<HistoryKline> data, int index) {
    if (index < 20) return 0;
    final returns = <double>[];
    for (var j = index - 19; j <= index; j++) {
      if (j > 0 && data[j - 1].close > 0) {
        returns.add(data[j].close / data[j - 1].close - 1);
      }
    }
    if (returns.length < 10) return 0;
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance =
        returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
            returns.length;
    return math.sqrt(variance) * math.sqrt(252) * 100;
  }

  static Map<String, String> _extractFeatureBins(HistoryKline kline) {
    final bins = <String, String>{};

    if (kline.rsi6.isFinite && kline.rsi6 >= 0 && kline.rsi6 <= 100) {
      if (kline.rsi6 >= 70) {
        bins['rsi'] = '超买';
      } else if (kline.rsi6 >= 50) {
        bins['rsi'] = '偏强';
      } else if (kline.rsi6 >= 30) {
        bins['rsi'] = '偏弱';
      } else {
        bins['rsi'] = '超卖';
      }
    }

    if (kline.macdHist.isFinite) {
      if (kline.macdHist > 0.001) {
        bins['macd_hist'] = '红柱';
      } else if (kline.macdHist < -0.001) {
        bins['macd_hist'] = '绿柱';
      } else {
        bins['macd_hist'] = '零轴';
      }
    }

    if (kline.macdDif.isFinite && kline.macdDea.isFinite) {
      if (kline.macdDif > kline.macdDea) {
        bins['macd_cross'] = '金叉区域';
      } else {
        bins['macd_cross'] = '死叉区域';
      }
    }

    if (kline.k.isFinite && kline.k >= 0 && kline.k <= 100) {
      if (kline.k >= 80) {
        bins['kdj'] = '超买';
      } else if (kline.k >= 50) {
        bins['kdj'] = '偏多';
      } else if (kline.k >= 20) {
        bins['kdj'] = '偏空';
      } else {
        bins['kdj'] = '超卖';
      }
    }

    if (kline.volMa5 > 0 && kline.volume > 0) {
      final volRatio = kline.volume / kline.volMa5;
      if (volRatio >= 1.5) {
        bins['volume'] = '放量';
      } else if (volRatio >= 1.0) {
        bins['volume'] = '正常';
      } else {
        bins['volume'] = '缩量';
      }
    }

    if (kline.ma5 > 0 && kline.ma10 > 0) {
      bins['ma5_ma10'] = kline.ma5 > kline.ma10 ? 'MA5上穿' : 'MA5下穿';
    }

    if (kline.adx14.isFinite && kline.adx14 >= 0 && kline.adx14 <= 100) {
      if (kline.adx14 >= 25) {
        bins['adx'] = '趋势明确';
      } else if (kline.adx14 >= 20) {
        bins['adx'] = '趋势形成';
      } else {
        bins['adx'] = '盘整';
      }
    }

    return bins;
  }

  static double _changePct(HistoryKline current, HistoryKline? previous) {
    if (current.changePct != 0) return current.changePct;
    if (previous != null && previous.close > 0) {
      return (current.close / previous.close - 1) * 100;
    }
    if (current.open > 0) {
      return (current.close / current.open - 1) * 100;
    }
    return 0;
  }

  static double _lookbackReturn(List<HistoryKline> data, int index, int days) {
    if (index <= 0) return 0;
    final start = math.max(0, index - days + 1);
    final base = data[start].close;
    if (base <= 0) return 0;
    return (data[index].close / base - 1) * 100;
  }

  static double _volumeRatio(List<HistoryKline> data, int index, int days) {
    if (index <= 0) return 0;
    final start = math.max(0, index - days);
    final previous = data.sublist(start, index).where((k) => k.volume > 0);
    if (previous.isEmpty) return 0;
    final avg =
        previous.map((k) => k.volume).reduce((a, b) => a + b) / previous.length;
    return avg > 0 ? data[index].volume / avg : 0;
  }

  static int _consecutiveDays(List<HistoryKline> data, int index,
      {required bool up}) {
    var count = 0;
    for (var i = index; i > 0; i--) {
      final change = _changePct(data[i], data[i - 1]);
      if (up ? change > 0 : change < 0) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static double _distanceToMa(double close, double ma) {
    if (close <= 0 || ma <= 0) return 0;
    return (close / ma - 1) * 100;
  }
}
