import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:charset_converter/charset_converter.dart';
import '../models/stock_models.dart';

typedef QuoteUpdateCallback = void Function(QuoteData quote);

class WebSocketClient {
  static final WebSocketClient _instance = WebSocketClient._internal();
  factory WebSocketClient() => _instance;
  WebSocketClient._internal();

  QuoteUpdateCallback? onQuoteUpdate;
  Timer? _pollingTimer;
  final Set<String> _subscriptions = {};
  bool _shouldPoll = false;
  final http.Client _httpClient = http.Client();

  Future<void> connect() async {
    _shouldPoll = true;
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollQuotes();
    });
  }

  void _pollQuotes() async {
    if (_subscriptions.isEmpty || !_shouldPoll) return;
    try {
      for (final code in _subscriptions) {
        final quote = await _fetchQuote(code);
        if (quote != null) {
          onQuoteUpdate?.call(quote);
        }
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  Future<QuoteData?> _fetchQuote(String code) async {
    try {
      final url = Uri.parse('https://qt.gtimg.cn/q=$code');
      final response = await _httpClient.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        String body;
        try {
          body = await CharsetConverter.decode("GBK", response.bodyBytes);
        } catch (e) {
          body = utf8.decode(response.bodyBytes, allowMalformed: true);
        }
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
              circulatingMarketCap = _parseDouble(parts[44]) * 10000;
            }
            if (parts.length >= 46) {
              totalMarketCap = _parseDouble(parts[45]) * 10000;
            }

            final high = _parseDouble(parts[33]);
            final low = _parseDouble(parts[34]);
            final preClose = _parseDouble(parts[4]);
            final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;

            return QuoteData(
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
          }
        }
      }
    } catch (e) {
      print('Fetch quote error: $e');
    }
    return null;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  void subscribe(String code) {
    _subscriptions.add(code);
  }

  void unsubscribe(String code) {
    _subscriptions.remove(code);
  }

  void disconnect() {
    _shouldPoll = false;
    _pollingTimer?.cancel();
    _subscriptions.clear();
    _httpClient.close();
  }
}
