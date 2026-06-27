import 'dart:async';

import 'package:flutter/material.dart';

import '../analysis/explore_engine.dart';
import '../analysis/sector_pick_engine.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
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

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

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

  StreamSubscription<ExploreProgress>? _exploreSub;

  // ─── 生命周期 ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadExploreFromDb();
    _loadWatchlistCodes();
    _loadSectorPicks();

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
  }

  @override
  void dispose() {
    _exploreSub?.cancel();
    _sectorPickSub?.cancel();
    _apiClient.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// 切回发现Tab时刷新自选状态
  void onTabVisible() {
    _loadWatchlistCodes();
    _loadSectorPicks();
  }

  // ─── 数据加载 ──────────────────────────────────────────────────

  Future<void> _loadExploreFromDb() async {
    try {
      final results = await _dbService.getExploreResults();
      if (mounted) {
        setState(() {
          _exploreResults = results;
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
        setState(() => _sectorPickResults = results);
      }
    } catch (e) {
      debugPrint('_loadSectorPicks failed: $e');
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
  List<ExploreResult> get _limitUpList {
    final list = _exploreResults.where((r) => r.isLimitUpApprox).toList();
    list.sort((a, b) => b.changePct.compareTo(a.changePct));
    return list;
  }

  // ─── Tab 2: 主线龙头（板块精选 + 主线标记） ───────────────────
  /// 主线板块个股优先；若无主线命中，回退展示全部板块精选（避免Tab常空）
  List<Map<String, dynamic>> get _mainLinePicks {
    final all = _sectorPickResults;
    // mainLine 经 SQLite 往返后为 int(0/1)，从引擎直接获取时为 bool
    var picks = all.where((p) => p['mainLine'] == 1 || p['mainLine'] == true).toList();
    // 无主线命中时回退到全部精选
    // 注意：db.query() 返回的 QueryResultSet 是只读的（operator []= 抛 read-only），
    // 不能直接赋值后 sort，必须创建可变副本
    if (picks.isEmpty && all.isNotEmpty) {
      picks = List<Map<String, dynamic>>.from(all);
    }
    picks.sort((a, b) =>
        (b['score'] as num? ?? 0).toInt().compareTo((a['score'] as num? ?? 0).toInt()));
    return picks;
  }

  /// 是否有主线板块命中（用于UI提示区分"无主线"与"回退展示"）
  bool get _hasMainLineHit => _sectorPickResults
      .any((p) => p['mainLine'] == 1 || p['mainLine'] == true);

  // ─── Tab 3: 分时低吸（买入推荐 + 涨幅温和 + 评分高） ─────────
  /// 低吸筛选：买入推荐 且 涨幅在 [-3%, +5%] 区间 且 评分≥6
  List<ExploreResult> get _lowBuyList {
    final list = _exploreResults.where((r) =>
        r.recommendation.contains('买入') &&
        r.changePct >= -3 &&
        r.changePct <= 5 &&
        r.score >= 6).toList();
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  // ─── Tab 4: 全市场（原探索结果，排序+筛选） ──────────────────
  List<ExploreResult> get _processedExploreResults {
    var list = List<ExploreResult>.from(_exploreResults);

    // 过滤
    switch (_exploreFilter) {
      case '买入':
        list = list
            .where((r) =>
                r.recommendation.contains('买入') ||
                r.recommendation.contains('强烈买入'))
            .toList();
        break;
      case '观望':
        list = list
            .where((r) =>
                !r.recommendation.contains('买入') &&
                !r.recommendation.contains('卖出'))
            .toList();
        break;
    }

    // 排序
    switch (_exploreSort) {
      case '评分':
        list.sort((a, b) => b.score.compareTo(a.score));
        break;
      case '涨幅':
        list.sort((a, b) => b.changePct.compareTo(a.changePct));
        break;
      case '名称':
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
    }

    return list;
  }

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

  // ─── 智能探索：一键加自选 ──────────────────────────────────────

  Future<void> _batchAddToWatchlist() async {
    final notInList = _processedExploreResults
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
    final items = notInList
        .map((r) => WatchlistItem(code: r.code, name: r.name))
        .toList();
    await _dbService.batchAddToWatchlist(items);
    await _loadWatchlistCodes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 ${items.length} 只股票到自选'),
          backgroundColor: _kAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    }
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
    final list = _limitUpList;
    return Column(
      children: [
        _buildTabHeader(
          count: list.length,
          hint: list.isEmpty
              ? (_exploreResults.isEmpty ? '暂无探索数据，点击刷新' : '今日暂无涨停标的')
              : '涨停/连板标的，按涨幅排序',
          accentColor: _kLimitUpColor,
          actionText: _exploreLoading ? '探索中...' : '刷新',
          onAction: _exploreLoading ? null : () => _exploreEngine.explore(),
        ),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.local_fire_department_outlined,
                  text: _exploreResults.isEmpty ? '暂无探索数据，请先刷新' : '今日暂无涨停标的',
                  actionText: _exploreResults.isEmpty ? '开始探索' : null,
                  onAction: _exploreResults.isEmpty ? () => _exploreEngine.explore() : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _buildExploreCard(list[i], i + 1,
                      accentTag: '涨停'),
                ),
        ),
      ],
    );
  }

  // ─── Tab 2: 主线龙头 ──────────────────────────────────────────

  Widget _buildMainLineTab() {
    final list = _mainLinePicks;
    String hint;
    if (_isPickingSectors) {
      hint = '板块精选分析中...';
    } else if (list.isEmpty) {
      hint = _sectorPickResults.isEmpty ? '暂无板块精选数据，点击刷新' : '当前无主线板块命中';
    } else if (_hasMainLineHit) {
      hint = '主线板块内精选个股，含轮动加成';
    } else {
      hint = '暂无主线命中，展示全部板块精选';
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
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.military_tech_outlined,
                  text: _sectorPickResults.isEmpty
                      ? '暂无板块精选数据'
                      : '当前无主线板块命中',
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
    final list = _lowBuyList;
    return Column(
      children: [
        _buildTabHeader(
          count: list.length,
          hint: list.isEmpty
              ? (_exploreResults.isEmpty ? '暂无探索数据，点击刷新' : '当前无低吸信号')
              : '买入推荐 · 涨幅[-3%,+5%] · 评分≥6',
          accentColor: _kLowBuyColor,
          actionText: _exploreLoading ? '探索中...' : '刷新',
          onAction: _exploreLoading ? null : () => _exploreEngine.explore(),
        ),
        Expanded(
          child: list.isEmpty
              ? _buildEmptyState(
                  icon: Icons.trending_down_outlined,
                  text: _exploreResults.isEmpty ? '暂无探索数据，请先刷新' : '当前无低吸信号',
                  actionText: _exploreResults.isEmpty ? '开始探索' : null,
                  onAction: _exploreResults.isEmpty ? () => _exploreEngine.explore() : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _buildExploreCard(list[i], i + 1,
                      accentTag: '低吸'),
                ),
        ),
      ],
    );
  }

  // ─── Tab 4: 全市场 ────────────────────────────────────────────

  Widget _buildAllMarketTab() {
    final processed = _processedExploreResults;
    return Column(
      children: [
        _buildExploreHeader(),
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
        if (!_exploreLoading && processed.isNotEmpty) _buildExploreBottomBar(),
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
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
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
          Expanded(
            child: Text(hint, style: const TextStyle(
                color: _kTextSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis),
          ),
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
                    if (v != null) setState(() => _exploreSort = v);
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
                    if (v != null) setState(() => _exploreFilter = v);
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

    // 主线龙头卡片没有现价/涨跌幅（SectorPickEngine 未保存），用评分驱动
    return StockCard(
      name: name,
      code: code,
      price: 0,
      changePct: 0,
      score: score,
      recommendation: rec,
      rank: rank,
      tags: tags,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuoteScreen(code: code, name: name),
          ),
        );
      },
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

  Widget _buildExploreBottomBar() {
    final notInList = _processedExploreResults
        .where((r) => !_watchlistCodes.contains(r.code))
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Text(
            '共 ${_processedExploreResults.length} 只 · $notInList 只未加自选',
            style: const TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('一键加自选'),
            onPressed: notInList > 0 ? _batchAddToWatchlist : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF21262D),
              disabledForegroundColor: _kTextSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
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
