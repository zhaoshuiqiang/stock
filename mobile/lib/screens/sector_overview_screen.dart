import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'sector_screen.dart';

enum SectorType {
  industry,
  concept,
}

class SectorOverviewScreen extends StatefulWidget {
  final bool autoLoad;

  const SectorOverviewScreen({super.key, this.autoLoad = true});

  @override
  State<SectorOverviewScreen> createState() => _SectorOverviewScreenState();
}

class _SectorOverviewScreenState extends State<SectorOverviewScreen> {
  final ApiClient _apiClient = ApiClient();
  SectorType _currentType = SectorType.industry;
  SectorSortMode _sortMode = SectorSortMode.all;
  bool _isLoading = true;
  List<SectorInfo> _sectors = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _loadSectors();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadSectors() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sectors = await _apiClient.getSectorRanking(
        category: _currentType == SectorType.industry
            ? SectorCategory.industry
            : SectorCategory.concept,
        sortMode: _sortMode,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _sectors = sectors;
      });
    } catch (e) {
      debugPrint('Load sectors failed: $e');
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSectorCard(SectorInfo sector) {
    final isUp = sector.changePct >= 0;
    final color = isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a);
    final backgroundColor = isUp
        ? const Color(0xFFef5350).withValues(alpha: 0.1)
        : const Color(0xFF26a69a).withValues(alpha: 0.1);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SectorScreen(
              sectorName: sector.name,
              sectorCode: sector.code,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isUp
                ? const Color(0xFFef5350).withValues(alpha: 0.3)
                : const Color(0xFF26a69a).withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              sector.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isUp ? Icons.trending_up : Icons.trending_down,
                  color: color,
                  size: 11,
                ),
                const SizedBox(width: 2),
                Text(
                  '${isUp ? '+' : ''}${sector.changePct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (sector.leadStockName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sector.leadStockName,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSortTabs() {
    return _buildTabRow<SectorSortMode>(
      value: _sortMode,
      items: const {
        SectorSortMode.all: '全部',
        SectorSortMode.gainers: '上涨',
        SectorSortMode.losers: '下跌',
      },
      onChanged: (value) {
        if (_sortMode == value) return;
        setState(() => _sortMode = value);
        _loadSectors();
      },
    );
  }

  Widget _buildTabRow<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final entry in items.entries) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Center(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color:
                            value == entry.key ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: value == entry.key
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (entry.key != items.keys.last)
              Container(
                width: 1,
                height: 22,
                color: const Color(0xFF30363D),
              ),
          ],
        ],
      ),
    );
  }

  String _buildSummary() {
    if (_sectors.isEmpty) return '';
    final upCount = _sectors.where((s) => s.changePct > 0).length;
    final downCount = _sectors.where((s) => s.changePct < 0).length;
    final avgChange = _sectors.map((s) => s.changePct).reduce((a, b) => a + b) /
        _sectors.length;
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

    return '${_currentType == SectorType.industry ? '行业' : '概念'}板块$direction(均$sign${avgChange.toStringAsFixed(2)}%)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '板块数据',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_currentType != SectorType.industry) {
                                setState(
                                    () => _currentType = SectorType.industry);
                                _loadSectors();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text(
                                  '行业板块',
                                  style: TextStyle(
                                    color: _currentType == SectorType.industry
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 14,
                                    fontWeight:
                                        _currentType == SectorType.industry
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: const Color(0xFF30363D),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_currentType != SectorType.concept) {
                                setState(
                                    () => _currentType = SectorType.concept);
                                _loadSectors();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text(
                                  '概念板块',
                                  style: TextStyle(
                                    color: _currentType == SectorType.concept
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 14,
                                    fontWeight:
                                        _currentType == SectorType.concept
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSortTabs(),
                  const SizedBox(height: 8),
                  Text(
                    _buildSummary(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!,
                                  style:
                                      const TextStyle(color: Colors.white38)),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loadSectors,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadSectors,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 520;
                              return GridView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isWide ? 4 : 3,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                  childAspectRatio: isWide ? 2.8 : 2.4,
                                ),
                                itemCount: _sectors.length,
                                itemBuilder: (context, index) {
                                  return _buildSectorCard(_sectors[index]);
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
