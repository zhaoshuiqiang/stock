import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';

/// 环球市场页面：展示全球主要股指（美股/港股/亚太/欧洲）
class GlobalMarketScreen extends StatefulWidget {
  const GlobalMarketScreen({super.key});

  @override
  State<GlobalMarketScreen> createState() => _GlobalMarketScreenState();
}

class _GlobalMarketScreenState extends State<GlobalMarketScreen> {
  final ApiClient _apiClient = ApiClient();
  List<GlobalIndex> _indices = [];
  bool _isLoading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await _apiClient.getGlobalIndices();
      if (mounted) {
        setState(() {
          _indices = result;
          _isLoading = false;
          if (result.isEmpty) _error = '暂无数据，下拉刷新重试';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  /// 生成全球市场趋势总结
  /// 按区域（美股/亚太/欧洲）归纳走势，并给出综合趋势判定
  String _buildSummary() {
    if (_indices.isEmpty) return '';

    final us = _indices.where((i) => i.market == 'US').toList();
    final asia = _indices.where((i) => i.market == 'HK' || i.market == 'JP' || i.market == 'KR').toList();
    final eu = _indices.where((i) => i.market == 'EU').toList();

    final parts = <String>[];

    // 美股
    if (us.isNotEmpty) {
      parts.add(_regionSummary('美股', us));
    }
    // 亚太
    if (asia.isNotEmpty) {
      parts.add(_regionSummary('亚太', asia));
    }
    // 欧洲
    if (eu.isNotEmpty) {
      parts.add(_regionSummary('欧洲', eu));
    }

    // 全球综合趋势判定
    final t = GlobalIndex.calculateTrend(_indices);
    parts.add('全球趋势: ${t.trend} (上涨${t.upCount}/下跌${t.downCount})');

    return parts.join('；');
  }

  /// 单个区域的涨跌总结
  String _regionSummary(String label, List<GlobalIndex> items) {
    if (items.isEmpty) return '';
    final t = GlobalIndex.calculateTrend(items);
    final upCount = t.upCount;
    final downCount = t.downCount;

    String direction;
    if (upCount == items.length) {
      direction = '全线收涨';
    } else if (downCount == items.length) {
      direction = '全线收跌';
    } else if (upCount > downCount) {
      direction = '多数上涨';
    } else if (downCount > upCount) {
      direction = '多数下跌';
    } else {
      direction = '涨跌互现';
    }

    final sign = t.avg >= 0 ? '+' : '';
    return '$label$direction(均$sign${t.avg.toStringAsFixed(2)}%)';
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedByMarket();
    final summary = _buildSummary(); // 缓存避免重复计算
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('环球市场'),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading && _indices.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  if (summary.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.public, color: Colors.blueAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              summary,
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...groups.entries.map((e) => _buildGroupCard(e.key, e.value)),
                  if (_indices.isEmpty && _error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(_error, style: const TextStyle(color: Colors.white54)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Map<String, List<GlobalIndex>> _groupedByMarket() {
    const order = ['US', 'HK', 'JP', 'EU', 'KR'];
    const labels = {
      'US': '🇺🇸 美股',
      'HK': '🇭🇰 港股',
      'JP': '🌏 亚太',
      'EU': '🇪🇺 欧洲',
      'KR': '🇰🇷 韩国',
    };
    final result = <String, List<GlobalIndex>>{};
    for (final idx in _indices) {
      result.putIfAbsent(idx.market, () => []).add(idx);
    }
    // 按 order 排序
    final sorted = <String, List<GlobalIndex>>{};
    for (final m in order) {
      if (result.containsKey(m)) {
        sorted[labels[m] ?? m] = result[m]!;
      }
    }
    // 其他市场
    result.forEach((m, list) {
      if (!order.contains(m)) {
        sorted[m] = list;
      }
    });
    return sorted;
  }

  Widget _buildGroupCard(String label, List<GlobalIndex> items) {
    return Card(
      color: const Color(0xFF161B22),
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF30363D), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map(_buildIndexRow),
          ],
        ),
      ),
    );
  }

  Widget _buildIndexRow(GlobalIndex idx) {
    final isUp = idx.changePct >= 0;
    final color = isUp ? Colors.red : Colors.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              idx.name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              idx.price.toStringAsFixed(2),
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${isUp ? '+' : ''}${idx.changePoint.toStringAsFixed(2)}',
              style: TextStyle(color: color, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${isUp ? '+' : ''}${idx.changePct.toStringAsFixed(2)}%',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
