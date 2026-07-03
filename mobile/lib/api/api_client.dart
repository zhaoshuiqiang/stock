import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:charset_converter/charset_converter.dart';
import '../models/stock_models.dart';
import '../analysis/limit_up_analyzer.dart';
import '../validators/data_validator.dart';

class ApiClient {
  http.Client _client = http.Client();
  HttpClient? _fallbackClient;
  final Map<String, dynamic> _cache = {};
  final Duration _cacheDuration = const Duration(minutes: 5);
  final Map<String, Future> _inFlightRequests = {};
  static const int _maxCacheSize = 100;
  bool _disposed = false;

  /// 重建HTTP客户端（连接池失效时调用）
  void _rebuildClient() {
    try { _client.close(); } catch (_) {}
    _client = http.Client();
  }

  /// 获取共享的fallback HttpClient
  HttpClient _getFallbackClient() {
    _fallbackClient ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 5);
    return _fallbackClient!;
  }

  /// 公共 HTTP GET 请求方法，统一处理超时、重试和异常捕获
  Future<http.Response?> _httpGet(Uri url, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 8), int retries = 2}) async {
    if (_disposed) return null;
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final response = await _client.get(url, headers: headers ?? {}).timeout(timeout);
        if (response.statusCode == 200) return response;
        debugPrint('HTTP ${response.statusCode}: ${url.host}${url.path}');
      } catch (e) {
        debugPrint('HTTP attempt ${attempt + 1}/$retries failed: ${url.host}${url.path} - $e');
        // 连接池失效时重建客户端
        if (e.toString().contains('Connection closed') || e.toString().contains('Connection reset')) {
          _rebuildClient();
        }
        if (attempt < retries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
    // http.Client全部失败时，回退到dart:io HttpClient
    return _httpGetFallback(url, headers: headers, timeout: timeout);
  }

  /// 备用HTTP GET：使用dart:io HttpClient，避免http包连接池问题
  Future<http.Response?> _httpGetFallback(Uri url, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 8)}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final client = _getFallbackClient();
        final request = await client.getUrl(url);
        headers?.forEach((key, value) => request.headers.set(key, value));
        final ioResponse = await request.close().timeout(timeout);
        final bodyBytes = await ioResponse.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d)).then((b) => b.takeBytes());
        if (ioResponse.statusCode == 200) {
          return http.Response.bytes(Uint8List.fromList(bodyBytes), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
        }
        debugPrint('HTTP fallback ${ioResponse.statusCode}: ${url.host}${url.path}');
      } catch (e) {
        debugPrint('HTTP fallback attempt ${attempt + 1}/2 failed: ${url.host}${url.path} - $e');
        // fallback客户端连接异常时重建
        try { _fallbackClient?.close(); } catch (_) {}
        _fallbackClient = null;
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return null;
  }

  Future<List<StockInfo>> searchStocks(String keyword) async {
    final cacheKey = 'search_$keyword';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<StockInfo>;

    // Check if request is already in flight
    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey] as Future<List<StockInfo>>;
    }

    // Make the request
    final future = _fetchSearchStocks(keyword, cacheKey);
    _inFlightRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  Future<List<StockInfo>> _fetchSearchStocks(String keyword, String cacheKey) async {
    final encoded = Uri.encodeComponent(keyword);
    final url = Uri.parse('https://suggest3.sinajs.cn/suggest/type=111&key=$encoded');
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
            if (group.trim().isEmpty) continue;
            final parts = group.split(',');
            if (parts.length >= 5) {
              // Sina API actual format (type=111):
              // sh600446,111,sh600446,sh600446,金证股份,,金证股份,99,1,,,
              // parts[0] = matched text (with prefix), parts[1] = category
              // parts[2] = code (may have prefix), parts[3] = market+code (may have prefix)
              // parts[4] = full stock name (always the real name)
              final name = parts[4].isNotEmpty ? parts[4] : parts[0];
              // Strip any existing sh/sz prefix from code field
              final rawCode = parts[2].replaceAll(RegExp(r'^(sh|sz|SH|SZ)'), '');
              final code = addMarketPrefix(rawCode);
              results.add(StockInfo(
                code: code,
                name: name,
                display: '$name($rawCode)',
              ));
            }
          }
        } else {
          final parts = dataStr.split(',');
          // Same format but without semicolons - step by actual field count
          // Each entry has: matched,category,code,marketCode,fullName,...
          for (var i = 0; i < parts.length; i += 5) {
            if (i + 4 < parts.length) {
              final name = parts[i + 4].isNotEmpty ? parts[i + 4] : parts[i];
              final rawCode = parts[i + 2].replaceAll(RegExp(r'^(sh|sz|SH|SZ)'), '');
              final code = addMarketPrefix(rawCode);
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
          // Ensure name is not empty; use raw code (without prefix) as fallback
          final name = stock.name.isEmpty ? stock.code.substring(2) : stock.name;
          final rawCode = stock.code.substring(2);
          final display = (name == rawCode) ? rawCode : '$name($rawCode)';
          filtered.add(StockInfo(
            code: stock.code,
            name: name,
            display: display,
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
    // 数据源优先级：通达信 > 腾讯(主接口) > 新浪 > 东方财富
    // 通达信与腾讯共享底层数据基础设施，使用通达信兼容格式

    // 主接口：通达信/腾讯行情（第一优先级）
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
          // [38]=换手率, [39]=市盈率, [43]=流通市值(万), [44]=总市值(万), [46]=市净率
          if (parts.length >= 40) {
            pe = _parseDouble(parts[39]);
          }
          if (parts.length >= 47) {
            pb = _parseDouble(parts[46]);
          }
          if (parts.length >= 39) {
            turnover = _parseDouble(parts[38]);
          }
          if (parts.length >= 44) {
            // 腾讯API fields: [44]=总市值(万), [43]=流通市值(万)
            circulatingMarketCap = _parseDouble(parts[43]) * 10000; // 万元→元
          }
          if (parts.length >= 45) {
            totalMarketCap = _parseDouble(parts[44]) * 10000; // 万元→元
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
          // Validate quote data
          final validation = DataValidator.validateQuote(quote);
          String confidence = 'high';
          if (validation.anomalies.isNotEmpty) {
            confidence = validation.anomalies.any((a) => a.type == DataAnomalyType.zeroPrice || a.type == DataAnomalyType.extremeChange) 
                ? 'low' : 'medium';
          }
          final validatedQuote = QuoteData(
            code: quote.code,
            name: quote.name,
            price: quote.price,
            change: quote.change,
            changePct: quote.changePct,
            open: quote.open,
            high: quote.high,
            low: quote.low,
            preClose: quote.preClose,
            volume: quote.volume,
            amount: quote.amount,
            amplitude: quote.amplitude,
            turnover: quote.turnover,
            pe: quote.pe,
            pb: quote.pb,
            totalMarketCap: quote.totalMarketCap,
            circulatingMarketCap: quote.circulatingMarketCap,
            mainInflow: quote.mainInflow,
            mainOutflow: quote.mainOutflow,
            mainNetFlow: quote.mainNetFlow,
            mainNetFlowRate: quote.mainNetFlowRate,
            updateTime: quote.updateTime,
            confidence: confidence,
          );
          _setCached(cacheKey, validatedQuote, duration: const Duration(seconds: 5));
          return validatedQuote;
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
            volume: _parseDouble(parts[8]) / 100, // 新浪返回单位为股，转为手
            amount: _parseDouble(parts[9]),
            change: _parseDouble(parts[3]) - sinaPreClose,
            changePct: (_parseDouble(parts[3]) - sinaPreClose) /
                    (sinaPreClose > 0 ? sinaPreClose : 1) *
                100,
            amplitude: sinaAmplitude,
          );
          // Validate quote data
          final validation = DataValidator.validateQuote(quote);
          String confidence = 'high';
          if (validation.anomalies.isNotEmpty) {
            confidence = validation.anomalies.any((a) => a.type == DataAnomalyType.zeroPrice || a.type == DataAnomalyType.extremeChange) 
                ? 'low' : 'medium';
          }
          final validatedQuote = QuoteData(
            code: quote.code,
            name: quote.name,
            price: quote.price,
            change: quote.change,
            changePct: quote.changePct,
            open: quote.open,
            high: quote.high,
            low: quote.low,
            preClose: quote.preClose,
            volume: quote.volume,
            amount: quote.amount,
            amplitude: quote.amplitude,
            turnover: quote.turnover,
            pe: quote.pe,
            pb: quote.pb,
            totalMarketCap: quote.totalMarketCap,
            circulatingMarketCap: quote.circulatingMarketCap,
            mainInflow: quote.mainInflow,
            mainOutflow: quote.mainOutflow,
            mainNetFlow: quote.mainNetFlow,
            mainNetFlowRate: quote.mainNetFlowRate,
            updateTime: quote.updateTime,
            confidence: confidence,
          );
          _setCached(cacheKey, validatedQuote, duration: const Duration(seconds: 5));
          return validatedQuote;
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

    // 使用 push2his 资金流接口（日K线，取最新一天）
    // fields2: f52=主力净流入额(元), f55=大单净流入, f56=超大单净流入, f57=主力净流入占比(%)
    final url = Uri.parse(
      'https://push2his.eastmoney.com/api/qt/stock/fflow/daykline/get'
      '?secid=$secid&lmt=1&klt=1'
      '&fields1=f1,f2,f3,f7'
      '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response == null) {
      debugPrint('[API] getMainFundFlow($code) HTTP failed');
      return null;
    }
    try {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final klines = data['data']?['klines'] as List?;
      if (klines == null || klines.isEmpty) return null;

      // kline 格式: "日期,主力净流入,小单净流入,中单净流入,大单净流入,超大单净流入,主力占比%,..."
      final parts = (klines.last as String).split(',');
      if (parts.length < 7) return null;

      final mainNetFlow = _parseDouble(parts[1]);     // f52 主力净流入额(元)
      final mainNetFlowRate = _parseDouble(parts[6]); // f57 主力净流入占比(%)

      // 从净流入和净流入率推算主力总成交额，再算流入流出
      // 净流入率(%) = 净流入 / 主力总成交额 * 100
      double mainInflow = 0;
      double mainOutflow = 0;
      if (mainNetFlowRate.abs() > 0.01) {
        final mainTotalAmount = (mainNetFlow.abs() / mainNetFlowRate.abs()) * 100;
        mainInflow = (mainTotalAmount + mainNetFlow) / 2;
        mainOutflow = (mainTotalAmount - mainNetFlow) / 2;
      } else if (mainNetFlow.abs() > 0) {
        mainInflow = mainNetFlow > 0 ? mainNetFlow : 0;
        mainOutflow = mainNetFlow < 0 ? mainNetFlow.abs() : 0;
      }

      debugPrint('[API] getMainFundFlow($code) netFlow=$mainNetFlow, rate=$mainNetFlowRate%, inflow=$mainInflow, outflow=$mainOutflow');

      return QuoteData(
        code: code,
        mainInflow: mainInflow,
        mainOutflow: mainOutflow,
        mainNetFlow: mainNetFlow,
        mainNetFlowRate: mainNetFlowRate,
      );
    } catch (e) {
      debugPrint('[API] getMainFundFlow($code) 解析失败: $e');
      return null;
    }
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
      'https://push2.eastmoney.com/api/qt/stock/get?secid=$secid&fltt=2&fields=f43,f44,f45,f46,f47,f48,f50,f51,f52,f55,f57,f58,f60,f116,f117,f162,f167,f170,f171,f10',
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response != null) {
      final body = response.body;
      Map<String, dynamic> data;
      try {
        data = json.decode(body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[API] JSON解析失败: $e');
        return null;
      }
      final d = data['data'] as Map<String, dynamic>?;
      if (d == null) return null;

      final price = _parseDouble(d['f43']);
      final high = _parseDouble(d['f44']);
      final low = _parseDouble(d['f45']);
      final open = _parseDouble(d['f46']);
      final volume = _parseDouble(d['f47']); // 成交量(手)
      final amount = _parseDouble(d['f48']); // 成交额
      final preClose = _parseDouble(d['f60']);
      final changePct = _parseDouble(d['f170']); // fltt=2时已是正确单位
      final change = _parseDouble(d['f171']); // fltt=2时已是正确单位
      final pe = _parseDouble(d['f162']); // 市盈率(动)
      final pb = _parseDouble(d['f167']); // 市净率
      final totalMarketCap = _parseDouble(d['f116']) * 10000; // 万元→元
      final circulatingMarketCap = _parseDouble(d['f117']) * 10000; // 万元→元
      final volumeRatio = _parseDouble(d['f10']); // 量比
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
        volumeRatio: volumeRatio,
      );
    }
    return null;
  }

  /// 多数据源交叉验证获取实时行情
  Future<ValidatedQuoteData?> getRealtimeQuoteWithValidation(String code) async {
    final results = await Future.wait([
      getRealtimeQuote(code),
      _fetchQuoteFromEastMoney(code),
      getMainFundFlow(code),
    ]);

    final tencentQuote = results[0];
    final eastMoneyQuote = results[1];
    final fundFlowQuote = results[2];

    // 如果两个源都获取失败，返回null
    if (tencentQuote == null && eastMoneyQuote == null) return null;

    QuoteData mergedQuote;
    if (tencentQuote != null) {
      mergedQuote = tencentQuote;
    } else {
      mergedQuote = eastMoneyQuote!;
    }

    // 合并主力资金数据
    if (fundFlowQuote != null) {
      mergedQuote = mergedQuote.copyWith(
        mainNetFlow: fundFlowQuote.mainNetFlow,
        mainNetFlowRate: fundFlowQuote.mainNetFlowRate,
        mainInflow: fundFlowQuote.mainInflow,
        mainOutflow: fundFlowQuote.mainOutflow,
      );
    }

    // 如果只有一个源成功，直接使用该数据，置信度为low
    if (tencentQuote == null) {
      return ValidatedQuoteData(
        quote: mergedQuote,
        confidence: DataConfidence.low,
        validationNote: '仅东方财富数据源可用',
      );
    }
    if (eastMoneyQuote == null) {
      return ValidatedQuoteData(
        quote: mergedQuote,
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

    // 使用合并后的数据作为主数据源
    return ValidatedQuoteData(
      quote: mergedQuote,
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
      // Validate kline data before returning
      final klineValidation = DataValidator.validateKlines(result);
      if (klineValidation.anomalies.isNotEmpty) {
        result.removeWhere((k) => k.close <= 0 || k.high <= 0 || k.low <= 0 || k.open <= 0);
      }
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  Future<List<HistoryKline>> _fetchStockHistory(String code, int days, String cacheKey) async {
    // 数据源优先级：通达信 > 腾讯 > 东方财富 > 新浪
    // 通达信（第一优先级）：使用通达信兼容格式的K线数据
    try {
      final tdxResult = await _fetchStockHistoryFromTDX(code, days);
      if (tdxResult.isNotEmpty) {
        _setCached(cacheKey, tdxResult, duration: const Duration(seconds: 60));
        return tdxResult;
      }
    } catch (e) {
      debugPrint('TDX kline failed for $code: $e');
    }

    // 备用1：腾讯K线API（通达信同源数据）
    try {
      final tencentResult = await _fetchStockHistoryFromTencent(code, days);
      if (tencentResult.isNotEmpty) {
        _setCached(cacheKey, tencentResult, duration: const Duration(minutes: 5));
        return tencentResult;
      }
    } catch (e) {
      debugPrint('Tencent kline failed for $code: $e');
    }

    // 备用1：新浪K线接口
    try {
      final sinaResult = await _fetchStockHistoryFromSina(code, days);
      if (sinaResult.isNotEmpty) {
        _setCached(cacheKey, sinaResult, duration: const Duration(minutes: 5));
        return sinaResult;
      }
    } catch (e) {
      debugPrint('Sina kline failed for $code: $e');
    }

    // 备用2：东方财富K线接口
    try {
      final emResult = await _fetchStockHistoryFromEastMoney(code, days);
      if (emResult.isNotEmpty) {
        _setCached(cacheKey, emResult, duration: const Duration(minutes: 5));
        return emResult;
      }
    } catch (e) {
      debugPrint('EastMoney kline failed for $code: $e');
    }
    return [];
  }

  /// 通达信K线API（第一优先级数据源）
  /// 通达信与腾讯共享底层数据基础设施，使用通达信兼容格式
  Future<List<HistoryKline>> _fetchStockHistoryFromTDX(String code, int days) async {
    // 计算日期范围：通达信格式要求 yyyyMMdd
    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 200));
    final startStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final endStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

    // 通达信兼容API：使用前复权日K线数据
    final url = Uri.parse(
        'https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=$code,day,$startStr,$endStr,$days,qfq');
    final response = await _httpGet(url, timeout: const Duration(seconds: 10));
    if (response == null) return [];

    final body = response.body;
    final data = json.decode(body) as Map<String, dynamic>;
    if (data['code'] != 0) return [];

    final stockData = data['data']?[code] as Map<String, dynamic>?;
    if (stockData == null) return [];

    // 通达信格式：qfqday 前复权日K线 [["日期","开盘","收盘","最高","最低","成交量"],...]
    final klines = stockData['qfqday'] as List?;
    if (klines == null || klines.isEmpty) return [];

    final results = <HistoryKline>[];
    for (int i = 0; i < klines.length; i++) {
      final item = klines[i];
      // 通达信除权日会插入分红信息对象，跳过非数组项
      if (item is! List) continue;
      if (item.length < 6) continue;

      final open = _parseDouble(item[1]);
      final close = _parseDouble(item[2]);
      final high = _parseDouble(item[3]);
      final low = _parseDouble(item[4]);
      final volume = _parseDouble(item[5]); // 手

      double preClose = open;
      if (i > 0 && klines[i - 1] is List) {
        preClose = _parseDouble((klines[i - 1] as List)[2]);
      }
      final change = close - preClose;
      final changePct = preClose > 0 ? (change / preClose) * 100 : 0.0;

      // 成交额估算：成交量(手) × 100 × 均价
      double amount = 0;
      final avgPrice = (open + high + low + close) / 4;
      if (avgPrice > 0 && volume > 0) {
        amount = volume * 100 * avgPrice;
      }

      results.add(HistoryKline(
        date: DateTime.tryParse(item[0].toString()) ?? DateTime.now(),
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

    // 校验数据
    final klineValidation = DataValidator.validateKlines(results);
    if (klineValidation.anomalies.isNotEmpty) {
      results.removeWhere((k) => k.close <= 0 || k.high <= 0 || k.low <= 0 || k.open <= 0);
    }
    return results;
  }

  /// 腾讯K线API（第二优先级，通达信同源数据）
  Future<List<HistoryKline>> _fetchStockHistoryFromTencent(String code, int days) async {
    // 计算日期范围：从半年前开始
    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 200));
    final startStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final endStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

    final url = Uri.parse(
        'https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=$code,day,$startStr,$endStr,$days,qfq');
    final response = await _httpGet(url, timeout: const Duration(seconds: 10));
    if (response == null) return [];

    final body = response.body;
    final data = json.decode(body) as Map<String, dynamic>;
    if (data['code'] != 0) return [];

    final stockData = data['data']?[code] as Map<String, dynamic>?;
    if (stockData == null) return [];

    // qfqday: 前复权日K线，格式: [["日期","开盘","收盘","最高","最低","成交量"],...]
    final klines = stockData['qfqday'] as List?;
    if (klines == null || klines.isEmpty) return [];

    final results = <HistoryKline>[];
    for (int i = 0; i < klines.length; i++) {
      final item = klines[i];
      // 腾讯API除权日会插入分红信息对象，跳过非数组项
      if (item is! List) continue;
      if (item.length < 6) continue;

      final open = _parseDouble(item[1]);
      final close = _parseDouble(item[2]);
      final high = _parseDouble(item[3]);
      final low = _parseDouble(item[4]);
      final volume = _parseDouble(item[5]); // 手

      double preClose = open;
      if (i > 0 && klines[i - 1] is List) {
        preClose = _parseDouble((klines[i - 1] as List)[2]);
      }
      final change = close - preClose;
      final changePct = preClose > 0 ? (change / preClose) * 100 : 0.0;

      // 成交额估算：成交量(手) × 100 × 均价
      double amount = 0;
      final avgPrice = (open + high + low + close) / 4;
      if (avgPrice > 0 && volume > 0) {
        amount = volume * 100 * avgPrice;
      }

      results.add(HistoryKline(
        date: DateTime.tryParse(item[0].toString()) ?? DateTime.now(),
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

    // 校验数据
    final klineValidation = DataValidator.validateKlines(results);
    if (klineValidation.anomalies.isNotEmpty) {
      results.removeWhere((k) => k.close <= 0 || k.high <= 0 || k.low <= 0 || k.open <= 0);
    }
    return results;
  }

  /// 新浪K线API（备用1）
  Future<List<HistoryKline>> _fetchStockHistoryFromSina(String code, int days) async {
    final url = Uri.parse(
        'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=$code&scale=240&ma=no&datalen=$days');
    final response = await _httpGet(url, headers: {
      'Referer': 'https://finance.sina.com.cn',
    }, timeout: const Duration(seconds: 10));
    if (response == null) return [];

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
    final klineValidation = DataValidator.validateKlines(results);
    if (klineValidation.anomalies.isNotEmpty) {
      results.removeWhere((k) => k.close <= 0 || k.high <= 0 || k.low <= 0 || k.open <= 0);
    }
    return results;
  }

  Future<List<HistoryKline>> _fetchStockHistoryFromEastMoney(String code, int days) async {
    // 东方财富K线API
    String secid;
    if (code.startsWith('sh')) {
      secid = '1.${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      secid = '0.${code.substring(2)}';
    } else {
      secid = code;
    }

    final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=$secid&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56,f57&klt=101&fqt=1&end=20500101&lmt=$days');
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
    }, timeout: const Duration(seconds: 15));

    if (response != null) {
      final body = response.body;
      final data = json.decode(body) as Map<String, dynamic>;
      final klines = data['data']?['klines'] as List?;
      if (klines == null || klines.isEmpty) return [];

      final results = <HistoryKline>[];
      for (int i = 0; i < klines.length; i++) {
        final line = klines[i].toString();
        final parts = line.split(',');
        if (parts.length >= 7) {
          final close = _parseDouble(parts[2]);
          final open = _parseDouble(parts[1]);
          final high = _parseDouble(parts[3]);
          final low = _parseDouble(parts[4]);
          final volume = _parseDouble(parts[5]); // 手（API直接返回手为单位）
          final amount = _parseDouble(parts[6]);

          double preClose = open;
          if (i > 0) {
            final prevLine = klines[i - 1].toString();
            final prevParts = prevLine.split(',');
            if (prevParts.length >= 3) {
              preClose = _parseDouble(prevParts[2]);
            }
          }
          final change = close - preClose;
          final changePct = preClose > 0 ? (change / preClose) * 100 : 0.0;

          results.add(HistoryKline(
            date: DateTime.tryParse(parts[0]) ?? DateTime.now(),
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
      }
      return results;
    }
    return [];
  }

  Future<MarketSentiment?> getMarketSentiment() async {
    const cacheKey = 'market_sentiment';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as MarketSentiment;

    final url = Uri.parse(
      'https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f1,f2,f3,f4,f6,f12,f13,f104,f105,f106&secids=1.000001,0.399001,0.399006',
    );
    final response = await _httpGet(url, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://quote.eastmoney.com/',
    });
    if (response != null) {
      final body = response.body;
      final data = json.decode(body) as Map<String, dynamic>;
      final diff = data['data']?['diff'] as List?;
      if (diff != null && diff.isNotEmpty) {
        int upCount = 0;
        int downCount = 0;
        int flatCount = 0;
        double totalAmount = 0;
        double avgChangePct = 0;
        int count = 0;

        for (final item in diff) {
          final m = item as Map<String, dynamic>;
          upCount += (m['f104'] as num?)?.toInt() ?? 0;
          downCount += (m['f105'] as num?)?.toInt() ?? 0;
          flatCount += (m['f106'] as num?)?.toInt() ?? 0;
          totalAmount += _parseDouble(m['f6']);
          avgChangePct += _parseDouble(m['f3']);
          count++;
        }

        if (count > 0) {
          avgChangePct = avgChangePct / count;
        }

        // 接入东方财富涨停/跌停池接口，修复原先硬编码为 0 的问题
        // 失败时 fallback 为 0，不影响主流程
        final limitPool = await _fetchLimitPoolCount();
        final result = MarketSentiment(
          upCount: upCount,
          downCount: downCount,
          flatCount: flatCount,
          limitUpCount: limitPool.up,
          limitDownCount: limitPool.down,
          avgChangePct: avgChangePct,
          totalVolume: 0,
          totalAmount: totalAmount,
          totalAmountYi: totalAmount / 1e8,
        );
        _setCached(cacheKey, result, duration: const Duration(seconds: 30));
        return result;
      }
    }
    return null;
  }

  /// 获取涨停/跌停家数（接入东方财富涨停池/跌停池接口）
  /// 失败时返回 (0, 0)，不影响主流程
  Future<({int up, int down})> _fetchLimitPoolCount() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final dateStr = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';

    int limitUp = 0;
    int limitDown = 0;

    // 涨停池
    try {
      final url = Uri.parse(
        'https://push2ex.eastmoney.com/getTopicZTPool?ut=7eea3edcaed734bea9cbfc24409ed989&dpt=wz.ztzt&date=$dateStr',
      );
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://quote.eastmoney.com/',
      });
      if (response != null) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final pool = data['data']?['pool'];
        if (pool is List) {
          limitUp = pool.length;
        }
      }
    } catch (e) {
      debugPrint('获取涨停家数失败: $e');
    }

    // 跌停池
    try {
      final url = Uri.parse(
        'https://push2ex.eastmoney.com/getTopicDTPool?ut=7eea3edcaed734bea9cbfc24409ed989&dpt=wz.ztzt&date=$dateStr',
      );
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://quote.eastmoney.com/',
      });
      if (response != null) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final pool = data['data']?['pool'];
        if (pool is List) {
          limitDown = pool.length;
        }
      }
    } catch (e) {
      debugPrint('获取跌停家数失败: $e');
    }

    return (up: limitUp, down: limitDown);
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
    if (code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj')) {
      return code.toLowerCase();
    }
    // 北交所：830xxx/870xxx/889xxx 或 430xxx
    if (code.startsWith('8') || code.startsWith('43')) {
      return 'bj$code';
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

  /// 判断是否为主板股票（沪深主板，排除创业板/科创板/北交所）
  bool isMainBoardStock(String code) {
    final pureCode = code.replaceAll(RegExp(r'^[a-zA-Z]+'), '');
    return pureCode.length == 6 && (pureCode.startsWith('60') || pureCode.startsWith('00'));
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
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  /// 获取个股所属行业板块（东方财富）
  Future<String> getStockSector(String code) async {
    final cacheKey = 'sector_$code';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as String;

    String secid;
    if (code.startsWith('sh')) {
      secid = '1.${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      secid = '0.${code.substring(2)}';
    } else {
      secid = code;
    }

    try {
      final url = Uri.parse(
        'https://push2.eastmoney.com/api/qt/stock/get?secid=$secid&fltt=2&fields=f126,f127',
      );
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://quote.eastmoney.com/',
      });
      if (response != null) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final d = data['data'] as Map<String, dynamic>?;
        if (d != null) {
          final sector = d['f126']?.toString() ?? '';
          if (sector.isNotEmpty) {
            _setCached(cacheKey, sector, duration: const Duration(minutes: 30));
            return sector;
          }
        }
      }
    } catch (e) {
      debugPrint('getStockSector failed: $e');
    }
    return '';
  }

  /// 获取热门行业板块（东方财富行业板块涨幅排名前5）
  Future<List<SectorInfo>> getHotSectors() async {
    const cacheKey = 'hot_sectors';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<SectorInfo>;

    // 主接口：东方财富板块列表
    List<SectorInfo>? sectors;
    try {
      final url = Uri.parse(
        'https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=30&po=1&np=1&fltt=2&invl=2&fid=f3&fs=m:90+t:2&fields=f12,f14,f2,f3,f104,f105,f128,f136,f140,f141',
      );
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://quote.eastmoney.com/',
      }, retries: 3);
      if (response != null) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final diff = data['data']?['diff'] as List?;
        if (diff != null && diff.isNotEmpty) {
          sectors = [];
          for (final item in diff) {
            final m = item as Map<String, dynamic>;
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
        }
      }
    } catch (e) {
      debugPrint('getHotSectors eastmoney failed: $e');
    }

    // 备用接口：新浪行业板块
    if (sectors == null || sectors.isEmpty) {
      try {
        sectors = await _fetchHotSectorsFromSina();
        if (sectors.isNotEmpty) {
          _setCached(cacheKey, sectors, duration: const Duration(seconds: 30));
        }
      } catch (e) {
        debugPrint('getHotSectors sina failed: $e');
      }
    }

    return sectors ?? [];
  }

  /// 获取全球主要股指（美股/港股/亚太/欧洲）
  ///
  /// 数据来源：东方财富 push2his K线接口（并行请求各指数最近2条日K线）。
  /// 返回 10 个主要指数，按 market 字段标识所属市场（US/HK/JP/EU/KR）。
  Future<List<GlobalIndex>> getGlobalIndices() async {
    const cacheKey = 'global_indices';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<GlobalIndex>;

    // secid → [显示名, 市场区域]
    const indexSpec = <String, List<String>>{
      '100.NDX': ['纳斯达克100', 'US'],
      '100.SPX': ['标普500', 'US'],
      '100.DJIA': ['道琼斯', 'US'],
      '116.HSI': ['恒生指数', 'HK'],
      '116.HSCEI': ['恒生中国企业', 'HK'],
      '100.N225': ['日经225', 'JP'],
      '100.GDAXI': ['德国DAX', 'EU'],
      '100.FTSE': ['英国富时100', 'EU'],
      '100.FCHI': ['法国CAC40', 'EU'],
      '100.KOSPI': ['韩国KOSPI', 'KR'],
    };

    try {
      // 并行请求所有指数的K线数据
      final futures = indexSpec.entries.map((e) => _fetchGlobalIndexKline(e.key, e.value[0], e.value[1]));
      final results = await Future.wait(futures);
      final result = results.whereType<GlobalIndex>().toList();

      debugPrint('[API] getGlobalIndices fetched ${result.length}/${indexSpec.length} indices');
      if (result.isNotEmpty) {
        _setCached(cacheKey, result, duration: const Duration(minutes: 2));
      }
      return result;
    } catch (e) {
      debugPrint('getGlobalIndices failed: $e');
      return [];
    }
  }

  /// 获取单个全球指数的最近2条日K线，计算当前价格和涨跌幅
  Future<GlobalIndex?> _fetchGlobalIndexKline(String secid, String displayName, String market) async {
    try {
      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get'
        '?secid=$secid&klt=101&fqt=0&lmt=2&end=20500101'
        '&fields1=f1,f2,f3,f4,f5,f6'
        '&fields2=f51,f52,f53,f54,f55,f56,f57',
      );
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://quote.eastmoney.com/',
      }, retries: 2);
      if (response == null) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final klines = data['data']?['klines'] as List?;
      if (klines == null || klines.isEmpty) return null;

      // K线格式: "日期,开盘,收盘,最高,最低,成交量,振幅"
      final latestParts = (klines.last as String).split(',');
      if (latestParts.length < 5) return null;
      final latestClose = _parseDouble(latestParts[2]);

      double changePct = 0;
      double changePoint = 0;
      if (klines.length >= 2) {
        final prevParts = (klines[klines.length - 2] as String).split(',');
        if (prevParts.length >= 5) {
          final prevClose = _parseDouble(prevParts[2]);
          if (prevClose > 0) {
            changePoint = latestClose - prevClose;
            changePct = changePoint / prevClose * 100;
          }
        }
      }

      // code 从 secid 提取（如 100.NDX → NDX）
      final code = secid.split('.').last;
      return GlobalIndex(
        code: code,
        name: displayName,
        price: latestClose,
        changePct: changePct,
        changePoint: changePoint,
        market: market,
      );
    } catch (e) {
      debugPrint('[API] _fetchGlobalIndexKline($secid) failed: $e');
      return null;
    }
  }

  Future<List<SectorInfo>> _fetchHotSectorsFromSina() async {
    final url = Uri.parse(
      'https://vip.stock.finance.sina.com.cn/q/view/newSinaHy.php',
    );
    final response = await _httpGet(url, headers: {
      'Referer': 'https://finance.sina.com.cn',
    }, timeout: const Duration(seconds: 10));
    if (response != null) {
      final body = await _decodeGbk(response.bodyBytes);
      // 新浪行业板块返回格式: var S_Finance_bankuai_sinaindustry = {"key":"key,板块名,股票数,均价,涨跌额,涨跌幅,...",...}
      // 尝试JSON解析
      try {
        final jsonStart = body.indexOf('{');
        final jsonEnd = body.lastIndexOf('}');
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          final jsonStr = body.substring(jsonStart, jsonEnd + 1);
          final data = json.decode(jsonStr) as Map<String, dynamic>;
          final sectors = <SectorInfo>[];
          for (final entry in data.values) {
            final parts = entry.toString().split(',');
            if (parts.length >= 6) {
              final name = parts[1].trim();
              final changePct = double.tryParse(parts[5].trim()) ?? 0.0;
              String leadStockName = '';
              String leadStockCode = '';
              if (parts.length >= 9) leadStockCode = parts[8].trim();
              if (parts.length >= 10) leadStockName = parts[9].trim();
              if (name.isNotEmpty) {
                sectors.add(SectorInfo(
                  name: name,
                  code: parts[0].trim(),
                  changePct: changePct,
                  leadStockName: leadStockName,
                  leadStockCode: addMarketPrefix(leadStockCode),
                ));
              }
            }
          }
          // 按涨跌幅降序排列
          sectors.sort((a, b) => b.changePct.compareTo(a.changePct));
          return sectors;
        }
      } catch (e) {
        debugPrint('Sina sectors JSON parse failed: $e');
      }
    }
    return [];
  }

  /// 获取板块内个股（涨幅前20）
  Future<List<QuoteData>> getSectorStocks(String sectorCode) async {
    final cacheKey = 'sector_stocks_$sectorCode';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<QuoteData>;

    // 主接口：东方财富板块个股
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final url = Uri.parse(
          'https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=30&po=1&np=1&fltt=2&invl=2&fid=f3&fs=b:$sectorCode+f:!50&fields=f12,f14,f2,f3,f4,f15,f16,f17,f5,f6,f60',
        );
        final response = await _httpGet(url, headers: {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://quote.eastmoney.com/',
        });
        if (response != null) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final diff = data['data']?['diff'] as List?;
          if (diff != null && diff.isNotEmpty) {
            final stocks = <QuoteData>[];
            for (final item in diff) {
              final m = item as Map<String, dynamic>;
              final rawCode = m['f12']?.toString() ?? '';
              final code = addMarketPrefix(rawCode);
              // 仅保留主板股票（沪深主板，排除创业板/科创板/北交所）
              if (!isMainBoardStock(code)) continue;
              final preClose = _parseDouble(m['f60']);
              final high = _parseDouble(m['f15']);
              final low = _parseDouble(m['f16']);
              stocks.add(QuoteData(
                code: code,
                name: m['f14']?.toString() ?? '',
                price: _parseDouble(m['f2']),
                change: _parseDouble(m['f4']),
                changePct: _parseDouble(m['f3']),
                open: _parseDouble(m['f17']),
                high: high,
                low: low,
                preClose: preClose,
                volume: _parseDouble(m['f5']),
                amount: _parseDouble(m['f6']),
                amplitude: preClose > 0 ? (high - low) / preClose * 100 : 0.0,
              ));
            }
            _setCached(cacheKey, stocks, duration: const Duration(seconds: 60));
            return stocks;
          }
        }
      } catch (e) {
        // ignore
      }
    }

    // 备用接口：新浪板块个股
    try {
      final stocks = await _fetchSectorStocksFromSina(sectorCode);
      if (stocks.isNotEmpty) {
        _setCached(cacheKey, stocks, duration: const Duration(seconds: 60));
        return stocks;
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  Future<List<QuoteData>> _fetchSectorStocksFromSina(String sectorCode) async {
    // 新浪板块个股接口：使用板块代码查询
    final encodedSectorCode = Uri.encodeComponent(sectorCode);
    final url = Uri.parse(
      'https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=30&sort=changepercent&asc=0&node=$encodedSectorCode&symbol=&_s_r_a=auto',
    );
    final response = await _httpGet(url, headers: {
      'Referer': 'https://finance.sina.com.cn',
    }, timeout: const Duration(seconds: 10));
    if (response != null) {
      final body = await _decodeGbk(response.bodyBytes);
      final data = json.decode(body);
      if (data is List && data.isNotEmpty) {
        final stocks = <QuoteData>[];
        for (final item in data) {
          final m = item as Map<String, dynamic>;
          final rawCode = m['code']?.toString() ?? '';
          final code = addMarketPrefix(rawCode);
          // 仅保留主板股票
          if (!isMainBoardStock(code)) continue;
          final price = _parseDouble(m['trade']);
          final preClose = _parseDouble(m['settlement']);
          final change = price - preClose;
          final changePct = preClose > 0 ? (change / preClose) * 100 : 0.0;
          stocks.add(QuoteData(
            code: code,
            name: m['name']?.toString() ?? '',
            price: price,
            change: change,
            changePct: changePct,
            open: _parseDouble(m['open']),
            high: _parseDouble(m['high']),
            low: _parseDouble(m['low']),
            preClose: preClose,
          ));
        }
        return stocks;
      }
    }
    return [];
  }

  /// 批量获取实时行情（腾讯批量接口）
  Future<List<QuoteData>> getBatchRealtimeQuotes(List<String> codes) async {
    if (codes.isEmpty) return [];

    final cacheKey = 'batch_quotes_${codes.join(',')}';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<QuoteData>;

    // Check if request is already in flight
    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey] as Future<List<QuoteData>>;
    }

    // Make the request
    final future = _fetchBatchRealtimeQuotes(codes, cacheKey);
    _inFlightRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  Future<List<QuoteData>> _fetchBatchRealtimeQuotes(List<String> codes, String cacheKey) async {
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
          if (parts.length >= 38) {
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
              amount: parts.length > 37 ? _parseDouble(parts[37]) * 10000 : 0,
              change: _parseDouble(parts[31]),
              changePct: _parseDouble(parts[32]),
              amplitude: amplitude,
              turnover: parts.length > 38 ? _parseDouble(parts[38]) : 0,
              pe: parts.length > 39 ? _parseDouble(parts[39]) : 0,
              pb: parts.length > 46 ? _parseDouble(parts[46]) : 0,
              totalMarketCap: parts.length > 44 ? _parseDouble(parts[44]) * 10000 : 0,
              circulatingMarketCap: parts.length > 43 ? _parseDouble(parts[43]) * 10000 : 0,
              volumeRatio: parts.length > 49 ? _parseDouble(parts[49]) : 0,
            ));
          }
        }
      }
      _setCached(cacheKey, results, duration: const Duration(seconds: 5));
      return results;
    }
    return [];
  }

  /// 当日涨停板池（东方财富 push2ex.eastmoney.com/getTopicZTPool）
  /// 返回完整涨停数据：连板数/首封时间/封单/换手/炸板标记
  Future<List<LimitUpStock>> getLimitUpBoard({DateTime? date, int pageSize = 500}) async {
    // A股交易日按上海时区(UTC+8)计算，避免海外用户日期偏移
    final base = date ?? DateTime.now();
    final shanghai = base.toUtc().add(const Duration(hours: 8));
    final dateStr = shanghai.toIso8601String().substring(0, 10).replaceAll('-', '');
    final url = Uri.parse(
      'https://push2ex.eastmoney.com/getTopicZTPool'
      '?ut=7eea3edcaed734bea9cbfc24409ed989'
      '&dpt=wz.ztzt'
      '&Pageindex=0'
      '&Pagesize=$pageSize'
      '&sort=fbt:asc'
      '&date=$dateStr'
      '&_=${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      final response = await _httpGet(url, headers: {
        'Referer': 'https://quote.eastmoney.com/ztb/detail',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0',
      });
      if (response == null) {
        debugPrint('getLimitUpBoard: response null for date=$dateStr');
        return [];
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final pool = json['data']?['pool'];
      if (pool is! List) return [];
      return pool
          .map((e) => LimitUpStock.fromEastMoney(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getLimitUpBoard failed: $e');
      return [];
    }
  }

  /// 昨日涨停股池（用于计算赚钱效应）
  Future<List<LimitUpStock>> getYesterdayLimitUpPool() async {
    final shanghaiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    var yesterday = shanghaiNow.subtract(const Duration(days: 1));
    // 跳过周末：周六回退到周五，周日回退到周五
    while (yesterday.weekday == DateTime.saturday || yesterday.weekday == DateTime.sunday) {
      yesterday = yesterday.subtract(const Duration(days: 1));
    }
    return getLimitUpBoard(date: yesterday);
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

    // 优先尝试东方财富，失败则降级到新浪
    final result = await _getTimeshareFromEastMoney(code);
    if (result != null) {
      final now = DateTime.now();
      final isWeekday = now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
      final totalMin = now.hour * 60 + now.minute;
      final isTradingHour = isWeekday && totalMin >= (9 * 60 + 30) && totalMin <= 15 * 60;
      _setCached(cacheKey, result, duration: isTradingHour ? const Duration(seconds: 5) : const Duration(seconds: 10));
      return result;
    }

    debugPrint('getTimeshareData: 东方财富分时接口失败，降级使用新浪5分钟K线');
    final fallback = await _getTimeshareFromSina(code);
    if (fallback != null) {
      _setCached(cacheKey, fallback, duration: const Duration(seconds: 60));
      return fallback;
    }

    debugPrint('getTimeshareData: 新浪分时降级也失败，分时数据不可用');
    return null;
  }

  /// 东方财富分时数据（主接口）
  Future<Map<String, Map<int, double>>?> _getTimeshareFromEastMoney(String code) async {
    String secid;
    if (code.startsWith('sh')) {
      secid = '1.${code.substring(2)}';
    } else if (code.startsWith('sz')) {
      secid = '0.${code.substring(2)}';
    } else {
      secid = code;
    }

    final url = Uri.parse(
      'https://push2his.eastmoney.com/api/qt/stock/trends2/get'
      '?secid=$secid'
      '&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13'
      '&fields2=f51,f52,f53,f54,f55,f56,f57,f58'
      '&iscr=0'
    );

    try {
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0',
        'Referer': 'https://quote.eastmoney.com/',
      });
      if (response == null) {
        debugPrint('getTimeshareData: EastMoney HTTP请求返回null (重试耗尽)');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final rc = data['rc'];
      if (rc == null) {
        debugPrint('getTimeshareData: EastMoney响应缺少rc字段, body=${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return null;
      }
      if (rc != 0) {
        debugPrint('getTimeshareData: EastMoney返回错误rc=$rc');
        return null;
      }

      final trendsData = data['data'] as Map<String, dynamic>?;
      if (trendsData == null) {
        debugPrint('getTimeshareData: EastMoney响应缺少data字段');
        return null;
      }

      final trends = trendsData['trends'] as List?;
      if (trends == null || trends.isEmpty) {
        debugPrint('getTimeshareData: EastMoney trends为空(可能非交易日)');
        return null;
      }

      final preClose = _parseDouble(trendsData['preClose']);
      final priceMap = <int, double>{};
      final volumeMap = <int, double>{};
      final amountMap = <int, double>{};

      for (final item in trends) {
        final parts = (item as String).split(',');
        if (parts.length < 5) continue;

        final timeStr = parts[0];
        final price = _parseDouble(parts[1]);
        final volume = _parseDouble(parts[2]);
        final amount = _parseDouble(parts[3]);

        final timePart = timeStr.split(' ').last;
        final timeParts = timePart.split(':');
        if (timeParts.length < 2) continue;
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final totalMinutes = hour * 60 + minute;

        const morningStart = 9 * 60 + 30;
        const morningEnd = 11 * 60 + 30;
        const afternoonStart = 13 * 60;

        int offset;
        if (totalMinutes >= morningStart && totalMinutes <= morningEnd) {
          offset = totalMinutes - morningStart;
        } else if (totalMinutes >= afternoonStart) {
          offset = 120 + (totalMinutes - afternoonStart);
        } else {
          continue;
        }

        priceMap[offset] = price;
        volumeMap[offset] = volume;
        amountMap[offset] = amount;
      }

      return {
        'prices': priceMap,
        'volumes': volumeMap,
        'amounts': amountMap,
        'preClose': {0: preClose},
      };
    } on FormatException catch (e) {
      debugPrint('getTimeshareData: EastMoney响应JSON解析失败 $e');
      return null;
    } catch (e) {
      debugPrint('getTimeshareData: EastMoney请求异常 $e');
      return null;
    }
  }

  /// 新浪5分钟K线降级（盘后和主接口失败时使用）
  Future<Map<String, Map<int, double>>?> _getTimeshareFromSina(String code) async {
    // 新浪K线API symbol格式: sh600519 或 sz000001
    final sinaCode = code.toLowerCase();

    final url = Uri.parse(
      'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData'
      '?symbol=$sinaCode&scale=5&ma=no&datalen=240'
    );

    try {
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0',
        'Referer': 'https://finance.sina.com.cn/',
      });
      if (response == null) {
        debugPrint('getTimeshareData: Sina HTTP请求返回null');
        return null;
      }

      final bodyStr = response.body.trim();
      if (bodyStr.isEmpty || bodyStr == 'null') {
        debugPrint('getTimeshareData: Sina返回空/无效响应');
        return null;
      }
      if (!bodyStr.startsWith('[')) {
        debugPrint('getTimeshareData: Sina返回非数组响应(前100字符): ${bodyStr.substring(0, bodyStr.length.clamp(0, 100))}');
        return null;
      }

      // 新浪返回格式: [{day, open, high, low, close, volume}]
      final decoded = json.decode(bodyStr);
      if (decoded is! List<dynamic>) {
        debugPrint('getTimeshareData: Sina响应不是数组, type=${decoded.runtimeType}');
        return null;
      }
      final list = decoded;
      if (list.isEmpty) {
        debugPrint('getTimeshareData: Sina返回空数据数组');
        return null;
      }

      final priceMap = <int, double>{};
      final volumeMap = <int, double>{};
      final amountMap = <int, double>{};
      double preClose = 0;

      for (int i = 0; i < list.length; i++) {
        final item = list[i] as Map<String, dynamic>;
        final day = item['day'] as String? ?? '';
        final close = _parseDouble(item['close']);
        final volume = _parseDouble(item['volume']);

        // 从5分钟K线的时间计算偏移量
        final timePart = day.split(' ').last;
        final timeParts = timePart.split(':');
        if (timeParts.length < 2) continue;
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final totalMinutes = hour * 60 + minute;

        const morningStart = 9 * 60 + 30;
        const morningEnd = 11 * 60 + 30;
        const afternoonStart = 13 * 60;

        if (totalMinutes < morningStart) {
          // 集合竞价等盘前数据，跳过
          // 首个有效bar的close作为preClose参考
          continue;
        }

        int offset;
        if (totalMinutes >= morningStart && totalMinutes <= morningEnd) {
          offset = totalMinutes - morningStart;
        } else if (totalMinutes >= afternoonStart) {
          offset = 120 + (totalMinutes - afternoonStart);
        } else {
          continue;
        }

        priceMap[offset] = close;
        // 新浪5min K线返回手数，转换为手
        volumeMap[offset] = volume;
        // 新浪没有成交额，用 close*volume 估算
        amountMap[offset] = close * volume * 100;
      }

      // 计算昨收（取第一条有效数据的open近似昨收）
      if (list.isNotEmpty) {
        final firstItem = list[0] as Map<String, dynamic>;
        final open = _parseDouble(firstItem['open']);
        if (open > 0) preClose = open;
      }

      return {
        'prices': priceMap,
        'volumes': volumeMap,
        'amounts': amountMap,
        'preClose': {0: preClose},
      };
    } on FormatException catch (e) {
      debugPrint('getTimeshareData: Sina响应JSON解析失败 $e');
      return null;
    } catch (e) {
      debugPrint('getTimeshareData: Sina请求异常 $e');
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _client.close();
    _fallbackClient?.close();
    _cache.clear();
    _inFlightRequests.clear();
  }
}
