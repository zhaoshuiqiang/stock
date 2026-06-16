import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('沪电股份(002463) 详细分析调试', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    tearDown(() {
      apiClient.dispose();
    });

    test('002463 全量分析输出', () async {
      const code = 'sz002463';
      const name = '沪电股份';

      // 1. 获取120天K线数据
      print('\n========== 1. 获取K线数据 ==========');
      final rawKlines = await apiClient.getStockHistory(code, days: 120);
      print('K线数据条数: ${rawKlines.length}');
      if (rawKlines.isNotEmpty) {
        final first = rawKlines.first;
        final last = rawKlines.last;
        print('首日: ${first.date} open=${first.open} close=${first.close} vol=${first.volume}');
        print('末日: ${last.date} open=${last.open} close=${last.close} vol=${last.volume}');
      }

      // 2. 获取实时行情
      print('\n========== 2. 获取实时行情 ==========');
      final quote = await apiClient.getRealtimeQuote(code);
      if (quote != null) {
        print('名称: ${quote.name}');
        print('现价: ${quote.price}');
        print('涨跌: ${quote.change} (${quote.changePct.toStringAsFixed(2)}%)');
        print('开盘: ${quote.open}  最高: ${quote.high}  最低: ${quote.low}');
        print('昨收: ${quote.preClose}');
        print('成交量: ${quote.volume}  成交额: ${quote.amount}');
        print('振幅: ${quote.amplitude.toStringAsFixed(2)}%');
        print('换手率: ${quote.turnover.toStringAsFixed(2)}%');
        print('PE: ${quote.pe.toStringAsFixed(2)}  PB: ${quote.pb.toStringAsFixed(2)}');
        print('总市值: ${(quote.totalMarketCap / 1e8).toStringAsFixed(2)}亿');
        print('流通市值: ${(quote.circulatingMarketCap / 1e8).toStringAsFixed(2)}亿');
        print('主力净流入: ${quote.mainNetFlow}');
        print('主力净流入率: ${quote.mainNetFlowRate.toStringAsFixed(2)}%');
        print('数据置信度: ${quote.confidence}');
      } else {
        print('实时行情获取失败!');
      }

      // 3. 获取主力资金流向
      print('\n========== 3. 获取主力资金 ==========');
      final fundFlow = await apiClient.getMainFundFlow(code);
      if (fundFlow != null) {
        print('主力流入: ${fundFlow.mainInflow}');
        print('主力流出: ${fundFlow.mainOutflow}');
        print('主力净流入: ${fundFlow.mainNetFlow}');
        print('主力净流入率: ${fundFlow.mainNetFlowRate.toStringAsFixed(2)}%');
        // 合并到quote
        if (quote != null) {
          quote.mainInflow = fundFlow.mainInflow;
          quote.mainOutflow = fundFlow.mainOutflow;
          quote.mainNetFlow = fundFlow.mainNetFlow;
          quote.mainNetFlowRate = fundFlow.mainNetFlowRate;
        }
      } else {
        print('主力资金数据获取失败');
      }

      // 4. 获取市场情绪
      print('\n========== 4. 获取市场情绪 ==========');
      final sentiment = await apiClient.getMarketSentiment();
      if (sentiment != null) {
        print('上涨家数: ${sentiment.upCount}');
        print('下跌家数: ${sentiment.downCount}');
        print('平盘家数: ${sentiment.flatCount}');
        print('平均涨跌幅: ${sentiment.avgChangePct.toStringAsFixed(2)}%');
        print('总成交额: ${sentiment.totalAmountYi.toStringAsFixed(2)}亿');
      }

      // 5. 获取个股新闻
      print('\n========== 5. 获取个股新闻 ==========');
      final newsList = await apiClient.getStockNews(name);
      print('新闻条数: ${newsList.length}');
      for (int i = 0; i < newsList.length && i < 5; i++) {
        final news = newsList[i];
        print('  [$i] ${news['showTime']} - ${news['title']}');
      }

      // 6. 构建MarketContext
      MarketContext? marketContext;
      if (sentiment != null) {
        marketContext = MarketContext(
          shIndexPct: 0,
          szIndexPct: 0,
          indexChange: 0,
          marketTrend: sentiment.avgChangePct > 0.5
              ? 'up'
              : sentiment.avgChangePct < -0.5
                  ? 'down'
                  : 'neutral',
          upCount: sentiment.upCount,
          downCount: sentiment.downCount,
          avgChangePct: sentiment.avgChangePct,
          updateTime: DateTime.now(),
        );
      }

      // 7. 计算技术指标
      print('\n========== 6. 计算技术指标 ==========');
      final calculated = calcAllIndicators(rawKlines);
      if (calculated.isNotEmpty) {
        final last = calculated.last;
        print('MA5=${last.ma5.toStringAsFixed(2)} MA10=${last.ma10.toStringAsFixed(2)} MA20=${last.ma20.toStringAsFixed(2)} MA60=${last.ma60.toStringAsFixed(2)}');
        print('EMA5=${last.ema5.toStringAsFixed(2)} EMA10=${last.ema10.toStringAsFixed(2)} EMA20=${last.ema20.toStringAsFixed(2)}');
        print('MACD: DIF=${last.macdDif.toStringAsFixed(4)} DEA=${last.macdDea.toStringAsFixed(4)} HIST=${last.macdHist.toStringAsFixed(4)}');
        print('RSI: RSI6=${last.rsi6.toStringAsFixed(2)} RSI12=${last.rsi12.toStringAsFixed(2)} RSI24=${last.rsi24.toStringAsFixed(2)}');
        print('KDJ: K=${last.k.toStringAsFixed(2)} D=${last.d.toStringAsFixed(2)} J=${last.j.toStringAsFixed(2)}');
        print('BOLL: Upper=${last.bollUpper.toStringAsFixed(2)} Mid=${last.bollMid.toStringAsFixed(2)} Lower=${last.bollLower.toStringAsFixed(2)}');
        print('ATR14=${last.atr14.toStringAsFixed(2)} OBV=${last.obv.toStringAsFixed(2)}');
        print('BIAS: BIAS6=${last.bias6.toStringAsFixed(2)} BIAS12=${last.bias12.toStringAsFixed(2)} BIAS24=${last.bias24.toStringAsFixed(2)}');
        print('DMI: +DI14=${last.plusDi14.toStringAsFixed(2)} -DI14=${last.minusDi14.toStringAsFixed(2)} ADX14=${last.adx14.toStringAsFixed(2)}');
        print('WR14=${last.wr14?.toStringAsFixed(2)} CCI14=${last.cci14?.toStringAsFixed(2)}');
        print('VOL_MA5=${last.volMa5.toStringAsFixed(2)} VOL_MA10=${last.volMa10.toStringAsFixed(2)}');
      }

      // 8. 运行分析
      print('\n========== 7. 运行 generateAnalysis ==========');
      final analysis = generateAnalysis(
        calculated,
        quote,
        marketContext: marketContext,
        newsList: newsList,
      );

      // 9. 输出完整分析结果
      print('\n========== 8. 完整分析结果 ==========');
      print('--- 基础评分 ---');
      print('综合评分: ${analysis.score} / 10');
      print('推荐操作: ${analysis.recommendation}');
      print('风险等级: ${analysis.riskLevel}');
      print('置信度: ${analysis.confidenceScore.toStringAsFixed(4)}');

      print('\n--- 风险因素 ---');
      for (int i = 0; i < analysis.riskFactors.length; i++) {
        print('  [$i] ${analysis.riskFactors[i]}');
      }
      if (analysis.riskFactors.isEmpty) {
        print('  (无)');
      }

      print('\n--- 操作建议 ---');
      for (int i = 0; i < analysis.suggestions.length; i++) {
        print('  [$i] ${analysis.suggestions[i]}');
      }

      print('\n--- 推荐理由 ---');
      for (int i = 0; i < analysis.reasons.length; i++) {
        print('  [$i] ${analysis.reasons[i]}');
      }

      print('\n--- 共振评分 ---');
      print('confluenceScore: ${analysis.confluenceScore}');
      print('confluenceDetails:');
      for (final detail in analysis.confluenceDetails) {
        print('  $detail');
      }

      print('\n--- 信号列表 (共${analysis.signals.length}个) ---');
      final buySignals = analysis.signals.where((s) => s.type == 'buy').toList();
      final sellSignals = analysis.signals.where((s) => s.type == 'sell').toList();
      print('买入信号: ${buySignals.length}个');
      print('卖出信号: ${sellSignals.length}个');
      for (int i = 0; i < analysis.signals.length; i++) {
        final s = analysis.signals[i];
        print('  [$i] type=${s.type} indicator=${s.indicator} signal=${s.signal}');
        print('       desc=${s.description} strength=${s.strength}');
        print('       duration=${s.duration} confidence=${s.confidence} signalCount=${s.signalCount}');
      }

      print('\n--- 基本面评分 ---');
      final fs = analysis.fundamentalScore;
      if (fs != null) {
        print('估值评分(0-10): ${fs.valuationScore.toStringAsFixed(2)}');
        print('资金评分(0-10): ${fs.capitalFlowScore.toStringAsFixed(2)}');
        print('流动性评分(0-10): ${fs.liquidityScore.toStringAsFixed(2)}');
        print('总评分(0-10): ${fs.totalScore.toStringAsFixed(2)}');
        print('评分因素:');
        for (final f in fs.factors) {
          print('  - $f');
        }
      } else {
        print('(无基本面评分)');
      }

      print('\n--- 新闻情绪 ---');
      final ns = analysis.newsSentiment;
      if (ns != null) {
        print('情绪评分(-10~+10): ${ns.score.toStringAsFixed(2)}');
        print('情绪方向: ${ns.direction}');
        print('利好: ${ns.positiveCount}  利空: ${ns.negativeCount}  中性: ${ns.neutralCount}');
        print('关键因素:');
        for (final f in ns.keyFactors) {
          print('  - $f');
        }
      } else {
        print('(无新闻情绪)');
      }

      print('\n--- 置信度分项明细 ---');
      final cb = analysis.confidenceBreakdown;
      if (cb != null && cb.isNotEmpty) {
        for (final entry in cb.entries) {
          print('  ${entry.key}: ${entry.value.toStringAsFixed(4)}');
        }
      } else {
        print('(无置信度分项)');
      }

      print('\n--- 对抗验证信号 ---');
      final vs = analysis.validatedSignals;
      if (vs != null && vs.isNotEmpty) {
        for (int i = 0; i < vs.length; i++) {
          final v = vs[i];
          print('  [$i] signal=${v.signal.signal} type=${v.signal.type}');
          print('       adjustedConfidence=${v.adjustedConfidence.toStringAsFixed(4)}');
          print('       counterPoints:');
          for (final cp in v.counterPoints) {
            print('         - $cp');
          }
        }
      } else {
        print('(无对抗验证信号)');
      }

      print('\n--- 详细推荐理由 ---');
      for (int i = 0; i < analysis.detailedReasons.length; i++) {
        final r = analysis.detailedReasons[i];
        print('  [$i] ${r.title}');
        print('       ${r.description}');
        print('       confidence=${r.confidence.toStringAsFixed(4)} duration=${r.duration}');
      }

      print('\n--- 回测结果 ---');
      final br = analysis.backtestResults;
      if (br != null && br.isNotEmpty) {
        for (final entry in br.entries) {
          print('  ${entry.key}:');
          final bt = entry.value;
          print('    胜率=${bt.winRate.toStringAsFixed(2)}% 平均盈利=${bt.avgWinPct.toStringAsFixed(2)}% 平均亏损=${bt.avgLossPct.toStringAsFixed(2)}% 总信号=${bt.totalSignals}');
        }
      } else {
        print('(无回测结果)');
      }

      print('\n--- 指标摘要 ---');
      final ind = analysis.indicators;
      for (final entry in ind.entries) {
        print('  ${entry.key}: ${entry.value}');
      }

      print('\n========== 分析完成 ==========');

      expect(calculated, isNotEmpty, reason: 'K线数据不应为空');
      expect(analysis.score, greaterThan(0), reason: '评分应大于0');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
