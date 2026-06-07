import 'package:flutter/material.dart';
import 'package:stock_analyzer/core/navigator_key.dart';
import 'package:stock_analyzer/screens/home_screen.dart';
import 'package:stock_analyzer/screens/watchlist_screen.dart';
import 'package:stock_analyzer/screens/news_screen.dart';
import 'package:stock_analyzer/screens/alerts_screen.dart';
import 'package:stock_analyzer/screens/update_log_screen.dart';
import 'package:stock_analyzer/services/notification_service.dart';

const String appVersion = 'v2.3.0';

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

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const WatchlistScreen(),
      const NewsScreen(),
      const AlertsScreen(),
    ];

    final titles = [
      '首页',
      '自选',
      '资讯',
      '预警',
    ];

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '股票分析助手',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        cardColor: const Color(0xFF16213e),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0f3460),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF0f3460),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          titleLarge: TextStyle(color: Colors.white),
          titleMedium: TextStyle(color: Colors.white),
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
              icon: Icon(Icons.article),
              label: '资讯',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: '预警',
            ),
          ],
        ),
      )),
    );
  }
}
