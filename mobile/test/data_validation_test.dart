import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/validators/data_validator.dart';

QuoteData createTestQuote({
  double price = 10.0,
  String name = '测试股票',
  double changePct = 1.0,
  double volume = 10000,
  double amount = 10000000,
  double high = 10.5,
  double low = 9.5,
  double open = 9.8,
  double preClose = 9.9,
  double turnover = 1.5,
  double pe = 20,
  double pb = 2,
  double totalMarketCap = 10000000000,
  double circulatingMarketCap = 6000000000,
  double mainNetFlow = 0,
  double mainNetFlowRate = 0,
}) {
  return QuoteData(
    code: 'sh600000',
    name: name,
    price: price,
    open: open,
    high: high,
    low: low,
    preClose: preClose,
    volume: volume,
    amount: amount,
    change: price - preClose,
    changePct: changePct,
    turnover: turnover,
    pe: pe,
    pb: pb,
    totalMarketCap: totalMarketCap,
    circulatingMarketCap: circulatingMarketCap,
    mainNetFlow: mainNetFlow,
    mainNetFlowRate: mainNetFlowRate,
  );
}

List<HistoryKline> createTestKlines(int count, {double basePrice = 10.0}) {
  return List.generate(count, (i) {
    final price = basePrice + i * 0.1;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.05,
      high: price + 0.1,
      low: price - 0.1,
      close: price,
      volume: 10000,
      amount: 10000 * price,
      change: 0.1,
      changePct: 1.0,
    );
  });
}

void main() {
  // ============================================================
  // 1. StockModels Serialization Tests
  // ============================================================
  group('StockModels Serialization', () {
    test('StockInfo fromJson/toJson round-trip', () {
      final json = {
        'code': 'sh600000',
        'name': '浦发银行',
        'display': '浦发银行(sh600000)'
      };
      final stockInfo = StockInfo.fromJson(json);

      expect(stockInfo.code, 'sh600000');
      expect(stockInfo.name, '浦发银行');
      expect(stockInfo.display, '浦发银行(sh600000)');

      final outputJson = stockInfo.toJson();
      expect(outputJson['code'], 'sh600000');
      expect(outputJson['name'], '浦发银行');
      expect(outputJson['display'], '浦发银行(sh600000)');
    });

    test('StockInfo fromJson with missing fields uses defaults', () {
      final json = <String, dynamic>{};
      final stockInfo = StockInfo.fromJson(json);

      expect(stockInfo.code, '');
      expect(stockInfo.name, '');
      // display falls back to name(code) pattern
      expect(stockInfo.display, '()');
    });

    test('QuoteData construction and field access', () {
      final quote = createTestQuote();

      expect(quote.code, 'sh600000');
      expect(quote.name, '测试股票');
      expect(quote.price, 10.0);
      expect(quote.open, 9.8);
      expect(quote.high, 10.5);
      expect(quote.low, 9.5);
      expect(quote.preClose, 9.9);
      expect(quote.volume, 10000);
      expect(quote.amount, 10000000);
      expect(quote.change, closeTo(0.1, 0.001));
      expect(quote.changePct, 1.0);
    });

    test('QuoteData fromJson parses correctly', () {
      final json = {
        'code': 'sz000001',
        'name': '平安银行',
        'price': 15.5,
        'change_pct': 2.3,
        'open': 15.0,
        'high': 15.8,
        'low': 14.9,
        'pre_close': 15.15,
        'volume': 50000,
        'amount': 775000,
      };
      final quote = QuoteData.fromJson(json);

      expect(quote.code, 'sz000001');
      expect(quote.name, '平安银行');
      expect(quote.price, 15.5);
      expect(quote.changePct, 2.3);
      expect(quote.open, 15.0);
      expect(quote.high, 15.8);
      expect(quote.low, 14.9);
      expect(quote.preClose, 15.15);
      expect(quote.volume, 50000);
      expect(quote.amount, 775000);
    });

    test('QuoteData.empty() creates empty quote', () {
      final quote = QuoteData.empty();
      expect(quote.code, '');
      expect(quote.name, '');
      expect(quote.price, 0);
    });

    test('HistoryKline construction', () {
      final kline = HistoryKline(
        date: DateTime(2024, 1, 15),
        open: 10.0,
        high: 10.5,
        low: 9.8,
        close: 10.2,
        volume: 5000,
        amount: 51000,
        changePct: 2.0,
        change: 0.2,
      );

      expect(kline.date, DateTime(2024, 1, 15));
      expect(kline.open, 10.0);
      expect(kline.high, 10.5);
      expect(kline.low, 9.8);
      expect(kline.close, 10.2);
      expect(kline.volume, 5000);
      expect(kline.amount, 51000);
      expect(kline.changePct, 2.0);
      expect(kline.change, 0.2);
    });

    test('HistoryKline fromJson parses correctly', () {
      final json = {
        'date': '2024-01-15',
        'open': 10.0,
        'high': 10.5,
        'low': 9.8,
        'close': 10.2,
        'volume': 5000,
        'amount': 51000,
        'change_pct': 2.0,
        'change': 0.2,
      };
      final kline = HistoryKline.fromJson(json);

      expect(kline.date.year, 2024);
      expect(kline.date.month, 1);
      expect(kline.date.day, 15);
      expect(kline.open, 10.0);
      expect(kline.high, 10.5);
      expect(kline.low, 9.8);
      expect(kline.close, 10.2);
    });

    test('MarketSentiment construction', () {
      final sentiment = MarketSentiment(
        upCount: 2000,
        downCount: 2500,
        flatCount: 500,
        limitUpCount: 30,
        limitDownCount: 20,
        avgChangePct: -0.5,
        totalVolume: 500000000,
        totalAmount: 6000000000,
        totalAmountYi: 60.0,
      );

      expect(sentiment.upCount, 2000);
      expect(sentiment.downCount, 2500);
      expect(sentiment.flatCount, 500);
      expect(sentiment.limitUpCount, 30);
      expect(sentiment.limitDownCount, 20);
      expect(sentiment.avgChangePct, -0.5);
      expect(sentiment.total, 5000);
      expect(sentiment.upRatio, closeTo(0.4, 0.001));
    });

    test('MarketSentiment fromJson', () {
      final json = {
        'up_count': 100,
        'down_count': 200,
        'flat_count': 50,
        'limit_up_count': 5,
        'limit_down_count': 3,
        'avg_change_pct': -1.2,
        'total_volume': 1000000,
        'total_amount': 2000000,
        'total_amount_yi': 2.0,
      };
      final sentiment = MarketSentiment.fromJson(json);

      expect(sentiment.upCount, 100);
      expect(sentiment.downCount, 200);
      expect(sentiment.flatCount, 50);
      expect(sentiment.total, 350);
      expect(sentiment.upRatio, closeTo(100 / 350, 0.001));
    });

    test('SignalItem construction', () {
      final signal = SignalItem(
        type: 'buy',
        indicator: 'MACD',
        signal: 'golden_cross',
        description: 'MACD金叉信号',
        desc: 'MACD金叉信号',
        strength: 3,
      );

      expect(signal.type, 'buy');
      expect(signal.indicator, 'MACD');
      expect(signal.signal, 'golden_cross');
      expect(signal.description, 'MACD金叉信号');
      expect(signal.desc, 'MACD金叉信号');
      expect(signal.strength, 3);
    });

    test('SignalItem fromJson', () {
      final json = {
        'type': 'sell',
        'indicator': 'RSI',
        'signal': 'overbought',
        'desc': 'RSI超买',
        'strength': 4,
      };
      final signal = SignalItem.fromJson(json);

      expect(signal.type, 'sell');
      expect(signal.indicator, 'RSI');
      expect(signal.description, 'RSI超买');
      expect(signal.desc, 'RSI超买');
      expect(signal.strength, 4);
    });

    test(
        'AnalysisResult construction with all fields including reasons and opportunities',
        () {
      final quote = createTestQuote();
      final result = AnalysisResult(
        quote: quote,
        indicators: {'macd': 'golden_cross'},
        signals: [
          SignalItem(type: 'buy', indicator: 'MACD', description: '金叉'),
        ],
        score: 75,
        recommendation: '建议买入',
        riskLevel: '低',
        riskFactors: ['市场波动'],
        suggestions: ['分批建仓'],
        confluenceScore: 80,
        confluenceDetails: [
          {'indicator': 'MACD', 'signal': 'buy'}
        ],
        reasons: ['MACD金叉', '成交量放大'],
        opportunities: [
          {'type': 'short', 'description': '短线机会'},
          {'type': 'mid', 'description': '中线布局'},
        ],
      );

      expect(result.quote, quote);
      expect(result.indicators['macd'], 'golden_cross');
      expect(result.signals.length, 1);
      expect(result.score, 75);
      expect(result.recommendation, '建议买入');
      expect(result.riskLevel, '低');
      expect(result.riskFactors, ['市场波动']);
      expect(result.suggestions, ['分批建仓']);
      expect(result.confluenceScore, 80);
      expect(result.reasons, ['MACD金叉', '成交量放大']);
      expect(result.opportunities.length, 2);
      expect(result.opportunities[0]['type'], 'short');
      expect(result.opportunities[1]['description'], '中线布局');
    });

    test('AnalysisResult fromJson with reasons and opportunities', () {
      final json = {
        'score': 60,
        'recommendation': '观望',
        'risk_level': '中等',
        'risk_factors': ['趋势不明'],
        'suggestions': ['等待信号'],
        'reasons': ['指标矛盾', '量能不足'],
        'opportunities': [
          {'type': 'long', 'description': '长线价值'},
        ],
        'signals': [
          {'type': 'buy', 'indicator': 'KDJ', 'desc': 'KDJ金叉', 'strength': 2},
        ],
      };
      final result = AnalysisResult.fromJson(json);

      expect(result.score, 60);
      expect(result.recommendation, '观望');
      expect(result.riskLevel, '中等');
      expect(result.riskFactors, ['趋势不明']);
      expect(result.suggestions, ['等待信号']);
      expect(result.reasons, ['指标矛盾', '量能不足']);
      expect(result.opportunities.length, 1);
      expect(result.opportunities[0]['type'], 'long');
      expect(result.signals.length, 1);
    });

    test('AnalysisResult round-trip preserves decision dashboard fields', () {
      final result = AnalysisResult(
        score: 6,
        recommendation: '谨慎买入',
        tradeLevels: {
          'entry_low': 10.2,
          'stop_loss': 9.8,
          'risk_reward_ratio': 2.1,
        },
        confidenceBreakdown: {
          'signal_consistency': 0.7,
          'prediction_support': 0.6,
        },
        dimensionScores: {
          '技术面': 7.2,
          '资金面': 6.1,
        },
        momentumPersistence: {
          'persistence_score': 0.66,
        },
        nextDayPrediction: {
          'up_probability': 0.58,
          'down_probability': 0.32,
          'neutral_probability': 0.10,
        },
        earlyWarningSignals: [
          SignalItem(
            type: 'buy',
            indicator: 'MACD',
            signal: 'MACD金叉预警',
            strength: 55,
          ),
        ],
      );

      final decoded = AnalysisResult.fromJson(result.toJson());

      expect(decoded.tradeLevels?['entry_low'], equals(10.2));
      expect(decoded.confidenceBreakdown?['prediction_support'], equals(0.6));
      expect(decoded.dimensionScores?['技术面'], equals(7.2));
      expect(decoded.momentumPersistence?['persistence_score'], equals(0.66));
      expect(decoded.nextDayPrediction?['up_probability'], equals(0.58));
      expect(decoded.earlyWarningSignals?.single.signal, equals('MACD金叉预警'));
    });

    test('AnalysisResult.copyWith preserves decision dashboard fields', () {
      final result = AnalysisResult(
        score: 6,
        recommendation: '谨慎买入',
        tradeLevels: {'entry_low': 10.2},
        dimensionScores: {'技术面': 7.2},
        momentumPersistence: {'persistence_score': 0.66},
        nextDayPrediction: {'up_probability': 0.58},
        earlyWarningSignals: [
          SignalItem(type: 'buy', signal: 'MACD金叉预警', strength: 55),
        ],
      );

      final copied = result.copyWith(
        quote: createTestQuote(price: 10.8),
      );

      expect(copied.quote?.price, equals(10.8));
      expect(copied.tradeLevels?['entry_low'], equals(10.2));
      expect(copied.dimensionScores?['技术面'], equals(7.2));
      expect(copied.momentumPersistence?['persistence_score'], equals(0.66));
      expect(copied.nextDayPrediction?['up_probability'], equals(0.58));
      expect(copied.earlyWarningSignals?.single.signal, equals('MACD金叉预警'));
    });

    test('ValidatedQuoteData construction with different confidence levels',
        () {
      final quote = createTestQuote();

      final high = ValidatedQuoteData(
        quote: quote,
        confidence: DataConfidence.high,
        validationNote: null,
      );
      expect(high.confidence, DataConfidence.high);
      expect(high.validationNote, isNull);

      final medium = ValidatedQuoteData(
        quote: quote,
        confidence: DataConfidence.medium,
        validationNote: '成交量偏低',
      );
      expect(medium.confidence, DataConfidence.medium);
      expect(medium.validationNote, '成交量偏低');

      final low = ValidatedQuoteData(
        quote: quote,
        confidence: DataConfidence.low,
        validationNote: '数据异常',
      );
      expect(low.confidence, DataConfidence.low);
      expect(low.validationNote, '数据异常');
    });

    test('ValidatedQuoteData defaults to high confidence', () {
      final quote = createTestQuote();
      final validated = ValidatedQuoteData(quote: quote);
      expect(validated.confidence, DataConfidence.high);
      expect(validated.validationNote, isNull);
    });
  });

  // ============================================================
  // 2. DataValidator.validateQuote Tests
  // ============================================================
  group('DataValidator.validateQuote', () {
    test('detects zero price', () {
      final quote = createTestQuote(price: 0);
      final result = DataValidator.validateQuote(quote);

      expect(result.isValid, isFalse);
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.type == DataAnomalyType.zeroPrice),
          ));
    });

    test('detects negative price', () {
      final quote = createTestQuote(price: -5.0);
      final result = DataValidator.validateQuote(quote);

      expect(result.isValid, isFalse);
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.type == DataAnomalyType.zeroPrice),
          ));
    });

    test('detects extreme change for non-ST stocks (>20%)', () {
      final quote = createTestQuote(changePct: 25.0, name: '测试股票');
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>(
                (a) => a.type == DataAnomalyType.extremeChange),
          ));
    });

    test('detects extreme change for ST stocks (>10%)', () {
      final quote = createTestQuote(changePct: 12.0, name: '*ST测试');
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>(
                (a) => a.type == DataAnomalyType.extremeChange),
          ));
    });

    test('ST stock within 5% limit is not flagged as extreme change', () {
      final quote = createTestQuote(changePct: 4.0, name: '*ST测试');
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          isNot(anyElement(
            predicate<DataAnomaly>(
                (a) => a.type == DataAnomalyType.extremeChange),
          )));
    });

    test('ST stock exceeding 5% limit is flagged as extreme change', () {
      final quote = createTestQuote(changePct: 8.0, name: '*ST测试');
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>(
                (a) => a.type == DataAnomalyType.extremeChange),
          ));
    });

    test('detects zero volume', () {
      final quote = createTestQuote(volume: 0);
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.type == DataAnomalyType.zeroVolume),
          ));
    });

    test('detects high < low', () {
      final quote = createTestQuote(high: 9.0, low: 10.0);
      final result = DataValidator.validateQuote(quote);

      expect(result.isValid, isFalse);
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.description.contains('最高价低于最低价')),
          ));
    });

    test('valid quote data has no anomalies', () {
      final quote = createTestQuote();
      final result = DataValidator.validateQuote(quote);

      expect(result.isValid, isTrue);
      expect(result.anomalies, isEmpty);
    });

    test('detects multiple anomalies in one quote', () {
      final quote = createTestQuote(price: 0, volume: 0, high: 5.0, low: 10.0);
      final result = DataValidator.validateQuote(quote);

      expect(result.isValid, isFalse);
      expect(result.anomalies.length, greaterThanOrEqualTo(3));

      final types = result.anomalies.map((a) => a.type).toSet();
      expect(types, contains(DataAnomalyType.zeroPrice));
      expect(types, contains(DataAnomalyType.zeroVolume));
    });

    test('detects inconsistent amount unit against price and volume', () {
      final quote = createTestQuote(
        price: 10,
        volume: 10000,
        amount: 100000,
      );
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) =>
                a.type == DataAnomalyType.suspiciousUnit &&
                a.field == 'amount'),
          ));
    });

    test('detects invalid valuation and fund flow ranges', () {
      final quote = createTestQuote(
        turnover: 120,
        pe: 1500,
        pb: -1,
        mainNetFlowRate: 150,
      );
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.field == 'turnover'),
          ));
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.field == 'pe'),
          ));
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.field == 'pb'),
          ));
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.field == 'mainNetFlowRate'),
          ));
    });

    test('detects circulating market cap larger than total market cap', () {
      final quote = createTestQuote(
        totalMarketCap: 1000000000,
        circulatingMarketCap: 2000000000,
      );
      final result = DataValidator.validateQuote(quote);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) =>
                a.type == DataAnomalyType.invalidRange &&
                a.field == 'marketCap'),
          ));
    });
  });

  // ============================================================
  // 3. DataValidator.validateKlines Tests
  // ============================================================
  group('DataValidator.validateKlines', () {
    test('detects negative values in kline data', () {
      final klines = [
        HistoryKline(
          date: DateTime(2024, 1, 15),
          open: -1.0,
          high: 10.0,
          low: 9.0,
          close: 9.5,
          volume: 1000,
        ),
      ];
      final result = DataValidator.validateKlines(klines);

      expect(result.isValid, isFalse);
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>(
                (a) => a.type == DataAnomalyType.negativeValue),
          ));
    });

    test('detects high < low in kline data', () {
      final klines = [
        HistoryKline(
          date: DateTime(2024, 1, 15),
          open: 10.0,
          high: 9.0,
          low: 10.5,
          close: 10.2,
          volume: 1000,
        ),
      ];
      final result = DataValidator.validateKlines(klines);

      expect(result.isValid, isFalse);
      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.description.contains('最高价低于最低价')),
          ));
    });

    test('valid kline data has no anomalies', () {
      final klines = createTestKlines(5);
      final result = DataValidator.validateKlines(klines);

      expect(result.isValid, isTrue);
      expect(result.anomalies, isEmpty);
    });
  });

  // ============================================================
  // 4. DataValidator.findMissingTradingDays Tests
  // ============================================================
  group('DataValidator.findMissingTradingDays', () {
    test('returns empty for continuous weekday data', () {
      // Monday 2024-01-08 to Friday 2024-01-12 (continuous weekdays)
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 8), close: 10.0, volume: 1000),
        HistoryKline(date: DateTime(2024, 1, 9), close: 10.1, volume: 1000),
        HistoryKline(date: DateTime(2024, 1, 10), close: 10.2, volume: 1000),
        HistoryKline(date: DateTime(2024, 1, 11), close: 10.3, volume: 1000),
        HistoryKline(date: DateTime(2024, 1, 12), close: 10.4, volume: 1000),
      ];
      final missing = DataValidator.findMissingTradingDays(klines);

      expect(missing, isEmpty);
    });

    test('detects missing weekdays', () {
      // Monday 2024-01-08 and Thursday 2024-01-11, missing Tue/Wed
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 8), close: 10.0, volume: 1000),
        // 2024-01-09 (Tue) missing
        // 2024-01-10 (Wed) missing
        HistoryKline(date: DateTime(2024, 1, 11), close: 10.3, volume: 1000),
      ];
      final missing = DataValidator.findMissingTradingDays(klines);

      expect(missing, isNotEmpty);
      expect(missing.any((d) => d == DateTime(2024, 1, 9)), isTrue);
      expect(missing.any((d) => d == DateTime(2024, 1, 10)), isTrue);
    });

    test('does not flag weekends as missing', () {
      // Friday 2024-01-12 and Monday 2024-01-15 (weekend in between)
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 12), close: 10.0, volume: 1000),
        HistoryKline(date: DateTime(2024, 1, 15), close: 10.1, volume: 1000),
      ];
      final missing = DataValidator.findMissingTradingDays(klines);

      // Weekend (Jan 13 Sat, Jan 14 Sun) should not be flagged
      expect(missing, isEmpty);
    });

    test('returns empty for empty data', () {
      final missing = DataValidator.findMissingTradingDays([]);
      expect(missing, isEmpty);
    });

    test('returns empty for single data point', () {
      final klines = [
        HistoryKline(date: DateTime(2024, 1, 8), close: 10.0, volume: 1000),
      ];
      final missing = DataValidator.findMissingTradingDays(klines);
      expect(missing, isEmpty);
    });
  });

  // ============================================================
  // 5. DataValidator.validateKlinePrices Tests
  // ============================================================
  group('DataValidator.validateKlinePrices', () {
    test('detects extreme daily change (>30%)', () {
      final klines = [
        HistoryKline(
          date: DateTime(2024, 1, 15),
          open: 10.0,
          close: 10.1,
          volume: 1000,
          changePct: 35.0,
        ),
      ];
      final result = DataValidator.validateKlinePrices(klines);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>(
                (a) => a.type == DataAnomalyType.extremeChange),
          ));
    });

    test('detects zero volume with price change', () {
      final klines = [
        HistoryKline(
          date: DateTime(2024, 1, 15),
          open: 10.0,
          close: 10.5,
          volume: 0,
          changePct: 5.0,
        ),
      ];
      final result = DataValidator.validateKlinePrices(klines);

      expect(
          result.anomalies,
          anyElement(
            predicate<DataAnomaly>((a) => a.type == DataAnomalyType.zeroVolume),
          ));
    });

    test('valid price data has no anomalies', () {
      final klines = createTestKlines(5);
      final result = DataValidator.validateKlinePrices(klines);

      expect(result.anomalies, isEmpty);
    });
  });

  // ============================================================
  // 6. ValidatedQuoteData and DataConfidence Tests
  // ============================================================
  group('ValidatedQuoteData and DataConfidence', () {
    test('high confidence creation', () {
      final quote = createTestQuote();
      final validated = ValidatedQuoteData(
        quote: quote,
        confidence: DataConfidence.high,
      );

      expect(validated.quote, quote);
      expect(validated.confidence, DataConfidence.high);
      expect(validated.validationNote, isNull);
    });

    test('medium confidence creation', () {
      final quote = createTestQuote();
      final validated = ValidatedQuoteData(
        quote: quote,
        confidence: DataConfidence.medium,
        validationNote: '成交量偏低',
      );

      expect(validated.confidence, DataConfidence.medium);
      expect(validated.validationNote, '成交量偏低');
    });

    test('low confidence creation', () {
      final quote = createTestQuote();
      final validated = ValidatedQuoteData(
        quote: quote,
        confidence: DataConfidence.low,
        validationNote: '数据可能异常',
      );

      expect(validated.confidence, DataConfidence.low);
      expect(validated.validationNote, '数据可能异常');
    });
  });

  // ============================================================
  // DataValidationResult helper tests
  // ============================================================
  group('DataValidationResult', () {
    test('hasWarnings returns true when anomaly severity < 0.8', () {
      final result = DataValidationResult(
        isValid: true,
        anomalies: [
          DataAnomaly(
            type: DataAnomalyType.extremeChange,
            field: 'changePct',
            description: 'test',
            severity: 0.7,
          ),
        ],
      );
      expect(result.hasWarnings, isTrue);
      expect(result.hasErrors, isFalse);
    });

    test('hasErrors returns true when anomaly severity >= 0.8', () {
      final result = DataValidationResult(
        isValid: false,
        anomalies: [
          DataAnomaly(
            type: DataAnomalyType.zeroPrice,
            field: 'price',
            description: 'test',
            severity: 1.0,
          ),
        ],
      );
      expect(result.hasWarnings, isFalse);
      expect(result.hasErrors, isTrue);
    });
  });
}
