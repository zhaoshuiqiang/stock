import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:charset_converter/charset_converter.dart';
import '../models/stock_models.dart';

typedef QuoteUpdateCallback = void Function(QuoteData quote);

/// 实时行情轮询客户端
/// 使用HTTP定时轮询获取行情数据（非WebSocket协议）
class QuotePollingClient {
  static final QuotePollingClient _instance = QuotePollingClient._internal();
  factory QuotePollingClient() => _instance;
  QuotePollingClient._internal();

  QuoteUpdateCallback? onQuoteUpdate;
  Timer? _pollingTimer;
  final Set<String> _subscriptions = {};
  bool _shouldPoll = false;
  bool _isPolling = false;
  http.Client? _httpClient;
  Duration _interval = const Duration(seconds: 5);

  /// 兼容旧名称的引用
  @Deprecated('Use QuotePollingClient instead')
  static QuotePollingClient get WebSocketClientInstance => _instance;

  http.Client _getClient() {
    _httpClient ??= http.Client();
    return _httpClient!;
  }

  Future<void> connect() async {
    _shouldPoll = true;
    _startPolling();
  }

  /// 设置轮询间隔（持仓页盘中用3秒，其他场景用5秒）
  void setInterval(Duration interval) {
    if (_interval != interval) {
      _interval = interval;
      if (_shouldPoll) _startPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_interval, (_) {
      _pollQuotes();
    });
  }

  Future<void> _pollQuotes() async {
    if (_isPolling) return; // 防止重入
    _isPolling = true;
    try {
      if (_subscriptions.isEmpty || !_shouldPoll) return;
      // 批量请求：使用腾讯批量接口一次获取所有订阅股票行情
      final codes = _subscriptions.toList();
      if (codes.isEmpty) return;

      final codesStr = codes.join(',');
      final url = Uri.parse('https://qt.gtimg.cn/q=$codesStr');
      final response = await _getClient().get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        String body;
        try {
          body = await CharsetConverter.decode("GBK", response.bodyBytes);
        } catch (e) {
          body = utf8.decode(response.bodyBytes, allowMalformed: true);
        }

        // 每只股票数据以分号分隔
        final entries = body.split(';');
        for (final entry in entries) {
          final quote = _parseQuoteFromEntry(entry);
          if (quote != null) {
            onQuoteUpdate?.call(quote);
          }
        }
      }
    } catch (e) {
      debugPrint('Polling error: $e');
    } finally {
      _isPolling = false;
    }
  }

  /// 从腾讯API单条数据解析行情
  QuoteData? _parseQuoteFromEntry(String entry) {
    final start = entry.indexOf('="');
    final end = entry.lastIndexOf('"');
    if (start < 0 || end <= start) return null;

    final dataStr = entry.substring(start + 2, end);
    final parts = dataStr.split('~');
    if (parts.length < 30) return null;

    double pe = 0, pb = 0, totalMarketCap = 0, circulatingMarketCap = 0, turnover = 0;
    if (parts.length >= 40) pe = _parseDouble(parts[39]);
    if (parts.length >= 47) pb = _parseDouble(parts[46]);
    if (parts.length >= 39) turnover = _parseDouble(parts[38]);
    if (parts.length >= 44) circulatingMarketCap = _parseDouble(parts[43]) * 10000;
    if (parts.length >= 45) totalMarketCap = _parseDouble(parts[44]) * 10000;

    final code = parts[2] ?? '';
    final high = _parseDouble(parts[33]);
    final low = _parseDouble(parts[34]);
    final preClose = _parseDouble(parts[4]);
    final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;

    return QuoteData(
      code: _addMarketPrefix(code),
      name: parts[1] ?? '',
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
      turnover: turnover,
      pe: pe,
      pb: pb,
      totalMarketCap: totalMarketCap,
      circulatingMarketCap: circulatingMarketCap,
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// 为裸代码添加市场前缀（sh/sz/bj）
  String _addMarketPrefix(String code) {
    if (code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj')) {
      return code;
    }
    if (code.startsWith('6')) return 'sh$code';
    if (code.startsWith('8') || code.startsWith('43') || code.startsWith('9')) return 'bj$code';
    return 'sz$code';
  }

  void subscribe(String code) {
    _subscriptions.add(code);
  }

  void unsubscribe(String code) {
    _subscriptions.remove(code);
  }

  /// 批量订阅
  void subscribeAll(Iterable<String> codes) {
    _subscriptions.addAll(codes);
  }

  /// 批量退订
  void unsubscribeAll(Iterable<String> codes) {
    for (final c in codes) {
      _subscriptions.remove(c);
    }
  }

  /// 当前订阅代码（不可变视图）
  Set<String> get subscriptions => Set.unmodifiable(_subscriptions);

  void disconnect() {
    _shouldPoll = false;
    _pollingTimer?.cancel();
    _subscriptions.clear();
    _httpClient?.close();
    _httpClient = null;
    onQuoteUpdate = null;
  }

  /// 释放资源
  void dispose() {
    disconnect();
  }
}

/// 向后兼容的类型别名
@Deprecated('Use QuotePollingClient instead')
typedef WebSocketClient = QuotePollingClient;
