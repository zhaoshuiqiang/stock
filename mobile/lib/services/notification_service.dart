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

        for (final rule in rules) {
          // 冷却检查：5分钟内不重复触发
          if (rule.lastTriggeredAt != null) {
            final elapsed = DateTime.now().difference(rule.lastTriggeredAt!);
            if (elapsed.inMinutes < _alertCooldownMinutes) continue;
          }

          final triggered = _evaluateAlert(rule, quote);
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

  /// 评估单个预警规则是否触发
  bool _evaluateAlert(AlertRule rule, QuoteData quote) {
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
        return _evaluateIndicatorAlert(rule, quote);
      default:
        return false;
    }
  }

  /// 评估指标类预警
  bool _evaluateIndicatorAlert(AlertRule rule, QuoteData quote) {
    // 指标预警需要K线数据，此处仅基于行情数据做简单判断
    // 完整指标计算需要在应用内维护K线缓存，当前版本先支持基础指标
    switch (rule.indicatorType) {
      case '成交量':
        // 成交量超过阈值（手数）
        return quote.volume > 0 && quote.volume >= rule.thresholdValue;
      default:
        // RSI/MACD/KDJ/MA 等需要K线数据，暂不支持自动触发
        return false;
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
