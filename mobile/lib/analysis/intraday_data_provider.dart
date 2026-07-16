import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import '../api/api_client.dart';

class IntradayDataProvider {
  static final IntradayDataProvider _instance = IntradayDataProvider._();
  factory IntradayDataProvider() => _instance;
  IntradayDataProvider._();

  final ApiClient _apiClient = ApiClient();
  final Map<String, List<IntradayKline>> _cache = {};
  final Map<String, DateTime> _cacheTime = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  Future<List<IntradayKline>> fetchIntradayKline(String code) async {
    final now = DateTime.now();
    final cachedTime = _cacheTime[code];
    if (cachedTime != null && now.difference(cachedTime) < _cacheTtl) {
      final cached = _cache[code];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    try {
      final marketPrefix = code.startsWith('6') ? '1' : '0';
      final secid = '$marketPrefix.$code';
      final rawData = await _apiClient.getIntradayKline(
        secid: secid,
        klt: 5,
        lmt: 48,
      );
      final klines = rawData
          .map((row) => IntradayKline.fromApi(row))
          .where((k) => k.open > 0)
          .toList();
      _cache[code] = klines;
      _cacheTime[code] = now;
      return klines;
    } catch (e) {
      debugPrint('[分时数据] 获取失败: $e');
      return _cache[code] ?? [];
    }
  }

  void clearCache() {
    _cache.clear();
    _cacheTime.clear();
  }

  void clearCacheFor(String code) {
    _cache.remove(code);
    _cacheTime.remove(code);
  }
}
