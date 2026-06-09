import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/storage/database_service.dart';
import 'package:stock_analyzer/core/navigator_key.dart';
import 'package:stock_analyzer/screens/webview_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();

  Timer? _pollTimer;
  String _lastNewsId = '';
  bool _initialized = false;

  static const String _prefKeyEnabled = 'news_notification_enabled';
  static const String _prefKeyInterval = 'news_notification_interval';
  static const String _prefKeyLastNewsId = 'last_news_id';
  static const String _channelId = 'stock_news';
  static const String _channelName = '股票资讯推送';
  static const String _channelDesc = '自选股和财经快讯推送通知';

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
    if (payload != null && payload.isNotEmpty) {
      final parts = payload.split('|');
      final url = parts[0];
      final title = parts.length > 1 ? parts[1] : '';
      if (url.isNotEmpty) {
        _navigateToWebView(url, title);
      }
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
    } else {
      stopPolling();
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
    });

    // 启动时立即检查一次
    _checkForNewNews();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
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
      print('News poll error: $e');
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

  Future<void> requestPermission() async {
    // Android 13+ 需要请求通知权限
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }
}
