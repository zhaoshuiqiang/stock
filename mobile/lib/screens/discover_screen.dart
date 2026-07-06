import 'dart:async';

import 'package:flutter/material.dart';

import '../analysis/explore_engine.dart';
import '../analysis/sector_pick_engine.dart';
import '../analysis/limit_up_analyzer.dart';
import '../analysis/limit_up_scan_engine.dart';
import '../analysis/intraday_scan_engine.dart';
import '../analysis/intraday_level_analyzer.dart';
import '../api/api_client.dart';
import '../core/trading_session.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/limit_up_card.dart';
import '../widgets/stock_card.dart';
import 'quote_screen.dart';

// ─── 配色常量 ────────────────────────────────────────────────────────
const _kBg = Color(0xFF0D1117);
const _kCard = Color(0xFF161B22);
const _kAccent = Color(0xFF58A6FF);
const _kUp = Color(0xFFE74C3C);
const _kDown = Color(0xFF2ECC71);
const _kTextPrimary = Color(0xFFF0F6FC);
const _kTextSecondary = Color(0xFF8B949E);
const _kBorder = Color(0xFF30363D);
const _kLimitUpColor = Color(0xFFE74C3C);   // 打板红
const _kMainLineColor = Color(0xFFFFB000);  // 主线金
const _kLowBuyColor = Color(0xFF2ECC71);    // 低吸绿

/// 打板梯队分组数据模型
class _LimitUpGroup {
  final String title;
  final String subtitle;
  final Color accentColor;
  final List<LimitUpAnalysis> items;
  const _LimitUpGroup({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.items,
  });
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    this.limitUpPoolOverride,
    this.sentimentOverride,
  });
  final List<LimitUpAnalysis>? limitUpPoolOverride;
  final SentimentResult? sentimentOverride;

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

class DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  final ExploreEngine _exploreEngine = ExploreEngine.instance;
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();

  late final TabController _tabController;

  // ─── 智能探索状态 ──────────────────────────────────────────────
  List<ExploreResult> _exploreResults = [];
  bool _exploreLoading = false;
  String _exploreSort = '评分'; // 评分 / 涨幅 / 名称
  String _exploreFilter = '全部'; // 全部 / 买入 / 观望
  Set<String> _watchlistCodes = {};
  // 板块精选结果（主线龙头 Tab 数据源）
  List<Map<String, dynamic>> _sectorPickResults = [];
  bool _isPickingSectors = false; // 板块精选引擎运行中
  StreamSubscription<SectorPickProgress>? _sectorPickSub;
  // 主线龙头实时行情缓存（裸code → QuoteData），用于显示价格/涨跌幅
  Map<String, QuoteData> _mainLineQuotes = {};

  StreamSubscription<ExploreProgress>? _exploreSub;

  // ─── 打板梯队状态 ──────────────────────────────────────────────
  List<LimitUpAnalysis> _limitUpPool = [];
  SentimentResult? _sentiment;
  bool _limitUpScanLoading = false;
  StreamSubscription<LimitUpScanProgress>? _limitUpScanSub;
  String? _limitUpTradeDate;      // 当前打板数据所属交易日
  bool _isLimitUpDataHistorical = false; // 是否为历史数据

  // ─── 缓存的列表数据（避免 build 中重复计算） ──────────────────
  List<_LimitUpGroup> _cachedLimitUpGroups = [];
  List<Map<String, dynamic>> _cachedMainLinePicks = [];
  // 分时低吸 Tab：基于 IntradayScanEngine 的分时扫描结果
  List<IntradayScanResult> _cachedIntradayBuyList = [];
  bool _isScanningIntraday = false;
  DateTime? _lastIntradayScanTime;
  List<ExploreResult> _cachedProcessedExploreResults = [];

  // ─── 生命周期 ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      // 切到分时低吸 Tab（index=2）时触发懒加载扫描
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        _maybeRefreshIntradayScan();
      }
    });
    _loadExploreFromDb();
    _loadWatchlistCodes();
    _loadSectorPicks();

    // 如果DB无板块精选数据，自动触发一次分析
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_sectorPickResults.isEmpty && !SectorPickEngine.instance.isRunning) {
        await _autoTriggerSectorPicks();
      }
    });

    // 订阅智能探索进度
    _exploreSub = _exploreEngine.progressStream.listen(_onExploreProgress);
    if (_exploreEngine.latestProgress != null) {
      // 延迟到首帧后再恢复进度，避免在 initState 中调用 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onExploreProgress(_exploreEngine.latestProgress!);
      });
    }
    // 订阅板块精选进度（主线龙头 Tab 数据更新）
    _sectorPickSub = SectorPickEngine.instance.progressStream.listen((p) {
      if (!mounted) return;
      switch (p.status) {
        case SectorPickStatus.analyzing:
        case SectorPickStatus.saving:
          setState(() => _isPickingSectors = true);
          break;
        case SectorPickStatus.complete:
          setState(() => _isPickingSectors = false);
          _loadSectorPicks();
          break;
        case SectorPickStatus.error:
          setState(() => _isPickingSectors = false);
          if (p.message != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(p.message!)),
            );
          }
          break;
        case SectorPickStatus.alreadyRunning:
          setState(() => _isPickingSectors = true);
          break;
        case SectorPickStatus.idle:
          break;
      }
    });
    // 如果引擎已在运行，恢复状态
    if (SectorPickEngine.instance.isRunning) {
      _isPickingSectors = true;
    }

    // 订阅打板扫描进度（情绪温度计 + 打板池更新）
    _limitUpScanSub = LimitUpScanEngine.instance.progressStream.listen((p) {
      if (!mounted) return;
      switch (p.stage) {
        case 'fetching':
        case 'analyzing':
        case 'computing_sentiment':
          setState(() => _limitUpScanLoading = true);
          break;
        case 'done':
          setState(() => _limitUpScanLoading = false);
          _loadLimitUpPoolFromDb();
          break;
        case 'error':
          setState(() => _limitUpScanLoading = false);
          break;
        case 'already_running':
          // 引擎已在运行，从DB读取已有数据，同时等待进度流完成
          _loadLimitUpPoolFromDb();
          break;
      }
    });
    // 如果引擎已在运行，恢复状态
    if (LimitUpScanEngine.instance.isRunning) {
      _limitUpScanLoading = true;
    }
    // 延迟到首帧后加载打板池，避免在 initState 中同步调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLimitUpPoolFromDb();
    });

    // 如果通过 override 直接传入打板池数据（测试或外部注入场景），立即初始化缓存
    // 避免异步加载失败时缓存为空导致 UI 不渲染分组
    if (widget.limitUpPoolOverride != null) {
      _updateCachedLists();
    }
  }

  @override
  void dispose() {
    _exploreSub?.cancel();
    _sectorPickSub?.cancel();
    _limitUpScanSub?.cancel();
    _apiClient.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// 切回发现Tab时刷新自选状态
  void onTabVisible() {
    _loadWatchlistCodes();
    _loadSectorPicks();
  }

  /// 检查是否需要刷新分时低吸扫描
  /// 仅在交易时段内、距上次扫描超过 1 分钟时刷新
  void _maybeRefreshIntradayScan() {
    if (!TradingSession.isInTradingSession()) return;
    if (_isScanningIntraday) return;
    final now = DateTime.now();
    if (_lastIntradayScanTime != null &&
        now.difference(_lastIntradayScanTime!).inMinutes < 1) return;
    _loadIntradayScanResults();
  }

  Future<void> _loadIntradayScanResults() async {
    if (_isScanningIntraday) return;
    if (!mounted) return;

    // 非交易时段给用户提示
    if (!TradingSession.isInTradingSession()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('非交易时段，分时低吸扫描仅在盘中有效'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }

    setState(() => _isScanningIntraday = true);
    try {
      // 先确保explore_results有数据
      var exploreResults = await _dbService.getExploreResults();
      if (exploreResults.isEmpty) {
        // 无探索数据，先触发一次全市场扫描
        try {
          await ExploreEngine.instance.explore();
          exploreResults = await _dbService.getExploreResults();
        } catch (e) {
          debugPrint('_loadIntradayScanResults: explore scan failed: $e');
        }
      }
      final results = await IntradayScanEngine.scan();
      if (mounted) {
        setState(() {
          _cachedIntradayBuyList = results;
          _lastIntradayScanTime = DateTime.now();
          _isScanningIntraday = false;
        });
        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前无符合条件的低吸信号'), duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      debugPrint('_loadIntradayScanResults error: $e');
      if (mounted) {
        setState(() => _isScanningIntraday = false);
      }
    }
  }

  // ─── 数据加载 ──────────────────────────────────────────────────

  Future<void> _loadExploreFromDb() async {
    try {
      final results = await _dbService.getExploreResults();
      if (mounted) {
        setState(() {
          _exploreResults = results;
          _updateCachedLists();
        });
      }
    } catch (e) {
      debugPrint('_loadExploreFromDb failed: $e');
    }
  }

  Future<void> _loadWatchlistCodes() async {
    try {
      final list = await _dbService.getWatchlist();
      if (mounted) {
        setState(() {
          _watchlistCodes = list.map((e) => e.code).toSet();
        });
      }
    } catch (e) {
      debugPrint('_loadWatchlistCodes failed: $e');
    }
  }

  Future<void> _loadSectorPicks() async {
    try {
      final results = await _dbService.getSectorPickResults();
      if (mounted) {
        setState(() {
          _sectorPickResults = results;
          _updateCachedLists();
        });
        _fetchMainLineQuotes(); // fire-and-forget 补充实时行情
      }
    } catch (e) {
      debugPrint('_loadSectorPicks failed: $e');
    }
  }

  /// 批量获取主线龙头的实时行情（显示价格/涨跌幅用）
  Future<void> _fetchMainLineQuotes() async {
    final picks = _cachedMainLinePicks;
    if (picks.isEmpty) return;
    try {
      final codes = picks
          .map((p) => (p['code'] as String?) ?? '')
          .where((c) => c.isNotEmpty)
          .toList();
      if (codes.isEmpty) return;
      final prefixed = codes.map((c) => _apiClient.addMarketPrefix(c)).toList();
      final quotes = await _apiClient.getBatchRealtimeQuotes(prefixed);
      // key 用带前缀的 quote.code，与 _buildMainLineCard 中 addMarketPrefix(code) 匹配
      final map = <String, QuoteData>{};
      for (final q in quotes) {
        map[q.code] = q;
      }
      if (mounted) setState(() => _mainLineQuotes = map);
    } catch (e) {
      debugPrint('_fetchMainLineQuotes failed: $e');
    }
  }

  // ─── 打板梯队：加载/刷新 ──────────────────────────────────────

  Future<void> _loadLimitUpPoolFromDb() async {
    try {
      final pool = await _dbService.getLimitUpPool();
      final shanghaiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      final todayDate = shanghaiNow.toIso8601String().substring(0, 10);
      if (mounted) {
        setState(() {
          _limitUpPool = pool;
          _limitUpTradeDate = LimitUpScanEngine.instance.currentTradeDate ?? todayDate;
          _isLimitUpDataHistorical = LimitUpScanEngine.instance.isCurrentDataHistorical;
          _updateCachedLists();
        });
      }
    } catch (e) {
      debugPrint('_loadLimitUpPoolFromDb failed: $e');
    }
  }

  Future<void> _refreshLimitUpPool() async {
    if (_limitUpScanLoading) return;
    setState(() => _limitUpScanLoading = true);
    try {
      final sentiment = await LimitUpScanEngine.instance.scan();
      if (sentiment == null && LimitUpScanEngine.instance.isRunning) {
        return;
      }
      final pool = await _dbService.getLimitUpPool();
      if (mounted) {
        setState(() {
          _sentiment = sentiment;
          _limitUpPool = pool;
          _limitUpTradeDate = LimitUpScanEngine.instance.currentTradeDate;
          _isLimitUpDataHistorical = LimitUpScanEngine.instance.isCurrentDataHistorical;
          _limitUpScanLoading = false;
          _updateCachedLists();
        });
      }
    } catch (e) {
      debugPrint('_refreshLimitUpPool failed: $e');
      if (mounted) setState(() => _limitUpScanLoading = false);
    }
  }

  /// 触发板块精选引擎：获取热门板块 → SectorPickEngine.pick()
  Future<void> _refreshSectorPicks() async {
    if (_isPickingSectors) return; // 防止重复触发
    if (SectorPickEngine.instance.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('板块精选分析进行中...'), duration: Duration(seconds: 1)),
      );
      return;
    }
    setState(() => _isPickingSectors = true);
    try {
      final sectors = await _apiClient.getHotSectors();
      if (sectors.isEmpty) {
        if (mounted) {
          setState(() => _isPickingSectors = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取板块数据失败，请检查网络')),
          );
        }
        return;
      }
      // 引擎异步运行，通过 progressStream 通知进度
      SectorPickEngine.instance.pick(sectors);
    } catch (e) {
      if (mounted) {
        setState(() => _isPickingSectors = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刷新失败: $e')),
        );
      }
    }
  }

  /// 自动触发板块精选（DB无数据时静默执行，不弹错误提示）
  Future<void> _autoTriggerSectorPicks() async {
    if (_isPickingSectors || SectorPickEngine.instance.isRunning) return;
    setState(() => _isPickingSectors = true);
    try {
      final sectors = await _apiClient.getHotSectors();
      if (sectors.isEmpty) {
        if (mounted) setState(() => _isPickingSectors = false);
        return;
      }
      SectorPickEngine.instance.pick(sectors);
    } catch (e) {
      debugPrint('_autoTriggerSectorPicks failed: $e');
      if (mounted) setState(() => _isPickingSectors = false);
    }
  }

  // ─── 智能探索进度回调 ──────────────────────────────────────────

  void _onExploreProgress(ExploreProgress p) {
    if (!mounted) return;
    setState(() {
      switch (p.status) {
        case ExploreStatus.fetchingSectors:
        case ExploreStatus.fetchingStocks:
        case ExploreStatus.fetchingKlines:
        case ExploreStatus.fetchingQuotes:
        case ExploreStatus.analyzing:
        case ExploreStatus.saving:
          _exploreLoading = true;
          break;
        case ExploreStatus.complete:
          _exploreLoading = false;
          if (p.results != null) {
            _exploreResults = p.results!;
          }
          _updateCachedLists();
          break;
        case ExploreStatus.error:
          _exploreLoading = false;
          break;
        case ExploreStatus.alreadyRunning:
          _exploreLoading = true;
          break;
        case ExploreStatus.idle:
          break;
      }
    });
  }

  // ─── Tab 1: 打板梯队（涨停/连板标的） ─────────────────────────

  /// 重新计算所有缓存的列表（在数据变更的 setState 内调用）
  void _updateCachedLists() {
    // 打板梯队分组：龙头(≥4连板) / 高度板(3连板) / 中度板(2连板) / 首板 / 炸板
    final pool = widget.limitUpPoolOverride ?? _limitUpPool;
    if (pool.isEmpty) {
      _cachedLimitUpGroups = [];
    } else {
      _cachedLimitUpGroups = [
        _LimitUpGroup(
          title: '龙头',
          subtitle: '≥4连板',
          accentColor: const Color(0xFF9D2933),
          items: pool.where((a) => a.consecutiveDays >= 4).toList()
            ..sort((a, b) => b.consecutiveDays.compareTo(a.consecutiveDays)),
        ),
        _LimitUpGroup(
          title: '高度板',
          subtitle: '3连板',
          accentColor: const Color(0xFFE74C3C),
          items: pool.where((a) => a.consecutiveDays == 3).toList()
            ..sort((a, b) => b.sealAmount.compareTo(a.sealAmount)),
        ),
        _LimitUpGroup(
          title: '中度板',
          subtitle: '2连板',
          accentColor: const Color(0xFFE67E22),
          items: pool.where((a) => a.consecutiveDays == 2).toList()
            ..sort((a, b) => b.sealAmount.compareTo(a.sealAmount)),
        ),
        _LimitUpGroup(
          title: '首板',
          subtitle: '今日首封',
          accentColor: const Color(0xFF58A6FF),
          items: pool.where((a) => a.consecutiveDays == 1 && !a.isZhaBan).toList()
            ..sort((a, b) {
              // 按首封时间升序，未知时间(null)排到末尾
              final aT = a.firstLimitTime?.millisecondsSinceEpoch;
              final bT = b.firstLimitTime?.millisecondsSinceEpoch;
              if (aT == null && bT == null) return 0;
              if (aT == null) return 1;
              if (bT == null) return -1;
              return aT.compareTo(bT);
            }),
        ),
        if (pool.any((a) => a.isZhaBan))
          _LimitUpGroup(
            title: '炸板',
            subtitle: '曾封后开',
            accentColor: const Color(0xFF8B5A5A),
            items: pool.where((a) => a.isZhaBan).toList()
              ..sort((a, b) => b.sealAmount.compareTo(a.sealAmount)),
          ),
      ].where((g) => g.items.isNotEmpty).toList();
    }

    // 主线龙头：仅展示主线板块个股；无主线命中时显示空状态，不回退展示全部精选
    final all = _sectorPickResults;
    // mainLine 经 SQLite 往返后为 int(0/1)，从引擎直接获取时为 bool
    var picks = all.where((p) => p['mainLine'] == 1 || p['mainLine'] == true).toList();
    // 注意：db.query() 返回的 QueryResultSet 是只读的（operator []= 抛 read-only），
    // 不能直接赋值后 sort，必须创建可变副本
    if (picks.isNotEmpty) {
      picks = List<Map<String, dynamic>>.from(picks);
    }
    picks.sort((a, b) =>
        (b['score'] as num? ?? 0).toInt().compareTo((a['score'] as num? ?? 0).toInt()));
    _cachedMainLinePicks = picks;

    // 分时低吸：由 IntradayScanEngine 独立扫描，此处不再基于日线 ExploreResult 筛选

    // 全市场：排序+筛选
    var processedList = List<ExploreResult>.from(_exploreResults);
    switch (_exploreFilter) {
      case '买入':
        processedList = processedList
            .where((r) =>
                r.recommendation.contains('买入') ||
                r.recommendation.contains('强烈买入'))
            .toList();
        break;
      case '观望':
        processedList = processedList
            .where((r) =>
                !r.recommendation.contains('买入') &&
                !r.recommendation.contains('卖出'))
            .toList();
        break;
    }
    switch (_exploreSort) {
      case '评分':
        processedList.sort((a, b) => b.score.compareTo(a.score));
        break;
      case '涨幅':
        processedList.sort((a, b) => b.changePct.compareTo(a.changePct));
        break;
      case '名称':
        processedList.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    _cachedProcessedExploreResults = processedList;
  }

  /// 是否有主线板块命中（用于UI提示区分"无主线"与"回退展示"）
  bool get _hasMainLineHit => _sectorPickResults
      .any((p) => p['mainLine'] == 1 || p['mainLine'] == true);

  // ─── 智能探索：自选切换 ────────────────────────────────────────

  Future<void> _toggleWatchlist(ExploreResult r) async {
    final isIn = _watchlistCodes.contains(r.code);
    if (isIn) {
      await _dbService.removeFromWatchlist(r.code);
    } else {
      await _dbService.addToWatchlist(r.code, r.name);
    }
    await _loadWatchlistCodes();
  }

  Future<void> _toggleWatchlistByCode(String code, String name) async {
    final isIn = _watchlistCodes.contains(code);
    if (isIn) {
      await _dbService.removeFromWatchlist(code);
    } else {
      await _dbService.addToWatchlist(code, name);
    }
    await _loadWatchlistCodes();
  }

  // ─── 一键加自选（4个Tab通用） ──────────────────────────────────

  /// 批量加入自选：接收任意来源的 WatchlistItem 列表
  Future<void> _batchAddToWatchlist(List<WatchlistItem> allStocks) async {
    final notInList = allStocks
        .where((r) => !_watchlistCodes.contains(r.code))
        .toList();
    if (notInList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('所有股票已在自选中'),
          backgroundColor: _kAccent,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    await _dbService.batchAddToWatchlist(notInList);
    await _loadWatchlistCodes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 ${notInList.length} 只股票到自选'),
          backgroundColor: _kAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 一键加自选条（置于各Tab顶部）：显示总数+未加自选数+按钮
  Widget _buildBatchAddBar(List<WatchlistItem> allStocks) {
    final notInList = allStocks
        .where((r) => !_watchlistCodes.contains(r.code))
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Text(
            '共 ${allStocks.length} 只 · $notInList 只未加自选',
            style: const TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('一键加自选', style: TextStyle(fontSize: 12)),
            onPressed: notInList > 0
                ? () => _batchAddToWatchlist(allStocks)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF21262D),
              disabledForegroundColor: _kTextSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTabBar(),
            // 进度条（仅探索进行中时显示）
            if (_exploreLoading) _buildExploreProgress(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLimitUpTab(),
                  _buildMainLineTab(),
                  _buildLowBuyTab(),
                  _buildAllMarketTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TabBar ────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        labelColor: Colors.white,
        unselectedLabelColor: _kTextSecondary,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _kAccent,
        ),
        dividerHeight: 0,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabAlignment: TabAlignment.fill,
        tabs: const [
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department, size: 16),
                SizedBox(width: 4),
                Text('打板梯队'),
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.military_tech, size: 16),
                SizedBox(width: 4),
                Text('主线龙头'),
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.trending_down, size: 16),
                SizedBox(width: 4),
                Text('分时低吸'),
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.public, size: 16),
                SizedBox(width: 4),
                Text('全市场'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab 1: 打板梯队 ──────────────────────────────────────────

  Widget _buildLimitUpTab() {
    final pool = widget.limitUpPoolOverride ?? _limitUpPool;
    if (_limitUpScanLoading && pool.isEmpty) {
      return _buildLoadingIndicator();
    }
    if (pool.isEmpty) {
      return _buildEmptyState(
        icon: Icons.local_fire_department_outlined,
        text: '今日暂无涨停标的',
        actionText: '刷新打板池',
        onAction: _refreshLimitUpPool,
      );
    }
    final sealedCount = pool.where((a) => !a.isZhaBan).length;
    final dateLabel = _limitUpTradeDate != null
        ? _formatDateLabel(_limitUpTradeDate!)
        : '';
    final isHistorical = widget.limitUpPoolOverride == null && _isLimitUpDataHistorical;
    return Column(
      children: [
        _buildTabHeader(
          count: sealedCount,
          hint: _sentiment != null
              ? '情绪${_sentiment!.temperature.toStringAsFixed(0)}° · $sealedCount只涨停'
              : '$sealedCount只涨停 · 点击刷新',
          accentColor: _kLimitUpColor,
          actionText: _limitUpScanLoading ? '扫描中...' : '刷新打板池',
          onAction: _limitUpScanLoading ? null : _refreshLimitUpPool,
          dateLabel: dateLabel,
          isHistorical: isHistorical,
        ),
        _buildBatchAddBar(
          pool.map((a) => WatchlistItem(code: a.code, name: a.name)).toList(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _buildSentimentMiniCard(),
              const SizedBox(height: 4),
              for (final group in _cachedLimitUpGroups) ...[
                _buildGroupHeader(group),
                for (final item in group.items)
                  LimitUpCard(
                    analysis: item,
                    isWatched: _watchlistCodes.contains(item.code),
                    onTap: () => _navigateToQuote(item.code, item.name),
                    onWatchlistToggle: () => _toggleWatchlistByCode(item.code, item.name),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 格式化日期标签（如 "7/3 周四"）
  String _formatDateLabel(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final targetDate = DateTime(date.year, date.month, date.day);

      final weekDays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

      if (targetDate == today) {
        return '今日 ${weekDays[date.weekday % 7]}';
      } else if (targetDate == yesterday) {
        return '昨日 ${weekDays[date.weekday % 7]}';
      } else {
        return '${date.month}/${date.day} ${weekDays[date.weekday % 7]}';
      }
    } catch (_) {
      return dateStr;
    }
  }

  /// 打板扫描加载指示器
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _kLimitUpColor),
          SizedBox(height: 12),
          Text('扫描打板池中...', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  /// 情绪温度计迷你卡（顶部摘要）
  Widget _buildSentimentMiniCard() {
    final s = widget.sentimentOverride ?? _sentiment;
    if (s == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('情绪温度',
                  style: TextStyle(color: _kTextSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              Text('${s.temperature.toStringAsFixed(0)}°',
                  style: TextStyle(
                    color: _temperatureColor(s.temperature),
                    fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _buildPhaseChip(s.phase),
              const Spacer(),
              Text('${s.limitUpCount}家涨停',
                  style: const TextStyle(color: _kLimitUpColor, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildMetricChip('炸板率', '${(s.zhabanRate * 100).toStringAsFixed(0)}%',
                  s.zhabanRate < 0.3 ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C)),
              _buildMetricChip('晋级率', '${(s.continuationRate * 100).toStringAsFixed(0)}%',
                  s.continuationRate > 0.4 ? const Color(0xFF2ECC71) : const Color(0xFFE67E22)),
              _buildMetricChip('封板率', '${(s.sealSuccessRate * 100).toStringAsFixed(0)}%',
                  const Color(0xFF58A6FF)),
              _buildMetricChip('赚钱效应', '${s.moneyMakingEffect.toStringAsFixed(1)}%',
                  s.moneyMakingEffect >= 0 ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C)),
              _buildMetricChip('最高连板', '${s.continuationHeight}板', const Color(0xFFFFB000)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseChip(EmotionPhase phase) {
    final (label, color) = switch (phase) {
      EmotionPhase.startup => ('启动期', const Color(0xFF2ECC71)),
      EmotionPhase.climax => ('高潮期', const Color(0xFFE74C3C)),
      EmotionPhase.retreat => ('退潮期', const Color(0xFFE67E22)),
      EmotionPhase.freezing => ('冰点期', const Color(0xFF58A6FF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label $value', style: TextStyle(fontSize: 10, color: color),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Color _temperatureColor(double t) {
    if (t >= 70) return const Color(0xFFE74C3C);
    if (t >= 45) return const Color(0xFFE67E22);
    if (t >= 25) return const Color(0xFFFFB000);
    return const Color(0xFF58A6FF);
  }

  /// 分组头部：标题 + 副标题 + 数量
  Widget _buildGroupHeader(_LimitUpGroup group) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: group.accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(group.title, style: TextStyle(
              color: group.accentColor, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text(group.subtitle, style: const TextStyle(
              color: _kTextSecondary, fontSize: 11),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: group.accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${group.items.length}',
                style: TextStyle(color: group.accentColor, fontSize: 10, fontWeight: FontWeight.w600),
                maxLines: 1),
          ),
        ],
      ),
    );
  }

  void _navigateToQuote(String code, String name) {
    // 确保代码带市场前缀（打板池存的是裸6位代码，API 需要 sh/sz/bj 前缀）
    final prefixedCode = _apiClient.addMarketPrefix(code);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuoteScreen(code: prefixedCode, name: name),
      ),
    );
  }

  // ─── Tab 2: 主线龙头 ──────────────────────────────────────────

  Widget _buildMainLineTab() {
    final list = _cachedMainLinePicks;
    String hint;
    if (_isPickingSectors) {
      hint = '板块精选分析中...';
    } else if (list.isEmpty) {
      hint = _sectorPickResults.isEmpty ? '暂无板块精选数据，点击刷新' : '当前无主线板块命中';
    } else if (_hasMainLineHit) {
      hint = '主线板块内精选个股，含轮动加成';
    } else {
      hint = '暂无主线命中，盘后更新';
    }
    return Column(
      children: [
        _buildTabHeader(
          count: list.length,
          hint: hint,
          accentColor: _kMainLineColor,
          actionText: _isPickingSectors ? '分析中...' : '刷新板块',
          onAction: _isPickingSectors ? null : _refreshSectorPicks,
        ),
        if (_isPickingSectors)
          const LinearProgressIndicator(
            backgroundColor: Color(0xFF21262D),
            valueColor: AlwaysStoppedAnimation<Color>(_kMainLineColor),
          ),
        _buildBatchAddBar(
          list
              .map((p) => WatchlistItem(
                    code: (p['code'] as String?) ?? '',
                    name: (p['name'] as String?) ?? '',
                  ))
              .where((w) => w.code.isNotEmpty)
              .toList(),
        ),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.military_tech_outlined,
                  text: _sectorPickResults.isEmpty
                      ? '暂无板块精选数据'
                      : '当前无明确主线板块，盘后更新',
                  actionText: _sectorPickResults.isEmpty && !_isPickingSectors
                      ? '开始精选' : null,
                  onAction: _sectorPickResults.isEmpty && !_isPickingSectors
                      ? _refreshSectorPicks : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _buildMainLineCard(list[i], i + 1),
                ),
        ),
      ],
    );
  }

  // ─── Tab 3: 分时低吸 ──────────────────────────────────────────

  Widget _buildLowBuyTab() {
    final list = _cachedIntradayBuyList;
    final inSession = TradingSession.isInTradingSession();
    final hint = _isScanningIntraday
        ? '分时扫描中...'
        : list.isEmpty
            ? (inSession ? '当前无高可信度低吸信号' : '非交易时段，盘后显示最近一次扫描结果')
            : '高可信度低吸信号 · 按置信度排序';
    return Column(
      children: [
        _buildTabHeader(
          count: list.length,
          hint: hint,
          accentColor: _kLowBuyColor,
          actionText: _isScanningIntraday ? '扫描中...' : '刷新扫描',
          onAction: _isScanningIntraday ? null : _loadIntradayScanResults,
        ),
        if (_isScanningIntraday)
          const LinearProgressIndicator(
            backgroundColor: Color(0xFF21262D),
            valueColor: AlwaysStoppedAnimation<Color>(_kLowBuyColor),
          ),
        _buildBatchAddBar(
          list.map((r) => WatchlistItem(code: r.code, name: r.name)).toList(),
        ),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.trending_down_outlined,
                  text: inSession ? '当前无分时低吸信号' : '非交易时段，无分时低吸信号',
                  actionText: inSession && !_isScanningIntraday ? '手动扫描' : null,
                  onAction: inSession && !_isScanningIntraday
                      ? _loadIntradayScanResults
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _buildIntradayScanCard(list[i], i + 1),
                ),
        ),
      ],
    );
  }

  /// 分时低吸信号卡片
  Widget _buildIntradayScanCard(IntradayScanResult r, int rank) {
    final isUp = r.changePct >= 0;
    final trendLabel = r.trend == IntradayTrend.bullish
        ? '日内上涨'
        : r.trend == IntradayTrend.bearish
            ? '日内下跌'
            : '日内震荡';
    final trendColor = r.trend == IntradayTrend.bullish
        ? _kUp
        : r.trend == IntradayTrend.bearish
            ? _kDown
            : _kTextSecondary;
    return Card(
      color: _kCard,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _kBorder, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _navigateToQuote(r.code, r.name),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 排名
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kLowBuyColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: _kLowBuyColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 股票信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          r.name,
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          r.code,
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kLowBuyColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r.topBuySignal.shortLabel,
                            style: const TextStyle(
                              color: _kLowBuyColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          trendLabel,
                          style: TextStyle(
                            color: trendColor,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '置信度 ${(r.topBuySignal.confidence * 100).toInt()}%',
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 右侧：价格 + 涨跌幅
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '¥${r.currentPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isUp ? '+' : ''}${r.changePct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: isUp ? _kUp : _kDown,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tab 4: 全市场 ────────────────────────────────────────────

  Widget _buildAllMarketTab() {
    final processed = _cachedProcessedExploreResults;
    return Column(
      children: [
        _buildExploreHeader(),
        _buildBatchAddBar(
          processed
              .map((r) => WatchlistItem(code: r.code, name: r.name))
              .toList(),
        ),
        Expanded(
          child: processed.isEmpty
              ? _buildEmptyState(
                  icon: Icons.explore_outlined,
                  text: _exploreResults.isEmpty ? '暂无探索数据' : '当前筛选无结果',
                  actionText: _exploreResults.isEmpty ? '开始探索' : null,
                  onAction: _exploreResults.isEmpty
                      ? () => _exploreEngine.explore()
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: processed.length,
                  itemBuilder: (_, i) => _buildExploreCard(processed[i], i + 1),
                ),
        ),
      ],
    );
  }

  // ─── Tab 通用头部（计数+提示+可选操作） ────────────────────────

  Widget _buildTabHeader({
    required int count,
    required String hint,
    required Color accentColor,
    String? actionText,
    VoidCallback? onAction,
    String? dateLabel,
    bool isHistorical = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 14,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text('$count只', style: TextStyle(
                color: accentColor, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (dateLabel?.isNotEmpty ?? false)
                Text(dateLabel!, style: const TextStyle(
                  color: _kTextSecondary, fontSize: 11)),
              if (isHistorical)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF26A69A).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('历史数据', style: TextStyle(
                    color: Color(0xFF26A69A), fontSize: 10)),
                ),
              const Spacer(),
              if (actionText != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: accentColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionText, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(hint, style: const TextStyle(
            color: _kTextSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ─── 排序+筛选条（仅全市场Tab） ────────────────────────────────

  Widget _buildExploreHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('排序', style: TextStyle(color: _kTextSecondary, fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.only(left: 8, right: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _exploreSort,
                  isDense: true,
                  isExpanded: true,
                  icon: const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.expand_more, color: _kTextSecondary, size: 18),
                  ),
                  iconEnabledColor: _kTextSecondary,
                  dropdownColor: const Color(0xFF21262D),
                  alignment: Alignment.centerLeft,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 12),
                  items: ['评分', '涨幅', '名称'].map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(s, style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() {
                      _exploreSort = v;
                      _updateCachedLists();
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('筛选', style: TextStyle(color: _kTextSecondary, fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.only(left: 8, right: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _exploreFilter,
                  isDense: true,
                  isExpanded: true,
                  icon: const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.expand_more, color: _kTextSecondary, size: 18),
                  ),
                  iconEnabledColor: _kTextSecondary,
                  dropdownColor: const Color(0xFF21262D),
                  alignment: Alignment.centerLeft,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 12),
                  items: ['全部', '买入', '观望'].map((f) {
                    return DropdownMenuItem(
                      value: f,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(f, style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() {
                      _exploreFilter = v;
                      _updateCachedLists();
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 刷新
          IconButton(
            icon: const Icon(Icons.refresh, color: _kTextSecondary, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _exploreLoading ? null : () => _exploreEngine.explore(),
            tooltip: '刷新探索',
          ),
        ],
      ),
    );
  }

  Widget _buildExploreProgress() {
    final p = _exploreEngine.latestProgress;
    final analyzed = p?.analyzedStocks ?? 0;
    final total = p?.totalStocks ?? 1;
    final found = p?.foundStocks ?? 0;
    final progress = total > 0 ? analyzed / total : 0.0;
    String statusText;
    switch (p?.status) {
      case ExploreStatus.fetchingSectors:
        statusText = '获取热门板块...';
        break;
      case ExploreStatus.fetchingStocks:
        statusText = '获取成分股 ${total}只';
        break;
      case ExploreStatus.fetchingKlines:
        statusText = '预取K线 $analyzed/$total';
        break;
      case ExploreStatus.fetchingQuotes:
        statusText = '批量获取行情...';
        break;
      case ExploreStatus.analyzing:
        statusText = '分析中 $analyzed/$total · 已发现$found只';
        break;
      case ExploreStatus.saving:
        statusText = '保存结果...';
        break;
      default:
        statusText = '处理中...';
    }
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          backgroundColor: const Color(0xFF21262D),
          valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            statusText,
            style: const TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ─── ExploreResult 卡片（打板/低吸/全市场共用） ────────────────

  Widget _buildExploreCard(ExploreResult r, int rank, {String? accentTag}) {
    final isInWatchlist = _watchlistCodes.contains(r.code);

    // 信号标签
    final tags = <Widget>[];
    if (accentTag != null) {
      final color = accentTag == '涨停' ? _kLimitUpColor : _kLowBuyColor;
      tags.add(SignalTag(text: accentTag, color: color));
    }
    if (r.confluenceScore > 0) {
      tags.add(SignalTag(text: '共振${r.confluenceScore}', color: _kAccent));
    }
    if (r.sector.isNotEmpty) {
      tags.add(SignalTag(text: r.sector, color: _kTextSecondary));
    }
    // Phase 1: 市场结构标签
    if (r.marketStructure != null && r.marketStructure!.isNotEmpty) {
      tags.add(SignalTag(text: r.marketStructure!, color: _kAccent));
    }
    // Phase 2: 概念标签
    if (r.conceptSummary != null && r.conceptSummary!.isNotEmpty) {
      tags.add(SignalTag(text: r.conceptSummary!, color: _kTextSecondary));
    }
    // Phase 3: 20日收益标签
    if (r.day20Return != null) {
      final isPositive = r.day20Return! >= 0;
      final returnText = '20日${isPositive ? "+" : ""}${r.day20Return!.toStringAsFixed(1)}%';
      tags.add(SignalTag(
        text: returnText,
        color: isPositive ? _kUp : _kDown,
      ));
    }

    return StockCard(
      name: r.name,
      code: r.code,
      price: r.price,
      changePct: r.changePct,
      pe: r.pe > 0 ? r.pe : null,
      pb: r.pb > 0 ? r.pb : null,
      score: r.score,
      recommendation: r.recommendation,
      rank: rank,
      tags: tags.isNotEmpty ? tags : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuoteScreen(code: r.code, name: r.name),
          ),
        );
      },
      trailing: IconButton(
        icon: Icon(
          isInWatchlist ? Icons.star : Icons.star_border,
          color: isInWatchlist ? _kAccent : _kTextSecondary,
          size: 22,
        ),
        onPressed: () => _toggleWatchlist(r),
      ),
    );
  }

  // ─── 主线龙头卡片（来自 SectorPickEngine 结果） ────────────────

  Widget _buildMainLineCard(Map<String, dynamic> p, int rank) {
    final code = p['code'] as String? ?? '';
    final name = p['name'] as String? ?? '';
    final score = (p['score'] as num?)?.toInt() ?? 0;
    final rec = p['recommendation'] as String? ?? '';
    final sector = p['sector'] as String? ?? '';
    final bonus = (p['bonus'] as num?)?.toDouble() ?? 1.0;
    final originalScore = (p['originalScore'] as num?)?.toInt() ?? score;
    final isInWatchlist = _watchlistCodes.contains(code);

    final tags = <Widget>[
      SignalTag(text: sector, color: _kMainLineColor),
      if (bonus > 1.0)
        SignalTag(text: '主线+${((bonus - 1) * 100).toStringAsFixed(0)}%', color: _kMainLineColor),
      if (originalScore != score)
        SignalTag(text: '原$originalScore分', color: _kTextSecondary),
    ];

    // 主线龙头实时行情（从 _mainLineQuotes 缓存读取，异步补充）
    // key 统一用带前缀的 code，与 _fetchMainLineQuotes 的 map key 一致
    final quote = _mainLineQuotes[_apiClient.addMarketPrefix(code)];
    return StockCard(
      name: name,
      code: code,
      price: quote?.price ?? 0,
      changePct: quote?.changePct ?? 0,
      score: score,
      recommendation: rec,
      rank: rank,
      tags: tags,
      onTap: () => _navigateToQuote(code, name),
      trailing: IconButton(
        icon: Icon(
          isInWatchlist ? Icons.star : Icons.star_border,
          color: isInWatchlist ? _kAccent : _kTextSecondary,
          size: 22,
        ),
        onPressed: () => _toggleWatchlistByCode(code, name),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 通用空状态
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEmptyState({
    required IconData icon,
    required String text,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _kTextSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: _kTextSecondary, fontSize: 14)),
          if (actionText != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(actionText),
            ),
          ],
        ],
      ),
    );
  }
}
