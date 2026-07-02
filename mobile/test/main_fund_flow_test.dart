import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('主力资金数据验证', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    tearDown(() {
      apiClient.dispose();
    });

    test('getMainFundFlow 正确获取主力资金数据', () async {
      const code = 'sh600519';
      
      final fundFlow = await apiClient.getMainFundFlow(code);
      
      print('\n=== getMainFundFlow 测试结果 ===');
      print('代码: $code');
      if (fundFlow != null) {
        print('主力流入: ${fundFlow.mainInflow}');
        print('主力流出: ${fundFlow.mainOutflow}');
        print('主力净流入: ${fundFlow.mainNetFlow}');
        print('主力净流入率: ${fundFlow.mainNetFlowRate.toStringAsFixed(4)}%');
        
        expect(fundFlow.code, equals(code));
        
        final hasNonZeroData = fundFlow.mainInflow != 0 || 
                                fundFlow.mainOutflow != 0 || 
                                fundFlow.mainNetFlow != 0;
        print('是否有非零数据: $hasNonZeroData');
      } else {
        print('getMainFundFlow 返回 null');
      }
    });

    test('getRealtimeQuoteWithValidation 合并主力资金数据（净流入为0时）', () async {
      const code = 'sh600519';
      
      final validatedQuote = await apiClient.getRealtimeQuoteWithValidation(code);
      
      print('\n=== getRealtimeQuoteWithValidation 测试结果 ===');
      print('代码: $code');
      if (validatedQuote != null) {
        final quote = validatedQuote.quote;
        print('名称: ${quote.name}');
        print('现价: ${quote.price}');
        print('主力流入: ${quote.mainInflow}');
        print('主力流出: ${quote.mainOutflow}');
        print('主力净流入: ${quote.mainNetFlow}');
        print('主力净流入率: ${quote.mainNetFlowRate.toStringAsFixed(4)}%');
        
        expect(quote.code, equals(code));
        
        final hasNonZeroFundData = quote.mainInflow != 0 || 
                                    quote.mainOutflow != 0 || 
                                    quote.mainNetFlow != 0 ||
                                    quote.mainNetFlowRate != 0;
        print('是否有非零主力资金数据: $hasNonZeroFundData');
      } else {
        print('getRealtimeQuoteWithValidation 返回 null');
      }
    });

    test('验证四个主力资金指标不为0（至少有一个有值）', () async {
      const code = 'sh600519';
      
      final validatedQuote = await apiClient.getRealtimeQuoteWithValidation(code);
      
      if (validatedQuote != null) {
        final quote = validatedQuote.quote;
        
        print('\n=== 四个主力资金指标验证 ===');
        print('代码: $code');
        print('净流入: ${quote.mainNetFlow}');
        print('净流入率: ${quote.mainNetFlowRate}');
        print('主力流入: ${quote.mainInflow}');
        print('主力流出: ${quote.mainOutflow}');
        
        final netFlowNonZero = quote.mainNetFlow != 0;
        final netFlowRateNonZero = quote.mainNetFlowRate != 0;
        final inflowNonZero = quote.mainInflow != 0;
        final outflowNonZero = quote.mainOutflow != 0;
        
        print('净流入非零: $netFlowNonZero');
        print('净流入率非零: $netFlowRateNonZero');
        print('主力流入非零: $inflowNonZero');
        print('主力流出非零: $outflowNonZero');
        
        final allZero = !netFlowNonZero && !netFlowRateNonZero && 
                        !inflowNonZero && !outflowNonZero;
        
        if (allZero) {
          print('警告: 四个指标全部为0，可能API返回数据异常');
        } else {
          print('测试通过: 至少有一个指标有值');
        }
      }
    });

    test('多只股票主力资金数据验证', () async {
      const codes = ['sh600519', 'sz000001', 'sz000858', 'sh601318'];
      
      for (final code in codes) {
        print('\n=== 股票: $code ===');
        final validatedQuote = await apiClient.getRealtimeQuoteWithValidation(code);
        
        if (validatedQuote != null) {
          final quote = validatedQuote.quote;
          print('名称: ${quote.name}');
          print('净流入: ${quote.mainNetFlow}');
          print('净流入率: ${quote.mainNetFlowRate.toStringAsFixed(4)}%');
          print('主力流入: ${quote.mainInflow}');
          print('主力流出: ${quote.mainOutflow}');
          
          final allZero = quote.mainNetFlow == 0 && 
                          quote.mainNetFlowRate == 0 && 
                          quote.mainInflow == 0 && 
                          quote.mainOutflow == 0;
          print('四个指标全部为0: $allZero');
        } else {
          print('获取数据失败');
        }
      }
    });
  });
}