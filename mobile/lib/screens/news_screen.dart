import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../storage/database_service.dart';
import '../services/notification_service.dart';
import 'webview_screen.dart';

class NewsItem {
  final String title;
  final String digest;
  final String url;
  final String showTime;
  final String source;

  NewsItem({
    required this.title,
    this.digest = '',
    required this.url,
    this.showTime = '',
    this.source = '',
  });
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  final NotificationService _notificationService = NotificationService();
  List<NewsItem> _newsList = [];
  List<NewsItem> _stockNewsList = [];
  bool _isLoading = true;
  bool _pushEnabled = false;
  int _pushInterval = 15;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPushSettings();
    _loadData();
  }

  Future<void> _loadPushSettings() async {
    final enabled = await _notificationService.isEnabled();
    final interval = await _notificationService.getIntervalMinutes();
    setState(() {
      _pushEnabled = enabled;
      _pushInterval = interval;
    });
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; });
    try {
      final results = await Future.wait([
        _apiClient.getMarketNews(),
        _loadStockNews(),
      ]);
      setState(() {
        _newsList = (results[0] as List).map((item) => NewsItem(
          title: item['title'] ?? '',
          digest: item['digest'] ?? '',
          url: item['url'] ?? '',
          showTime: item['showTime'] ?? '',
          source: item['source'] ?? '',
        )).toList();
        _stockNewsList = (results[1] as List).map((item) => NewsItem(
          title: item['title'] ?? '',
          digest: item['digest'] ?? '',
          url: item['url'] ?? '',
          showTime: item['showTime'] ?? '',
          source: item['source'] ?? '',
        )).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load news error: $e');
      setState(() { _isLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('资讯加载失败: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<List<Map<String, String>>> _loadStockNews() async {
    final watchlist = await _dbService.getWatchlist();
    if (watchlist.isEmpty) return [];

    // 并行请求所有自选股新闻（最多5只）
    final futures = watchlist.take(5).map((item) async {
      try {
        final news = await _apiClient.getStockNews(item.name);
        return news.map<Map<String, String>>((n) => {
          'title': n['title'] ?? '',
          'digest': n['digest'] ?? '',
          'url': n['url'] ?? '',
          'showTime': n['showTime'] ?? '',
          'source': n['source'] ?? '',
        }).toList();
      } catch (e) {
        debugPrint('Load stock news failed for ${item.name}: $e');
        return <Map<String, String>>[];
      }
    });

    final results = await Future.wait(futures);
    final allNews = results.expand((list) => list).toList();
    allNews.sort((a, b) => (b['showTime'] ?? '').compareTo(a['showTime'] ?? ''));
    return allNews;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '财经快讯'),
            Tab(text: '自选资讯'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _pushEnabled ? Icons.notifications_active : Icons.notifications_off_outlined,
              color: _pushEnabled ? Colors.amber : Colors.grey,
            ),
            onPressed: _showPushSettings,
            tooltip: '推送设置',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNewsList(_newsList, textTheme),
                _buildStockNewsView(textTheme),
              ],
            ),
    );
  }

  Widget _buildStockNewsView(TextTheme textTheme) {
    if (_stockNewsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('暂无自选股资讯', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              '请先添加自选股，或下拉刷新重试',
              style: textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _buildNewsList(_stockNewsList, textTheme),
    );
  }

  Widget _buildNewsList(List<NewsItem> news, TextTheme textTheme) {
    if (news.isEmpty) {
      return Center(child: Text('暂无资讯', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: news.length,
        itemBuilder: (context, index) {
          final item = news[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            color: const Color(0xFF161B22),
            child: InkWell(
              onTap: () {
                if (item.url.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WebViewScreen(url: item.url, title: item.title),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.digest.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.digest,
                        style: textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.source.isNotEmpty) ...[
                          Icon(Icons.source, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(item.source, style: textTheme.bodySmall?.copyWith(color: Colors.grey[500], fontSize: 11)),
                          const SizedBox(width: 12),
                        ],
                        Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(item.showTime, style: textTheme.bodySmall?.copyWith(color: Colors.grey[500], fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPushSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('资讯推送设置', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                title: const Text('开启推送', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _pushEnabled ? '有新资讯时会收到通知' : '推送已关闭',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                value: _pushEnabled,
                activeColor: Colors.amber,
                onChanged: (value) async {
                  if (value) {
                    await _notificationService.requestPermission();
                  }
                  await _notificationService.setEnabled(value);
                  setDialogState(() => _pushEnabled = value);
                  setState(() => _pushEnabled = value);
                },
              ),
              const SizedBox(height: 8),
              if (_pushEnabled) ...[
                const Text('检查频率', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [5, 15, 30, 60].map((min) {
                    final selected = _pushInterval == min;
                    return ChoiceChip(
                      label: Text(min >= 60 ? '${min ~/ 60}小时' : '$min分钟'),
                      selected: selected,
                      selectedColor: Colors.amber.withOpacity(0.3),
                      backgroundColor: const Color(0xFF161B22),
                      labelStyle: TextStyle(
                        color: selected ? Colors.amber : Colors.white70,
                        fontSize: 12,
                      ),
                      onSelected: (_) async {
                        await _notificationService.setIntervalMinutes(min);
                        setDialogState(() => _pushInterval = min);
                        setState(() => _pushInterval = min);
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }
}
