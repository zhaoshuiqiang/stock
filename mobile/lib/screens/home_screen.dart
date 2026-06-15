import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/sector_pick_engine.dart';
import '../storage/database_service.dart';
import 'quote_screen.dart';
import 'sector_screen.dart';
import 'quant_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  final SectorPickEngine _pickEngine = SectorPickEngine.instance;
  StreamSubscription<SectorPickProgress>? _pickSubscription;
  List<QuoteData> _quotes = [];
  List<SectorInfo> _sectors = [];
  bool _isLoading = false;
  bool _isPickingSectors = false;
  int _pickProgress = 0;
  int _pickTotal = 0;
  List<Map<String, dynamic>> _cachedPicks = [];
  DateTime? _pickLastTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFromCache();
    _loadCachedPicks();
    // 如果引擎正在运行，订阅进度流并恢复状态
    if (_pickEngine.isRunning) {
      _subscribeToPickProgress();
      _restorePickProgress();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 不自动刷新，用户需手动下拉刷新
  }

  /// Tab切换到首页时调用，仅恢复引擎订阅，不自动刷新
  void onTabVisible() {
    if (_pickEngine.isRunning) {
      if (_pickSubscription?.isPaused == true) {
        _pickSubscription!.resume();
        _restorePickProgress();
      } else if (_pickSubscription == null) {
        _subscribeToPickProgress();
        _restorePickProgress();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiClient.dispose();
    // 不取消订阅，让引擎继续后台运行
    _pickSubscription?.pause();
    super.dispose();
  }

  void _subscribeToPickProgress() {
    _pickSubscription?.cancel();
    _pickSubscription = _pickEngine.progressStream.listen(_onPickProgress);
  }

  /// 从 latestProgress 恢复状态
  void _restorePickProgress() {
    final lp = _pickEngine.latestProgress;
    if (lp == null) return;
    setState(() {
      _isPickingSectors = true;
      _pickProgress = lp.progress;
      _pickTotal = lp.total;
    });
  }

  void _onPickProgress(SectorPickProgress progress) {
    if (!mounted) return; // 仅跳过setState，不取消订阅
    switch (progress.status) {
      case SectorPickStatus.analyzing:
        setState(() {
          _isPickingSectors = true;
          _pickProgress = progress.progress;
          _pickTotal = progress.total;
        });
        break;
      case SectorPickStatus.saving:
        break;
      case SectorPickStatus.complete:
        final picks = progress.picks ?? [];
        final now = DateTime.now();
        final hadPreviousCache = _cachedPicks.isNotEmpty;
        setState(() {
          _isPickingSectors = false;
          _pickProgress = 0;
          _pickTotal = 0;
          if (picks.isNotEmpty) {
            _cachedPicks = picks;
            _pickLastTime = now;
          }
        });
        // 如果之前没有缓存，现在分析完了直接展示
        if (picks.isNotEmpty) {
          _showPickResults(picks);
        } else if (!hadPreviousCache) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前热门板块中暂无买入推荐')),
          );
        }
        break;
      case SectorPickStatus.error:
        setState(() {
          _isPickingSectors = false;
          _pickProgress = 0;
          _pickTotal = 0;
        });
        if (progress.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(progress.message!)),
          );
        }
        break;
      case SectorPickStatus.alreadyRunning:
      case SectorPickStatus.idle:
        break;
    }
  }

  String _loadError = '';

  /// 从本地缓存加载，无缓存时才从API获取
  Future<void> _loadFromCache() async {
    final cachedQuotes = await _dbService.getMarketQuotesCache();
    final cachedSectors = await _dbService.getSectorsCache();
    if (mounted) {
      setState(() {
        _quotes = cachedQuotes;
        _sectors = cachedSectors;
      });
    }
    // 任一缓存为空时从API加载
    if (cachedQuotes.isEmpty || cachedSectors.isEmpty) {
      await _loadData();
    }
  }

  /// 从API加载数据并保存到缓存
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
      final quotes = results.where((q) => q != null).cast<QuoteData>().toList();
      if (mounted) {
        setState(() {
          _quotes = quotes;
        });
      }
      // 保存到缓存
      if (quotes.isNotEmpty) {
        await _dbService.saveMarketQuotesCache(quotes);
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
      // 保存到缓存
      if (sectors.isNotEmpty) {
        await _dbService.saveSectorsCache(sectors);
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

  Future<void> _loadCachedPicks() async {
    final results = await _dbService.getSectorPickResults();
    final lastTime = await _dbService.getSectorPickLastTime();
    if (mounted && results.isNotEmpty) {
      setState(() {
        _cachedPicks = results;
        _pickLastTime = lastTime;
      });
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return _isLoading && _quotes.isEmpty && _sectors.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Card(
                  margin: const EdgeInsets.all(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const QuantScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.analytics, color: Colors.blue, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('量化分析', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text('选择股票，运行热门量化策略实时分析', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white38),
                        ],
                      ),
                    ),
                  ),
                ),
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
                            if (_sectors.isNotEmpty || _cachedPicks.isNotEmpty)
                              GestureDetector(
                                onTap: _isPickingSectors ? null : _onPickTapped,
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
                                      Text(_isPickingSectors ? '分析中$_pickProgress/$_pickTotal' : (_cachedPicks.isNotEmpty ? '精选(${_cachedPicks.length})' : '精选'), style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
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

  /// 点击精选：有缓存则先展示缓存，同时后台刷新；无缓存则直接分析
  void _onPickTapped() {
    if (_cachedPicks.isNotEmpty) {
      _showPickResults(_cachedPicks);
      // 后台静默刷新
      if (_sectors.isNotEmpty) {
        _startPickAnalysis();
      }
    } else if (_sectors.isNotEmpty) {
      // 无缓存但有板块数据，启动分析
      _startPickAnalysis();
    } else {
      // 无缓存也无板块数据，提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('板块数据加载中，请稍后再试')),
      );
    }
  }

  void _startPickAnalysis() {
    if (_isPickingSectors) return;
    setState(() {
      _isPickingSectors = true;
      _pickProgress = 0;
      _pickTotal = _sectors.take(10).length;
    });
    _subscribeToPickProgress();
    // 引擎独立运行，不await
    _pickEngine.pick(_sectors);
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

  void _showPickResults(List<Map<String, dynamic>> picks) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1117),
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
                  Row(
                    children: [
                      Text('板块精选（${picks.length}只）', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      if (_pickLastTime != null) ...[
                        const SizedBox(width: 8),
                        Text(_formatTime(_pickLastTime), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ],
                  ),
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
                      color: const Color(0xFF161B22),
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
