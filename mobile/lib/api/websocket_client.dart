import 'dart:async';
import 'dart:convert';
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
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  final Set<String> _subscriptions = {};

  bool get isConnected => _isConnected;

  void setWsUrl(String url) {
    _wsUrl = url;
  }

  Future<void> connect() async {
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    await _doConnect();
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
              if (jsonData['code'] != null) {
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

    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _getReconnectDelay();
    print('Reconnecting in ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect) {
        _doConnect();
      }
    });
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
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _subscriptions.clear();
  }
}