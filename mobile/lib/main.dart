import 'package:flutter/material.dart';
import 'package:stock_analyzer/core/navigator_key.dart';
import 'package:stock_analyzer/screens/home_screen.dart';
import 'package:stock_analyzer/screens/watchlist_screen.dart';
import 'package:stock_analyzer/screens/news_screen.dart';
import 'package:stock_analyzer/screens/discover_screen.dart';
import 'package:stock_analyzer/screens/archive_screen.dart';
import 'package:stock_analyzer/screens/alerts_screen.dart';
import 'package:stock_analyzer/screens/update_log_screen.dart';
import 'package:stock_analyzer/services/notification_service.dart';

const String appVersion = 'v2.22.0';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  await notificationService.init();
  // 如果用户已开启推送，启动轮询
  if (await notificationService.isEnabled()) {
    notificationService.startPolling();
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
    final pages = [
      HomeScreen(key: _homeKey),
      const WatchlistScreen(),
      DiscoverScreen(key: _discoverKey),
      const NewsScreen(),
      const ArchiveScreen(),
    ];

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
        body: pages[_currentIndex],
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
