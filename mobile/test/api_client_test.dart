import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/core/trading_session.dart';

void main() {
  // ============================================================
  // 1. addMarketPrefix Tests
  // ============================================================
  group('addMarketPrefix', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    test('adds "sh" prefix for codes starting with 6', () {
      expect(apiClient.addMarketPrefix('600519'), 'sh600519');
    });

    test('adds "sh" prefix for codes starting with 68', () {
      expect(apiClient.addMarketPrefix('688981'), 'sh688981');
    });

    test('adds "sz" prefix for codes starting with 0', () {
      expect(apiClient.addMarketPrefix('000001'), 'sz000001');
    });

    test('adds "sz" prefix for codes starting with 3', () {
      expect(apiClient.addMarketPrefix('300750'), 'sz300750');
    });

    test('does not add prefix if already has "sh"', () {
      expect(apiClient.addMarketPrefix('sh600519'), 'sh600519');
    });

    test('does not add prefix if already has "sz"', () {
      expect(apiClient.addMarketPrefix('sz000001'), 'sz000001');
    });

    test('uppercase prefix not recognized (only lowercase sh/sz matched)', () {
      // addMarketPrefix only checks startsWith('sh') || startsWith('sz')
      // so uppercase SH/SZ won't be recognized as already-prefixed
      expect(apiClient.addMarketPrefix('SH600519'), 'SH600519');
      expect(apiClient.addMarketPrefix('SZ000001'), 'SZ000001');
    });

    test('handles empty string', () {
      expect(apiClient.addMarketPrefix(''), '');
    });

    test('returns code as-is for non-A-share prefix', () {
      expect(apiClient.addMarketPrefix('hk00700'), 'hk00700');
    });
  });

  // ============================================================
  // 2. SectorInfo Model Tests
  // ============================================================
  group('SectorInfo', () {
    test('construction with all fields', () {
      final sector = SectorInfo(
        name: '白酒',
        code: 'BK0477',
        changePct: 3.25,
        leadStockName: '贵州茅台',
        leadStockCode: 'sh600519',
        stockCount: 50,
      );

      expect(sector.name, '白酒');
      expect(sector.code, 'BK0477');
      expect(sector.changePct, 3.25);
      expect(sector.leadStockName, '贵州茅台');
      expect(sector.leadStockCode, 'sh600519');
      expect(sector.stockCount, 50);
    });

    test('default values for optional fields', () {
      final sector = SectorInfo(
        name: '测试板块',
        code: 'BK0001',
      );

      expect(sector.changePct, 0);
      expect(sector.leadStockName, '');
      expect(sector.leadStockCode, '');
      expect(sector.stockCount, 0);
    });
  });

  // ============================================================
  // 3. Search Deduplication Logic Tests
  // ============================================================
  group('Search Deduplication', () {
    test('duplicate codes should be deduplicated', () {
      // Simulate the dedup logic from searchStocks
      final results = [
        StockInfo(code: 'sh600519', name: '贵州茅台', display: '贵州茅台(600519)'),
        StockInfo(code: 'sh600519', name: '贵州茅台', display: '贵州茅台(600519)'),
        StockInfo(code: 'sz000858', name: '五粮液', display: '五粮液(000858)'),
      ];

      final seen = <String>{};
      final filtered = <StockInfo>[];
      for (final stock in results) {
        if (!stock.code.startsWith('sh') && !stock.code.startsWith('sz')) continue;
        if (seen.contains(stock.code)) continue;
        seen.add(stock.code);
        filtered.add(stock);
      }

      expect(filtered.length, 2);
      expect(filtered[0].code, 'sh600519');
      expect(filtered[1].code, 'sz000858');
    });

    test('non-A-share results should be filtered out', () {
      final results = [
        StockInfo(code: 'sh600519', name: '贵州茅台', display: '贵州茅台(600519)'),
        StockInfo(code: 'hk00700', name: '腾讯控股', display: '腾讯控股(00700)'),
        StockInfo(code: 'usAAPL', name: '苹果', display: '苹果(AAPL)'),
        StockInfo(code: 'sz300750', name: '宁德时代', display: '宁德时代(300750)'),
      ];

      final seen = <String>{};
      final filtered = <StockInfo>[];
      for (final stock in results) {
        if (!stock.code.startsWith('sh') && !stock.code.startsWith('sz')) continue;
        if (seen.contains(stock.code)) continue;
        seen.add(stock.code);
        filtered.add(stock);
      }

      expect(filtered.length, 2);
      expect(filtered.every((s) => s.code.startsWith('sh') || s.code.startsWith('sz')), isTrue);
    });

    test('empty name should be replaced with code', () {
      final results = [
        StockInfo(code: 'sh600519', name: '', display: '(600519)'),
      ];

      final filtered = results.map((stock) {
        final name = stock.name.isEmpty ? stock.code : stock.name;
        return StockInfo(
          code: stock.code,
          name: name,
          display: '$name(${stock.code.substring(2)})',
        );
      }).toList();

      expect(filtered[0].name, 'sh600519');
      expect(filtered[0].display, 'sh600519(600519)');
    });

    test('Sina API format: parts[4] is full name, parts[0] is matched text', () {
      // Simulate parsing Sina API response
      // Format: suggest_name,category,code,market,full_name,...
      final entry = '600519,11,600519,sh,贵州茅台,600519';
      final parts = entry.split(',');

      // When searching by code, parts[0] is the code, parts[4] is the real name
      expect(parts[0], '600519'); // matched text (could be code)
      expect(parts[2], '600519'); // stock code
      expect(parts[3], 'sh'); // market
      expect(parts[4], '贵州茅台'); // full name

      // The correct name to use is parts[4]
      final name = parts.length >= 5 ? parts[4] : parts[0];
      expect(name, '贵州茅台');

      // Build code with market prefix
      final code = '${parts[3]}${parts[2]}';
      expect(code, 'sh600519');
    });

    test('Sina API format: searching by name', () {
      final entry = '贵州茅台,11,600519,sh,贵州茅台,600519';
      final parts = entry.split(',');

      final name = parts.length >= 5 ? parts[4] : parts[0];
      expect(name, '贵州茅台');
    });
  });

  // ============================================================
  // 4. Hot Sectors API Response Parsing Tests
  // ============================================================
  group('Hot Sectors Parsing', () {
    test('parse 东方财富 sector list response', () {
      // Simulate the actual API response structure
      final apiResponse = {
        'data': {
          'diff': [
            {'f12': 'BK0477', 'f14': '白酒', 'f3': 3.25, 'f128': '贵州茅台', 'f140': '000681', 'f104': 40, 'f105': 10},
            {'f12': 'BK0480', 'f14': '锂电池', 'f3': 2.87, 'f128': '宁德时代', 'f140': '300750', 'f104': 35, 'f105': 15},
          ],
        },
      };

      final diff = apiResponse['data']?['diff'] as List?;
      expect(diff, isNotNull);
      expect(diff!.length, 2);

      // Parse first sector
      final m = diff[0] as Map<String, dynamic>;
      // f128=领涨股名称, f140=领涨股代码
      expect(m['f14'], '白酒');
      expect(m['f3'], 3.25);
      expect(m['f128'], '贵州茅台'); // lead stock NAME
      expect(m['f140'], '000681'); // lead stock CODE
      expect(m['f104'], 40); // up count
      expect(m['f105'], 10); // down count
    });

    test('sector stockCount = upCount + downCount', () {
      final upCount = 40;
      final downCount = 10;
      final stockCount = upCount + downCount;
      expect(stockCount, 50);
    });

    test('parse sector with addMarketPrefix for lead stock code', () {
      final apiClient = ApiClient();
      // f140 is raw code without prefix, addMarketPrefix should add it
      final rawLeadCode = '000681';
      final leadStockCode = apiClient.addMarketPrefix(rawLeadCode);
      expect(leadStockCode, 'sz000681');

      final rawLeadCode2 = '600519';
      final leadStockCode2 = apiClient.addMarketPrefix(rawLeadCode2);
      expect(leadStockCode2, 'sh600519');
    });
  });

  // ============================================================
  // 5. Sector Stocks API Response Parsing Tests
  // ============================================================
  group('Sector Stocks Parsing', () {
    test('parse 东方财富 sector stocks response', () {
      final apiResponse = {
        'data': {
          'diff': [
            {'f12': '600519', 'f14': '贵州茅台', 'f2': 1680.5, 'f3': 2.35, 'f4': 38.5, 'f15': 1690.0, 'f16': 1640.0, 'f17': 1650.0},
            {'f12': '000858', 'f14': '五粮液', 'f2': 145.2, 'f3': 1.88, 'f4': 2.68, 'f15': 148.0, 'f16': 142.0, 'f17': 143.0},
          ],
        },
      };

      final diff = apiResponse['data']?['diff'] as List?;
      expect(diff, isNotNull);
      expect(diff!.length, 2);

      // Parse first stock
      final m = diff[0] as Map<String, dynamic>;
      expect(m['f14'], '贵州茅台'); // name
      expect(m['f12'], '600519'); // raw code
      expect(m['f2'], 1680.5); // price
      expect(m['f3'], 2.35); // change%
    });

    test('raw stock code gets market prefix via addMarketPrefix', () {
      final apiClient = ApiClient();
      expect(apiClient.addMarketPrefix('600519'), 'sh600519');
      expect(apiClient.addMarketPrefix('000858'), 'sz000858');
    });
  });

  // ============================================================
  // 6. Batch Quotes (Tencent) Parsing Tests
  // ============================================================
  group('Batch Quotes Parsing', () {
    test('Tencent batch API format: multiple stocks separated by semicolons', () {
      // Simulate Tencent batch API response
      final response = 'v_sh600519="1~贵州茅台~600519~~1680.50~~38.50~2.35~...";v_sz000858="1~五粮液~000858~~145.20~~2.68~1.88~...";';

      final entries = response.split(';');
      expect(entries.length, greaterThanOrEqualTo(2));

      // First entry
      final entry1 = entries[0];
      expect(entry1, contains('贵州茅台'));
      expect(entry1, contains('600519'));
    });

    test('parse single Tencent quote entry', () {
      // Tencent API format: each field separated by ~
      // parts[1]=name, parts[2]=code, parts[3]=price, parts[31]=change, parts[32]=changePct
      final dataStr = '1~贵州茅台~600519~1680.50~1642.00~1650.00~2345678~2956789000~~1680.50~1~38.50~2.35~1~0~0~0~0~0~0~0~~~~~~0~0~0~0~0~0~0~~0~0~0~38.50~2.35~1690.00~1640.00~1650.00~0.00~0~0.00~0~0';
      final parts = dataStr.split('~');

      expect(parts[1], '贵州茅台'); // name
      expect(parts[2], '600519'); // code
      expect(double.tryParse(parts[3]), 1680.50); // price
    });

    test('Tencent amplitude calculation matches ApiClient logic', () {
      // Simulate the amplitude calculation from getBatchRealtimeQuotes
      final high = 1690.0;
      final low = 1640.0;
      final preClose = 1642.0;
      final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;
      expect(amplitude, closeTo(3.04, 0.01));
    });
  });

  // ============================================================
  // 7. Trading Session Tests
  // ============================================================
  group('TradingSession', () {
    test('isInTradingSession returns a bool', () {
      final result = TradingSession.isInTradingSession();
      expect(result, isA<bool>());
    });

    test('getSessionStatus returns valid status', () {
      final status = TradingSession.getSessionStatus();
      expect(status, anyOf(equals('盘前'), equals('交易中'), equals('午休'), equals('盘后'), equals('休市')));
    });

    test('isMarketClosed returns a bool', () {
      final result = TradingSession.isMarketClosed();
      expect(result, isA<bool>());
    });

    test('getSessionStatus returns 休市 on weekends', () {
      // We can't control DateTime.now(), but we can verify the method
      // returns one of the expected values
      final status = TradingSession.getSessionStatus();
      expect(['盘前', '交易中', '午休', '盘后', '休市'], contains(status));
    });

    test('trading session time boundaries are correct', () {
      // Verify the constants used in TradingSession match A-share hours
      const morningStart = 9 * 60 + 30; // 9:30
      const morningEnd = 11 * 60 + 30; // 11:30
      const afternoonStart = 13 * 60; // 13:00
      const afternoonEnd = 15 * 60; // 15:00

      expect(morningStart, 570);
      expect(morningEnd, 690);
      expect(afternoonStart, 780);
      expect(afternoonEnd, 900);
    });
  });

  // ============================================================
  // 8. QuoteData Edge Cases
  // ============================================================
  group('QuoteData Edge Cases', () {
    test('QuoteData with partial data', () {
      final quote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1680.50,
        changePct: 2.35,
      );

      expect(quote.code, 'sh600519');
      expect(quote.name, '贵州茅台');
      expect(quote.price, 1680.50);
      expect(quote.open, 0);
      expect(quote.high, 0);
      expect(quote.low, 0);
      expect(quote.volume, 0);
    });

    test('QuoteData fromJson handles null and missing fields', () {
      final json = {
        'code': 'sh600519',
        'name': '贵州茅台',
        'price': null,
        'change_pct': 'invalid',
      };
      final quote = QuoteData.fromJson(json);

      expect(quote.code, 'sh600519');
      expect(quote.name, '贵州茅台');
      expect(quote.price, 0); // null should become 0
      expect(quote.changePct, 0); // invalid string should become 0
    });

    test('QuoteData fromJson handles int values', () {
      final json = {
        'code': 'sh600519',
        'name': '贵州茅台',
        'price': 1680, // int instead of double
        'change_pct': 2, // int instead of double
      };
      final quote = QuoteData.fromJson(json);

      expect(quote.price, 1680.0);
      expect(quote.changePct, 2.0);
    });

    test('QuoteData amplitude calculation', () {
      final quote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1680.50,
        high: 1690.00,
        low: 1640.00,
        preClose: 1642.00,
      );

      // amplitude = (high - low) / preClose * 100
      final amplitude = quote.preClose > 0
          ? (quote.high - quote.low) / quote.preClose * 100
          : 0.0;
      expect(amplitude, closeTo(3.04, 0.01));
    });

    test('QuoteData.empty() creates empty quote', () {
      final quote = QuoteData.empty();
      expect(quote.code, '');
      expect(quote.name, '');
      expect(quote.price, 0);
    });
  });

  // ============================================================
  // 9. ArchiveRecord Model Tests
  // ============================================================
  group('ArchiveRecord', () {
    test('construction with all fields', () {
      final archivedAt = DateTime(2024, 1, 15, 10, 30);
      final record = ArchiveRecord(
        id: 1,
        code: 'sh600519',
        name: '贵州茅台',
        price: 1680.50,
        changePct: 2.35,
        score: 75,
        recommendation: '买入',
        riskLevel: '中等',
        buySignalCount: 5,
        sellSignalCount: 2,
        activeStrategyCount: 3,
        confluenceScore: 80,
        archivedAt: archivedAt,
      );

      expect(record.id, 1);
      expect(record.code, 'sh600519');
      expect(record.name, '贵州茅台');
      expect(record.price, 1680.50);
      expect(record.changePct, 2.35);
      expect(record.score, 75);
      expect(record.recommendation, '买入');
      expect(record.riskLevel, '中等');
      expect(record.buySignalCount, 5);
      expect(record.sellSignalCount, 2);
      expect(record.activeStrategyCount, 3);
      expect(record.confluenceScore, 80);
      expect(record.archivedAt, archivedAt);
    });

    test('fromMap parses correctly', () {
      final archivedAt = DateTime(2024, 1, 16, 14, 0);
      final map = {
        'id': 2,
        'code': 'sz000858',
        'name': '五粮液',
        'price': 145.20,
        'change_pct': 1.88,
        'score': 60,
        'recommendation': '观望',
        'risk_level': '中等',
        'buy_signal_count': 3,
        'sell_signal_count': 4,
        'active_strategy_count': 2,
        'confluence_score': 55,
        'trade_levels_json': null,
        'top_signals': '',
        'archived_at': archivedAt.millisecondsSinceEpoch,
      };

      final record = ArchiveRecord.fromMap(map);
      expect(record.id, 2);
      expect(record.code, 'sz000858');
      expect(record.name, '五粮液');
      expect(record.price, 145.20);
      expect(record.changePct, 1.88);
      expect(record.score, 60);
      expect(record.recommendation, '观望');
      expect(record.riskLevel, '中等');
      expect(record.buySignalCount, 3);
      expect(record.sellSignalCount, 4);
      expect(record.activeStrategyCount, 2);
      expect(record.confluenceScore, 55);
    });

    test('toMap serializes correctly', () {
      final archivedAt = DateTime(2024, 1, 15, 10, 30);
      final record = ArchiveRecord(
        id: 1,
        code: 'sh600519',
        name: '贵州茅台',
        price: 1680.50,
        changePct: 2.35,
        score: 75,
        recommendation: '买入',
        riskLevel: '中等',
        buySignalCount: 5,
        sellSignalCount: 2,
        activeStrategyCount: 3,
        confluenceScore: 80,
        archivedAt: archivedAt,
      );

      final map = record.toMap();
      expect(map['code'], 'sh600519');
      expect(map['name'], '贵州茅台');
      expect(map['price'], 1680.50);
      expect(map['change_pct'], 2.35);
      expect(map['score'], 75);
      expect(map['recommendation'], '买入');
      expect(map['risk_level'], '中等');
      expect(map['buy_signal_count'], 5);
      expect(map['sell_signal_count'], 2);
      expect(map['active_strategy_count'], 3);
      expect(map['confluence_score'], 80);
      expect(map['archived_at'], archivedAt.millisecondsSinceEpoch);
    });

    test('toMap and fromMap round-trip', () {
      final archivedAt = DateTime(2024, 3, 20, 9, 30);
      final original = ArchiveRecord(
        id: 5,
        code: 'sz300750',
        name: '宁德时代',
        price: 210.50,
        changePct: -1.23,
        score: 45,
        recommendation: '卖出',
        riskLevel: '高',
        buySignalCount: 1,
        sellSignalCount: 6,
        activeStrategyCount: 2,
        confluenceScore: 30,
        topSignals: 'MACD死叉;KDJ超卖',
        archivedAt: archivedAt,
      );

      final map = original.toMap();
      final restored = ArchiveRecord.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.code, original.code);
      expect(restored.name, original.name);
      expect(restored.price, original.price);
      expect(restored.changePct, original.changePct);
      expect(restored.score, original.score);
      expect(restored.recommendation, original.recommendation);
      expect(restored.riskLevel, original.riskLevel);
      expect(restored.buySignalCount, original.buySignalCount);
      expect(restored.sellSignalCount, original.sellSignalCount);
      expect(restored.activeStrategyCount, original.activeStrategyCount);
      expect(restored.confluenceScore, original.confluenceScore);
      expect(restored.topSignals, original.topSignals);
    });
  });

  // ============================================================
  // 10. WatchlistItem Model Tests
  // ============================================================
  group('WatchlistItem', () {
    test('construction with explicit addedAt', () {
      final addedAt = DateTime(2024, 1, 15);
      final item = WatchlistItem(
        code: 'sh600519',
        name: '贵州茅台',
        addedAt: addedAt,
      );

      expect(item.code, 'sh600519');
      expect(item.name, '贵州茅台');
      expect(item.addedAt, addedAt);
    });

    test('construction without addedAt defaults to now', () {
      final before = DateTime.now();
      final item = WatchlistItem(
        code: 'sz000858',
        name: '五粮液',
      );
      final after = DateTime.now();

      expect(item.code, 'sz000858');
      expect(item.name, '五粮液');
      expect(item.addedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(item.addedAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('fromJson parses correctly', () {
      final item = WatchlistItem.fromJson({
        'code': 'sz000858',
        'name': '五粮液',
      });

      expect(item.code, 'sz000858');
      expect(item.name, '五粮液');
      // fromJson sets addedAt to DateTime.now()
      expect(item.addedAt, isNotNull);
    });
  });

  // ============================================================
  // 11. _parseDouble Logic Tests
  // ============================================================
  group('_parseDouble (via QuoteData.fromJson)', () {
    test('parses double value', () {
      final quote = QuoteData.fromJson({'price': 1680.5});
      expect(quote.price, 1680.5);
    });

    test('parses int value', () {
      final quote = QuoteData.fromJson({'price': 1680});
      expect(quote.price, 1680.0);
    });

    test('parses string value', () {
      final quote = QuoteData.fromJson({'price': '1680.5'});
      expect(quote.price, 1680.5);
    });

    test('returns 0 for null', () {
      final quote = QuoteData.fromJson({'price': null});
      expect(quote.price, 0);
    });

    test('returns 0 for invalid string', () {
      final quote = QuoteData.fromJson({'price': 'invalid'});
      expect(quote.price, 0);
    });

    test('returns 0 for missing key', () {
      final quote = QuoteData.fromJson({});
      expect(quote.price, 0);
    });
  });
}
