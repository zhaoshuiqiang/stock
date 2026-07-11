import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/storage/database_service.dart';
import 'package:stock_analyzer/core/navigator_key.dart';
import 'package:stock_analyzer/core/trading_session.dart';
import 'package:stock_analyzer/screens/webview_screen.dart';
import 'package:stock_analyzer/screens/quote_screen.dart';
import 'package:stock_analyzer/analysis/intraday_level_analyzer.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/models/stock_models.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();

  Timer? _pollTimer;
  Timer? _intradayPollTimer;
  String _lastNewsId = '';
  bool _initialized = false;

  static const String _prefKeyEnabled = 'news_notification_enabled';
  static const String _prefKeyInterval = 'news_notification_interval';
  static const String _prefKeyLastNewsId = 'last_news_id';
  static const String _channelId = 'stock_news';
  static const String _channelName = '股票资讯推送';
  static const String _channelDesc = '自选股和财经快讯推送通知';
  static const String _alertChannelId = 'stock_alerts';
  static const String _alertChannelName = '预警通知';
  static const String _alertChannelDesc = '自选股价格和指标预警通知';

  // 日内高抛低吸信号通道
  static const String _intradayChannelId = 'stock_intraday';
  static const String _intradayChannelName = '高抛低吸信号';
  static const String _intradayChannelDesc = '持仓股分时高抛低吸信号推送';

  // 预警冷却时间：同一预警5分钟内不重复触发
  static const int _alertCooldownMinutes = 5;

  // 日内信号时效：信号产生后超过此分钟数不再推送
  static const int _intradaySignalMaxAgeMinutes = 5;
  // 日内信号轮询间隔（秒）
  static const int _intradayPollIntervalSeconds = 30;
  // 日内信号单次扫描持仓股上限
  static const int _intradayMaxPositions = 20;

  static const String _intradayPrefKeyEnabled = 'intraday_notification_enabled';

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final prefs = await SharedPreferences.getInstance();
    _lastNewsId = prefs.getString(_prefKeyLastNewsId) ?? '';

    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    // 高抛低吸信号：payload 格式 "quote|{code}|{name}"
    if (payload.startsWith('quote|')) {
      final parts = payload.split('|');
      final code = parts.length > 1 ? parts[1] : '';
      final name = parts.length > 2 ? parts[2] : '';
      if (code.isNotEmpty) {
        _navigateToQuoteScreen(code, name);
      }
      return;
    }

    // 资讯/预警：payload 格式 "{url}|{title}"
    final parts = payload.split('|');
    final url = parts[0];
    final title = parts.length > 1 ? parts[1] : '';
    if (url.isNotEmpty) {
      _navigateToWebView(url, title);
    }
  }

  void _navigateToQuoteScreen(String code, String name) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuoteScreen(code: code, name: name),
        ),
      );
    }
  }

  void _navigateToWebView(String url, String title) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebViewScreen(url: url, title: title),
        ),
      );
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyEnabled) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, enabled);
    if (enabled) {
      startPolling();
      // 日内信号独立控制，不再随资讯推送联动开关
      if (await isIntradayEnabled()) {
        startIntradayPolling();
      }
    } else {
      stopPolling();
      // 不停止日内轮询 - 二者独立控制
    }
  }

  Future<bool> isIntradayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_intradayPrefKeyEnabled) ?? true;
  }

  Future<void> setIntradayEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_intradayPrefKeyEnabled, enabled);
    if (enabled) {
      startIntradayPolling();
    } else {
      stopIntradayPolling();
    }
  }

  Future<int> getIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefKeyInterval) ?? 15;
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyInterval, minutes);
    // 如果正在轮询，重启以应用新间隔
    if (_pollTimer != null) {
      stopPolling();
      startPolling();
    }
  }

  void startPolling() async {
    stopPolling();
    final enabled = await isEnabled();
    if (!enabled) return;

    final interval = await getIntervalMinutes();
    _pollTimer = Timer.periodic(Duration(minutes: interval), (_) {
      _checkForNewNews();
      _checkAlerts();
    });

    // 启动时立即检查一次
    _checkForNewNews();
    _checkAlerts();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 启动日内高抛低吸信号轮询（30秒间隔）
  void startIntradayPolling() async {
    stopIntradayPolling();
    if (!await isIntradayEnabled()) return;

    _intradayPollTimer = Timer.periodic(
      Duration(seconds: _intradayPollIntervalSeconds),
      (_) => _checkIntradaySignals(),
    );
    // 启动时立即检查一次
    _checkIntradaySignals();
  }

  void stopIntradayPolling() {
    _intradayPollTimer?.cancel();
    _intradayPollTimer = null;
  }

  Future<void> _checkForNewNews() async {
    try {
      // 检查财经快讯
      final marketNews = await _apiClient.getMarketNews();
      if (marketNews.isNotEmpty) {
        final latest = marketNews.first;
        final newsId = latest['showTime'] ?? latest['title'] ?? '';
        if (newsId.isNotEmpty && newsId != _lastNewsId && _lastNewsId.isNotEmpty) {
          final title = latest['title'] ?? '财经快讯';
          final url = latest['url'] ?? '';
          await _showNotification(
            id: 0,
            title: '财经快讯',
            body: title.length > 50 ? '${title.substring(0, 50)}...' : title,
            payload: '$url|$title',
          );
        }
        if (newsId.isNotEmpty) {
          _lastNewsId = newsId;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKeyLastNewsId, newsId);
        }
      }

      // 检查自选股资讯
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isNotEmpty) {
        int notificationId = 1;
        for (final stock in watchlist.take(3)) {
          final stockNews = await _apiClient.getStockNews(stock.name);
          if (stockNews.isNotEmpty) {
            final latest = stockNews.first;
            final newsKey = 'stock_news_${stock.code}_${latest['showTime'] ?? latest['title'] ?? ''}';
            final prefs = await SharedPreferences.getInstance();
            final lastKey = prefs.getString('last_stock_news_${stock.code}');
            if (lastKey != null && newsKey != lastKey) {
              final title = latest['title'] ?? '${stock.name}资讯';
              final url = latest['url'] ?? '';
              await _showNotification(
                id: notificationId,
                title: '${stock.name} 新资讯',
                body: title.length > 50 ? '${title.substring(0, 50)}...' : title,
                payload: '$url|$title',
              );
              notificationId++;
            }
            if (newsKey.isNotEmpty) {
              final prefs2 = await SharedPreferences.getInstance();
              await prefs2.setString('last_stock_news_${stock.code}', newsKey);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('News poll error: $e');
    }
  }

  /// 检查所有启用的预警规则
  Future<void> _checkAlerts() async {
    try {
      final alerts = await _dbService.getEnabledAlerts();
      if (alerts.isEmpty) return;

      // 按股票代码分组，减少API调用
      final codeGroups = <String, List<AlertRule>>{};
      for (final alert in alerts) {
        codeGroups.putIfAbsent(alert.code, () => []).add(alert);
      }

      int notificationId = 100; // 预警通知ID从100开始，避免与新闻通知冲突

      for (final entry in codeGroups.entries) {
        final code = entry.key;
        final rules = entry.value;

        // 获取实时行情
        final codeWithPrefix = _apiClient.addMarketPrefix(code);
        QuoteData? quote;
        try {
          quote = await _apiClient.getRealtimeQuote(codeWithPrefix);
        } catch (_) {
          continue;
        }
        if (quote == null || quote.price <= 0) continue;

        // P3: 检查是否需要K线数据（指标类预警）, 按需获取并只计算一次
        final needsKline = rules.any((r) => _needsKlineData(r));
        List<HistoryKline>? klines;
        if (needsKline) {
          try {
            final raw = await _apiClient.getStockHistory(code, days: 120);
            if (raw.isNotEmpty) {
              klines = calcAllIndicators(raw);
            }
          } catch (e) {
            // K线获取失败，指标预警本次跳过但不影响价格/涨跌幅预警
          }
        }

        for (final rule in rules) {
          // 冷却检查：5分钟内不重复触发
          if (rule.lastTriggeredAt != null) {
            final elapsed = DateTime.now().difference(rule.lastTriggeredAt!);
            if (elapsed.inMinutes < _alertCooldownMinutes) continue;
          }

          final triggered = _evaluateAlert(rule, quote, klines);
          if (triggered) {
            final desc = _formatAlertDesc(rule, quote);
            await _showAlertNotification(
              id: notificationId++,
              title: '${rule.name} 预警触发',
              body: desc,
              payload: codeWithPrefix,
            );
            // 更新触发时间
            await _dbService.updateAlertTriggerTime(rule.id, DateTime.now());
          }
        }
      }
    } catch (e) {
      // 预警检查失败不影响新闻轮询
    }
  }

  /// 是否需要K线数据来计算该预警
  static bool _needsKlineData(AlertRule rule) {
    final type = rule.conditionType.isNotEmpty ? rule.conditionType : rule.alertType;
    if (type != 'indicator') return false;
    // volume/volume_ratio/turnover/amplitude 可从 QuoteData 直接获取
    return !['volume', 'volume_ratio', 'turnover', 'amplitude']
        .contains(rule.indicatorType);
  }

  /// 评估单个预警规则是否触发
  bool _evaluateAlert(AlertRule rule, QuoteData quote, List<HistoryKline>? klines) {
    final type = rule.conditionType.isNotEmpty ? rule.conditionType : rule.alertType;
    switch (type) {
      case 'price_above':
      case 'above':
        return quote.price >= rule.thresholdValue;
      case 'price_below':
      case 'below':
        return quote.price <= rule.thresholdValue;
      case 'change_above':
      case 'rise':
        return quote.changePct >= rule.thresholdValue;
      case 'change_below':
      case 'fall':
        return quote.changePct <= -rule.thresholdValue;
      case 'indicator':
        return _evaluateIndicatorAlert(rule, quote, klines);
      default:
        return false;
    }
  }

  /// 评估指标类预警 (P3: 完整支持 RSI/MACD/KDJ/MA/BOLL/CCI/WR/ATR)
  bool _evaluateIndicatorAlert(AlertRule rule, QuoteData quote, List<HistoryKline>? klines) {
    switch (rule.indicatorType) {
      // --- 基于行情数据的基础指标 ---
      case 'volume':
        return quote.volume > 0 && quote.volume >= rule.thresholdValue;
      case 'volume_ratio':
        return quote.volumeRatio > 0 && quote.volumeRatio >= rule.thresholdValue;
      case 'turnover':
        return quote.turnover > 0 && quote.turnover >= rule.thresholdValue;
      case 'amplitude':
        return quote.amplitude > 0 && quote.amplitude >= rule.thresholdValue;

      // --- 需要K线数据的技术指标 ---
      default:
        if (klines == null || klines.length < 2) return false;
        return _evaluateKlineIndicator(rule, klines);
    }
  }

  /// 基于K线数据 + calcAllIndicators 的技术指标评估
  bool _evaluateKlineIndicator(AlertRule rule, List<HistoryKline> klines) {
    final last = klines.last;
    final prev = klines[klines.length - 2];
    final t = rule.thresholdValue;

    switch (rule.indicatorType) {
      case 'rsi':
        if (last.rsi6 <= 0) return false;
        // t>=50 表示"高于阈值"(超买)，t<50 表示"低于阈值"(超卖)
        if (t >= 50) return last.rsi6 >= t;
        return last.rsi6 <= t;

      case 'macd':
        if (last.macdDif.isNaN) return false;
        // DIF 绝对值或方向变化
        if (t > 0) return last.macdDif >= t;
        // t==0 表示金叉: prev DIF < prev DEA AND last DIF > last DEA
        // t<0 表示死叉: prev DIF > prev DEA AND last DIF < last DEA
        return _detectMacdSignal(prev, last, t);

      case 'kdj':
        if (last.k <= 0) return false;
        if (t >= 50) return last.k >= t;
        return last.k <= t;

      case 'ma_cross':
        // t 为均线周期，检测对应MA与下一级别MA的交叉
        return _detectMaCross(prev, last, t.toInt());

      case 'boll':
        // t==1 突破上轨, t==0 突破下轨
        if (last.bollUpper <= 0) return false;
        if (t >= 1) return last.close >= last.bollUpper && prev.close < prev.bollUpper;
        return last.close <= last.bollLower && prev.close > prev.bollLower;

      case 'cci':
        final cci = last.cci14 ?? double.nan;
        if (cci.isNaN) return false;
        if (t >= 0) return cci >= t;
        return cci <= t;  // t 为负值，如 -100 检测 CCI <= -100

      case 'wr':
        final wr = last.wr14 ?? double.nan;
        if (wr.isNaN) return false;
        // t>=50 表示超卖(WR>80), t<50 表示超买(WR<20)
        if (t >= 50) return wr >= t;
        return wr <= t;

      case 'atr':
        if (last.atr14 <= 0 || last.close <= 0) return false;
        final atrPct = last.atr14 / last.close * 100;
        return atrPct >= t;

      default:
        return false;
    }
  }

  /// MACD 信号检测: t=0→金叉, t<0→死叉
  static bool _detectMacdSignal(HistoryKline prev, HistoryKline last, double t) {
    if (prev.macdDif.isNaN || prev.macdDea.isNaN ||
        last.macdDif.isNaN || last.macdDea.isNaN) return false;
    if (t == 0) {
      // 金叉: 前一日 DIF < DEA, 当日 DIF > DEA
      return prev.macdDif < prev.macdDea && last.macdDif > last.macdDea;
    } else {
      // 死叉: 前一日 DIF > DEA, 当日 DIF < DEA
      return prev.macdDif > prev.macdDea && last.macdDif < last.macdDea;
    }
  }

  /// 均线交叉检测: period 指定短期MA, 自动匹配下一级长期MA
  /// period=60 时使用收盘价 vs MA60 交叉（MA120 不可用）
  static bool _detectMaCross(HistoryKline prev, HistoryKline last, int period) {
    final short = _getMa(last, period);
    final shortPrev = _getMa(prev, period);

    if (period == 60) {
      // MA60 vs 收盘价交叉: 价格突破长期均线
      if (short <= 0 || prev.close <= 0 || last.close <= 0) return false;
      final prevCross = prev.close - shortPrev;
      final nowCross = last.close - short;
      return (prevCross * nowCross < 0);
    }

    final longPeriod = period == 5 ? 10 : period == 10 ? 20 : 60;
    final long = _getMa(last, longPeriod);
    final longPrev = _getMa(prev, longPeriod);
    if (short <= 0 || long <= 0 || shortPrev <= 0 || longPrev <= 0) return false;
    // 金叉 OR 死叉均触发（用户可自行判断方向）
    final prevCross = shortPrev - longPrev;
    final nowCross = short - long;
    return (prevCross * nowCross < 0); // 正负号反转即交叉
  }

  /// 安全获取MA值, 0表示无效
  static double _getMa(HistoryKline k, int period) {
    switch (period) {
      case 5: return k.ma5;
      case 10: return k.ma10;
      case 20: return k.ma20;
      case 60: return k.ma60;
      default: return 0; // ma120 暂不可用
    }
  }

  /// 格式化预警描述
  String _formatAlertDesc(AlertRule rule, QuoteData quote) {
    final type = rule.conditionType.isNotEmpty ? rule.conditionType : rule.alertType;
    switch (type) {
      case 'price_above':
      case 'above':
        return '当前价 ${quote.price.toStringAsFixed(2)}，已高于 ${rule.thresholdValue.toStringAsFixed(2)}';
      case 'price_below':
      case 'below':
        return '当前价 ${quote.price.toStringAsFixed(2)}，已低于 ${rule.thresholdValue.toStringAsFixed(2)}';
      case 'change_above':
      case 'rise':
        return '当前涨幅 ${quote.changePct.toStringAsFixed(2)}%，已超过 ${rule.thresholdValue.toStringAsFixed(1)}%';
      case 'change_below':
      case 'fall':
        return '当前跌幅 ${quote.changePct.toStringAsFixed(2)}%，已超过 ${rule.thresholdValue.toStringAsFixed(1)}%';
      case 'indicator':
        return '${rule.indicatorType} 触发阈值 ${rule.thresholdValue}';
      default:
        return '预警条件已满足';
    }
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> _showAlertNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      color: const Color(0xFFE74C3C),
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> _showIntradayNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    required bool isBuy,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _intradayChannelId,
      _intradayChannelName,
      channelDescription: _intradayChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      color: isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// 检查持仓股的日内高抛低吸信号并推送通知
  ///
  /// 仅在交易时段执行；仅推送产生时间在 3 分钟内的高置信度信号；
  /// 同一信号（股票+类型+minuteOffset）当天只推送一次。
  Future<void> _checkIntradaySignals() async {
    if (!TradingSession.isInTradingSession()) return;
    try {
      final positions = await _dbService.getPositions();
      if (positions.isEmpty) return;

      final now = DateTime.now();
      final currentOffset = IntradayLevelAnalyzer.timeToMinuteOffset(now);
      if (currentOffset == null) return;

      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final prefs = await SharedPreferences.getInstance();

      int notificationId = 200; // 日内信号通知 ID 区间 200+
      final positionsToScan = positions.take(_intradayMaxPositions).toList();

      for (final pos in positionsToScan) {
        if (pos.quantity <= 0) continue;

        // 获取分时数据
        final timeshare = await _apiClient.getTimeshareData(pos.code);
        if (timeshare == null) continue;
        final prices = timeshare['prices'] ?? {};
        final volumes = timeshare['volumes'] ?? {};
        final vwapData = timeshare['vwapData'] ?? {};
        if (prices.isEmpty) continue;

        // 获取实时行情（取 preClose/open/high/low/amplitude）
        QuoteData? quote;
        try {
          quote = await _apiClient.getRealtimeQuote(_apiClient.addMarketPrefix(pos.code));
        } catch (_) {
          continue;
        }
        if (quote == null || quote.price <= 0) continue;

        final result = IntradayLevelAnalyzer.analyze(
          prices: prices,
          volumes: volumes,
          vwapData: vwapData,
          preClose: quote.preClose,
          openPrice: quote.open,
          dayHigh: quote.high,
          dayLow: quote.low,
          currentOffset: currentOffset,
          estimatedAmplitude: quote.amplitude,
        );

        // 检查买入（低吸）信号
        for (final sig in result.buySignals) {
          if (!sig.isHighConfidence) continue;
          // 时效性：信号产生时间超过 3 分钟则跳过
          final ageMinutes = currentOffset - sig.minuteOffset;
          if (ageMinutes > _intradaySignalMaxAgeMinutes || ageMinutes < 0) continue;
          // 当天去重
          final key = 'intraday_notified_${pos.code}_buy_${sig.minuteOffset}_$dateStr';
          if (prefs.getBool(key) == true) continue;

          await _showIntradayNotification(
            id: notificationId++,
            title: '低吸信号 · ${pos.name}',
            body: '${sig.shortLabel} ¥${sig.price.toStringAsFixed(2)}（${quote.changePct.toStringAsFixed(2)}%）',
            payload: 'quote|${pos.code}|${pos.name}',
            isBuy: true,
          );
          await prefs.setBool(key, true);
        }

        // 检查卖出（高抛）信号
        for (final sig in result.sellSignals) {
          if (!sig.isHighConfidence) continue;
          final ageMinutes = currentOffset - sig.minuteOffset;
          if (ageMinutes > _intradaySignalMaxAgeMinutes || ageMinutes < 0) continue;
          final key = 'intraday_notified_${pos.code}_sell_${sig.minuteOffset}_$dateStr';
          if (prefs.getBool(key) == true) continue;

          await _showIntradayNotification(
            id: notificationId++,
            title: '高抛信号 · ${pos.name}',
            body: '${sig.shortLabel} ¥${sig.price.toStringAsFixed(2)}（${quote.changePct.toStringAsFixed(2)}%）',
            payload: 'quote|${pos.code}|${pos.name}',
            isBuy: false,
          );
          await prefs.setBool(key, true);
        }
      }
    } catch (e) {
      debugPrint('Intraday signal poll error: $e');
    }
  }

  Future<void> requestPermission() async {
    // Android 13+ 需要请求通知权限
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }
}
