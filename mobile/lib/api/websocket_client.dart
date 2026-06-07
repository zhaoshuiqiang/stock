import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:charset_converter/charset_converter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/stock_models.dart';

typedef QuoteUpdateCallback = void Function(QuoteData quote);

class WebSocketClient {
  static final WebSocketClient _instance = WebSocketClient._internal();
  factory WebSocketClient() => _instance;
  WebSocketClient._internal();

  String _wsUrl = 'ws://10.0.2.2:8000/ws/quote?user_id=mobile';
  WebSocketChannel? _channel;
  QuoteUpdateCallback? onQuoteUpdate;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _pollingTimer;
  final Set<String> _subscriptions = {};
  bool _usePolling = true;
  final http.Client _httpClient = http.Client();

  bool get isConnected => _isConnected;

  void setWsUrl(String url) {
    _wsUrl = url;
  }

  Future<void> connect() async {
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    if (_usePolling) {
      _startPolling();
    } else {
      await _doConnect();
    }
  }

  Future<void> _doConnect() async {
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      await _channel!.ready;
      _isConnected = true;
      _reconnectAttempts = 0;

      // 重新订阅
      for (final code in _subscriptions) {
        _channel!.sink.add(json.encode({'action': 'subscribe', 'code': code}));
      }

      // 启动心跳
      _startPing();

      _channel!.stream.listen(
        (data) {
          try {
            final jsonData = json.decode(data as String);
            if (jsonData is Map<String, dynamic>) {
              if (jsonData['type'] == 'ping') {
                _channel?.sink.add(json.encode({'type': 'pong'}));
                return;
              }
              if (jsonData['type'] == 'quote' && jsonData['data'] != null) {
                // 服务器推送格式: {"type":"quote","code":"xxx","data":{...}}
                final data = jsonData['data'] as Map<String, dynamic>;
                final quote = _parseServerQuote(data);
                if (quote != null) {
                  onQuoteUpdate?.call(quote);
                }
              } else if (jsonData['code'] != null && jsonData['price'] != null) {
                // 直接格式: {"code":"xxx","price":...}
                final quote = QuoteData.fromJson(jsonData);
                onQuoteUpdate?.call(quote);
              }
            }
          } catch (e) {
            print('WebSocket data parse error: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('WebSocket connect error: $e');
      _handleDisconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        try {
          _channel?.sink.add(json.encode({'type': 'ping'}));
        } catch (e) {
          print('Ping error: $e');
          _handleDisconnect();
        }
      }
    });
  }

  void _handleDisconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;

    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    } else if (_shouldReconnect && _reconnectAttempts >= _maxReconnectAttempts && !_usePolling) {
      _startPolling();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _getReconnectDelay();
    print('Reconnecting in ${delay.inSeconds}s... (attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect) {
        _doConnect();
      }
    });
  }

  void _startPolling() {
    _usePolling = true;
    print('WebSocket connection failed, switching to polling mode...');
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollQuotes();
    });
  }

  void _pollQuotes() async {
    if (_subscriptions.isEmpty || !_shouldReconnect) return;
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

  /// 解析服务器推送的行情数据（中文字段名映射为英文）
  QuoteData? _parseServerQuote(Map<String, dynamic> data) {
    try {
      final code = data['code'] ?? data['代码'] ?? '';
      final price = _parseDouble(data['price'] ?? data['最新价']);
      if (code == '' || price == 0) return null;
      return QuoteData(
        code: code,
        name: data['name'] ?? data['名称'] ?? '',
        price: price,
        change: _parseDouble(data['change'] ?? data['涨跌额']),
        changePct: _parseDouble(data['change_pct'] ?? data['涨跌幅']),
        open: _parseDouble(data['open'] ?? data['今开']),
        high: _parseDouble(data['high'] ?? data['最高']),
        low: _parseDouble(data['low'] ?? data['最低']),
        preClose: _parseDouble(data['prev_close'] ?? data['昨收']),
        volume: _parseDouble(data['volume'] ?? data['成交量']),
        amount: _parseDouble(data['amount'] ?? data['成交额']),
        amplitude: _parseDouble(data['amplitude'] ?? data['振幅']),
        turnover: _parseDouble(data['turnover'] ?? data['换手率']),
        pe: _parseDouble(data['pe'] ?? data['市盈率-动态']),
        pb: _parseDouble(data['pb'] ?? data['市净率']),
        totalMarketCap: _parseDouble(data['total_market_cap']),
        circulatingMarketCap: _parseDouble(data['circulating_market_cap']),
      );
    } catch (e) {
      print('Parse server quote error: $e');
      return null;
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

  Duration _getReconnectDelay() {
    _reconnectAttempts++;
    final maxDelay = Duration(seconds: 60);
    final baseDelay = Duration(seconds: 1);
    final delay = baseDelay * (1 << (_reconnectAttempts - 1));
    return delay > maxDelay ? maxDelay : delay;
  }

  void subscribe(String code) {
    _subscriptions.add(code);
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode({'action': 'subscribe', 'code': code}));
    }
  }

  void unsubscribe(String code) {
    _subscriptions.remove(code);
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode({'action': 'unsubscribe', 'code': code}));
    }
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pollingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _usePolling = false;
    _reconnectAttempts = 0;
    _subscriptions.clear();
    _httpClient.close();
  }
}