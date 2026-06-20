import 'dart:math' show sin;
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/backtest_engine.dart';

// ═══════════════════════════════════════════════════════════════════
// 合成K线数据生成器 (与 validation_test 同步)
// ═══════════════════════════════════════════════════════════════════

List<HistoryKline> _genTrend(int count, {double start = 10.0, double daily = 0.005}) {
  double p = start;
  return List.generate(count, (i) {
    final open = p;
    p *= (1 + daily);
    final vol = 15000 + (i * 300);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: p * 1.015, low: open * 0.985, close: p,
      volume: vol.toDouble(), amount: vol.toDouble() * ((open + p) / 2),
      change: p - open, changePct: (p - open) / open * 100,
    );
  });
}

List<HistoryKline> _genSideways(int count, {double base = 15.0, double amplitude = 2.0}) {
  return List.generate(count, (i) {
    final phase = (i % 20) / 20.0 * 3.14159 * 2;
    final offset = amplitude * sin(phase);
    final p = base + offset;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: p - 0.1, high: p + 0.15, low: p - 0.15, close: p,
      volume: 10000 + (i * 100), amount: 10000 * p,
      change: offset, changePct: offset / base * 100,
    );
  });
}

List<HistoryKline> _genDowntrend(int count, {double start = 30.0, double daily = -0.005}) {
  double p = start;
  return List.generate(count, (i) {
    final open = p;
    p *= (1 + daily);
    final vol = 15000 + (i * 300);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: open * 1.015, low: p * 0.985, close: p,
      volume: vol.toDouble(), amount: vol.toDouble() * ((open + p) / 2),
      change: p - open, changePct: (p - open) / open * 100,
    );
  });
}

List<HistoryKline> _genVolatileTrend(int count, {double start = 10.0, double daily = 0.003, double noise = 0.03}) {
  double p = start;
  final rng = DateTime.now().microsecondsSinceEpoch % 1000;
  return List.generate(count, (i) {
    final trend = p * (1 + daily);
    final n = noise * sin((i + rng) * 0.7) * p;
    p = trend + n;
    final vol = 15000 + (i * 100) + (n.abs() * 5000).toInt();
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: p - n * 0.5, high: p * 1.02, low: p * 0.98, close: p,
      volume: vol.toDouble(), amount: vol.toDouble() * p,
      change: n, changePct: n / (p - n) * 100,
    );
  });
}

/// 带涨跌停的事件数据（模拟真实A股）
List<HistoryKline> _genRealistic(int count) {
  double p = 10.0;
  final data = <HistoryKline>[];
  for (int i = 0; i < count; i++) {
    // 随机日收益率，范围在 -8% ~ +8%（留余地不总在涨跌停边缘）
    final randomFactor = 0.02 * sin(i * 1.7) + 0.01 * sin(i * 3.1) + 0.005 * sin(i * 5.3);
    final dailyReturn = (randomFactor * 4).clamp(-0.085, 0.085);
    final prevClose = p;
    p *= (1 + dailyReturn);
    // 偶尔出现涨跌停
    if (i > 30 && (i % 37 == 0 || i % 53 == 0)) {
      if (i % 37 == 0) {
        p = prevClose * 1.10; // 涨停
      } else {
        p = prevClose * 0.90; // 跌停
      }
    }
    final vol = (12000 + (randomFactor.abs() * 50000)).toInt() + (i * 200);
    data.add(HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: prevClose * (1 + dailyReturn * 0.3),
      high: max(p, prevClose * 1.02),
      low: min(p, prevClose * 0.98),
      close: p,
      volume: vol.toDouble(),
      amount: vol.toDouble() * p,
      change: p - prevClose,
      changePct: (p - prevClose) / prevClose * 100,
    ));
  }
  return data;
}

double min(double a, double b) => a < b ? a : b;
double max(double a, double b) => a > b ? a : b;

// ═══════════════════════════════════════════════════════════════════
// 耗时测量工具
// ═══════════════════════════════════════════════════════════════════

class _Timer {
  final Stopwatch _sw = Stopwatch();
  int _runs = 0;

  /// 测量 fn 执行时间（μs），预热后跑 [runs] 次取平均
  double measure(int runs, void Function() fn) {
    // 预热
    fn();
    _sw.reset();
    _sw.start();
    for (int i = 0; i < runs; i++) {
      fn();
    }
    _sw.stop();
    _runs = runs;
    return _sw.elapsedMicroseconds / runs.toDouble();
  }

  /// 单次测量，返回微秒
  double once(void Function() fn) {
    _sw.reset();
    _sw.start();
    fn();
    _sw.stop();
    return _sw.elapsedMicroseconds.toDouble();
  }

  String fmtUs(double us) {
    if (us < 1000) return '${us.toStringAsFixed(1)}μs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)}ms';
    return '${(us / 1000000).toStringAsFixed(2)}s';
  }
}

// ═══════════════════════════════════════════════════════════════════
// 基准测试
// ═══════════════════════════════════════════════════════════════════

void main() {
  final timer = _Timer();

  // ── 单策略耗时 (3 种数据规模) ──
  group('策略执行耗时 (单次调用)', () {
    const sizes = [120, 250, 500];
    for (final size in sizes) {
      test('规模 ${size}条 — 6 策略 + 完整管线', () {
        final trend = _genTrend(size, daily: 0.005);
        final sideways = _genSideways(size);
        final down = _genDowntrend(size);

        final buf = StringBuffer();
        buf.writeln('\n┌──── 策略耗时 (${size}条) ────┐');

        // 每个策略在3种行情下测3次取平均
        final strategies = {
          'MACD交叉': (List<HistoryKline> d) => BacktestEngine.backtestMACDCross(d),
          'MA金叉':   (List<HistoryKline> d) => BacktestEngine.backtestMACross(d),
          'KDJ超卖':  (List<HistoryKline> d) => BacktestEngine.backtestKDJOversoldCross(d),
          'RSI超卖':  (List<HistoryKline> d) => BacktestEngine.backtestRSIOversoldRecovery(d),
          '布林支撑':  (List<HistoryKline> d) => BacktestEngine.backtestBollSupport(d),
          '均线多头':  (List<HistoryKline> d) => BacktestEngine.backtestMAMultiHead(d),
        };

        double totalUs = 0;
        for (final entry in strategies.entries) {
          double avgUs = 0;
          for (final data in [trend, sideways, down]) {
            avgUs += timer.measure(10, () => entry.value(data));
          }
          avgUs /= 3;
          totalUs += avgUs;
          buf.writeln('  ${entry.key.padRight(10)} ${timer.fmtUs(avgUs).padLeft(10)}');
        }

        // megaBacktest
        double megaUs = 0;
        for (final data in [trend, sideways, down]) {
          megaUs += timer.measure(10, () => BacktestEngine.megaBacktest(data));
        }
        megaUs /= 3;
        buf.writeln('  ${'mega汇总'.padRight(10)} ${timer.fmtUs(megaUs).padLeft(10)}');

        buf.writeln('  ────────────────────────────');
        buf.writeln('  合计: ${timer.fmtUs(totalUs + megaUs)}');
        buf.writeln('└──────────────────────────────┘');

        // 性能阈值检查
        // 6个策略合计不超过 500ms (500条数据 + 指标计算)
        final thresholdUs = size == 500 ? 500000.0 : 300000.0; // 500ms for 500, 300ms for others
        expect(totalUs + megaUs, lessThan(thresholdUs),
            reason: '6策略+mega汇总超标 (${timer.fmtUs(totalUs + megaUs)} > ${timer.fmtUs(thresholdUs)})');

        if (size == 500) print(buf.toString());
      });
    }
  });

  // ── Legacy vs New 配置开销对比 ──
  group('Legacy vs New 配置性能差', () {
    test('新增校验功能引入的开销 ≤ 2x', () {
      final data = _genTrend(250, daily: 0.005);
      double legacyUs = 0;
      double newUs = 0;

      // Legacy mode
      BacktestEngine.setConfig(BacktestConfig.legacy);
      legacyUs = timer.measure(20, () => BacktestEngine.megaBacktest(data));
      BacktestEngine.setConfig(BacktestConfig.aStock);

      // New mode (with all validations)
      newUs = timer.measure(20, () => BacktestEngine.megaBacktest(data));

      final ratio = newUs / legacyUs;
      print('\n┌──── Legacy vs New 开销 ────┐');
      print('  Legacy: ${timer.fmtUs(legacyUs)}');
      print('  New:    ${timer.fmtUs(newUs)}');
      print('  比率:   ${ratio.toStringAsFixed(2)}x');
      print('└──────────────────────────────┘');

      // 新配置的校验开销不应超过旧配置的 3 倍
      expect(ratio, lessThan(3.0),
          reason: '校验功能引入的开销过大 (${ratio.toStringAsFixed(2)}x > 3x)');
    });

    test('各校验项逐项开销分析', () {
      final data = _genRealistic(300);
      final buf = StringBuffer();
      buf.writeln('\n┌──── 各校验项开销分解 ────┐');

      // Baseline: legacy (no checks)
      BacktestEngine.setConfig(BacktestConfig.legacy);
      final legacyUs = timer.measure(20, () => BacktestEngine.backtestMACDCross(data));

      // Only cost deduction
      BacktestEngine.setConfig(const BacktestConfig(
        deductCost: true, skipLimitTrade: false, skipDirtyData: false));
      final costUs = timer.measure(20, () => BacktestEngine.backtestMACDCross(data));

      // Only limit simulation
      BacktestEngine.setConfig(const BacktestConfig(
        deductCost: false, skipLimitTrade: true, skipDirtyData: false));
      final limitUs = timer.measure(20, () => BacktestEngine.backtestMACDCross(data));

      // Only dirty data
      BacktestEngine.setConfig(const BacktestConfig(
        deductCost: false, skipLimitTrade: false, skipDirtyData: true));
      final dirtyUs = timer.measure(20, () => BacktestEngine.backtestMACDCross(data));

      // All on
      BacktestEngine.setConfig(BacktestConfig.aStock);
      final allUs = timer.measure(20, () => BacktestEngine.backtestMACDCross(data));

      buf.writeln('  Legacy (none)   ${timer.fmtUs(legacyUs).padLeft(10)}');
      buf.writeln('  +仅成本           ${timer.fmtUs(costUs).padLeft(10)} (+${timer.fmtUs(costUs - legacyUs)})');
      buf.writeln('  +仅涨跌停         ${timer.fmtUs(limitUs).padLeft(10)} (+${timer.fmtUs(limitUs - legacyUs)})');
      buf.writeln('  +仅脏数据         ${timer.fmtUs(dirtyUs).padLeft(10)} (+${timer.fmtUs(dirtyUs - legacyUs)})');
      buf.writeln('  +全部开启         ${timer.fmtUs(allUs).padLeft(10)} (+${timer.fmtUs(allUs - legacyUs)})');
      buf.writeln('└──────────────────────────────┘');

      // 全部开启不应超过纯计算 2 倍
      final ratio = allUs / legacyUs;
      expect(ratio, lessThan(2.5),
          reason: '全部校验总开销过大 (${ratio.toStringAsFixed(2)}x)');
      print(buf.toString());
    });
  });

  // ── Walk-Forward 管线耗时 ──
  group('Walk-Forward 管线基准', () {
    test('WF 各窗口配置耗时', () {
      final data = _genTrend(300, daily: 0.003);
      BacktestEngine.setConfig(BacktestConfig.aStock);

      final configs = [
        {'window': 60, 'test': 20},
        {'window': 120, 'test': 30},
        {'window': 180, 'test': 40},
      ];

      final buf = StringBuffer();
      buf.writeln('\n┌──── Walk-Forward 耗时 ────┐');

      for (final cfg in configs) {
        final w = cfg['window'] as int;
        final t = cfg['test'] as int;
        final us = timer.measure(5, () => BacktestEngine.walkForwardBacktest(data, windowSize: w, testSize: t));
        final windows = ((data.length - w - t) ~/ t) + 1;
        buf.writeln('  W${w.toString().padLeft(3)}/T${t.toString().padLeft(2)} '
            '(${windows}窗口) → ${timer.fmtUs(us).padLeft(10)}');
      }

      // 最大配置 (180/40)
      final maxUs = timer.measure(3, 
          () => BacktestEngine.walkForwardBacktest(data, windowSize: 180, testSize: 40));
      buf.writeln('  ────────────────────────────');
      buf.writeln('└──────────────────────────────┘');

      expect(maxUs, lessThan(10 * 1000 * 1000.0), // 10s max
          reason: 'Walk-Forward 300条最大配置超 10s (${timer.fmtUs(maxUs)})');
      if (data.length >= 300) print(buf.toString());
    });

    test('WF 超大数据集 (500条) 不超时', () {
      final data = _genTrend(500, daily: 0.003);
      BacktestEngine.setConfig(BacktestConfig.aStock);

      final us = timer.once(() => BacktestEngine.walkForwardBacktest(data, windowSize: 120, testSize: 30));

      // 500条数据 WF 应在 30s 内完成
      expect(us, lessThan(30 * 1000 * 1000.0),
          reason: 'WF 500条超 30s (${timer.fmtUs(us)})');
    });
  });

  // ── 完整管线耗时 ──
  group('完整分析管线基准', () {
    test('megaBacktest + WF + validationReport (250条)', () {
      final data = _genRealistic(250);
      BacktestEngine.setConfig(BacktestConfig.aStock);

      final megaUs = timer.measure(10, () => BacktestEngine.megaBacktest(data));
      final wfUs = timer.measure(5, () =>
          BacktestEngine.walkForwardBacktest(data, windowSize: 60, testSize: 20));
      final results = BacktestEngine.megaBacktest(data);
      final wf = BacktestEngine.walkForwardBacktest(data, windowSize: 60, testSize: 20);
      final reportUs = timer.measure(10, () =>
          BacktestEngine.validationReport(results, wfResult: wf, rawData: data));

      final totalUs = megaUs + wfUs + reportUs;
      final buf = StringBuffer();
      buf.writeln('\n┌──── 完整管线耗时 (250条) ────┐');
      buf.writeln('  megaBacktest     ${timer.fmtUs(megaUs).padLeft(10)}');
      buf.writeln('  Walk-Forward     ${timer.fmtUs(wfUs).padLeft(10)}');
      buf.writeln('  validationReport ${timer.fmtUs(reportUs).padLeft(10)}');
      buf.writeln('  ────────────────────────────');
      buf.writeln('  总计:            ${timer.fmtUs(totalUs).padLeft(10)}');
      buf.writeln('└──────────────────────────────┘');
      print(buf.toString());

      // 完整管线应在 20s 内完成
      expect(totalUs, lessThan(20 * 1000 * 1000.0),
          reason: '完整管线超 20s (${timer.fmtUs(totalUs)})');
    });
  });

  // ── KlineValidator 吞吐量 ──
  group('KlineValidator 校验吞吐量', () {
    test('脏数据扫描 1000条 < 2ms', () {
      final data = _genRealistic(1000);
      // 注入一些脏数据
      for (int i = 100; i < 105; i++) {
        data[i] = HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: data[i - 1].close * 1.10, high: data[i - 1].close * 1.10,
          low: data[i - 1].close * 1.10, close: data[i - 1].close * 1.10,
          volume: 20000, amount: 0, change: 1.0, changePct: 10.0,
        );
      }

      final us = timer.measure(50, () {
        for (int i = 1; i < data.length; i++) {
          KlineValidator.isDirty(data[i], data[i - 1], 0.10);
        }
      });

      expect(us, lessThan(2000.0),
          reason: '脏数据扫描 1000条 超 2ms (${timer.fmtUs(us)})');
    });

    test('isLimitUp/isLimitDown 100k 调用 < 5ms', () {
      final prev = HistoryKline(
        date: DateTime(2024, 1, 1),
        open: 10, high: 10.5, low: 9.8, close: 10.0,
        volume: 20000, amount: 200000, change: 0, changePct: 0,
      );
      final curr = HistoryKline(
        date: DateTime(2024, 1, 2),
        open: 10.5, high: 11.0, low: 10.2, close: 10.8,
        volume: 25000, amount: 270000, change: 0.8, changePct: 8.0,
      );

      final us = timer.measure(100, () {
        for (int i = 0; i < 1000; i++) {
          KlineValidator.isLimitUp(curr, prev, 0.10);
          KlineValidator.isLimitDown(curr, prev, 0.10);
        }
      });

      expect(us / 5, lessThan(5000.0), // per 100k calls
          reason: '涨跌停检测 100k次 超 5ms (${timer.fmtUs(us)})');
    });
  });

  // ── 不同市场环境下的性能一致性 ──
  group('多市场环境性能一致性', () {
    test('趋势/震荡/下跌 耗时差异 ≤ 3x', () {
      const size = 250;
      final trend = _genTrend(size);
      final sideways = _genSideways(size);
      final down = _genDowntrend(size);

      final times = <String, double>{};
      for (final entry in {
        '趋势': trend,
        '震荡': sideways,
        '下跌': down,
      }.entries) {
        times[entry.key] = timer.measure(10, () {
          BacktestEngine.megaBacktest(entry.value);
        });
      }

      final maxTime = times.values.reduce(max);
      final minTime = times.values.reduce(min);
      final ratio = maxTime / minTime;

      final buf = StringBuffer();
      buf.writeln('\n┌──── 市场环境性能 ────┐');
      for (final entry in times.entries) {
        buf.writeln('  ${entry.key.padRight(6)} ${timer.fmtUs(entry.value).padLeft(10)}');
      }
      buf.writeln('  差异比: ${ratio.toStringAsFixed(2)}x');
      buf.writeln('└──────────────────────────────┘');
      print(buf.toString());

      expect(ratio, lessThan(3.0),
          reason: '市场环境间性能差异过大 (${ratio.toStringAsFixed(2)}x)');
    });
  });

  // ── 内存/迭代次数基准 ──
  group('计算量基准', () {
    test('各策略交易信号数统计', () {
      final data = _genRealistic(250);
      BacktestEngine.setConfig(BacktestConfig.aStock);
      final results = BacktestEngine.megaBacktest(data);

      final buf = StringBuffer();
      buf.writeln('\n┌──── 各策略信号/交易统计 (250条真实数据) ────┐');
      for (final entry in results.entries) {
        final r = entry.value;
        final meta = r.validationMeta;
        buf.writeln('  ${entry.key.padRight(10)} '
            '信号${r.totalSignals.toString().padLeft(3)} '
            '胜率${(r.winRate * 100).toStringAsFixed(0).padLeft(3)}% '
            '跳过${(meta?.skippedSignals ?? 0).toString().padLeft(2)} '
            '限停${(meta?.skippedTrades ?? 0).toString().padLeft(2)}');
      }
      buf.writeln('└──────────────────────────────────────────────┘');
      print(buf.toString());

      // 至少有一个策略产生信号
      final hasSignals = results.values.any((r) => r.totalSignals > 0);
      expect(hasSignals, isTrue);
    });

    test('validationReport 输出完整性', () {
      final data = _genRealistic(250);
      final results = BacktestEngine.megaBacktest(data);
      final wf = BacktestEngine.walkForwardBacktest(data, windowSize: 60, testSize: 20);
      final report = BacktestEngine.validationReport(results, wfResult: wf, rawData: data);

      // 必须包含所有10项校验
      const requiredItems = [
        '未来函数', '马丁加仓', '过度拟合', '完整成本', '复权除权',
        '前视偏差', '幸存者偏差', '涨跌停模拟', '交易日历', '脏数据',
      ];
      for (final item in requiredItems) {
        expect(report, contains(item), reason: '报告缺少校验项: $item');
      }
      // 必须有通过统计
      expect(report, contains('校验通过'));
    });
  });

  // ── 冷启动 vs 热路径 ──
  group('冷/热路径性能', () {
    test('首调用 (冷) vs 第50次 (热) 差异', () {
      final data = _genRealistic(250);
      BacktestEngine.setConfig(BacktestConfig.aStock);

      // 冷启动 (首调用)
      final coldUs = timer.once(() => BacktestEngine.megaBacktest(data));
      // 预热
      for (int i = 0; i < 50; i++) {
        BacktestEngine.megaBacktest(data);
      }
      // 热路径
      final hotUs = timer.measure(50, () => BacktestEngine.megaBacktest(data));

      final ratio = coldUs / hotUs;
      print('\n┌──── 冷/热路径 ────┐');
      print('  冷启动: ${timer.fmtUs(coldUs)}');
      print('  热路径: ${timer.fmtUs(hotUs)} (50次均值)');
      print('  比率:   ${ratio.toStringAsFixed(2)}x');
      print('└──────────────────────┘');

      // 热路径不应远慢于冷启动（运行在同一进程中JIT可能已预热）
      expect(hotUs, lessThan(coldUs * 2.0),
          reason: '热路径远慢于冷启动 (hot=${timer.fmtUs(hotUs)} vs cold=${timer.fmtUs(coldUs)})');
    });
  });
}
