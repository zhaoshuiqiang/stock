import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:charset_converter/charset_converter.dart';
import '../models/stock_models.dart';

class ApiClient {
  final http.Client _client = http.Client();
  final Map<String, dynamic> _cache = {};
  final Duration _cacheDuration = const Duration(minutes: 5);
  final Map<String, Future> _inFlightRequests = {};
  static const int _maxCacheSize = 100;

  /// 公共 HTTP GET 请求方法，统一处理超时、状态码检查和异常捕获
  Future<http.Response?> _httpGet(Uri url, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final response = await _client.get(url, headers: headers ?? {}).timeout(timeout);
      if (response.statusCode == 200) return response;
    } catch (e) {
      print('HTTP GET error ($url): $e');
    }
    return null;
  }

  Future<List<StockInfo>> searchStocks(String keyword) async {
    final cacheKey = 'search_$keyword';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<StockInfo>;

    final url = Uri.parse('https://suggest3.sinajs.cn/suggest/type=111&key=$keyword');
    final response = await _httpGet(url, headers: {
      'Referer': 'https://finance.sina.com.cn',
    });
    if (response != null) {
      final body = await _decodeGbk(response.bodyBytes);
      final start = body.indexOf('"');
      final end = body.lastIndexOf('"');
      if (start >= 0 && end > start) {
        final dataStr = body.substring(start + 1, end);
        final results = <StockInfo>[];

        if (dataStr.contains(';')) {
          final groups = dataStr.split(';');
          for (final group in groups) {
            final parts = group.split(',');
            if (parts.length >= 4) {
              // Sina API format: suggest_name,category,code,market,full_name,...
              // parts[0] = matched text (could be code or name)
              // parts[4] = full stock name (always the real name)
              final name = parts.length >= 5 ? parts[4] : parts[0];
              final rawCode = parts[2];
              final market = parts[3];
              final code = market.isNotEmpty ? '$market$rawCode' : addMarketPrefix(rawCode);
              results.add(StockInfo(
                code: code,
                name: name,
                display: '$name($rawCode)',
              ));
            }
          }
        } else {
          final parts = dataStr.split(',');
          for (var i = 0; i < parts.length; i += 4) {
            if (i + 3 < parts.length) {
              final name = i + 4 < parts.length ? parts[i + 4] : parts[i];
              final rawCode = parts[i + 2];
              final market = parts[i + 3];
              final code = market.isNotEmpty ? '$market$rawCode' : addMarketPrefix(rawCode);
              results.add(StockInfo(
                code: code,
                name: name,
                display: '$name($rawCode)',
              ));
            }
          }
        }

        // Deduplicate by code and filter A-share only
        final seen = <String>{};
        final filtered = <StockInfo>[];
        for (final stock in results) {
          // Only keep A-share stocks (sh/sz prefix)
          if (!stock.code.startsWith('sh') && !stock.code.startsWith('sz')) continue;
          // Deduplicate by code
          if (seen.contains(stock.code)) continue;
          seen.add(stock.code);
          // Ensure name is not empty
          final name = stock.name.isEmpty ? stock.code : stock.name;
          filtered.add(StockInfo(
            code: stock.code,
            name: name,
            display: '$name(${stock.code.substring(2)})',
          ));
        }

        _setCached(cacheKey, filtered, duration: const Duration(minutes: 5));
        return filtered;
      }
    }
    return [];
  }

  Future<QuoteData?> getRealtimeQuote(String code) async {
    final cacheKey = 'quote_$code';

    // Check cache first
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as QuoteData;

    // Check if request is already in flight
    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey] as Future<QuoteData?>;
    }

    // Make the request
    final future = _fetchRealtimeQuote(code, cacheKey);
    _inFlightRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  Future<QuoteData?> _fetchRealtimeQuote(String code, String cacheKey) async {
    // 主接口：腾讯行情
    final url = Uri.parse('https://qt.gtimg.cn/q=$code');
    final response = await _httpGet(url);
    if (response != null) {
      final body = await _decodeGbk(response.bodyBytes);
      final start = body.indexOf('="');
      final end = body.lastIndexOf('";');
      if (start >= 0 && end > start) {
        final dataStr = body.substring(start + 2, end);
        final parts = dataStr.split('~');
        if (parts.length >= 30) {
          double pe = 0;
          double pb = 0;
          double totalMarketCap = 0;
          double circulatingMarketCap = 0;
          double turnover = 0;

          // 腾讯API字段映射：
          // [38]=换手率, [39]=市盈率, [44]=流通市值(万元), [45]=总市值(万元), [46]=市净率
          if (parts.length >= 40) {
            pe = _parseDouble(parts[39]);
          }
          if (parts.length >= 47) {
            pb = _parseDouble(parts[46]);
          }
          if (parts.length >= 39) {
            turnover = _parseDouble(parts[38]);
          }
          if (parts.length >= 45) {
            // API返回单位为万元，转换为元
            circulatingMarketCap = _parseDouble(parts[44]) * 10000;
          }
          if (parts.length >= 46) {
            // API返回单位为万元，转换为元
            totalMarketCap = _parseDouble(parts[45]) * 10000;
          }

          // PB/PE 合理性校验：异常值记录日志便于排查字段索引问题
          if (pb > 0 && (pb > 100 || pb < 0.01)) {
            print('[PB Warning] code=$code pb=$pb parts.length=${parts.length}');
            print('[PB Debug] parts[44]=${parts.length > 44 ? parts[44] : "N/A"} parts[45]=${parts.length > 45 ? parts[45] : "N/A"} parts[46]=${parts.length > 46 ? parts[46] : "N/A"}');
          }
          if (pe > 0 && (pe > 10000 || pe < 0.01)) {
            print('[PE Warning] code=$code pe=$pe parts.length=${parts.length}');
            print('[PE Debug] parts[38]=${parts.length > 38 ? parts[38] : "N/A"} parts[39]=${parts.length > 39 ? parts[39] : "N/A"}');
          }

          final high = _parseDouble(parts[33]);
          final low = _parseDouble(parts[34]);
          final preClose = _parseDouble(parts[4]);
          // 振幅 = (最高价 - 最低价) / 昨收价 * 100
          final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;

          final quote = QuoteData(
            code: code,
            name: parts[1],
            price: _parseDouble(parts[3]),
            open: _parseDouble(parts[5]),
            high: high,
            low: low,
            preClose: preClose,
            volume: _parseDouble(parts[6]),
            amount: _parseDouble(parts[37]) * 10000,
            change: _parseDouble(parts[31]),
            changePct: _parseDouble(parts[32]),
            amplitude: amplitude,
            turnover: turnover,
            pe: pe,
            pb: pb,
            totalMarketCap: totalMarketCap,
            circulatingMarketCap: circulatingMarketCap,
          );
          _setCached(cacheKey, quote, duration: const Duration(seconds: 5));
          return quote;
        }
      }
    }

    // 备用接口：新浪行情
    final fallbackUrl = Uri.parse('https://hq.sinajs.cn/list=$code');
    final fallbackResponse = await _httpGet(fallbackUrl, headers: {
      'Referer': 'https://finance.sina.com.cn',
    });
    if (fallbackResponse != null) {
      final body = await _decodeGbk(fallbackResponse.bodyBytes);
      final start = body.indexOf('="');
      final end = body.lastIndexOf('";');
      if (start >= 0 && end > start) {
        final dataStr = body.substring(start + 2, end);
        final parts = dataStr.split(',');
        if (parts.length >= 11) {
          final sinaHigh = _parseDouble(parts[4]);
          final sinaLow = _parseDouble(parts[5]);
          final sinaPreClose = _parseDouble(parts[2]);
          final sinaAmplitude = sinaPreClose > 0 ? (sinaHigh - sinaLow) / sinaPreClose * 100 : 0.0;
          final quote = QuoteData(
            code: code,
            name: parts[0],
            price: _parseDouble(parts[3]),
            open: _parseDouble(parts[1]),
            high: sinaHigh,
            low: sinaLow,
            preClose: sinaPreClose,
            volume: _parseDouble(parts[8]),
            amount: _parseDouble(parts[9]),
            change: _parseDouble(parts[3]) - sinaPreClose,
            changePct: (_parseDouble(parts[3]) - sinaPreClose) /
                    (sinaPreClose > 0 ? sinaPreClose : 1) *
                100,
            amplitude: sinaAmplitude,
          );
          _setCached(cacheKey, quote, duration: const Duration(seconds: 5));
          return quote;
        }
      }
    }
    return null;
  }

  Future<QuoteData?> getMainFundFlow(String code) async {
    String secid;
    if (code.startsWith('sh')) {
      secid = '1.${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      secid = '0.${code.substring(2)}';
    } else {
      secid = code;
    }

    final url = Uri.parse('https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f62,f184,f66,f69,f72,f75,f78,f81,f84,f87&secids=$secid');
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
    });
    if (response != null) {
      final body = response.body;
      final data = json.decode(body) as Map<String, dynamic>;
      final diff = data['data']?['diff'] as List?;
      if (diff != null && diff.isNotEmpty) {
        final item = diff.first as Map<String, dynamic>;
        final mainNetFlow = _parseDouble(item['f62']);
        final mainNetFlowRateBps = _parseDouble(item['f184']);
        final mainNetFlowRate = mainNetFlowRateBps / 100;

        // 从净流入和净流入率计算主力总成交额，再推算流入流出
        // 净流入率 = 净流入 / 主力总成交额 * 100
        double mainInflow = 0;
        double mainOutflow = 0;
        if (mainNetFlowRateBps.abs() > 0.01) {
          final mainTotalAmount = (mainNetFlow.abs() / mainNetFlowRateBps.abs()) * 10000;
          mainInflow = (mainTotalAmount + mainNetFlow) / 2;
          mainOutflow = (mainTotalAmount - mainNetFlow) / 2;
        } else {
          mainInflow = mainNetFlow > 0 ? mainNetFlow : 0;
          mainOutflow = mainNetFlow < 0 ? mainNetFlow.abs() : 0;
        }

        return QuoteData(
          code: code,
          mainInflow: mainInflow,
          mainOutflow: mainOutflow,
          mainNetFlow: mainNetFlow,
          mainNetFlowRate: mainNetFlowRate,
        );
      }
    }
    return null;
  }

  /// 从东方财富获取实时行情
  Future<QuoteData?> _fetchQuoteFromEastMoney(String code) async {
    String secid;
    if (code.startsWith('sh')) {
      secid = '1.${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      secid = '0.${code.substring(2)}';
    } else {
      secid = code;
    }

    final url = Uri.parse(
      'https://push2.eastmoney.com/api/qt/stock/get?secid=$secid&fields=f43,f44,f45,f46,f47,f48,f50,f51,f52,f55,f57,f58,f60,f116,f117,f162,f167,f170,f171',
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response != null) {
      final body = response.body;
      final data = json.decode(body) as Map<String, dynamic>;
      final d = data['data'] as Map<String, dynamic>?;
      if (d == null) return null;

      final price = _parseDouble(d['f43']);
      final high = _parseDouble(d['f44']);
      final low = _parseDouble(d['f45']);
      final open = _parseDouble(d['f46']);
      final volume = _parseDouble(d['f47']); // 成交量(手)
      final amount = _parseDouble(d['f48']); // 成交额
      final preClose = _parseDouble(d['f60']);
      final changePct = _parseDouble(d['f170']) / 100; // 涨跌幅需除以100
      final change = _parseDouble(d['f171']) / 100; // 涨跌额需除以100
      final pe = _parseDouble(d['f162']); // 市盈率(动)
      final pb = _parseDouble(d['f167']); // 市净率
      final totalMarketCap = _parseDouble(d['f116']); // 总市值
      final circulatingMarketCap = _parseDouble(d['f117']); // 流通市值
      final name = d['f58']?.toString() ?? '';

      final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;

      return QuoteData(
        code: code,
        name: name,
        price: price,
        open: open,
        high: high,
        low: low,
        preClose: preClose,
        volume: volume,
        amount: amount,
        change: change,
        changePct: changePct,
        amplitude: amplitude,
        pe: pe,
        pb: pb,
        totalMarketCap: totalMarketCap,
        circulatingMarketCap: circulatingMarketCap,
      );
    }
    return null;
  }

  /// 多数据源交叉验证获取实时行情
  Future<ValidatedQuoteData?> getRealtimeQuoteWithValidation(String code) async {
    final results = await Future.wait([
      getRealtimeQuote(code),
      _fetchQuoteFromEastMoney(code),
    ]);

    final tencentQuote = results[0];
    final eastMoneyQuote = results[1];

    // 如果两个源都获取失败，返回null
    if (tencentQuote == null && eastMoneyQuote == null) return null;

    // 如果只有一个源成功，直接使用该数据，置信度为low
    if (tencentQuote == null) {
      return ValidatedQuoteData(
        quote: eastMoneyQuote!,
        confidence: DataConfidence.low,
        validationNote: '仅东方财富数据源可用',
      );
    }
    if (eastMoneyQuote == null) {
      return ValidatedQuoteData(
        quote: tencentQuote,
        confidence: DataConfidence.low,
        validationNote: '仅腾讯数据源可用',
      );
    }

    // 两个源都成功，进行交叉验证
    final priceDiff = (tencentQuote.price - eastMoneyQuote.price).abs();
    final priceDiffPct = tencentQuote.price > 0 ? (priceDiff / tencentQuote.price) * 100 : 0.0;

    DataConfidence confidence;
    String? validationNote;

    if (priceDiffPct <= 0.5) {
      confidence = DataConfidence.high;
      if (priceDiffPct > 0.1) {
        validationNote = '价格偏差${priceDiffPct.toStringAsFixed(2)}%，数据一致';
      }
    } else if (priceDiffPct <= 2.0) {
      confidence = DataConfidence.medium;
      validationNote = '价格偏差${priceDiffPct.toStringAsFixed(2)}%，腾讯:${tencentQuote.price.toStringAsFixed(2)} 东方财富:${eastMoneyQuote.price.toStringAsFixed(2)}';
    } else {
      confidence = DataConfidence.low;
      validationNote = '价格偏差${priceDiffPct.toStringAsFixed(2)}%过大，使用腾讯数据';
    }

    // 使用腾讯数据作为主数据源
    return ValidatedQuoteData(
      quote: tencentQuote,
      confidence: confidence,
      validationNote: validationNote,
    );
  }

  Future<List<HistoryKline>> getStockHistory(String code, {int days = 120, bool bypassCache = false}) async {
    final cacheKey = 'history_${code}_$days';

    // Check cache first (skip if bypassCache is true)
    if (!bypassCache) {
      final cached = _getCached(cacheKey);
      if (cached != null) return cached as List<HistoryKline>;

      // Check if request is already in flight
      if (_inFlightRequests.containsKey(cacheKey)) {
        return _inFlightRequests[cacheKey] as Future<List<HistoryKline>>;
      }
    }

    // Make the request
    final future = _fetchStockHistory(code, days, cacheKey);
    _inFlightRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  Future<List<HistoryKline>> _fetchStockHistory(String code, int days, String cacheKey) async {
    final url = Uri.parse(
        'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=$code&scale=240&ma=no&datalen=$days');
    final response = await _httpGet(url, headers: {
      'Referer': 'https://finance.sina.com.cn',
    }, timeout: const Duration(seconds: 15));
    if (response != null) {
      final body = response.body;
      final data = json.decode(body) as List;
      final results = <HistoryKline>[];

      for (int i = 0; i < data.length; i++) {
        final item = data[i] as Map<String, dynamic>;
        final close = _parseDouble(item['close']);
        final open = _parseDouble(item['open']);
        final high = _parseDouble(item['high']);
        final low = _parseDouble(item['low']);
        final volume = _parseDouble(item['volume']) / 100;
        double preClose = open;
        if (i > 0) {
          preClose = _parseDouble(data[i - 1]['close']);
        }
        final change = close - preClose;
        final changePct = preClose > 0 ? (change / preClose) * 100 : 0.0;

        // 新浪K线API不返回amount字段，使用估算公式计算：
        // 成交额 ≈ 成交量(手) × 100 × 均价
        // 均价 = (开盘 + 最高 + 最低 + 收盘) / 4
        double amount = _parseDouble(item['amount']);
        if (amount == 0 && volume > 0) {
          final avgPrice = (open + high + low + close) / 4;
          if (avgPrice > 0) {
            amount = volume * 100 * avgPrice;
          }
        }

        results.add(HistoryKline(
          date: DateTime.tryParse(item['day'] ?? '') ?? DateTime.now(),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
          amount: amount,
          change: change,
          changePct: changePct,
        ));
      }
      _setCached(cacheKey, results, duration: const Duration(seconds: 60));
      return results;
    }
    return [];
  }

  Future<MarketSentiment?> getMarketSentiment() async {
    const cacheKey = 'market_sentiment';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as MarketSentiment;

    final url = Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=1&sort=changepercent&asc=0&node=hs_a&symbol=&_s_r_a=auto');
    final response = await _httpGet(url, headers: {
      'Referer': 'https://finance.sina.com.cn',
    });
    if (response != null) {
      final body = response.body;
      final data = json.decode(body);

      if (data is List && data.isNotEmpty) {
        final item = data.first as Map<String, dynamic>;
        final result = MarketSentiment(
          upCount: item['up_count'] ?? 0,
          downCount: item['down_count'] ?? 0,
          flatCount: item['flat_count'] ?? 0,
          limitUpCount: item['limit_up_count'] ?? 0,
          limitDownCount: item['limit_down_count'] ?? 0,
          avgChangePct: _parseDouble(item['changepercent']),
          totalVolume: _parseDouble(item['volume']),
          totalAmount: _parseDouble(item['amount']),
          totalAmountYi: _parseDouble(item['amount']),
        );
        _setCached(cacheKey, result, duration: const Duration(seconds: 30));
        return result;
      } else if (data is Map<String, dynamic>) {
        final result = MarketSentiment(
          upCount: data['up_count'] ?? 0,
          downCount: data['down_count'] ?? 0,
          flatCount: data['flat_count'] ?? 0,
          limitUpCount: data['limit_up_count'] ?? 0,
          limitDownCount: data['limit_down_count'] ?? 0,
          avgChangePct: _parseDouble(data['avg_change_pct']),
          totalVolume: _parseDouble(data['total_volume']),
          totalAmount: _parseDouble(data['total_amount']),
          totalAmountYi: _parseDouble(data['total_amount_yi']),
        );
        _setCached(cacheKey, result, duration: const Duration(seconds: 30));
        return result;
      }
    }
    return null;
  }

  dynamic _getCached(String key) {
    final cached = _cache[key];
    if (cached is Map && cached['timestamp'] != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(cached['timestamp'] as int);
      final duration = Duration(milliseconds: cached['duration'] as int? ?? _cacheDuration.inMilliseconds);
      if (DateTime.now().difference(timestamp) < duration) {
        return cached['data'];
      }
    }
    return null;
  }

  void _setCached(String key, dynamic data, {Duration? duration}) {
    if (_cache.length >= _maxCacheSize) {
      _cleanupCache();
    }
    _cache[key] = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
      'duration': (duration ?? _cacheDuration).inMilliseconds,
    };
  }

  void _cleanupCache() {
    final now = DateTime.now().millisecondsSinceEpoch;
    // First remove all expired entries
    _cache.removeWhere((key, value) {
      if (value is Map && value['timestamp'] != null) {
        final timestamp = value['timestamp'] as int;
        final duration = Duration(milliseconds: value['duration'] as int? ?? _cacheDuration.inMilliseconds);
        return now - timestamp > duration.inMilliseconds;
      }
      return true;
    });

    // If still over limit, remove oldest entries
    if (_cache.length >= _maxCacheSize) {
      final sortedKeys = _cache.keys.toList()..sort((a, b) {
        final ta = (_cache[a] as Map)['timestamp'] as int;
        final tb = (_cache[b] as Map)['timestamp'] as int;
        return ta.compareTo(tb);
      });
      final removeCount = _cache.length - _maxCacheSize + 1;
      for (var i = 0; i < removeCount && i < sortedKeys.length; i++) {
        _cache.remove(sortedKeys[i]);
      }
    }
  }

  String addMarketPrefix(String code) {
    if (code.isEmpty) return code;
    if (code.startsWith('sh') || code.startsWith('sz')) {
      return code.toLowerCase();
    }
    final firstChar = code[0];
    if (firstChar == '6') {
      return 'sh$code';
    }
    if (firstChar == '0' || firstChar == '3') {
      return 'sz$code';
    }
    return code;
  }

  /// 获取财经快讯
  Future<List<dynamic>> getMarketNews() async {
    const cacheKey = 'market_news';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<dynamic>;

    final url = Uri.parse('https://newsapi.eastmoney.com/kuaixun/v1/getlist_102_ajaxResult_50_1_.html');
    final response = await _httpGet(url);
    if (response != null) {
      final body = response.body;
      // 返回格式: var ajaxResult={...}
      final jsonStart = body.indexOf('{');
      final jsonEnd = body.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final jsonStr = body.substring(jsonStart, jsonEnd + 1);
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        final list = data['LivesList'] as List?;
        if (list != null) {
          final result = list.map((item) => {
            'title': item['title'] ?? '',
            'digest': item['digest'] ?? item['simdigest'] ?? '',
            'url': item['url_m'] ?? item['url_w'] ?? '',
            'showTime': item['showtime'] ?? '',
            'source': item['column'] == '100,102,105' ? '东方财富' : '财经快讯',
          }).toList();
          _setCached(cacheKey, result, duration: const Duration(seconds: 60));
          return result;
        }
      }
    }
    return [];
  }

  /// 获取个股相关新闻
  Future<List<dynamic>> getStockNews(String stockName) async {
    final cacheKey = 'stock_news_$stockName';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<dynamic>;

    final encoded = Uri.encodeComponent(stockName);
    final url = Uri.parse('https://search-api-web.eastmoney.com/search/jsonp?cb=jQueryCallback&param=%7B%22uid%22%3A%22%22%2C%22keyword%22%3A%22$encoded%22%2C%22type%22%3A%5B%22cmsArticleWebOld%22%5D%2C%22client%22%3A%22web%22%2C%22clientType%22%3A%22web%22%2C%22clientVersion%22%3A%22curr%22%2C%22param%22%3A%7B%22cmsArticleWebOld%22%3A%7B%22searchScope%22%3A%22default%22%2C%22sort%22%3A%22default%22%2C%22pageIndex%22%3A1%2C%22pageSize%22%3A10%2C%22preTag%22%3A%22%22%2C%22postTag%22%3A%22%22%7D%7D%7D');
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://so.eastmoney.com/',
    });
    if (response != null) {
      var body = response.body;
      // 去掉 JSONP 包裹：jQueryCallback({...})
      final jsonpMatch = RegExp(r'^[a-zA-Z_]\w*\(([\s\S]*)\);?$').firstMatch(body);
      if (jsonpMatch != null) {
        body = jsonpMatch.group(1)!;
      } else {
        // 兜底：去掉首尾括号
        if (body.startsWith('(')) body = body.substring(1);
        if (body.endsWith(')')) body = body.substring(0, body.length - 1);
      }
      final data = json.decode(body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result != null) {
        // cmsArticleWebOld 是一个直接的 List（数组），不是 Map
        final list = result['cmsArticleWebOld'] as List?;
        if (list != null) {
          final newsList = list.map((item) => {
            'title': item['title'] ?? item['articleTitle'] ?? '',
            'digest': item['content'] ?? item['description'] ?? '',
            'url': item['url'] ?? item['articleUrl'] ?? '',
            'showTime': item['date'] ?? item['publishDate'] ?? '',
            'source': item['mediaName'] ?? item['source'] ?? '',
          }).toList();
          _setCached(cacheKey, newsList, duration: const Duration(seconds: 60));
          return newsList;
        }
      }
    }
    return [];
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// 获取热门行业板块（东方财富行业板块涨幅排名前5）
  Future<List<SectorInfo>> getHotSectors() async {
    const cacheKey = 'hot_sectors';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<SectorInfo>;

    final url = Uri.parse(
      'https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=5&po=1&np=1&fltt=2&invl=2&fid=f3&fs=m:90+t:2&fields=f12,f14,f2,f3,f104,f105,f128,f136,f140,f141',
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response != null) {
      try {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final diff = data['data']?['diff'] as List?;
        if (diff != null) {
          final sectors = <SectorInfo>[];
          for (final item in diff) {
            final m = item as Map<String, dynamic>;
            // f128=领涨股名称, f140=领涨股代码
            final rawLeadCode = m['f140']?.toString() ?? '';
            final leadStockCode = addMarketPrefix(rawLeadCode);
            sectors.add(SectorInfo(
              name: m['f14']?.toString() ?? '',
              code: m['f12']?.toString() ?? '',
              changePct: _parseDouble(m['f3']),
              leadStockName: m['f128']?.toString() ?? '',
              leadStockCode: leadStockCode,
              stockCount: (m['f104'] as int? ?? 0) + (m['f105'] as int? ?? 0),
            ));
          }
          _setCached(cacheKey, sectors, duration: const Duration(seconds: 30));
          return sectors;
        }
      } catch (e) {
        print('Parse hot sectors failed: $e');
      }
    }
    return [];
  }

  /// 获取板块内个股（涨幅前10）
  Future<List<QuoteData>> getSectorStocks(String sectorCode) async {
    final cacheKey = 'sector_stocks_$sectorCode';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<QuoteData>;

    final url = Uri.parse(
      'https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=10&po=1&np=1&fltt=2&invl=2&fid=f3&fs=b:$sectorCode+f:!50&fields=f12,f14,f2,f3,f4,f15,f16,f17,f5,f6',
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response != null) {
      try {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final diff = data['data']?['diff'] as List?;
        if (diff != null) {
          final stocks = <QuoteData>[];
          for (final item in diff) {
            final m = item as Map<String, dynamic>;
            final rawCode = m['f12']?.toString() ?? '';
            final code = addMarketPrefix(rawCode);
            stocks.add(QuoteData(
              code: code,
              name: m['f14']?.toString() ?? '',
              price: _parseDouble(m['f2']),
              change: _parseDouble(m['f4']),
              changePct: _parseDouble(m['f3']),
              open: _parseDouble(m['f17']),
              high: _parseDouble(m['f15']),
              low: _parseDouble(m['f16']),
            ));
          }
          _setCached(cacheKey, stocks, duration: const Duration(seconds: 60));
          return stocks;
        }
      } catch (e) {
        print('Parse sector stocks failed: $e');
      }
    }
    return [];
  }

  /// 批量获取实时行情（腾讯批量接口）
  Future<List<QuoteData>> getBatchRealtimeQuotes(List<String> codes) async {
    if (codes.isEmpty) return [];

    // 腾讯批量接口：多个代码用逗号分隔
    final codesStr = codes.join(',');
    final url = Uri.parse('https://qt.gtimg.cn/q=$codesStr');
    final response = await _httpGet(url);
    if (response != null) {
      final body = await _decodeGbk(response.bodyBytes);
      final results = <QuoteData>[];

      // 每只股票数据以分号分隔
      final entries = body.split(';');
      for (final entry in entries) {
        final start = entry.indexOf('="');
        final end = entry.lastIndexOf('"');
        if (start >= 0 && end > start) {
          final dataStr = entry.substring(start + 2, end);
          final parts = dataStr.split('~');
          if (parts.length >= 35) {
            final code = parts[2];
            final prefixedCode = addMarketPrefix(code);
            final high = _parseDouble(parts[33]);
            final low = _parseDouble(parts[34]);
            final preClose = _parseDouble(parts[4]);
            final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;

            results.add(QuoteData(
              code: prefixedCode,
              name: parts[1],
              price: _parseDouble(parts[3]),
              open: _parseDouble(parts[5]),
              high: high,
              low: low,
              preClose: preClose,
              volume: _parseDouble(parts[6]),
              amount: _parseDouble(parts[37]) * 10000,
              change: _parseDouble(parts[31]),
              changePct: _parseDouble(parts[32]),
              amplitude: amplitude,
            ));
          }
        }
      }
      return results;
    }
    return [];
  }

  Future<String> _decodeGbk(Uint8List bytes) async {
    try {
      return await CharsetConverter.decode("GBK", bytes);
    } catch (e) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 获取分时线数据（东方财富接口，盘后也可获取全天走势）
  /// 返回: Map<int, double> 分钟偏移量->价格, Map<int, double> 分钟偏移量->均价
  Future<Map<String, Map<int, double>>?> getTimeshareData(String code, {bool bypassCache = false}) async {
    final cacheKey = 'timeshare_$code';
    if (!bypassCache) {
      final cached = _getCached(cacheKey);
      if (cached != null) return cached as Map<String, Map<int, double>>;
    }

    String secid;
    if (code.startsWith('sh')) {
      secid = '1.${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      secid = '0.${code.substring(2)}';
    } else {
      secid = code;
    }

    final url = Uri.parse(
      'http://push2his.eastmoney.com/api/qt/stock/trends2/get'
      '?secid=$secid'
      '&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13'
      '&fields2=f51,f52,f53,f54,f55,f56,f57,f58'
      '&iscr=0'
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response != null) {
      final body = response.body;
      final data = json.decode(body) as Map<String, dynamic>;
      final rc = data['rc'];
      if (rc == null || rc != 0) return null;

      final trendsData = data['data'] as Map<String, dynamic>?;
      if (trendsData == null) return null;

      final trends = trendsData['trends'] as List?;
      if (trends == null || trends.isEmpty) return null;

      final preClose = _parseDouble(trendsData['preClose']);
      final priceMap = <int, double>{};
      final avgMap = <int, double>{};

      for (final item in trends) {
        // 格式: "2024-01-01 09:30,10.50,12345,150000.00,10.48"
        // 字段: 时间,价格,成交量,成交额,均价
        final parts = (item as String).split(',');
        if (parts.length < 5) continue;

        final timeStr = parts[0];
        final price = _parseDouble(parts[1]);
        final avgPrice = _parseDouble(parts[4]);

        // 解析时间获取分钟偏移量
        final timePart = timeStr.split(' ').last;
        final timeParts = timePart.split(':');
        if (timeParts.length < 2) continue;
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final totalMinutes = hour * 60 + minute;

        // 上午盘 9:30~11:30 -> offset 0~120
        const morningStart = 9 * 60 + 30;
        const morningEnd = 11 * 60 + 30;
        // 下午盘 13:00~15:00 -> offset 121~240
        const afternoonStart = 13 * 60;

        int offset;
        if (totalMinutes >= morningStart && totalMinutes <= morningEnd) {
          offset = totalMinutes - morningStart;
        } else if (totalMinutes >= afternoonStart) {
          offset = 121 + (totalMinutes - afternoonStart);
        } else {
          continue;
        }

        priceMap[offset] = price;
        if (avgPrice > 0) {
          avgMap[offset] = avgPrice;
        }
      }

      final result = {
        'prices': priceMap,
        'avgs': avgMap,
        'preClose': {0: preClose},
      };
      // 交易时段(9:30-15:00工作日)缩短缓存至5秒，其他时段10秒
      final now = DateTime.now();
      final isWeekday = now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
      final totalMin = now.hour * 60 + now.minute;
      final isTradingHour = isWeekday && totalMin >= (9 * 60 + 30) && totalMin <= 15 * 60;
      _setCached(cacheKey, result, duration: isTradingHour ? const Duration(seconds: 5) : const Duration(seconds: 10));
      return result;
    }
    return null;
  }

}
