import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../analysis/opportunity_engine.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/stock_card.dart';
import 'quote_screen.dart';
import 'alerts_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen>
    with WidgetsBindingObserver {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();

  // ─── 自选列表状态 ──────────────────────────────────────────────
  List<WatchlistItem> _watchlist = [];
  List<QuoteData> _quotes = [];
  bool _isLoading = true;
  String _filterType = '全部'; // 全部/强烈买入/买入/谨慎买入/偏多观望/偏空观望/谨慎卖出/卖出/强烈卖出
  String _sortBy = 'default'; // 'default', 'change_pct', 'score'
  bool _sortAscending = false;
  bool _isEditMode = false;
  Set<String> _selectedCodes = {};
  Timer? _refreshTimer;

  // ─── 自选分析状态 ──────────────────────────────────────────────
  final OpportunityEngine _oppEngine = OpportunityEngine.instance;
  List<OpportunityResult> _oppResults = [];
  bool _oppLoading = false;
  StreamSubscription<OpportunityProgress>? _oppSub;
  // 分析结果索引，O(1) 查找
  Map<String, OpportunityResult> _oppMap = {};

  // ─── 颜色常量 ──────────────────────────────────────────────────
  static const Color _bgColor = Color(0xFF0D1117);
  static const Color _cardColor = Color(0xFF161B22);
  static const Color _accentColor = Color(0xFF58A6FF);
  static const Color _upColor = Color(0xFFE74C3C);
  static const Color _downColor = Color(0xFF2ECC71);
  static const Color _textPrimary = Color(0xFFF0F6FC);
  static const Color _textSecondary = Color(0xFF8B949E);
  static const Color _borderColor = Color(0xFF30363D);
  static const Color _darkSurface = Color(0xFF21262D);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWatchlist();
    _startRefreshTimer();
    _loadOppFromDb();

    // 订阅自选分析进度
    _oppSub = _oppEngine.progressStream.listen(_onOppProgress);
    if (_oppEngine.latestProgress != null) {
      _onOppProgress(_oppEngine.latestProgress!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.dispose();
    _oppSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      _loadWatchlist();
    }
  }

  // ─── 自选列表：数据加载 ────────────────────────────────────────

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshQuotes();
    });
  }

  Future<void> _refreshQuotes() async {
    if (_watchlist.isEmpty) return;
    try {
      final codes =
          _watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
      final quotes = await _apiClient.getBatchRealtimeQuotes(codes);
      if (mounted) {
        setState(() {
          _quotes = quotes;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadWatchlist() async {
    try {
      final watchlist = await _dbService.getWatchlist();
      setState(() {
        _watchlist = watchlist;
        _isLoading = false;
      });
      if (watchlist.isNotEmpty) {
        _refreshQuotes();
      }
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onStockTap(String code, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuoteScreen(code: code, name: name),
      ),
    );
  }

  void _removeFromWatchlist(String code) async {
    await _dbService.removeFromWatchlist(code);
    _loadWatchlist();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已从自选股移除')),
    );
  }

  // ─── 合并数据：自选列表 + 自选分析 ─────────────────────────────

  /// 重建分析结果索引
  void _rebuildOppMap() {
    _oppMap = {for (final r in _oppResults) r.code: r};
  }

  /// 判断股票的筛选分类（优先使用分析推荐，否则用涨跌幅）
  String _classifyStock(QuoteData quote, OpportunityResult? opp) {
    if (opp != null && opp.recommendation.isNotEmpty) {
      return opp.recommendation;
    }
    // 无分析数据或推荐为空时用涨跌幅
    if (quote.changePct > 0) return '偏多观望';
    if (quote.changePct < 0) return '偏空观望';
    return '偏空观望';
  }

  List<Map<String, dynamic>> _getFilteredAndSortedItems() {
    final items = <Map<String, dynamic>>[];

    for (var i = 0; i < _watchlist.length; i++) {
      final item = _watchlist[i];
      final codeWithPrefix = _apiClient.addMarketPrefix(item.code);
      final quote = _quotes.firstWhere(
        (q) => q.code == codeWithPrefix,
        orElse: () => QuoteData.empty(),
      );
      final opp = _oppMap[item.code];
      final category = _classifyStock(quote, opp);

      // 筛选
      if (_filterType != '全部' && category != _filterType) continue;

      items.add({
        'item': item,
        'quote': quote,
        'codeWithPrefix': codeWithPrefix,
        'opp': opp,
        'category': category,
      });
    }

    // 排序
    if (_sortBy == 'change_pct') {
      items.sort((a, b) {
        final changeA = (a['quote'] as QuoteData).changePct;
        final changeB = (b['quote'] as QuoteData).changePct;
        return _sortAscending
            ? changeA.compareTo(changeB)
            : changeB.compareTo(changeA);
      });
    } else if (_sortBy == 'score') {
      items.sort((a, b) {
        final scoreA = (a['opp'] as OpportunityResult?)?.score ?? 0;
        final scoreB = (b['opp'] as OpportunityResult?)?.score ?? 0;
        return _sortAscending
            ? scoreA.compareTo(scoreB)
            : scoreB.compareTo(scoreA);
      });
    }

    return items;
  }

  // ─── 自选分析：数据加载 ────────────────────────────────────────

  Future<void> _loadOppFromDb() async {
    final maps = await _dbService.getOpportunityResults();
    if (mounted) {
      setState(() {
        _oppResults = maps.map((m) => OpportunityResult.fromMap(m)).toList();
        _rebuildOppMap();
      });
    }
  }

  void _onOppProgress(OpportunityProgress p) {
    if (!mounted) return;
    setState(() {
      switch (p.status) {
        case OpportunityStatus.fetching:
        case OpportunityStatus.analyzing:
        case OpportunityStatus.saving:
          _oppLoading = true;
          break;
        case OpportunityStatus.complete:
          _oppLoading = false;
          if (p.results != null) {
            _oppResults = p.results!;
            _rebuildOppMap();
          }
          break;
        case OpportunityStatus.error:
          _oppLoading = false;
          break;
        case OpportunityStatus.alreadyRunning:
          _oppLoading = true;
          break;
        case OpportunityStatus.idle:
          break;
      }
    });
  }

  // ─── 自选分析：归档 ────────────────────────────────────────────

  Future<void> _archiveOppItem(OpportunityResult r) async {
    final record = ArchiveRecord(
      code: r.code,
      name: r.name,
      price: r.price,
      changePct: r.changePct,
      score: r.score,
      recommendation: r.recommendation,
      riskLevel: r.riskLevel,
      buySignalCount: r.buySignalCount,
      sellSignalCount: r.sellSignalCount,
      activeStrategyCount: r.activeStrategyCount,
      confluenceScore: r.confluenceScore,
      tradeLevelsJson: r.tradeLevels != null ? r.tradeLevels.toString() : null,
      topSignals: r.topSignals.join('  '),
      archivedAt: DateTime.now(),
    );
    await _dbService.addArchive(record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${r.name} 已归档'),
          backgroundColor: _accentColor,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _batchArchiveSelected() async {
    if (_selectedCodes.isEmpty) return;
    final toArchive = _oppResults.where((r) => _selectedCodes.contains(r.code)).toList();
    if (toArchive.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('确认留档', style: TextStyle(color: _textPrimary)),
        content: Text(
          '确定要将 ${toArchive.length} 只股票的分析结果留档吗？',
          style: const TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认', style: TextStyle(color: _accentColor)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final r in toArchive) {
      final record = ArchiveRecord(
        code: r.code,
        name: r.name,
        price: r.price,
        changePct: r.changePct,
        score: r.score,
        recommendation: r.recommendation,
        riskLevel: r.riskLevel,
        buySignalCount: r.buySignalCount,
        sellSignalCount: r.sellSignalCount,
        activeStrategyCount: r.activeStrategyCount,
        confluenceScore: r.confluenceScore,
        tradeLevelsJson: r.tradeLevels != null ? r.tradeLevels.toString() : null,
        topSignals: r.topSignals.join('  '),
        archivedAt: DateTime.now(),
      );
      await _dbService.addArchive(record);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已归档 ${toArchive.length} 只股票'),
          backgroundColor: _accentColor,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ─── 批量移出自选 ──────────────────────────────────────────────

  Future<void> _batchRemoveFromWatchlist() async {
    if (_selectedCodes.isEmpty) return;
    final removedCodes = Set<String>.from(_selectedCodes);
    await _dbService.batchRemoveFromWatchlist(removedCodes.toList());
    setState(() {
      _isEditMode = false;
      _selectedCodes.clear();
      _oppResults = _oppResults.where((r) => !removedCodes.contains(r.code)).toList();
      _rebuildOppMap();
    });
    _loadWatchlist();
    _oppEngine.analyze();
  }

  // ─── 一键归档 ──────────────────────────────────────────────────

  Future<void> _oneClickArchive() async {
    if (_oppResults.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('一键归档', style: TextStyle(color: _textPrimary)),
        content: Text(
          '确定要将全部 ${_oppResults.length} 只股票的分析结果归档吗？',
          style: const TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认', style: TextStyle(color: _accentColor)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final r in _oppResults) {
      final record = ArchiveRecord(
        code: r.code,
        name: r.name,
        price: r.price,
        changePct: r.changePct,
        score: r.score,
        recommendation: r.recommendation,
        riskLevel: r.riskLevel,
        buySignalCount: r.buySignalCount,
        sellSignalCount: r.sellSignalCount,
        activeStrategyCount: r.activeStrategyCount,
        confluenceScore: r.confluenceScore,
        tradeLevelsJson: r.tradeLevels != null ? r.tradeLevels.toString() : null,
        topSignals: r.topSignals.join('  '),
        archivedAt: DateTime.now(),
      );
      await _dbService.addArchive(record);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已归档 ${_oppResults.length} 只股票'),
          backgroundColor: _accentColor,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ─── 评分信息弹窗 ──────────────────────────────────────────────

  void _showScoringInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('评分说明', style: TextStyle(color: _textPrimary)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ScoringRow(label: '9-10', desc: '强烈买入，多指标共振'),
            SizedBox(height: 6),
            _ScoringRow(label: '7-8', desc: '买入，多数指标看多'),
            SizedBox(height: 6),
            _ScoringRow(label: '5-6', desc: '观望，多空分歧较大'),
            SizedBox(height: 6),
            _ScoringRow(label: '3-4', desc: '谨慎，偏空信号较多'),
            SizedBox(height: 6),
            _ScoringRow(label: '1-2', desc: '卖出，空方主导'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: _accentColor)),
          ),
        ],
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: _bgColor,
        child: const Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }
    return Container(
      color: _bgColor,
      child: Column(
        children: [
          _buildSearchBar(),
          _buildControlBar(),
          if (_oppLoading) _buildOppProgress(),
          Expanded(child: _buildList()),
          if (_isEditMode) _buildEditBottomBar(),
        ],
      ),
    );
  }

  // ─── 搜索栏 ────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: _darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: _textPrimary, fontSize: 15),
        decoration: const InputDecoration(
          hintText: '搜索股票名称或代码',
          hintStyle: TextStyle(color: _textSecondary, fontSize: 15),
          prefixIcon: Icon(Icons.search, color: _textSecondary, size: 22),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onSubmitted: _searchAndAddStock,
      ),
    );
  }

  // ─── 控制栏：筛选 + 排序 + 分析操作 ────────────────────────────

  Widget _buildControlBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          // 筛选下拉框
          const Text('筛选', style: TextStyle(color: _textSecondary, fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _filterType != '全部'
                    ? _accentColor.withOpacity(0.1)
                    : _darkSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _filterType != '全部' ? _accentColor : _borderColor,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterType,
                  isDense: true,
                  iconEnabledColor: _filterType != '全部' ? _accentColor : _textSecondary,
                  dropdownColor: _darkSurface,
                  style: TextStyle(
                    color: _filterType != '全部' ? _accentColor : _textPrimary,
                    fontSize: 13,
                  ),
                  items: const [
                    DropdownMenuItem(value: '全部', child: Text('全部')),
                    DropdownMenuItem(value: '强烈买入', child: Text('强烈买入')),
                    DropdownMenuItem(value: '买入', child: Text('买入')),
                    DropdownMenuItem(value: '谨慎买入', child: Text('谨慎买入')),
                    DropdownMenuItem(value: '偏多观望', child: Text('偏多观望')),
                    DropdownMenuItem(value: '偏空观望', child: Text('偏空观望')),
                    DropdownMenuItem(value: '谨慎卖出', child: Text('谨慎卖出')),
                    DropdownMenuItem(value: '卖出', child: Text('卖出')),
                    DropdownMenuItem(value: '强烈卖出', child: Text('强烈卖出')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _filterType = v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 排序下拉框
          const Text('排序', style: TextStyle(color: _textSecondary, fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _sortBy != 'default'
                    ? _accentColor.withOpacity(0.1)
                    : _darkSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _sortBy != 'default' ? _accentColor : _borderColor,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortBy == 'change_pct'
                      ? (_sortAscending ? '涨幅↑' : '涨幅↓')
                      : _sortBy == 'score'
                          ? (_sortAscending ? '评分↑' : '评分↓')
                          : '默认',
                  isDense: true,
                  iconEnabledColor: _sortBy != 'default' ? _accentColor : _textSecondary,
                  dropdownColor: _darkSurface,
                  style: TextStyle(
                    color: _sortBy != 'default' ? _accentColor : _textPrimary,
                    fontSize: 13,
                  ),
                  items: const [
                    DropdownMenuItem(value: '默认', child: Text('默认排序')),
                    DropdownMenuItem(value: '涨幅↓', child: Text('涨幅降序')),
                    DropdownMenuItem(value: '涨幅↑', child: Text('涨幅升序')),
                    DropdownMenuItem(value: '评分↓', child: Text('评分降序')),
                    DropdownMenuItem(value: '评分↑', child: Text('评分升序')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      if (v == '默认') {
                        _sortBy = 'default';
                      } else if (v == '涨幅↓') {
                        _sortBy = 'change_pct';
                        _sortAscending = false;
                      } else if (v == '涨幅↑') {
                        _sortBy = 'change_pct';
                        _sortAscending = true;
                      } else if (v == '评分↓') {
                        _sortBy = 'score';
                        _sortAscending = false;
                      } else if (v == '评分↑') {
                        _sortBy = 'score';
                        _sortAscending = true;
                      }
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 一键归档按钮
          IconButton(
            icon: Icon(
              Icons.archive_outlined,
              color: _oppResults.isEmpty ? _textSecondary.withOpacity(0.4) : _accentColor,
              size: 18,
            ),
            onPressed: _oppResults.isEmpty ? null : _oneClickArchive,
            tooltip: '一键归档',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: _textSecondary, size: 18),
            onPressed: _showScoringInfo,
            tooltip: '评分说明',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: _oppLoading ? _textSecondary.withOpacity(0.4) : _accentColor,
              size: 18,
            ),
            onPressed: _oppLoading ? null : () => _oppEngine.analyze(),
            tooltip: '刷新分析',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ─── 分析进度条 ────────────────────────────────────────────────

  Widget _buildOppProgress() {
    final p = _oppEngine.latestProgress;
    final completed = p?.completedCount ?? 0;
    final total = p?.totalCount ?? 1;
    final progress = total > 0 ? completed / total : 0.0;
    String statusText;
    switch (p?.status) {
      case OpportunityStatus.fetching:
        statusText = '获取自选列表...';
        break;
      case OpportunityStatus.analyzing:
        statusText = '分析中 $completed/$total';
        break;
      case OpportunityStatus.saving:
        statusText = '保存结果...';
        break;
      default:
        statusText = '处理中...';
    }
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          backgroundColor: _darkSurface,
          valueColor: const AlwaysStoppedAnimation<Color>(_accentColor),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            statusText,
            style: const TextStyle(color: _textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ─── 股票列表 ──────────────────────────────────────────────────

  Widget _buildList() {
    final items = _getFilteredAndSortedItems();

    if (_watchlist.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.watch_later_outlined,
                  size: 64, color: _textSecondary.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text(
                '暂无自选股',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '在上方搜索框输入股票名称或代码添加',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '当前筛选无结果',
            style: TextStyle(color: _textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _accentColor,
      backgroundColor: _cardColor,
      onRefresh: _loadWatchlist,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final data = items[index];
          final item = data['item'] as WatchlistItem;
          final quote = data['quote'] as QuoteData;
          final codeWithPrefix = data['codeWithPrefix'] as String;
          final opp = data['opp'] as OpportunityResult?;

          if (_isEditMode) {
            return _buildEditItem(item, quote, codeWithPrefix, opp);
          }

          return _buildMergedCard(item, quote, codeWithPrefix, opp);
        },
      ),
    );
  }

  /// 合并卡片：同时显示行情 + 分析数据
  Widget _buildMergedCard(
      WatchlistItem item, QuoteData quote, String codeWithPrefix, OpportunityResult? opp) {
    // 信号标签
    final tags = <Widget>[];
    if (opp != null) {
      for (final s in opp.topSignals.take(3)) {
        final isBuy = s.startsWith('▲');
        tags.add(SignalTag(
          text: s,
          color: isBuy ? _upColor : _downColor,
        ));
      }
      if (opp.confluenceScore > 0) {
        tags.add(SignalTag(
          text: '共振${opp.confluenceScore}',
          color: _accentColor,
        ));
      }
    }

    // 操作按钮
    final actions = <Widget>[];
    if (opp != null) {
      actions.add(TextButton.icon(
        icon: const Icon(Icons.archive_outlined, size: 16),
        label: const Text('归档', style: TextStyle(fontSize: 12)),
        onPressed: () => _archiveOppItem(opp),
        style: TextButton.styleFrom(
          foregroundColor: _textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }

    return Dismissible(
      key: Key(item.code),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.red, size: 28),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _cardColor,
            title: const Text('确认删除',
                style: TextStyle(color: _textPrimary)),
            content: Text('确定要从自选股移除 ${item.name} 吗？',
                style: const TextStyle(color: _textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消',
                    style: TextStyle(color: _textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _removeFromWatchlist(item.code),
      child: GestureDetector(
        onLongPress: () {
          setState(() {
            _isEditMode = true;
            _selectedCodes.add(item.code);
          });
        },
        child: StockCard(
          name: item.name,
          code: codeWithPrefix,
          price: quote.price,
          changePct: quote.changePct,
          pe: quote.pe > 0 ? quote.pe : null,
          pb: quote.pb > 0 ? quote.pb : null,
          score: opp?.score,
          recommendation: opp?.recommendation,
          riskLevel: opp?.riskLevel,
          tags: tags.isNotEmpty ? tags : null,
          actions: actions.isNotEmpty ? actions : null,
          onTap: () => _onStockTap(codeWithPrefix, item.name),
          trailing: IconButton(
            icon: const Icon(Icons.add_alert,
                color: _accentColor, size: 22),
            onPressed: () => _addAlert(codeWithPrefix, item.name),
            tooltip: '添加预警',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ),
    );
  }

  /// 编辑模式下的卡片
  Widget _buildEditItem(
      WatchlistItem item, QuoteData quote, String codeWithPrefix, OpportunityResult? opp) {
    final isSelected = _selectedCodes.contains(item.code);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCodes.remove(item.code);
          } else {
            _selectedCodes.add(item.code);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _accentColor : _borderColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _accentColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? _accentColor : _textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: _textPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(item.name,
                          style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      if (opp != null && opp.recommendation.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (opp.recommendation.contains('买入')
                                    ? _upColor
                                    : opp.recommendation.contains('卖出')
                                        ? _downColor
                                        : Colors.orange)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            opp.recommendation,
                            style: TextStyle(
                              color: opp.recommendation.contains('买入')
                                  ? _upColor
                                  : opp.recommendation.contains('卖出')
                                      ? _downColor
                                      : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(codeWithPrefix,
                      style: const TextStyle(
                          color: _textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  quote.price > 0
                      ? '¥${quote.price.toStringAsFixed(2)}'
                      : '--',
                  style: TextStyle(
                    color: quote.changePct > 0
                        ? _upColor
                        : quote.changePct < 0
                            ? _downColor
                            : _textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: quote.changePct > 0
                            ? _upColor
                            : quote.changePct < 0
                                ? _downColor
                                : _textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (opp != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${opp.score}分',
                          style: const TextStyle(
                            color: _accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── 编辑底部栏 ────────────────────────────────────────────────

  Widget _buildEditBottomBar() {
    final hasOpp = _selectedCodes.any((code) => _oppMap.containsKey(code));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _darkSurface,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text(
              '已选${_selectedCodes.length}只',
              style: const TextStyle(color: _textSecondary, fontSize: 14),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() {
                  final allCodes = _watchlist.map((w) => w.code).toSet();
                  if (_selectedCodes.length == allCodes.length) {
                    _selectedCodes.clear();
                  } else {
                    _selectedCodes = allCodes;
                  }
                });
              },
              child: Text(
                _selectedCodes.length == _watchlist.length ? '取消全选' : '全选',
                style: TextStyle(
                  color: _selectedCodes.isEmpty
                      ? _textSecondary.withOpacity(0.5)
                      : _accentColor,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (hasOpp)
              GestureDetector(
                onTap: _selectedCodes.isEmpty ? null : _batchArchiveSelected,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedCodes.isEmpty
                        ? _accentColor.withOpacity(0.2)
                        : _accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '归档',
                    style: TextStyle(
                      color: _selectedCodes.isEmpty
                          ? _textSecondary
                          : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _selectedCodes.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: _cardColor,
                          title: const Text('确认删除',
                              style: TextStyle(color: _textPrimary)),
                          content: Text(
                              '确定要删除选中的${_selectedCodes.length}只股票吗？',
                              style:
                                  const TextStyle(color: _textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('取消',
                                  style:
                                      TextStyle(color: _textSecondary)),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _batchRemoveFromWatchlist();
                      }
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedCodes.isEmpty
                      ? Colors.red.withOpacity(0.2)
                      : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '删除(${_selectedCodes.length})',
                  style: TextStyle(
                    color: _selectedCodes.isEmpty
                        ? _textSecondary
                        : _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 预警 & 搜索
  // ═══════════════════════════════════════════════════════════════

  void _addAlert(String code, String name) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController priceController = TextEditingController();
        String conditionType = 'price_above';
        return AlertDialog(
          backgroundColor: _cardColor,
          title: Text('添加预警: $name',
              style: const TextStyle(color: _textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: conditionType,
                items: const [
                  DropdownMenuItem(
                      value: 'price_above', child: Text('价格高于')),
                  DropdownMenuItem(
                      value: 'price_below', child: Text('价格低于')),
                  DropdownMenuItem(
                      value: 'change_above', child: Text('涨幅超过')),
                  DropdownMenuItem(
                      value: 'change_below', child: Text('跌幅超过')),
                ],
                onChanged: (value) => conditionType = value!,
                dropdownColor: _darkSurface,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '预警值',
                  labelStyle: const TextStyle(color: _textSecondary),
                  filled: true,
                  fillColor: _darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                ),
                style: const TextStyle(color: _textPrimary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消',
                  style: TextStyle(color: _textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final threshold = double.tryParse(priceController.text);
                if (threshold != null) {
                  await _dbService.addAlert(AlertRule(
                    code: code,
                    name: name,
                    conditionType: conditionType,
                    thresholdValue: threshold,
                    enabled: true,
                  ));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('预警已添加')),
                  );
                }
              },
              child:
                  const Text('确认', style: TextStyle(color: _accentColor)),
            ),
          ],
        );
      },
    );
  }

  void _searchAndAddStock(String keyword) async {
    if (keyword.isEmpty) return;

    final results = await _apiClient.searchStocks(keyword);
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该股票')),
      );
      return;
    }

    if (results.length == 1) {
      final stock = results.first;
      await _dbService.addToWatchlist(stock.code, stock.name);
      _loadWatchlist();
      _searchController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${stock.name} 到自选股')),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _cardColor,
          title: const Text('选择股票',
              style: TextStyle(color: _textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final stock = results[index];
                return ListTile(
                  title: Text(stock.name,
                      style: const TextStyle(color: _textPrimary)),
                  subtitle: Text(stock.code,
                      style: const TextStyle(color: _textSecondary)),
                  onTap: () async {
                    await _dbService.addToWatchlist(stock.code, stock.name);
                    Navigator.pop(context);
                    _loadWatchlist();
                    _searchController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('已添加 ${stock.name} 到自选股')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消',
                  style: TextStyle(color: _textSecondary)),
            ),
          ],
        ),
      );
    }
  }
}

// ─── 评分说明行组件 ──────────────────────────────────────────────────

class _ScoringRow extends StatelessWidget {
  final String label;
  final String desc;

  const _ScoringRow({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF58A6FF).withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF58A6FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            desc,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
          ),
        ),
      ],
    );
  }
}
