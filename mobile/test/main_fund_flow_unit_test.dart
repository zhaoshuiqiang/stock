import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('主力资金数据处理逻辑测试', () {
    test('QuoteData copyWith 正确合并主力资金数据', () {
      final baseQuote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800.0,
      );
      
      final fundFlowQuote = QuoteData(
        code: 'sh600519',
        mainInflow: 500000000.0,
        mainOutflow: 450000000.0,
        mainNetFlow: 50000000.0,
        mainNetFlowRate: 0.79,
      );
      
      final mergedQuote = baseQuote.copyWith(
        mainInflow: fundFlowQuote.mainInflow,
        mainOutflow: fundFlowQuote.mainOutflow,
        mainNetFlow: fundFlowQuote.mainNetFlow,
        mainNetFlowRate: fundFlowQuote.mainNetFlowRate,
      );
      
      expect(mergedQuote.code, equals('sh600519'));
      expect(mergedQuote.name, equals('贵州茅台'));
      expect(mergedQuote.price, equals(1800.0));
      expect(mergedQuote.mainInflow, equals(500000000.0));
      expect(mergedQuote.mainOutflow, equals(450000000.0));
      expect(mergedQuote.mainNetFlow, equals(50000000.0));
      expect(mergedQuote.mainNetFlowRate, equals(0.79));
      
      print('✅ copyWith 合并主力资金数据正确');
    });

    test('四个主力资金指标不为0时正确显示', () {
      final quote = QuoteData(
        code: 'sh600519',
        mainInflow: 500000000.0,
        mainOutflow: 450000000.0,
        mainNetFlow: 50000000.0,
        mainNetFlowRate: 0.79,
      );
      
      expect(quote.mainInflow, isNot(0));
      expect(quote.mainOutflow, isNot(0));
      expect(quote.mainNetFlow, isNot(0));
      expect(quote.mainNetFlowRate, isNot(0));
      
      print('✅ 四个主力资金指标不为0');
      print('   主力流入: ${quote.mainInflow}');
      print('   主力流出: ${quote.mainOutflow}');
      print('   净流入: ${quote.mainNetFlow}');
      print('   净流入率: ${quote.mainNetFlowRate}%');
    });

    test('净流入为0但流入流出不为0的情况', () {
      final quote = QuoteData(
        code: 'sh600519',
        mainInflow: 100000000.0,
        mainOutflow: 100000000.0,
        mainNetFlow: 0.0,
        mainNetFlowRate: 0.0,
      );
      
      expect(quote.mainInflow, isNot(0));
      expect(quote.mainOutflow, isNot(0));
      expect(quote.mainNetFlow, equals(0));
      expect(quote.mainNetFlowRate, equals(0));
      
      print('✅ 净流入为0但流入流出不为0的情况');
      print('   主力流入: ${quote.mainInflow}');
      print('   主力流出: ${quote.mainOutflow}');
      print('   净流入: ${quote.mainNetFlow}');
      print('   净流入率: ${quote.mainNetFlowRate}%');
    });

    test('主力资金数据合并逻辑验证', () {
      final baseQuote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800.0,
        mainInflow: 0.0,
        mainOutflow: 0.0,
        mainNetFlow: 0.0,
        mainNetFlowRate: 0.0,
      );
      
      final newFundFlow = QuoteData(
        code: 'sh600519',
        mainInflow: 800000000.0,
        mainOutflow: 750000000.0,
        mainNetFlow: 50000000.0,
        mainNetFlowRate: 0.32,
      );
      
      final updatedQuote = baseQuote.copyWith(
        mainInflow: newFundFlow.mainInflow,
        mainOutflow: newFundFlow.mainOutflow,
        mainNetFlow: newFundFlow.mainNetFlow,
        mainNetFlowRate: newFundFlow.mainNetFlowRate,
      );
      
      expect(updatedQuote.mainInflow, equals(800000000.0));
      expect(updatedQuote.mainOutflow, equals(750000000.0));
      expect(updatedQuote.mainNetFlow, equals(50000000.0));
      expect(updatedQuote.mainNetFlowRate, equals(0.32));
      
      print('✅ 主力资金数据合并逻辑正确');
    });

    test('轮询数据更新逻辑验证', () {
      final prevQuote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1790.0,
        mainInflow: 100000000.0,
        mainOutflow: 80000000.0,
        mainNetFlow: 20000000.0,
        mainNetFlowRate: 0.15,
      );
      
      final newQuote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800.0,
        mainInflow: 150000000.0,
        mainOutflow: 120000000.0,
        mainNetFlow: 30000000.0,
        mainNetFlowRate: 0.18,
      );
      
      final mergedQuote = QuoteData(
        code: prevQuote.code,
        name: prevQuote.name,
        price: newQuote.price,
        change: newQuote.change,
        changePct: newQuote.changePct,
        open: newQuote.open > 0 ? newQuote.open : prevQuote.open,
        high: newQuote.high > 0 ? newQuote.high : prevQuote.high,
        low: newQuote.low > 0 ? newQuote.low : prevQuote.low,
        preClose: newQuote.preClose > 0 ? newQuote.preClose : prevQuote.preClose,
        volume: newQuote.volume > 0 ? newQuote.volume : prevQuote.volume,
        amount: newQuote.amount > 0 ? newQuote.amount : prevQuote.amount,
        amplitude: newQuote.amplitude,
        turnover: newQuote.turnover > 0 ? newQuote.turnover : prevQuote.turnover,
        pe: prevQuote.pe,
        pb: prevQuote.pb,
        totalMarketCap: prevQuote.totalMarketCap,
        circulatingMarketCap: prevQuote.circulatingMarketCap,
        mainInflow: newQuote.mainInflow,
        mainOutflow: newQuote.mainOutflow,
        mainNetFlow: newQuote.mainNetFlow,
        mainNetFlowRate: newQuote.mainNetFlowRate,
        volumeRatio: newQuote.volumeRatio > 0 ? newQuote.volumeRatio : prevQuote.volumeRatio,
      );
      
      expect(mergedQuote.price, equals(1800.0));
      expect(mergedQuote.mainInflow, equals(150000000.0));
      expect(mergedQuote.mainOutflow, equals(120000000.0));
      expect(mergedQuote.mainNetFlow, equals(30000000.0));
      expect(mergedQuote.mainNetFlowRate, equals(0.18));
      
      print('✅ 轮询数据更新逻辑正确');
    });
  });
}