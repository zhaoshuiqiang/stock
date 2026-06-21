import 'dart:math';
import '../models/stock_models.dart';

List<HistoryKline> calcMA(List<HistoryKline> data, List<int> periods) {
  if (data.isEmpty) return data;

  final result = List<HistoryKline>.from(data);

  for (final period in periods) {
    if (data.length < period) continue;

    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += data[i].close;
    }

    for (int i = 0; i < data.length; i++) {
      if (i >= period) {
        sum = sum - data[i - period].close + data[i].close;
      }

      final maValue = i >= period - 1 ? sum / period : 0.0;

      switch (period) {
        case 5:
          result[i] = result[i].copyWith(ma5: maValue);
          break;
        case 10:
          result[i] = result[i].copyWith(ma10: maValue);
          break;
        case 20:
          result[i] = result[i].copyWith(ma20: maValue);
          break;
        case 60:
          result[i] = result[i].copyWith(ma60: maValue);
          break;
      }
    }
  }

  return result;
}

List<HistoryKline> calcVolumeMA(List<HistoryKline> data, List<int> periods) {
  if (data.isEmpty) return data;

  final result = List<HistoryKline>.from(data);

  for (final period in periods) {
    if (data.length < period) continue;

    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += data[i].volume;
    }

    for (int i = 0; i < data.length; i++) {
      if (i >= period) {
        sum = sum - data[i - period].volume + data[i].volume;
      }

      final volMaValue = i >= period - 1 ? sum / period : 0.0;

      switch (period) {
        case 5:
          result[i] = result[i].copyWith(volMa5: volMaValue);
          break;
        case 10:
          result[i] = result[i].copyWith(volMa10: volMaValue);
          break;
      }
    }
  }

  return result;
}

List<HistoryKline> calcMACD(
  List<HistoryKline> data, {
  int fast = 12,
  int slow = 26,
  int signal = 9,
}) {
  if (data.isEmpty) return data;

  final result = List<HistoryKline>.from(data);

  final List<double> emaFast = List.filled(data.length, 0);
  final List<double> emaSlow = List.filled(data.length, 0);

  double alphaFast = 2.0 / (fast + 1);
  double alphaSlow = 2.0 / (slow + 1);

  emaFast[0] = data[0].close;
  emaSlow[0] = data[0].close;

  for (int i = 1; i < data.length; i++) {
    emaFast[i] = alphaFast * data[i].close + (1 - alphaFast) * emaFast[i - 1];
    emaSlow[i] = alphaSlow * data[i].close + (1 - alphaSlow) * emaSlow[i - 1];
  }

  final List<double> dif = List.filled(data.length, 0);
  for (int i = 0; i < data.length; i++) {
    dif[i] = emaFast[i] - emaSlow[i];
  }

  double alphaSignal = 2.0 / (signal + 1);
  final List<double> dea = List.filled(data.length, 0);
  dea[0] = dif[0];

  for (int i = 1; i < data.length; i++) {
    dea[i] = alphaSignal * dif[i] + (1 - alphaSignal) * dea[i - 1];
  }

  for (int i = 0; i < data.length; i++) {
    result[i] = result[i].copyWith(
      macdDif: dif[i],
      macdDea: dea[i],
      macdHist: 2 * (dif[i] - dea[i]),
    );
  }

  return result;
}

List<HistoryKline> calcRSI(List<HistoryKline> data, List<int> periods) {
  if (data.length < 2) return data;

  final result = List<HistoryKline>.from(data);
  final List<double> delta = List.filled(data.length, 0);

  for (int i = 1; i < data.length; i++) {
    delta[i] = data[i].close - data[i - 1].close;
  }

  for (final period in periods) {
    if (data.length < period) continue;

    final List<double> gains = List.filled(data.length, 0);
    final List<double> losses = List.filled(data.length, 0);

    for (int i = 0; i < data.length; i++) {
      gains[i] = delta[i] > 0 ? delta[i] : 0;
      losses[i] = delta[i] < 0 ? -delta[i] : 0;
    }

    final List<double> avgGain = List.filled(data.length, 0);
    final List<double> avgLoss = List.filled(data.length, 0);

    double sumGain = 0;
    double sumLoss = 0;
    for (int i = 1; i <= period; i++) {
      sumGain += gains[i];
      sumLoss += losses[i];
    }
    avgGain[period] = sumGain / period;
    avgLoss[period] = sumLoss / period;

    for (int i = period + 1; i < data.length; i++) {
      avgGain[i] = (avgGain[i - 1] * (period - 1) + gains[i]) / period;
      avgLoss[i] = (avgLoss[i - 1] * (period - 1) + losses[i]) / period;
    }

    final List<double> rsi = List.filled(data.length, 0);
    for (int i = period; i < data.length; i++) {
      if (avgLoss[i] == 0) {
        rsi[i] = 100;
      } else {
        final rs = avgGain[i] / avgLoss[i];
        rsi[i] = 100 - (100 / (1 + rs));
      }
    }

    for (int i = 0; i < data.length; i++) {
      switch (period) {
        case 6:
          result[i] = result[i].copyWith(rsi6: rsi[i]);
          break;
        case 12:
          result[i] = result[i].copyWith(rsi12: rsi[i]);
          break;
        case 24:
          result[i] = result[i].copyWith(rsi24: rsi[i]);
          break;
      }
    }
  }

  return result;
}

List<HistoryKline> calcKDJ(
  List<HistoryKline> data, {
  int n = 9,
  int m1 = 3,
  int m2 = 3,
}) {
  if (data.length < n) return data;

  final result = List<HistoryKline>.from(data);

  final List<double> lowMin = List.filled(data.length, 0);
  final List<double> highMax = List.filled(data.length, 0);

  for (int i = n - 1; i < data.length; i++) {
    double minL = data[i].low;
    double maxH = data[i].high;
    for (int j = i - n + 1; j <= i; j++) {
      if (data[j].low < minL) minL = data[j].low;
      if (data[j].high > maxH) maxH = data[j].high;
    }
    lowMin[i] = minL;
    highMax[i] = maxH;
  }

  final List<double> rsv = List.filled(data.length, 0);
  for (int i = n - 1; i < data.length; i++) {
    final diff = highMax[i] - lowMin[i];
    rsv[i] = diff > 0 ? ((data[i].close - lowMin[i]) / diff * 100) : 0;
  }

  final List<double> k = List.filled(data.length, 0);
  final List<double> d = List.filled(data.length, 0);

  k[n - 1] = 50;
  d[n - 1] = 50;

  double alphaK = 1.0 / m1;
  double alphaD = 1.0 / m2;

  for (int i = n; i < data.length; i++) {
    k[i] = alphaK * rsv[i] + (1 - alphaK) * k[i - 1];
    d[i] = alphaD * k[i] + (1 - alphaD) * d[i - 1];
  }

  for (int i = 0; i < data.length; i++) {
    final j = 3 * k[i] - 2 * d[i];
    result[i] = result[i].copyWith(k: k[i], d: d[i], j: j);
  }

  return result;
}

List<HistoryKline> calcBOLL(List<HistoryKline> data, {int n = 20, int k = 2}) {
  if (data.length < n) return data;

  final result = List<HistoryKline>.from(data);

  // O(n) sliding window: compute sum and sum-of-squares
  double sum = 0;
  double sumSq = 0;
  for (int i = 0; i < n; i++) {
    sum += data[i].close;
    sumSq += data[i].close * data[i].close;
  }

  for (int i = n - 1; i < data.length; i++) {
    if (i >= n) {
      sum = sum - data[i - n].close + data[i].close;
      sumSq = sumSq - data[i - n].close * data[i - n].close + data[i].close * data[i].close;
    }

    final mid = sum / n;
    // Sample standard deviation: sqrt(variance / (n-1))
    // variance = sumSq/n - mid^2, then variance * n / (n-1)
    final variance = (sumSq - sum * sum / n) / (n - 1);
    final std = variance > 0 ? sqrt(variance) : 0;

    final upper = mid + k * std;
    final lower = mid - k * std;

    result[i] = result[i].copyWith(
      bollUpper: upper,
      bollMid: mid,
      bollLower: lower,
    );
  }

  return result;
}

List<HistoryKline> calcEMA(List<HistoryKline> data, List<int> periods) {
  if (data.isEmpty) return data;

  final result = List<HistoryKline>.from(data);

  for (final period in periods) {
    final k = 2.0 / (period + 1);
    double ema = data[0].close;

    for (int i = 0; i < data.length; i++) {
      if (i == 0) {
        ema = data[0].close;
      } else {
        ema = k * data[i].close + (1 - k) * ema;
      }

      switch (period) {
        case 5:
          result[i] = result[i].copyWith(ema5: ema);
          break;
        case 10:
          result[i] = result[i].copyWith(ema10: ema);
          break;
        case 20:
          result[i] = result[i].copyWith(ema20: ema);
          break;
        case 60:
          result[i] = result[i].copyWith(ema60: ema);
          break;
      }
    }
  }

  return result;
}

List<HistoryKline> calcATR(List<HistoryKline> data, {int period = 14}) {
  if (data.length < 2) return data;

  final result = List<HistoryKline>.from(data);

  final List<double> tr = List.filled(data.length, 0);
  tr[0] = data[0].high - data[0].low;
  for (int i = 1; i < data.length; i++) {
    final hl = data[i].high - data[i].low;
    final hc = (data[i].high - data[i - 1].close).abs();
    final lc = (data[i].low - data[i - 1].close).abs();
    tr[i] = [hl, hc, lc].reduce((a, b) => a > b ? a : b);
  }

  if (data.length < period) return result;

  double atr = 0;
  for (int i = 0; i < period; i++) {
    atr += tr[i];
  }
  atr /= period;

  for (int i = 0; i < data.length; i++) {
    if (i < period - 1) {
      result[i] = result[i].copyWith(atr14: 0);
    } else if (i == period - 1) {
      result[i] = result[i].copyWith(atr14: atr);
    } else {
      atr = (atr * (period - 1) + tr[i]) / period;
      result[i] = result[i].copyWith(atr14: atr);
    }
  }

  return result;
}

List<HistoryKline> calcOBV(List<HistoryKline> data) {
  if (data.isEmpty) return data;

  final result = List<HistoryKline>.from(data);

  double obv = 0;
  for (int i = 0; i < data.length; i++) {
    if (i == 0) {
      obv = data[i].volume;
    } else if (data[i].close > data[i - 1].close) {
      obv += data[i].volume;
    } else if (data[i].close < data[i - 1].close) {
      obv -= data[i].volume;
    }
    result[i] = result[i].copyWith(obv: obv);
  }

  return result;
}

List<HistoryKline> calcBIAS(List<HistoryKline> data, List<int> periods) {
  if (data.isEmpty) return data;

  final result = List<HistoryKline>.from(data);

  for (final period in periods) {
    for (int i = period - 1; i < data.length; i++) {
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += data[j].close;
      }
      final ma = sum / period;
      final bias = ma > 0 ? (data[i].close - ma) / ma * 100 : 0;

      switch (period) {
        case 6:
          result[i] = result[i].copyWith(bias6: bias.toDouble());
          break;
        case 12:
          result[i] = result[i].copyWith(bias12: bias.toDouble());
          break;
        case 24:
          result[i] = result[i].copyWith(bias24: bias.toDouble());
          break;
      }
    }
  }

  return result;
}

List<HistoryKline> calcDMI(List<HistoryKline> data, {int period = 14}) {
  if (data.length < period + 1) return data;

  final result = List<HistoryKline>.from(data);

  final List<double> plusDm = List.filled(data.length, 0);
  final List<double> minusDm = List.filled(data.length, 0);
  final List<double> tr = List.filled(data.length, 0);

  for (int i = 1; i < data.length; i++) {
    final upMove = data[i].high - data[i - 1].high;
    final downMove = data[i - 1].low - data[i].low;

    plusDm[i] = (upMove > downMove && upMove > 0) ? upMove : 0;
    minusDm[i] = (downMove > upMove && downMove > 0) ? downMove : 0;

    final hl = data[i].high - data[i].low;
    final hc = (data[i].high - data[i - 1].close).abs();
    final lc = (data[i].low - data[i - 1].close).abs();
    tr[i] = [hl, hc, lc].reduce((a, b) => a > b ? a : b);
  }

  // Smooth using Wilder's method
  double smoothPlusDm = 0;
  double smoothMinusDm = 0;
  double smoothTr = 0;

  for (int i = 1; i <= period && i < data.length; i++) {
    smoothPlusDm += plusDm[i];
    smoothMinusDm += minusDm[i];
    smoothTr += tr[i];
  }

  final List<double> plusDi = List.filled(data.length, 0);
  final List<double> minusDi = List.filled(data.length, 0);
  final List<double> dxList = List.filled(data.length, 0);

  if (data.length > period) {
    plusDi[period] = smoothTr > 0 ? smoothPlusDm / smoothTr * 100 : 0;
    minusDi[period] = smoothTr > 0 ? smoothMinusDm / smoothTr * 100 : 0;
    final diSum = plusDi[period] + minusDi[period];
    dxList[period] = diSum > 0 ? (plusDi[period] - minusDi[period]).abs() / diSum * 100 : 0;

    for (int i = period + 1; i < data.length; i++) {
      smoothPlusDm = smoothPlusDm - smoothPlusDm / period + plusDm[i];
      smoothMinusDm = smoothMinusDm - smoothMinusDm / period + minusDm[i];
      smoothTr = smoothTr - smoothTr / period + tr[i];

      plusDi[i] = smoothTr > 0 ? smoothPlusDm / smoothTr * 100 : 0;
      minusDi[i] = smoothTr > 0 ? smoothMinusDm / smoothTr * 100 : 0;
      final diSum = plusDi[i] + minusDi[i];
      dxList[i] = diSum > 0 ? (plusDi[i] - minusDi[i]).abs() / diSum * 100 : 0;
    }
  }

  // ADX = EMA of DX (Wilder标准方法)
  double adx = 0;
  final initialCount = (2 * period > data.length ? data.length : 2 * period) - period;
  for (int i = period; i < 2 * period && i < data.length; i++) {
    adx += dxList[i];
  }
  if (initialCount > 0) {
    adx /= initialCount;
  }

  for (int i = 0; i < data.length; i++) {
    if (i < period) {
      result[i] = result[i].copyWith(plusDi14: 0, minusDi14: 0, dx: 0, adx14: 0);
    } else if (i < 2 * period) {
      // 预热期：使用初始平均值，不做递推（避免双重计数）
      // P1-1修复：原 i < 2*period-1 导致 i=2*period-1 时进入递推，
      // 而 dxList[2*period-1] 已在种子中，造成双重计数
      result[i] = result[i].copyWith(
        plusDi14: plusDi[i],
        minusDi14: minusDi[i],
        dx: dxList[i],
        adx14: adx,
      );
    } else {
      // 从2*period开始Wilder平滑（第一个递推使用dxList[2*period]，不在种子中）
      adx = (adx * (period - 1) + dxList[i]) / period;
      result[i] = result[i].copyWith(
        plusDi14: plusDi[i],
        minusDi14: minusDi[i],
        dx: dxList[i],
        adx14: adx,
      );
    }
  }

  return result;
}

List<HistoryKline> calcWR(List<HistoryKline> data, {int period = 14}) {
  if (data.length < period) return data;
  final result = List<HistoryKline>.from(data);

  for (int i = period - 1; i < data.length; i++) {
    double highest = data[i].high;
    double lowest = data[i].low;
    for (int j = i - period + 1; j <= i; j++) {
      if (data[j].high > highest) highest = data[j].high;
      if (data[j].low < lowest) lowest = data[j].low;
    }
    final wr = (highest - lowest) > 0 ? (highest - data[i].close) / (highest - lowest) * 100 : 50.0;
    result[i] = result[i].copyWith(wr14: wr);
  }
  return result;
}

List<HistoryKline> calcCCI(List<HistoryKline> data, {int period = 14}) {
  if (data.length < period) return data;
  final result = List<HistoryKline>.from(data);

  for (int i = period - 1; i < data.length; i++) {
    double tpSum = 0;
    for (int j = i - period + 1; j <= i; j++) {
      tpSum += (data[j].high + data[j].low + data[j].close) / 3;
    }
    final tpMa = tpSum / period;

    double md = 0;
    for (int j = i - period + 1; j <= i; j++) {
      final tp = (data[j].high + data[j].low + data[j].close) / 3;
      md += (tp - tpMa).abs();
    }
    md /= period;

    final tp = (data[i].high + data[i].low + data[i].close) / 3;
    final cci = md > 0 ? (tp - tpMa) / (0.015 * md) : 0.0;
    result[i] = result[i].copyWith(cci14: cci);
  }
  return result;
}

List<HistoryKline> calcAllIndicators(List<HistoryKline> data) {
  if (data.isEmpty || data.length < 2) return data;

  var result = calcMA(data, [5, 10, 20, 60]);
  result = calcEMA(result, [5, 10, 20, 60]);
  result = calcMACD(result);
  result = calcRSI(result, [6, 12, 24]);
  result = calcKDJ(result);
  result = calcBOLL(result);
  result = calcVolumeMA(result, [5, 10]);
  result = calcATR(result);
  result = calcOBV(result);
  result = calcBIAS(result, [6, 12, 24]);
  result = calcDMI(result);
  result = calcWR(result);
  result = calcCCI(result);

  return result;
}

Map<String, dynamic> getIndicatorSummary(List<HistoryKline> data) {
  if (data.isEmpty || data.length < 2) return {};

  final last = data[data.length - 1];
  final prev = data[data.length - 2];
  final summary = <String, dynamic>{};

  if (last.ma5 > 0) {
    final maPos = <String>[];
    for (final p in [5, 10, 20, 60]) {
      final maValue = _getMAValue(last, p);
      if (maValue > 0) {
        maPos.add(last.close > maValue ? 'MA$p上方' : 'MA$p下方');
      }
    }
    if (maPos.isNotEmpty) {
      summary['均线位置'] = maPos.join('、');
    }

    final ma5AboveMa10 = last.ma5 > last.ma10;
    final prevMa5AboveMa10 = prev.ma5 > prev.ma10;

    if (ma5AboveMa10 && !prevMa5AboveMa10) {
      summary['均线信号'] = '金叉（MA5上穿MA10）';
    } else if (!ma5AboveMa10 && prevMa5AboveMa10) {
      summary['均线信号'] = '死叉（MA5下穿MA10）';
    } else if (ma5AboveMa10) {
      summary['均线信号'] = '多头排列';
    } else {
      summary['均线信号'] = '空头排列';
    }
  }

  if (last.macdDif != 0) {
    summary['DIF'] = double.parse(last.macdDif.toStringAsFixed(4));
    summary['DEA'] = double.parse(last.macdDea.toStringAsFixed(4));
    summary['MACD柱'] = double.parse(last.macdHist.toStringAsFixed(4));

    if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDea) {
      summary['MACD信号'] = '金叉';
    } else if (last.macdDif < last.macdDea && prev.macdDif >= prev.macdDea) {
      summary['MACD信号'] = '死叉';
    } else if (last.macdHist > prev.macdHist && last.macdHist < 0) {
      summary['MACD信号'] = '绿柱缩短（偏多）';
    } else if (last.macdHist < prev.macdHist && last.macdHist > 0) {
      summary['MACD信号'] = '红柱缩短（偏空）';
    } else if (last.macdHist > 0) {
      summary['MACD信号'] = '红柱运行（多头）';
    } else {
      summary['MACD信号'] = '绿柱运行（空头）';
    }
  }

  if (last.rsi6 > 0) {
    summary['RSI6'] = double.parse(last.rsi6.toStringAsFixed(2));
    summary['RSI12'] = double.parse(last.rsi12.toStringAsFixed(2));
    summary['RSI24'] = double.parse(last.rsi24.toStringAsFixed(2));

    if (last.rsi6 > 80) {
      summary['RSI信号'] = '超买（>80）';
    } else if (last.rsi6 < 20) {
      summary['RSI信号'] = '超卖（<20）';
    } else if (last.rsi6 > 60) {
      summary['RSI信号'] = '偏强';
    } else if (last.rsi6 < 40) {
      summary['RSI信号'] = '偏弱';
    } else {
      summary['RSI信号'] = '中性';
    }
  }

  if (last.k > 0) {
    summary['K'] = double.parse(last.k.toStringAsFixed(2));
    summary['D'] = double.parse(last.d.toStringAsFixed(2));
    summary['J'] = double.parse(last.j.toStringAsFixed(2));

    if (last.k > last.d && prev.k <= prev.d) {
      summary['KDJ信号'] = '金叉';
    } else if (last.k < last.d && prev.k >= prev.d) {
      summary['KDJ信号'] = '死叉';
    } else if (last.j > 100) {
      summary['KDJ信号'] = '超买区（J>100）';
    } else if (last.j < 0) {
      summary['KDJ信号'] = '超卖区（J<0）';
    } else {
      summary['KDJ信号'] = '中性';
    }
  }

  if (last.bollUpper > 0) {
    summary['BOLL上轨'] = double.parse(last.bollUpper.toStringAsFixed(2));
    summary['BOLL中轨'] = double.parse(last.bollMid.toStringAsFixed(2));
    summary['BOLL下轨'] = double.parse(last.bollLower.toStringAsFixed(2));

    final bollWidth = last.bollMid > 0
        ? ((last.bollUpper - last.bollLower) / last.bollMid * 100)
        : 0.0;
    summary['BOLL带宽%'] = double.parse(bollWidth.toStringAsFixed(2));

    if (last.close > last.bollUpper) {
      summary['BOLL信号'] = '突破上轨（强势/超买）';
    } else if (last.close < last.bollLower) {
      summary['BOLL信号'] = '跌破下轨（弱势/超卖）';
    } else if (last.close > last.bollMid) {
      summary['BOLL信号'] = '中轨上方（偏多）';
    } else {
      summary['BOLL信号'] = '中轨下方（偏空）';
    }
  }

  if (last.ema5 > 0) {
    summary['EMA5'] = double.parse(last.ema5.toStringAsFixed(2));
    summary['EMA10'] = double.parse(last.ema10.toStringAsFixed(2));
    summary['EMA20'] = double.parse(last.ema20.toStringAsFixed(2));
  }

  if (last.atr14 > 0) {
    summary['ATR14'] = double.parse(last.atr14.toStringAsFixed(2));
  }

  if (last.bias6 != 0) {
    summary['BIAS6'] = double.parse(last.bias6.toStringAsFixed(2));
    summary['BIAS12'] = double.parse(last.bias12.toStringAsFixed(2));
    summary['BIAS24'] = double.parse(last.bias24.toStringAsFixed(2));
  }

  if (last.adx14 > 0) {
    summary['+DI14'] = double.parse(last.plusDi14.toStringAsFixed(2));
    summary['-DI14'] = double.parse(last.minusDi14.toStringAsFixed(2));
    summary['ADX14'] = double.parse(last.adx14.toStringAsFixed(2));
    if (last.adx14 > 25) {
      summary['ADX信号'] = '趋势明确(ADX=${last.adx14.toStringAsFixed(1)})';
    } else if (last.adx14 < 20) {
      summary['ADX信号'] = '盘整区间(ADX=${last.adx14.toStringAsFixed(1)})';
    } else {
      summary['ADX信号'] = '趋势形成中(ADX=${last.adx14.toStringAsFixed(1)})';
    }
  }

  if (last.wr14 != null) {
    summary['WR14'] = double.parse(last.wr14!.toStringAsFixed(2));
    if (last.wr14! > 80) {
      summary['WR信号'] = '超卖(WR=${last.wr14!.toStringAsFixed(1)})';
    } else if (last.wr14! < 20) {
      summary['WR信号'] = '超买(WR=${last.wr14!.toStringAsFixed(1)})';
    } else {
      summary['WR信号'] = '中性(WR=${last.wr14!.toStringAsFixed(1)})';
    }
  }

  if (last.cci14 != null && last.cci14!.abs() > 0) {
    summary['CCI14'] = double.parse(last.cci14!.toStringAsFixed(2));
    if (last.cci14! > 100) {
      summary['CCI信号'] = '超买(CCI=${last.cci14!.toStringAsFixed(1)})';
    } else if (last.cci14! < -100) {
      summary['CCI信号'] = '超卖(CCI=${last.cci14!.toStringAsFixed(1)})';
    } else {
      summary['CCI信号'] = '中性(CCI=${last.cci14!.toStringAsFixed(1)})';
    }
  }

  return summary;
}

double _getMAValue(HistoryKline kline, int period) {
  switch (period) {
    case 5:
      return kline.ma5;
    case 10:
      return kline.ma10;
    case 20:
      return kline.ma20;
    case 60:
      return kline.ma60;
    default:
      return 0;
  }
}

Map<String, dynamic> calcSupportResistance(List<HistoryKline> data, {int window = 20}) {
  if (data.length < window) return {};

  final current = data.last.close;
  final searchLen = data.length > 60 ? 60 : data.length;
  final recent = data.sublist(data.length - searchLen);

  final allHighs = <double>[];
  final allLows = <double>[];

  for (int i = 2; i < recent.length - 2; i++) {
    final d = recent[i];
    final prev1 = recent[i - 1];
    final prev2 = recent[i - 2];
    final next1 = recent[i + 1];
    final next2 = recent[i + 2];

    if (d.high > prev1.high && d.high > prev2.high && d.high > next1.high && d.high > next2.high) {
      allHighs.add(d.high);
    }

    if (d.low < prev1.low && d.low < prev2.low && d.low < next1.low && d.low < next2.low) {
      allLows.add(d.low);
    }
  }

  // 阻力位：仅保留高于当前价的水平，按升序排列（最近的在前）
  final resistance = allHighs.where((h) => h > current).toList()..sort();
  // 支撑位：仅保留低于当前价的水平，按降序排列（最近的在前）
  final support = allLows.where((l) => l < current).toList()..sort((a, b) => b.compareTo(a));

  final resistanceResult = resistance.length > 3 ? resistance.sublist(0, 3) : resistance;
  final supportResult = support.length > 3 ? support.sublist(0, 3) : support;

  // 兜底：如果找不到阻力位（股价创区间新高），用区间最高点作为参考
  if (resistanceResult.isEmpty && allHighs.isNotEmpty) {
    final maxHigh = allHighs.reduce((a, b) => a > b ? a : b);
    if (maxHigh > 0) resistanceResult.add(maxHigh);
  }
  // 兜底：如果找不到支撑位（股价创区间新低），用区间最低点作为参考
  if (supportResult.isEmpty && allLows.isNotEmpty) {
    final minLow = allLows.reduce((a, b) => a < b ? a : b);
    if (minLow > 0) supportResult.add(minLow);
  }

  final result = <String, dynamic>{
    'resistance': resistanceResult,
    'support': supportResult,
    'current_price': current,
  };

  if (resistanceResult.isNotEmpty) {
    result['nearest_resistance'] = resistanceResult.first;
  }
  if (supportResult.isNotEmpty) {
    result['nearest_support'] = supportResult.first;
  }

  return result;
}

Map<String, dynamic> calcFibonacci(List<HistoryKline> data, {int window = 20}) {
  if (data.length < window) return {};

  final recent = data.sublist(data.length - window);
  final swingLow = recent.map((d) => d.low).reduce((a, b) => a < b ? a : b);
  final swingHigh = recent.map((d) => d.high).reduce((a, b) => a > b ? a : b);

  // 计算斐波那契回撤位（从高到低）
  final levels = <String, double>{};
  const ratios = [0.236, 0.382, 0.5, 0.618, 0.786];
  for (final ratio in ratios) {
    // 回撤位 = 高点 - (高点-低点) * ratio
    levels['${(ratio * 100).toStringAsFixed(1)}%'] = swingHigh - (swingHigh - swingLow) * ratio;
  }

  // 判断当前位置（从高到低检查）
  String currentPosition = '无';
  final currentPrice = data.last.close;
  
  // 如果价格高于所有回撤位
  if (currentPrice >= swingHigh) {
    currentPosition = '突破新高';
  } 
  // 如果价格低于所有回撤位
  else if (currentPrice <= swingLow) {
    currentPosition = '跌破新低';
  }
  // 在区间内，找到具体位置
  else {
    for (int i = 0; i < ratios.length; i++) {
      final ratio = ratios[i];
      final levelPrice = swingHigh - (swingHigh - swingLow) * ratio;
      
      if (i == 0 && currentPrice >= levelPrice) {
        // 价格高于23.6%线
        currentPosition = '23.6%阻力位上方';
        break;
      } else if (i < ratios.length - 1) {
        // 检查是否在两个回撤位之间
        final nextRatio = ratios[i + 1];
        final nextLevelPrice = swingHigh - (swingHigh - swingLow) * nextRatio;
        
        if (currentPrice >= nextLevelPrice && currentPrice < levelPrice) {
          // 判断是支撑还是阻力
          final midPoint = (levelPrice + nextLevelPrice) / 2;
          if (currentPrice >= midPoint) {
            currentPosition = '${(nextRatio * 100).toStringAsFixed(1)}%阻力位附近';
          } else {
            currentPosition = '${(ratio * 100).toStringAsFixed(1)}%支撑位附近';
          }
          break;
        }
      } else if (i == ratios.length - 1 && currentPrice < levelPrice) {
        // 价格低于78.6%线
        currentPosition = '78.6%支撑位下方';
        break;
      }
    }
  }

  return {
    'swing_high': swingHigh,
    'swing_low': swingLow,
    'levels': levels,
    'current_position': currentPosition,
  };
}

Map<String, dynamic> detectDragonRetreat(List<HistoryKline> data) {
  if (data.length < 20) return {'found': false};

  final recent20 = data.sublist(data.length - 20);
  final low20 = recent20.map((d) => d.low).reduce((a, b) => a < b ? a : b);
  final high20 = recent20.map((d) => d.high).reduce((a, b) => a > b ? a : b);
  final risePct = (high20 - low20) / low20 * 100;

  if (risePct < 15) return {'found': false};

  int peakIdx = 0;
  double peakHigh = recent20[0].high;
  for (int i = 1; i < recent20.length; i++) {
    if (recent20[i].high > peakHigh) {
      peakHigh = recent20[i].high;
      peakIdx = i;
    }
  }

  final afterPeak = data.sublist(data.length - 20 + peakIdx + 1);
  if (afterPeak.isEmpty) return {'found': false};

  final pullbackLow = afterPeak.map((d) => d.low).reduce((a, b) => a < b ? a : b);
  final peakPrice = peakHigh;
  final pullbackPct = (peakPrice - pullbackLow) / peakPrice * 100;

  if (pullbackPct < 10 || pullbackPct > 40) return {'found': false};

  int pullbackDays = 0;
  for (final d in afterPeak) {
    if (d.low <= pullbackLow) pullbackDays++;
  }
  if (pullbackDays < 3 || pullbackDays > 10) return {'found': false};

  final last = data.last;

  final peakCloseIdx = data.length - 20 + peakIdx;
  final peakClose = peakCloseIdx >= 0 && peakCloseIdx < data.length ? data[peakCloseIdx].close : peakPrice;
  if (last.close <= peakClose * 0.95) return {'found': false};

  final pullbackVolAvg = afterPeak.map((d) => d.volume).reduce((a, b) => a + b) / afterPeak.length;
  if (pullbackVolAvg > 0 && last.volume < pullbackVolAvg * 1.5) return {'found': false};

  if (last.close <= pullbackLow * 1.03) return {'found': false};

  String level;
  if (pullbackPct >= 20 && last.volume > pullbackVolAvg * 2) {
    level = '强势';
  } else if (pullbackPct >= 15 && last.volume > pullbackVolAvg * 1.5) {
    level = '一般';
  } else {
    level = '弱势';
  }

  return {
    'found': true,
    'level': level,
    'start_index': data.length - 20,
    'peak_index': data.length - 20 + peakIdx,
    'pullback_pct': double.parse(pullbackPct.toStringAsFixed(2)),
  };
}

Map<String, dynamic> detectTrendSignals(List<HistoryKline> data) {
  if (data.length < 20) return {'stabilization': <String>[], 'top': <String>[], 'bottom': <String>[]};

  final last = data.last;
  final prev = data[data.length - 2];
  final prevPrev = data[data.length - 3];

  final result = <String, dynamic>{
    'stabilization': <String>[],
    'top': <String>[],
    'bottom': <String>[],
  };

  final body = (last.open - last.close).abs().toDouble();
  final bodyValue = body == 0 ? 0.01 : body;

  if (prev.close < prev.open && last.close > last.open) {
    result['stabilization'].add('止跌阳线');
  }

  if (last.volMa5 > 0 && prev.volMa5 > 0) {
    if (last.volume > prev.volume && prev.volume > prevPrev.volume
          && last.close > prev.close) {
      result['stabilization'].add('放量反弹');
    }
  }

  for (final ma in [5, 10]) {
    final maValue = ma == 5 ? last.ma5 : last.ma10;
    if (maValue > 0 && (last.close - maValue).abs() / maValue < 0.01 && last.close > last.open) {
      result['stabilization'].add('回踩MA$ma企稳');
    }
  }

  if (data[data.length - 3].rsi6 < 30 && last.rsi6 > 35) {
    result['stabilization'].add('RSI超卖回升');
  }

  final upperShadow = last.high - (last.open > last.close ? last.open : last.close);
  if (upperShadow >= 2 * bodyValue && last.ma5 > 0 && last.close > last.ma5) {
    result['top'].add('高位长上影线');
  }

  if (last.volMa5 > 0) {
    if (last.volume > last.volMa5 * 1.5 && last.high < prev.high && last.close < (last.high + last.low) / 2) {
      result['top'].add('高位放量滞涨');
    }
  }

  // MACD顶背离检测：找过去20天的前一个价格高点，比较两个高点的价格与MACD
  // 真正的顶背离：价格创新高，但MACD没有创新高（两个高点之间的趋势比较）
  if (last.macdHist != 0 && data.length >= 20) {
    // 找过去20天（不含最近3天）的最高价位置作为前一个高点
    int prevPeakIndex = -1;
    double prevPeakHigh = -double.infinity;
    final int searchStart = data.length - 20 < 0 ? 0 : data.length - 20;
    for (int i = searchStart; i < data.length - 3; i++) {
      if (data[i].high > prevPeakHigh) {
        prevPeakHigh = data[i].high;
        prevPeakIndex = i;
      }
    }
    // 当前价格创新高（超过前一个高点），但MACD低于前一个高点 → 顶背离
    if (prevPeakIndex >= 0 &&
        last.high > prevPeakHigh &&
        last.macdHist < data[prevPeakIndex].macdHist) {
      result['top'].add('MACD顶背离');
    }
  }

  final lowerShadow = (last.open < last.close ? last.open : last.close) - last.low;
  if (lowerShadow >= 2 * bodyValue && last.ma5 > 0 && last.close < last.ma5) {
    result['bottom'].add('低位长下影线');
  }

  if (last.volMa5 > 0) {
    if (last.volume > last.volMa5 * 1.2 && prev.volume < last.volMa5 * 0.8 && last.close > last.open) {
      result['bottom'].add('放量止跌');
    }
  }

  if (data[data.length - 3].k < 20 && last.k > last.d && prev.k <= prev.d) {
    result['bottom'].add('KDJ超卖金叉');
  }

  if (last.close < prev.close && last.volMa5 > 0 && last.volume < last.volMa5 * 0.7) {
    result['bottom'].add('价跌量缩（空头衰竭）');
  }

  return result;
}
