import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'sector_screen.dart';

enum SectorType {
  industry,
  concept,
}

class SectorOverviewScreen extends StatefulWidget {
  const SectorOverviewScreen({super.key});

  @override
  State<SectorOverviewScreen> createState() => _SectorOverviewScreenState();
}

class _SectorOverviewScreenState extends State<SectorOverviewScreen> {
  final ApiClient _apiClient = ApiClient();
  SectorType _currentType = SectorType.industry;
  bool _isLoading = true;
  List<SectorInfo> _sectors = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSectors();
  }

  Future<void> _loadSectors() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<SectorInfo> sectors;
      if (_currentType == SectorType.industry) {
        sectors = await _apiClient.getHotSectors(limit: 60);
      } else {
        sectors = await _apiClient.getConceptSectors(limit: 60);
      }
      setState(() {
        _sectors = sectors;
      });
    } catch (e) {
      debugPrint('Load sectors failed: $e');
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSectorCard(SectorInfo sector) {
    final isUp = sector.changePct >= 0;
    final color = isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a);
    final backgroundColor = isUp
        ? const Color(0xFFef5350).withOpacity(0.1)
        : const Color(0xFF26a69a).withOpacity(0.1);

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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isUp
                ? const Color(0xFFef5350).withOpacity(0.3)
                : const Color(0xFF26a69a).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              sector.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isUp ? Icons.trending_up : Icons.trending_down,
                  color: color,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '${isUp ? '+' : ''}${sector.changePct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildSummary() {
    if (_sectors.isEmpty) return '';
    final upCount = _sectors.where((s) => s.changePct > 0).length;
    final downCount = _sectors.where((s) => s.changePct < 0).length;
    final avgChange = _sectors.map((s) => s.changePct).reduce((a, b) => a + b) / _sectors.length;
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

    return '${_currentType == SectorType.industry ? '行业' : '概念'}板块${direction}(均$sign${avgChange.toStringAsFixed(2)}%)';
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
                                setState(() => _currentType = SectorType.industry);
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
                                    fontWeight: _currentType == SectorType.industry
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
                                setState(() => _currentType = SectorType.concept);
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
                                    fontWeight: _currentType == SectorType.concept
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
                              Text(_error!, style: const TextStyle(color: Colors.white38)),
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
                          child: GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.5,
                            ),
                            itemCount: _sectors.length,
                            itemBuilder: (context, index) {
                              return _buildSectorCard(_sectors[index]);
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