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
  http.Client? _httpClient;

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

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollQuotes();
    });
  }

  void _pollQuotes() async {
    if (_subscriptions.isEmpty || !_shouldPoll) return;
    try {
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
    if (parts.length >= 45) circulatingMarketCap = _parseDouble(parts[44]) * 10000;
    if (parts.length >= 46) totalMarketCap = _parseDouble(parts[45]) * 10000;

    final code = parts[2] ?? '';
    final high = _parseDouble(parts[33]);
    final low = _parseDouble(parts[34]);
    final preClose = _parseDouble(parts[4]);
    final amplitude = preClose > 0 ? (high - low) / preClose * 100 : 0.0;

    return QuoteData(
      code: code,
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
    _httpClient?.close();
    _httpClient = null;
  }

  /// 释放资源
  void dispose() {
    disconnect();
  }
}

/// 向后兼容的类型别名
@Deprecated('Use QuotePollingClient instead')
typedef WebSocketClient = QuotePollingClient;
