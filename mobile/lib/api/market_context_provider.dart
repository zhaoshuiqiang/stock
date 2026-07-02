import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:charset_converter/charset_converter.dart';
import '../models/stock_models.dart';

/// 市场环境提供者
class MarketContextProvider {
  static const String _fullSinaUrl = 'https://hq.sinajs.cn/list=sh000001,sz399001';
  static const String _hotEastMoneyUrl = 'https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=30&po=1&np=1&fltt=2&invl=2&fid=f3&fs=m:90+t:2&fields=f12,f14,f2,f3,f104,f105,f128,f136,f140,f141';

  static http.Client? _httpClient;

  static http.Client _getClient() {
    _httpClient ??= http.Client();
    return _httpClient!;
  }

  /// 关闭并释放 HTTP 客户端
  static void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }

  /// 获取市场环境（优先使用新浪，备用东方财富）
  static Future<MarketContext> getMarketContext() async {
    // 先尝试新浪完整行情API
    final sinaContext = await _fetchFromSina();
    if (sinaContext != null) {
      return sinaContext;
    }

    // 新浪失败，尝试东方财富
    final eastMoneyContext = await _fetchFromEastMoney();
    if (eastMoneyContext != null) {
      return eastMoneyContext;
    }

    // 都失败，返回空环境
    return MarketContext(
      shIndexPct: 0,
      szIndexPct: 0,
      indexChange: 0,
      marketTrend: 'neutral',
      upCount: 0,
      downCount: 0,
      avgChangePct: 0,
      updateTime: DateTime.now(),
    );
  }

  /// 从新浪获取市场环境
  static Future<MarketContext?> _fetchFromSina() async {
    try {
      // 使用完整行情格式获取指数数据（非简化格式）
      final url = Uri.parse(_fullSinaUrl);
      final response = await _httpGet(url, headers: {
        'Referer': 'https://finance.sina.com.cn',
      }, retries: 2);

      if (response != null) {
        final body = await _decodeGbk(response.bodyBytes);
        final lines = body.split('\n');

        double shIndexPct = 0;
        double szIndexPct = 0;

        for (final line in lines) {
          if (line.isEmpty) continue;

          // 完整行情格式：var hq_str_sh000001="..."
          if (line.startsWith('var hq_str_sh000001') || line.startsWith('var hq_str_s_sh000001')) {
            final start = line.indexOf('"') + 1;
            final end = line.lastIndexOf('"');
            if (start >= 0 && end > start) {
              final dataStr = line.substring(start, end);
              final parts = dataStr.split(',');

              // 完整行情格式(32+字段): 昨收=parts[2], 现价=parts[3]
              // 简化行情格式(~8字段): 名称,价格,涨跌额,涨跌幅,成交量,成交额,...
              if (parts.length >= 32) {
                // 完整行情格式
                final preClose = QuoteData.parseDouble(parts[2]);
                final currentPrice = QuoteData.parseDouble(parts[3]);
                if (preClose > 0) {
                  shIndexPct = ((currentPrice - preClose) / preClose) * 100;
                }
              } else if (parts.length >= 4) {
                // 简化行情格式: 名称,价格,涨跌额,涨跌幅,...
                shIndexPct = QuoteData.parseDouble(parts[3]);
              }
            }
          } else if (line.startsWith('var hq_str_sz399001') || line.startsWith('var hq_str_s_sz399001')) {
            final start = line.indexOf('"') + 1;
            final end = line.lastIndexOf('"');
            if (start >= 0 && end > start) {
              final dataStr = line.substring(start, end);
              final parts = dataStr.split(',');

              if (parts.length >= 32) {
                final preClose = QuoteData.parseDouble(parts[2]);
                final currentPrice = QuoteData.parseDouble(parts[3]);
                if (preClose > 0) {
                  szIndexPct = ((currentPrice - preClose) / preClose) * 100;
                }
              } else if (parts.length >= 4) {
                szIndexPct = QuoteData.parseDouble(parts[3]);
              }
            }
          }
        }

        // 从东方财富获取涨跌家数（新浪不提供此数据）
        int upCount = 0;
        int downCount = 0;
        double avgChangePct = 0;
        final eastMoney = await _fetchFromEastMoney();
        if (eastMoney != null) {
          upCount = eastMoney.upCount;
          downCount = eastMoney.downCount;
          avgChangePct = eastMoney.avgChangePct;
        }

        return MarketContext(
          shIndexPct: shIndexPct,
          szIndexPct: szIndexPct,
          indexChange: ((shIndexPct + szIndexPct) / 2),
          marketTrend: _classifyMarketTrend(shIndexPct),
          upCount: upCount,
          downCount: downCount,
          avgChangePct: avgChangePct,
          updateTime: DateTime.now(),
        );
      }
    } catch (e) {
      // ignore
    }

    return null;
  }

  /// 从东方财富获取市场环境
  static Future<MarketContext?> _fetchFromEastMoney() async {
    try {
      final url = Uri.parse(_hotEastMoneyUrl);
      final response = await _httpGet(url, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://quote.eastmoney.com/',
      }, retries: 2);

      if (response != null) {
        final body = response.body;
        final data = json.decode(body) as Map<String, dynamic>;

        final diff = data['data']?['diff'] as List?;
        if (diff != null && diff.isNotEmpty) {
          double shIndexPct = 0;
          double szIndexPct = 0;
          int upCount = 0;
          int downCount = 0;

          for (final item in diff) {
            final m = item as Map<String, dynamic>;
            final changePct = QuoteData.parseDouble(m['f3']);
            final riseCount = (m['f104'] as num?)?.toInt() ?? 0;
            final fallCount = (m['f105'] as num?)?.toInt() ?? 0;

            final code = m['f12']?.toString() ?? '';
            if (code.startsWith('1.')) {
              shIndexPct = changePct;
            } else if (code.startsWith('0.')) {
              szIndexPct = changePct;
            }

            upCount += riseCount;
            downCount += fallCount;
          }

          return MarketContext(
            shIndexPct: shIndexPct,
            szIndexPct: szIndexPct,
            indexChange: ((shIndexPct + szIndexPct) / 2),
            marketTrend: _classifyMarketTrend(shIndexPct),
            upCount: upCount,
            downCount: downCount,
            avgChangePct: 0,
            updateTime: DateTime.now(),
          );
        }
      }
    } catch (e) {
      // ignore
    }

    return null;
  }

  /// 市场趋势分类
  static String _classifyMarketTrend(double indexPct) {
    if (indexPct > 1.5) return 'strong_up';
    if (indexPct > 0.5) return 'up';
    if (indexPct > -0.5) return 'neutral';
    if (indexPct > -1.5) return 'down';
    return 'strong_down';
  }

  /// HTTP GET 请求（带重试）
  static Future<http.Response?> _httpGet(Uri url, {Map<String, String>? headers, int retries = 2}) async {
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final response = await _getClient().get(url, headers: headers ?? {}).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) return response;
      } catch (e) {
        debugPrint('HTTP attempt ${attempt + 1}/$retries failed: ${url.host}${url.path} - $e');
        if (attempt < retries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
    return null;
  }

  /// GBK 解码（使用 charset_converter 正确解码）
  static Future<String> _decodeGbk(Uint8List bytes) async {
    try {
      return await CharsetConverter.decode("GBK", bytes);
    } catch (e) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}