import '../models/stock_models.dart';
import 'indicators.dart';

/// 回测结果
class BacktestResult {
  final int totalSignals;      // 总信号数
  final int winningTrades;     // 盈利交易数
  final int losingTrades;      // 亏损交易数
  final double winRate;        // 胜率
  final double avgWinPct;      // 平均盈利百分比
  final double avgLossPct;     // 平均亏损百分比
  final double profitFactor;   // 盈亏比
  final double maxDrawdown;    // 最大回撤
  final double totalReturn;    // 总收益率
  final List<double> tradeReturns; // 每笔交易收益率

  BacktestResult({
    required this.totalSignals,
    required this.winningTrades,
    required this.losingTrades,
    required this.winRate,
    required this.avgWinPct,
    required this.avgLossPct,
    required this.profitFactor,
    required this.maxDrawdown,
    required this.totalReturn,
    required this.tradeReturns,
  });
}

/// 策略回测引擎
class BacktestEngine {
  /// 金叉买入/死叉卖出回测
  /// 
  /// 规则：
  /// - MACD金叉（DIF上穿DEA）且无持仓时买入
  /// - MACD死叉（DIF下穿DEA）且有持仓时卖出
  /// - 不考虑交易成本
  static BacktestResult backtestMACDCross(List<HistoryKline> data) {
    if (data.length < 60) {
      return BacktestResult(
        totalSignals: 0, winningTrades: 0, losingTrades: 0,
        winRate: 0, avgWinPct: 0, avgLossPct: 0, profitFactor: 0,
        maxDrawdown: 0, totalReturn: 0, tradeReturns: [],
      );
    }

    // 确保指标已计算
    final calcData = calcMACD(List<HistoryKline>.from(data));

    final tradeReturns = <double>[];
    double? buyPrice;
    int totalSignals = 0;
    double peakEquity = 1.0;
    double currentEquity = 1.0;
    double maxDrawdown = 0;

    for (int i = 1; i < calcData.length; i++) {
      final prev = calcData[i - 1];
      final curr = calcData[i];

      // MACD金叉买入信号
      if (curr.macdDif > curr.macdDea && prev.macdDif <= prev.macdDea && buyPrice == null) {
        buyPrice = curr.close;
        totalSignals++;
      }
      // MACD死叉卖出信号
      else if (curr.macdDif < curr.macdDea && prev.macdDif >= prev.macdDea && buyPrice != null) {
        final sellPrice = curr.close;
        final returnPct = (sellPrice - buyPrice) / buyPrice;
        tradeReturns.add(returnPct);
        
        currentEquity *= (1 + returnPct);
        if (currentEquity > peakEquity) {
          peakEquity = currentEquity;
        }
        final drawdown = (peakEquity - currentEquity) / peakEquity;
        if (drawdown > maxDrawdown) {
          maxDrawdown = drawdown;
        }

        buyPrice = null;
        totalSignals++;
      }
    }

    // 如果还有持仓，按最后收盘价平仓
    if (buyPrice != null) {
      final sellPrice = calcData.last.close;
      final returnPct = (sellPrice - buyPrice) / buyPrice;
      tradeReturns.add(returnPct);
      currentEquity *= (1 + returnPct);
    }

    final winningTrades = tradeReturns.where((r) => r > 0).length;
    final losingTrades = tradeReturns.where((r) => r < 0).length;
    final winRate = tradeReturns.isNotEmpty ? winningTrades / tradeReturns.length : 0.0;

    final wins = tradeReturns.where((r) => r > 0).toList();
    final losses = tradeReturns.where((r) => r < 0).toList();
    final double avgWinPct = wins.isNotEmpty ? wins.reduce((a, b) => a + b) / wins.length.toDouble() * 100 : 0;
    final double avgLossPct = losses.isNotEmpty ? losses.reduce((a, b) => a + b) / losses.length.toDouble() * 100 : 0;
    final double profitFactor = losses.isNotEmpty ? ((wins.isNotEmpty ? wins.reduce((a, b) => a + b) : 0) / losses.map((l) => l.abs()).reduce((a, b) => a + b).toDouble()) : 0;

    return BacktestResult(
      totalSignals: totalSignals,
      winningTrades: winningTrades,
      losingTrades: losingTrades,
      winRate: winRate,
      avgWinPct: avgWinPct,
      avgLossPct: avgLossPct,
      profitFactor: profitFactor,
      maxDrawdown: maxDrawdown,
      totalReturn: (currentEquity - 1) * 100,
      tradeReturns: tradeReturns,
    );
  }

  /// MA5上穿MA10 金叉策略回测
  static BacktestResult backtestMACross(List<HistoryKline> data) {
    if (data.length < 30) {
      return BacktestResult(
        totalSignals: 0, winningTrades: 0, losingTrades: 0,
        winRate: 0, avgWinPct: 0, avgLossPct: 0, profitFactor: 0,
        maxDrawdown: 0, totalReturn: 0, tradeReturns: [],
      );
    }

    final calcData = calcMA(List<HistoryKline>.from(data), [5, 10]);

    final tradeReturns = <double>[];
    double? buyPrice;
    int totalSignals = 0;
    double peakEquity = 1.0;
    double currentEquity = 1.0;
    double maxDrawdown = 0;

    for (int i = 1; i < calcData.length; i++) {
      final prev = calcData[i - 1];
      final curr = calcData[i];

      if (curr.ma5 > curr.ma10 && prev.ma5 <= prev.ma10 && buyPrice == null) {
        buyPrice = curr.close;
        totalSignals++;
      } else if (curr.ma5 < curr.ma10 && prev.ma5 >= prev.ma10 && buyPrice != null) {
        final sellPrice = curr.close;
        final returnPct = (sellPrice - buyPrice) / buyPrice;
        tradeReturns.add(returnPct);
        currentEquity *= (1 + returnPct);
        if (currentEquity > peakEquity) peakEquity = currentEquity;
        final drawdown = (peakEquity - currentEquity) / peakEquity;
        if (drawdown > maxDrawdown) maxDrawdown = drawdown;
        buyPrice = null;
        totalSignals++;
      }
    }

    if (buyPrice != null) {
      final sellPrice = calcData.last.close;
      final returnPct = (sellPrice - buyPrice) / buyPrice;
      tradeReturns.add(returnPct);
      currentEquity *= (1 + returnPct);
    }

    final winningTrades = tradeReturns.where((r) => r > 0).length;
    final losingTrades = tradeReturns.where((r) => r < 0).length;
    final winRate = tradeReturns.isNotEmpty ? winningTrades / tradeReturns.length : 0.0;
    final wins = tradeReturns.where((r) => r > 0).toList();
    final losses = tradeReturns.where((r) => r < 0).toList();
    final double avgWinPct = wins.isNotEmpty ? wins.reduce((a, b) => a + b) / wins.length.toDouble() * 100 : 0;
    final double avgLossPct = losses.isNotEmpty ? losses.reduce((a, b) => a + b) / losses.length.toDouble() * 100 : 0;
    final double profitFactor = losses.isNotEmpty ? (wins.isNotEmpty ? wins.reduce((a, b) => a + b) : 0) / losses.map((l) => l.abs()).reduce((a, b) => a + b).toDouble() : 0;

    return BacktestResult(
      totalSignals: totalSignals,
      winningTrades: winningTrades,
      losingTrades: losingTrades,
      winRate: winRate,
      avgWinPct: avgWinPct,
      avgLossPct: avgLossPct,
      profitFactor: profitFactor,
      maxDrawdown: maxDrawdown,
      totalReturn: (currentEquity - 1) * 100,
      tradeReturns: tradeReturns,
    );
  }

  /// 格式化回测结果为可读文本
  static String formatResult(BacktestResult result) {
    if (result.totalSignals == 0) {
      return '回测数据不足，无法生成有效结果';
    }
    return '信号总数: ${result.totalSignals}\n'
        '胜率: ${(result.winRate * 100).toStringAsFixed(1)}%\n'
        '盈利次数: ${result.winningTrades} | 亏损次数: ${result.losingTrades}\n'
        '平均盈利: ${result.avgWinPct.toStringAsFixed(2)}% | 平均亏损: ${result.avgLossPct.toStringAsFixed(2)}%\n'
        '盈亏比: ${result.profitFactor > 0 ? result.profitFactor.toStringAsFixed(2) : "N/A"}\n'
        '总收益: ${result.totalReturn.toStringAsFixed(2)}%\n'
        '最大回撤: ${(result.maxDrawdown * 100).toStringAsFixed(2)}%';
  }
}