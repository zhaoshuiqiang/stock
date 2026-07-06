import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/core/navigator_key.dart';
import 'package:stock_analyzer/core/ai_config.dart';
import 'package:stock_analyzer/analysis/ai_layer.dart';
import 'package:stock_analyzer/analysis/news_sentiment_analyzer.dart';
import 'package:stock_analyzer/screens/home_screen.dart';
import 'package:stock_analyzer/screens/watchlist_screen.dart';
import 'package:stock_analyzer/screens/news_screen.dart';
import 'package:stock_analyzer/screens/discover_screen.dart';
import 'package:stock_analyzer/screens/archive_screen.dart';
import 'package:stock_analyzer/screens/alerts_screen.dart';
import 'package:stock_analyzer/screens/update_log_screen.dart';
import 'package:stock_analyzer/screens/scoring_explanation_screen.dart';
import 'package:stock_analyzer/services/notification_service.dart';
import 'package:stock_analyzer/data/concept_tag_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 捕获构建期异常，防止 release 模式下白屏无任何提示
  ErrorWidget.builder = (FlutterErrorDetails details) {
    FlutterError.reportError(details);
    debugPrint('ErrorWidget: ${details.exception}');
    return Material(
      color: const Color(0xFF0D1117),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              const Text('页面渲染异常',
                  style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${details.exception}',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              const Text('请下拉刷新或重启应用',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  };
  final notificationService = NotificationService();
  await notificationService.init();
  // 预加载概念标签数据
  await ConceptTagProvider.instance.load();

  // v2.54: 初始化AI层
  if (AIConfig.enableAIEnhancement) {
    await AIConfig.init();
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString('ai_provider');
    final provider = providerName != null ? AIProvider.fromString(providerName) : AIProvider.zhipu;
    
    final apiKey = AIConfig.getApiKeyForProvider(provider);
    
    if (apiKey.isNotEmpty) {
      final aiLayer = ChatCompletionLayer(
        apiKey: apiKey,
        provider: provider,
      );
      AILayerProvider.set(aiLayer);
      NewsSentimentAnalyzer.setAILayer(aiLayer);
      debugPrint('[AI] ${provider.label} AI层已初始化');
    } else {
      debugPrint('[AI] ${provider.label} API Key为空，AI层未初始化');
    }
  }

  // 如果用户已开启推送，启动轮询
  if (await notificationService.isEnabled()) {
    notificationService.startPolling();
    // 日内高抛低吸信号轮询（独立于资讯轮询，默认开启）
    if (await notificationService.isIntradayEnabled()) {
      notificationService.startIntradayPolling();
    }
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<DiscoverScreenState> _discoverKey = GlobalKey<DiscoverScreenState>();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeScreen(key: _homeKey),
      const WatchlistScreen(),
      DiscoverScreen(key: _discoverKey),
      const NewsScreen(),
      const ArchiveScreen(),
    ];
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    // 切回首页时自动刷新数据
    if (index == 0) {
      _homeKey.currentState?.onTabVisible();
    }
    // 切回发现时刷新自选状态
    if (index == 2) {
      _discoverKey.currentState?.onTabVisible();
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      '首页',
      '自选',
      '发现',
      '资讯',
      '留档',
    ];

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '股票分析助手',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          elevation: 0,
          titleTextStyle: TextStyle(color: Color(0xFFF0F6FC), fontSize: 20, fontWeight: FontWeight.w500),
          iconTheme: IconThemeData(color: Color(0xFFF0F6FC)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF0D1117),
          selectedItemColor: Color(0xFF58A6FF),
          unselectedItemColor: Color(0xFF8B949E),
          type: BottomNavigationBarType.fixed,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF0F6FC)),
          bodyMedium: TextStyle(color: Color(0xFFF0F6FC)),
          titleLarge: TextStyle(color: Color(0xFFF0F6FC)),
          titleMedium: TextStyle(color: Color(0xFFF0F6FC)),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF161B22),
        ),
      ),
      home: Builder(builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(titles[_currentIndex]),
          actions: _currentIndex == 0
            ? [
                  IconButton(
                    icon: const Icon(Icons.help_outline),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ScoringExplanationScreen()),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const UpdateLogScreen()),
                      );
                    },
                  ),
                ]
            : _currentIndex == 1
                ? [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AlertsScreen()),
                        );
                      },
                    ),
                  ]
                : null,
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.star),
              label: '自选',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: '发现',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.article),
              label: '资讯',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bookmark),
              label: '留档',
            ),
          ],
        ),
      )),
    );
  }
}
