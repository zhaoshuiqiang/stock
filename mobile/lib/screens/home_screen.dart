import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/signal_engine.dart';
import '../analysis/indicators.dart';
import '../storage/database_service.dart';
import 'quote_screen.dart';
import 'sector_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final ApiClient _apiClient = ApiClient();
  List<QuoteData> _quotes = [];
  List<SectorInfo> _sectors = [];
  bool _isLoading = true;
  bool _isPickingSectors = false;
  int _pickProgress = 0;
  int _pickTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }

  String _loadError = '';

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = '';
    });

    // 大盘数据和板块数据分开加载，互不影响
    try {
      final codes = ['sh000001', 'sz399001', 'sz399006'];
      final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
      final results = await Future.wait(futures);
      if (mounted) {
        setState(() {
          _quotes = results.where((q) => q != null).cast<QuoteData>().toList();
        });
      }
    } catch (e) {
      debugPrint('Load market data failed: $e');
    }

    try {
      final sectors = await _apiClient.getHotSectors();
      if (mounted) {
        setState(() {
          _sectors = sectors;
          if (sectors.isEmpty) _loadError = '板块数据加载失败，下拉刷新重试';
        });
      }
    } catch (e) {
      debugPrint('Load sectors failed: $e');
      if (mounted) {
        setState(() {
          _loadError = '板块数据加载失败：$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () async {
              await _loadData();
            },
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          '今日大盘',
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildMarketItem('上证指数', 'sh000001'),
                            _buildMarketItem('深证成指', 'sz399001'),
                            _buildMarketItem('创业板指', 'sz399006'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('热门板块', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            if (_sectors.isNotEmpty)
                              GestureDetector(
                                onTap: _isPickingSectors ? null : _pickSectors,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _isPickingSectors
                                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                                        : const Icon(Icons.auto_awesome, color: Colors.orange, size: 14),
                                      const SizedBox(width: 4),
                                      Text(_isPickingSectors ? '分析中$_pickProgress/$_pickTotal' : '精选', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_sectors.isEmpty)
                          Text(_loadError.isNotEmpty ? _loadError : '暂无板块数据', style: const TextStyle(color: Colors.white38))
                        else
                          ..._sectors.take(20).map((sector) => _buildSectorItem(sector)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildMarketItem(String name, String code) {
    final quote = _quotes.firstWhere((q) => q.code == code, orElse: () => QuoteData.empty());
    final isUp = quote.change >= 0;
    final color = isUp ? Colors.red : Colors.green;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuoteScreen(code: code, name: name),
          ),
        );
      },
      child: Column(
        children: [
          Text(name, style: textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(quote.price.toStringAsFixed(2), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${isUp ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
            style: textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSectorItem(SectorInfo sector) {
    final isUp = sector.changePct >= 0;
    final color = isUp ? Colors.red : Colors.green;
    final textTheme = Theme.of(context).textTheme;

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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sector.name, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('领涨: ${sector.leadStockName}', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                ],
              ),
            ),
            Text(
              '${isUp ? '+' : ''}${sector.changePct.toStringAsFixed(2)}%',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSectors() async {
    final topSectors = _sectors.take(10).toList();
    setState(() {
      _isPickingSectors = true;
      _pickProgress = 0;
      _pickTotal = topSectors.length;
    });

    try {
      final List<Map<String, dynamic>> picks = [];
      final Set<String> seenCodes = {};

      // Process sectors in batches of 5
      for (int i = 0; i < topSectors.length; i += 5) {
        if (!mounted) return;
        final batch = topSectors.sublist(i, i + 5 > topSectors.length ? topSectors.length : i + 5);

        // Fetch sector stocks in parallel
        final sectorStocksList = await Future.wait(
          batch.map((sector) => _apiClient.getSectorStocks(sector.code).catchError((_) => <QuoteData>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          if (!mounted) return;
          final sector = batch[j];
          // 只取涨幅前10的主板股票
          final stocks = sectorStocksList[j].take(10).toList();

          setState(() {
            _pickProgress = (i + j + 1).clamp(0, _pickTotal);
          });

          // Analyze all stocks in parallel (max 10 per sector)
          final analyses = await Future.wait(
            stocks.map((stock) async {
              try {
                final klineData = await _apiClient.getStockHistory(stock.code);
                if (klineData.length < 20) return null;
                final analysis = generateAnalysis(calcAllIndicators(klineData), stock);
                if (analysis.recommendation.contains('买入')) {
                  return {
                    'code': stock.code,
                    'name': stock.name,
                    'recommendation': analysis.recommendation,
                    'score': analysis.score,
                    'sector': sector.name,
                  };
                }
                return null;
              } catch (_) {
                return null;
              }
            }),
          );

          for (final result in analyses) {
            if (result != null) {
              final code = result['code'] as String;
              if (!seenCodes.contains(code)) {
                seenCodes.add(code);
                picks.add(result);
              }
            }
          }
        }
      }

      // Sort by score descending
      picks.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      if (!mounted) return;

      if (picks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前热门板块中暂无买入推荐')),
        );
      } else {
        _showPickResults(picks);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingSectors = false;
          _pickProgress = 0;
          _pickTotal = 0;
        });
      }
    }
  }

  void _showPickResults(List<Map<String, dynamic>> picks) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('板块精选（${picks.length}只）', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white54)),
                ],
              ),
            ),
            // Stock list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: picks.length,
                itemBuilder: (context, index) {
                  final pick = picks[index];
                  final recColor = (pick['recommendation'] as String).contains('强烈')
                    ? const Color(0xFFef5350) : Colors.orange;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0f3460),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: recColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(pick['name'], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 6),
                                  Text(pick['code'], style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('来源：${pick['sector']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: recColor.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                              child: Text(pick['recommendation'], style: TextStyle(color: recColor, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 4),
                            Text('${pick['score']}分', style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Bottom action bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () async {
                      final dbService = DatabaseService();
                      final items = picks.map((p) => WatchlistItem(
                        code: p['code'] as String,
                        name: p['name'] as String,
                        addedAt: DateTime.now(),
                      )).toList();
                      final existing = await dbService.getWatchlist();
                      final existingCodes = existing.map((e) => e.code).toSet();
                      final newItems = items.where((i) => !existingCodes.contains(i.code)).toList();
                      if (newItems.isNotEmpty) {
                        await dbService.batchAddToWatchlist(newItems);
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已添加${newItems.length}只到自选${items.length - newItems.length > 0 ? "，${items.length - newItems.length}只已在自选中" : ""}')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    child: const Text('一键加自选', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
