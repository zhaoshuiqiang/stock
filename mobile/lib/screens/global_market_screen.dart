import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'quote_screen.dart';

/// 环球市场页面：展示全球主要股指 + A股热门板块
class GlobalMarketScreen extends StatefulWidget {
  const GlobalMarketScreen({super.key});

  @override
  State<GlobalMarketScreen> createState() => _GlobalMarketScreenState();
}

class _GlobalMarketScreenState extends State<GlobalMarketScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  List<GlobalIndex> _indices = [];
  List<SectorInfo> _sectors = [];
  bool _isLoading = false;
  String _indicesError = '';
  String _sectorsError = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _indicesError = '';
      _sectorsError = '';
    });

    try {
      final results = await Future.wait([
        _apiClient.getGlobalIndices(),
        _apiClient.getHotSectors(),
      ]);

      if (mounted) {
        setState(() {
          _indices = results[0] as List<GlobalIndex>;
          _sectors = results[1] as List<SectorInfo>;
          _isLoading = false;
          if (_indices.isEmpty) _indicesError = '暂无数据，下拉刷新重试';
          if (_sectors.isEmpty) _sectorsError = '暂无板块数据';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _indicesError = '加载失败：$e';
          _sectorsError = '加载失败：$e';
        });
      }
    }
  }

  /// 生成全球市场趋势总结
  String _buildGlobalSummary() {
    if (_indices.isEmpty) return '';

    final us = _indices.where((i) => i.market == 'US').toList();
    final asia = _indices.where((i) => i.market == 'HK' || i.market == 'JP' || i.market == 'KR').toList();
    final eu = _indices.where((i) => i.market == 'EU').toList();

    final parts = <String>[];

    if (us.isNotEmpty) {
      parts.add(_regionSummary('美股', us));
    }
    if (asia.isNotEmpty) {
      parts.add(_regionSummary('亚太', asia));
    }
    if (eu.isNotEmpty) {
      parts.add(_regionSummary('欧洲', eu));
    }

    final t = GlobalIndex.calculateTrend(_indices);
    parts.add('全球趋势: ${t.trend} (上涨${t.upCount}/下跌${t.downCount})');

    return parts.join('；');
  }

  /// 生成热门板块趋势总结
  String _buildSectorSummary() {
    if (_sectors.isEmpty) return '';
    final upCount = _sectors.where((s) => s.changePct > 0).length;
    final downCount = _sectors.where((s) => s.changePct < 0).length;

    final avgChange = _sectors.isNotEmpty
        ? _sectors.map((s) => s.changePct).reduce((a, b) => a + b) / _sectors.length
        : 0;
    final sign = avgChange >= 0 ? '+' : '';

    String direction;
    if (upCount == _sectors.length) {
      direction = '全线上涨';
    } else if (downCount == _sectors.length) {
      direction = '全线下跌';
    } else if (upCount > downCount) {
      direction = '多数上涨';
    } else if (downCount > upCount) {
      direction = '多数下跌';
    } else {
      direction = '涨跌互现';
    }

    final hot = _sectors.isNotEmpty ? _sectors.reduce((a, b) => a.changePct > b.changePct ? a : b) : null;
    final cold = _sectors.isNotEmpty ? _sectors.reduce((a, b) => a.changePct < b.changePct ? a : b) : null;

    final parts = <String>['板块${direction}(均$sign${avgChange.toStringAsFixed(2)}%)'];
    if (hot != null) {
      parts.add('热门: ${hot.name}(+${hot.changePct.toStringAsFixed(2)}%)');
    }
    if (cold != null) {
      parts.add('冷门: ${cold.name}(${cold.changePct.toStringAsFixed(2)}%)');
    }

    return parts.join(' · ');
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('环球市场'),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '全球指数'),
            Tab(text: '热门板块'),
          ],
          labelColor: const Color(0xFF58A6FF),
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xFF58A6FF),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGlobalIndicesView(),
          _buildHotSectorsView(),
        ],
      ),
    );
  }

  Widget _buildGlobalIndicesView() {
    final groups = _groupedByMarket();
    final summary = _buildGlobalSummary();

    return RefreshIndicator(
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
                if (_indices.isEmpty && _indicesError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(_indicesError, style: const TextStyle(color: Colors.white54)),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildHotSectorsView() {
    final summary = _buildSectorSummary();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _isLoading && _sectors.isEmpty
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
                        const Icon(Icons.trending_up, color: Colors.blueAccent, size: 20),
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
                ..._sectors.map((sector) => _buildSectorCard(sector)),
                if (_sectors.isEmpty && _sectorsError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(_sectorsError, style: const TextStyle(color: Colors.white54)),
                    ),
                  ),
              ],
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
    final sorted = <String, List<GlobalIndex>>{};
    for (final m in order) {
      if (result.containsKey(m)) {
        sorted[labels[m] ?? m] = result[m]!;
      }
    }
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
        side: const BorderSide(color: const Color(0xFF30363D), width: 0.5),
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

  Widget _buildSectorCard(SectorInfo sector) {
    final isUp = sector.changePct >= 0;
    final color = isUp ? Colors.red : Colors.green;

    return Card(
      color: const Color(0xFF161B22),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (sector.leadStockCode.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QuoteScreen(
                  code: sector.leadStockCode,
                  name: sector.leadStockName.isNotEmpty ? sector.leadStockName : sector.name,
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sector.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sector.leadStockName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '龙头: ${sector.leadStockName}',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isUp ? '+' : ''}${sector.changePct.toStringAsFixed(2)}%',
                      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (sector.stockCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${sector.stockCount}只',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
