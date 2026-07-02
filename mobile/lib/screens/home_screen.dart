import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/limit_up_analyzer.dart';
import '../analysis/limit_up_scan_engine.dart';
import '../analysis/market_timing.dart';
import '../analysis/sector_pick_engine.dart';
import '../storage/database_service.dart';
import '../widgets/sentiment_thermometer_card.dart';
import 'quote_screen.dart';
import 'sector_screen.dart';
import 'quant_screen.dart';
import 'global_market_screen.dart';

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
  List<GlobalIndex> _globalIndices = [];
  bool _isLoading = false;
  String _loadError = '';

  // ─── 短线工作台状态 (v2.33) ──────────────────────────────────
  MarketTimingResult? _marketTiming;
  int _limitUpCount = 0;    // 涨停梯队数量
  int _lowBuyCount = 0;     // 分时低吸数量
  int _mainLineCount = 0;   // 主线板块数量
  bool _isWorkbenchLoading = false; // 工作台刷新中
  // 情绪温度计 (v2.27+)：从 LimitUpScanEngine 缓存读取，不在工作台本地重算
  SentimentResult? _sentiment;
  bool _isScanning = false; // 打板扫描进行中（首页触发时跟踪状态）
  StreamSubscription<LimitUpScanProgress>? _limitUpScanSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFromCache();
    _loadCachedPicks();
    _loadWorkbenchData();
    // 如果引擎正在运行，订阅进度流（完成时刷新主线板块计数）
    if (_pickEngine.isRunning) {
      _subscribeToPickProgress();
    }
    // 订阅打板扫描进度：扫描完成/失败时刷新 _sentiment 并清除 _isScanning
    _limitUpScanSub = LimitUpScanEngine.instance.progressStream.listen((progress) {
      if (!mounted) return;
      if (progress.stage == 'done' || progress.stage == 'error') {
        setState(() {
          _sentiment = LimitUpScanEngine.instance.lastSentiment;
          _isScanning = false;
        });
      }
    });
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
      } else if (_pickSubscription == null) {
        _subscribeToPickProgress();
      }
    }
    _loadWorkbenchData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiClient.dispose();
    // 不取消订阅，让引擎继续后台运行
    _pickSubscription?.cancel();
    _limitUpScanSub?.cancel();
    super.dispose();
  }

  void _subscribeToPickProgress() {
    _pickSubscription?.cancel();
    _pickSubscription = _pickEngine.progressStream.listen(_onPickProgress);
  }

  void _onPickProgress(SectorPickProgress progress) {
    if (!mounted) return;
    if (progress.status == SectorPickStatus.complete) {
      // 精选完成：刷新主线板块计数
      _loadCachedPicks();
    } else if (progress.status == SectorPickStatus.error) {
      if (progress.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(progress.message!)),
        );
      }
    }
  }

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
    }

    // 加载全球指数（美股/港股/亚太/欧洲）
    try {
      final indices = await _apiClient.getGlobalIndices();
      if (mounted) {
        setState(() => _globalIndices = indices);
      }
    } catch (e) {
      debugPrint('Load global indices failed: $e');
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
    if (mounted && results.isNotEmpty) {
      setState(() {
        _mainLineCount = results.where((p) => p['mainLine'] == 1 || p['mainLine'] == true).length;
      });
    }
  }

  /// 加载短线工作台数据：择时 + 涨停/低吸计数 + 情绪温度计缓存
  Future<void> _loadWorkbenchData() async {
    if (_isWorkbenchLoading) return;
    setState(() => _isWorkbenchLoading = true);
    try {
      // 并发加载择时 / 探索结果 / 今日打板池
      final results = await Future.wait<dynamic>([
        MarketTiming.fetchTiming(),
        _dbService.getExploreResults(),
        _dbService.getLimitUpPool(),
      ]);
      final timing = results[0] as MarketTimingResult?;
      final exploreResults = results[1] as List<ExploreResult>;
      final limitUpPool = results[2] as List<LimitUpAnalysis>;

      // 涨停梯队：来自打板池（排除炸板），无打板池时回退到 explore 近似判定
      int limitUp = limitUpPool.where((a) => !a.isZhaBan).length;
      if (limitUp == 0) {
        for (final r in exploreResults) {
          if (r.isLimitUpApprox) limitUp++;
        }
      }
      int lowBuy = 0;
      for (final r in exploreResults) {
        if (r.recommendation.contains('买入') &&
            r.changePct >= -3 && r.changePct <= 5 && r.score >= 6) {
          lowBuy++;
        }
      }
      // 情绪温度计：读取扫描引擎缓存（DiscoverScreen 扫描时填充），不在本地重算
      // 避免 todayQuotePct bug（_computeMoneyMakingEffect 需以昨日 code 为键）
      final sentiment = LimitUpScanEngine.instance.lastSentiment;
      // sentiment 为 null 时后台触发扫描补全（无论 DB 是否有打板池缓存）
      // 修复：原条件含 limitUpPool.isEmpty，DB 有缓存时不会触发，导致首页永远拿不到 sentiment
      if (sentiment == null && !LimitUpScanEngine.instance.isRunning) {
        if (mounted) setState(() => _isScanning = true);
        LimitUpScanEngine.instance.scan();
      }
      if (mounted) {
        setState(() {
          _marketTiming = timing;
          _limitUpCount = limitUp;
          _lowBuyCount = lowBuy;
          _sentiment = sentiment;
          _isWorkbenchLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Workbench load failed: $e');
      if (mounted) {
        setState(() => _isWorkbenchLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('工作台刷新失败: $e', maxLines: 2, overflow: TextOverflow.ellipsis),
              duration: const Duration(seconds: 2)),
        );
      }
    }
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
                _buildGlobalMarketCard(),
                _buildWorkbenchCard(),
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

  /// 环球市场卡片：横向滚动展示全球主要指数 + 当日趋势摘要
  Widget _buildGlobalMarketCard() {
    final indices = _globalIndices;
    // 首页卡片只展示 6 个主要指数
    final display = indices.take(6).toList();
    final summary = _buildGlobalTrendSummary(indices);
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GlobalMarketScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public, color: Colors.blueAccent, size: 20),
                      const SizedBox(width: 6),
                      const Text('环球市场', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Row(
                    children: [
                      Text('查看更多', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                    ],
                  ),
                ],
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(summary, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              if (display.isEmpty)
                const Text('暂无数据', style: TextStyle(color: Colors.white38, fontSize: 13))
              else
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: display.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _buildGlobalIndexItem(display[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 首页环球市场卡片的简要趋势总结（一行）
  String _buildGlobalTrendSummary(List<GlobalIndex> indices) {
    if (indices.isEmpty) return '';
    final t = GlobalIndex.calculateTrend(indices);
    final sign = t.avg >= 0 ? '+' : '';
    return '全球趋势${t.trend} · 均幅$sign${t.avg.toStringAsFixed(2)}% · 涨${t.upCount}/跌${t.downCount}';
  }

  Widget _buildGlobalIndexItem(GlobalIndex idx) {
    final isUp = idx.changePct >= 0;
    final color = isUp ? Colors.red : Colors.green;
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            idx.name,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            idx.price.toStringAsFixed(2),
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${isUp ? '+' : ''}${idx.changePct.toStringAsFixed(2)}%',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 短线工作台卡片 (v2.33+)：情绪温度计大卡 + 2×2 指标网格
  Widget _buildWorkbenchCard() {
    final timing = _marketTiming;
    // 择时配色
    Color timingColor;
    String timingLabel;
    if (timing == null) {
      timingColor = Colors.grey;
      timingLabel = '加载中';
    } else if (timing.trendDirection == 'bull') {
      timingColor = Colors.red;
      timingLabel = timing.positionLabel;
    } else if (timing.trendDirection == 'bear') {
      timingColor = Colors.green;
      timingLabel = timing.positionLabel;
    } else {
      timingColor = Colors.orange;
      timingLabel = timing.positionLabel;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 情绪温度计大卡（_sentiment == null 时显示 skeleton）
        SentimentThermometerCard(
          sentiment: _sentiment,
          onRefresh: _isWorkbenchLoading ? null : _loadWorkbenchData,
          isLoading: _isWorkbenchLoading || _isScanning,
        ),
        // 2×2 指标网格卡片（保持原结构）
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dashboard, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 8),
                    Text('短线工作台',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _isWorkbenchLoading ? null : _loadWorkbenchData,
                      child: _isWorkbenchLoading
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white54))
                          : const Icon(Icons.refresh, color: Colors.white38, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // 择时
                    Expanded(
                      child: _buildWorkbenchMetric(
                        icon: Icons.trending_up,
                        iconColor: timingColor,
                        label: '市场择时',
                        value: timingLabel,
                        valueColor: timingColor,
                      ),
                    ),
                    Container(width: 1, height: 44, color: Colors.white12),
                    // 主线板块
                    Expanded(
                      child: _buildWorkbenchMetric(
                        icon: Icons.military_tech,
                        iconColor: const Color(0xFFFFB000),
                        label: '主线板块',
                        value: '$_mainLineCount个',
                        valueColor: const Color(0xFFFFB000),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // 涨停梯队
                    Expanded(
                      child: _buildWorkbenchMetric(
                        icon: Icons.local_fire_department,
                        iconColor: Colors.red,
                        label: '涨停梯队',
                        value: '$_limitUpCount只',
                        valueColor: Colors.red,
                      ),
                    ),
                    Container(width: 1, height: 44, color: Colors.white12),
                    // 分时低吸
                    Expanded(
                      child: _buildWorkbenchMetric(
                        icon: Icons.trending_down,
                        iconColor: Colors.green,
                        label: '分时低吸',
                        value: '$_lowBuyCount只',
                        valueColor: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkbenchMetric({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: valueColor, fontSize: 15, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis),
      ],
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
}
