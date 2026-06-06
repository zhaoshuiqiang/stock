import 'package:flutter/material.dart';
import 'package:stock_analyzer/screens/home_screen.dart';
import 'package:stock_analyzer/screens/search_screen.dart';
import 'package:stock_analyzer/screens/watchlist_screen.dart';
import 'package:stock_analyzer/screens/signals_screen.dart';
import 'package:stock_analyzer/screens/alerts_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _currentIndex = 0;
  String? _selectedStockCode;

  void _onStockSelected(String code) {
    setState(() {
      _selectedStockCode = code;
      _currentIndex = 3;
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      SearchScreen(onStockSelected: _onStockSelected),
      WatchlistScreen(onStockSelected: _onStockSelected),
      SignalsScreen(selectedCode: _selectedStockCode),
      const AlertsScreen(),
    ];

    final titles = [
      '首页',
      '搜索',
      '自选',
      '信号',
      '提醒',
    ];

    return MaterialApp(
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
      home: Scaffold(
        appBar: AppBar(
          title: Text(titles[_currentIndex]),
        ),
        body: pages[_currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: '搜索',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.star),
              label: '自选',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.signal_cellular_alt),
              label: '信号',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: '提醒',
            ),
          ],
        ),
      ),
    );
  }
}
