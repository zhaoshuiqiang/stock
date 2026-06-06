import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/stock_models.dart';

class ApiClient {
  final http.Client _client = http.Client();
  final Map<String, dynamic> _cache = {};
  final Duration _cacheDuration = const Duration(minutes: 5);

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
        final body = response.body;
        final start = body.indexOf('[');
        final end = body.lastIndexOf(']');
        if (start >= 0 && end > start) {
          final jsonStr = body.substring(start, end + 1);
          final data = json.decode(jsonStr) as List;
          final results = data
              .where((item) => item is List && item.length >= 4)
              .map((item) => StockInfo(
                    code: item[3].toString(),
                    name: item[0].toString(),
                    display: '${item[0]}(${item[3]})',
                  ))
              .toList();
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
      final market = code.startsWith('sh') ? 'sh' : 'sz';
      final url = Uri.parse('https://hq.sinajs.cn/list=$market$code');
      final response = await _client.get(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body;
        final start = body.indexOf('="');
        final end = body.lastIndexOf('";');
        if (start >= 0 && end > start) {
          final dataStr = body.substring(start + 2, end);
          final parts = dataStr.split(',');
          if (parts.length >= 11) {
            final quote = QuoteData(
              code: code,
              name: parts[0],
              price: _parseDouble(parts[3]),
              open: _parseDouble(parts[1]),
              high: _parseDouble(parts[4]),
              low: _parseDouble(parts[5]),
              preClose: _parseDouble(parts[2]),
              volume: _parseDouble(parts[8]),
              amount: _parseDouble(parts[9]),
              change: _parseDouble(parts[3]) - _parseDouble(parts[2]),
              changePct: (_parseDouble(parts[3]) - _parseDouble(parts[2])) /
                      (_parseDouble(parts[2]) > 0 ? _parseDouble(parts[2]) : 1) *
                  100,
            );
            _setCached(cacheKey, quote);
            return quote;
          }
        }
      }
    } catch (e) {
      print('Quote error: $e');
    }
    return null;
  }

  Future<List<HistoryKline>> getStockHistory(String code, {int days = 120}) async {
    final cacheKey = 'history_${code}_$days';
    final cached = _getCached(cacheKey);
    if (cached != null) return cached as List<HistoryKline>;

    try {
      final market = code.startsWith('sh') ? 'sh' : 'sz';
      final url = Uri.parse(
          'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=${market}${code}&scale=240&ma=no&datalen=$days');
      final response = await _client.get(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = response.body;
        final data = json.decode(body) as List;
        final results = data
            .where((item) => item is Map<String, dynamic>)
            .map((item) => HistoryKline(
                  date: DateTime.tryParse(item['day'] ?? '') ?? DateTime.now(),
                  open: _parseDouble(item['open']),
                  high: _parseDouble(item['high']),
                  low: _parseDouble(item['low']),
                  close: _parseDouble(item['close']),
                  volume: _parseDouble(item['volume']),
                  amount: _parseDouble(item['amount']),
                  change: _parseDouble(item['change']),
                  changePct: _parseDouble(item['changepercent']),
                ))
            .toList();
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
        final data = json.decode(body) as Map<String, dynamic>;
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
    _cache[key] = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
