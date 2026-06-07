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
  static const int _maxCacheSize = 100;
  String _baseUrl = '';

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<List<StockInfo>> searchStocks(String keyword) async {
    final cacheKey = 'search_$keyword';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<StockInfo>;

    try {
      final url = Uri.parse('https://suggest3.sinajs.cn/suggest/type=111&key=$keyword');
      final response = await _client.get(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
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
                final name = parts[0];
                final rawCode = parts[2];
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
            for (var i = 0; i < parts.length; i += 4) {
              if (i + 3 < parts.length) {
                final name = parts[i];
                final rawCode = parts[i + 2];
                final code = addMarketPrefix(rawCode);
                results.add(StockInfo(
                  code: code,
                  name: name,
                  display: '$name($rawCode)',
                ));
              }
            }
          }
          
          _setCached(cacheKey, results);
          return results;
        }
      }
    } catch (e) {
      print('Search error: $e');
    }
    return [];
  }

  Future<QuoteData?> getRealtimeQuote(String code) async {
    final cacheKey = 'quote_$code';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as QuoteData;

    try {
      final url = Uri.parse('https://qt.gtimg.cn/q=$code');
      final response = await _client.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
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
            _setCached(cacheKey, quote);
            return quote;
          }
        }
      }
    } catch (e) {
      print('Quote error: $e');
    }

    try {
      final url = Uri.parse('https://hq.sinajs.cn/list=$code');
      final response = await _client.get(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = await _decodeGbk(response.bodyBytes);
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
            _setCached(cacheKey, quote);
            return quote;
          }
        }
      }
    } catch (e) {
      print('Quote error (fallback): $e');
    }
    return null;
  }

  Future<QuoteData?> getMainFundFlow(String code) async {
    try {
      String secid;
      if (code.startsWith('sh')) {
        secid = '1.${code.substring(2)}';
      } else if (code.startsWith('sz')) {
        secid = '0.${code.substring(2)}';
      } else {
        secid = code;
      }
      
      final url = Uri.parse('https://push2.eastmoney.com/api/qt/ulist.np/get?fields=f62,f184,f66,f69,f72,f75,f78,f81,f84,f87&secids=$secid');
      final response = await _client.get(url, headers: {
        'User-Agent': 'Mozilla/5.0',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
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
    } catch (e) {
      print('Main fund flow error: $e');
    }
    return null;
  }

  Future<List<HistoryKline>> getStockHistory(String code, {int days = 120}) async {
    final cacheKey = 'history_${code}_$days';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<HistoryKline>;

    try {
      final url = Uri.parse(
          'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=$code&scale=240&ma=no&datalen=$days');
      final response = await _client.get(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = response.body;
        final data = json.decode(body) as List;
        final results = <HistoryKline>[];
        
        for (int i = 0; i < data.length; i++) {
          final item = data[i] as Map<String, dynamic>;
          final close = _parseDouble(item['close']);
          final open = _parseDouble(item['open']);
          double preClose = open;
          if (i > 0) {
            preClose = _parseDouble(data[i - 1]['close']);
          }
          final change = close - preClose;
          final changePct = preClose > 0 ? (change / preClose) * 100 : 0.0;
          
          results.add(HistoryKline(
            date: DateTime.tryParse(item['day'] ?? '') ?? DateTime.now(),
            open: open,
            high: _parseDouble(item['high']),
            low: _parseDouble(item['low']),
            close: close,
            volume: _parseDouble(item['volume']),
            amount: _parseDouble(item['amount']),
            change: change,
            changePct: changePct,
          ));
        }
        _setCached(cacheKey, results);
        return results;
      }
    } catch (e) {
      print('History error: $e');
    }
    return [];
  }

  Future<MarketSentiment?> getMarketSentiment() async {
    try {
      final url = Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=1&sort=changepercent&asc=0&node=hs_a&symbol=&_s_r_a=auto');
      final response = await _client.get(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body;
        final data = json.decode(body);
        
        if (data is List && data.isNotEmpty) {
          final item = data.first as Map<String, dynamic>;
          return MarketSentiment(
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
        } else if (data is Map<String, dynamic>) {
          return MarketSentiment(
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
        }
      }
    } catch (e) {
      print('Market sentiment error: $e');
    }
    return null;
  }

  dynamic _getCached(String key) {
    final cached = _cache[key];
    if (cached is Map && cached['timestamp'] != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(cached['timestamp'] as int);
      if (DateTime.now().difference(timestamp) < _cacheDuration) {
        return cached['data'];
      }
    }
    return null;
  }

  void _setCached(String key, dynamic data) {
    if (_cache.length >= _maxCacheSize) {
      _cleanupCache();
    }
    _cache[key] = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
  }

  void _cleanupCache() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _cache.removeWhere((key, value) {
      if (value is Map && value['timestamp'] != null) {
        final timestamp = value['timestamp'] as int;
        return now - timestamp > _cacheDuration.inMilliseconds;
      }
      return true;
    });

    if (_cache.length >= _maxCacheSize) {
      final sortedKeys = _cache.keys.toList()..sort((a, b) {
        final ta = (_cache[a] as Map)['timestamp'] as int;
        final tb = (_cache[b] as Map)['timestamp'] as int;
        return ta.compareTo(tb);
      });
      for (var i = 0; i < sortedKeys.length ~/ 2; i++) {
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
    try {
      final url = Uri.parse('https://newsapi.eastmoney.com/kuaixun/v1/getlist_102_ajaxResult_50_1_.html');
      final response = await _client.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final body = response.body;
        // 返回格式: var ajaxResult={...}
        final jsonStart = body.indexOf('{');
        final jsonEnd = body.lastIndexOf('}');
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          final jsonStr = body.substring(jsonStart, jsonEnd + 1);
          final data = json.decode(jsonStr) as Map<String, dynamic>;
          final list = data['LivesList'] as List?;
          if (list != null) {
            return list.map((item) => {
              'title': item['title'] ?? '',
              'digest': item['digest'] ?? item['simdigest'] ?? '',
              'url': item['url_m'] ?? item['url_w'] ?? '',
              'showTime': item['showtime'] ?? '',
              'source': item['column'] == '100,102,105' ? '东方财富' : '财经快讯',
            }).toList();
          }
        }
      }
    } catch (e) {
      print('Market news error: $e');
    }
    return [];
  }

  /// 获取个股相关新闻
  Future<List<dynamic>> getStockNews(String stockName) async {
    try {
      final encoded = Uri.encodeComponent(stockName);
      final url = Uri.parse('https://search-api-web.eastmoney.com/search/jsonp?cb=jQueryCallback&param=%7B%22uid%22%3A%22%22%2C%22keyword%22%3A%22$encoded%22%2C%22type%22%3A%5B%22cmsArticleWebOld%22%5D%2C%22client%22%3A%22web%22%2C%22clientType%22%3A%22web%22%2C%22clientVersion%22%3A%22curr%22%2C%22param%22%3A%7B%22cmsArticleWebOld%22%3A%7B%22searchScope%22%3A%22default%22%2C%22sort%22%3A%22default%22%2C%22pageIndex%22%3A1%2C%22pageSize%22%3A10%2C%22preTag%22%3A%22%22%2C%22postTag%22%3A%22%22%7D%7D%7D');
      final response = await _client.get(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://so.eastmoney.com/',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        var body = response.body;
        // 去掉 JSONP 包裹：jQueryCallback({...})
        final jsonpMatch = RegExp(r'^[a-zA-Z_]\w*\(([\s\S]*)\);?$').firstMatch(body);
        if (jsonpMatch != null) {
          body = jsonpMatch.group(1)!;
        } else {
          // 兆底：去掉首尾括号
          if (body.startsWith('(')) body = body.substring(1);
          if (body.endsWith(')')) body = body.substring(0, body.length - 1);
        }
        final data = json.decode(body) as Map<String, dynamic>;
        final result = data['result'] as Map<String, dynamic>?;
        if (result != null) {
          // cmsArticleWebOld 是一个直接的 List（数组），不是 Map
          final list = result['cmsArticleWebOld'] as List?;
          if (list != null) {
            return list.map((item) => {
              'title': item['title'] ?? item['articleTitle'] ?? '',
              'digest': item['content'] ?? item['description'] ?? '',
              'url': item['url'] ?? item['articleUrl'] ?? '',
              'showTime': item['date'] ?? item['publishDate'] ?? '',
              'source': item['mediaName'] ?? item['source'] ?? '',
            }).toList();
          }
        }
      }
    } catch (e) {
      print('Stock news error ($stockName): $e');
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

  Future<String> _decodeGbk(Uint8List bytes) async {
    try {
      return await CharsetConverter.decode("GBK", bytes);
    } catch (e) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
