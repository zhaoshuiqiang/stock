/*
 * @Author: error: error: git config user.name & please set dead value or install git && error: git config user.email & please set dead value or install git & please set dead value or install git
 * @Date: 2026-06-06 21:04:16
 * @LastEditors: error: error: git config user.name & please set dead value or install git && error: git config user.email & please set dead value or install git & please set dead value or install git
 * @LastEditTime: 2026-06-06 21:04:19
 * @FilePath: \stock\mobile\test\stock_models_test.dart
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('QuoteData fromJson', () {
    final json = {
      'code': '000001',
      'name': '平安银行',
      'price': 10.5,
      'change': 0.5,
      'change_pct': 5.0,
    };
    final quote = QuoteData.fromJson(json);
    expect(quote.code, '000001');
    expect(quote.name, '平安银行');
    expect(quote.price, 10.5);
    expect(quote.change, 0.5);
    expect(quote.changePct, 5.0);
  });

  test('MarketSentiment upRatio', () {
    final sentiment = MarketSentiment(upCount: 60, downCount: 40);
    expect(sentiment.total, 100);
    expect(sentiment.upRatio, 0.6);
  });

  test('AlertRule fromJson/toJson', () {
    final json = {
      'id': '123',
      'code': '000001',
      'name': '平安银行',
      'alert_type': 'price_up',
      'threshold': 15.0,
      'indicator_type': '',
      'enabled': true,
    };
    final rule = AlertRule.fromJson(json);
    expect(rule.id, '123');
    expect(rule.code, '000001');
    expect(rule.threshold, 15.0);

    final toJson = rule.toJson();
    expect(toJson['code'], '000001');
    expect(toJson['alert_type'], 'price_up');
  });
}