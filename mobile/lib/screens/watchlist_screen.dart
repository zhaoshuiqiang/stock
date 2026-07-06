import 'dart:async';
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../analysis/opportunity_engine.dart';
import '../analysis/ai_layer.dart';
import '../analysis/backtest_engine.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../analysis/sector_pick_engine.dart';
import '../widgets/stock_card.dart';
import '../widgets/alert_dialog.dart';
import 'quote_screen.dart';
import 'alerts_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

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
  StreamSubscription? _sectorSub;
  // 分析结果索引，O(1) 查找
  Map<String, OpportunityResult> _oppMap = {};

  // ─── 预警状态 ──────────────────────────────────────────────────
  Set<String> _alertCodes = {}; // 已有预警的股票代码

  // ─── 持仓状态 (v2.33) ────────────────────────────────────────
  Map<String, Position> _positionMap = {}; // code → Position

  // ─── AI 持仓分析状态 ──────────────────────────────────────────
  bool _isPortfolioAnalyzing = false;
  AIChatResult? _portfolioAnalysisResult;
  DateTime? _lastPortfolioAnalysisTime;

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
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadWatchlist();
    _startRefreshTimer();
    _loadOppFromDb();
    _loadAlerts();
    _loadPositions();

    // 订阅自选分析进度
    _oppSub = _oppEngine.progressStream.listen(_onOppProgress);
    if (_oppEngine.latestProgress != null) {
      // 延迟到首帧后再恢复进度，避免在 initState 中调用 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onOppProgress(_oppEngine.latestProgress!);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.dispose();
    _oppSub?.cancel();
    _sectorSub?.cancel();
    _apiClient.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      _loadWatchlist();
      _loadPositions();
    }
  }

  // ─── 自选列表：数据加载 ────────────────────────────────────────

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _refreshQuotes();
    });
  }

  Future<void> _refreshQuotes() async {
    // 合并自选和持仓的股票代码，一起获取行情
    final codeSet = <String>{};
    for (final item in _watchlist) {
      codeSet.add(_apiClient.addMarketPrefix(item.code));
    }
    for (final pos in _positionMap.values) {
      codeSet.add(_apiClient.addMarketPrefix(pos.code));
    }
    if (codeSet.isEmpty) return;
    try {
      final quotes = await _apiClient.getBatchRealtimeQuotes(codeSet.toList());
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
    if (quote.changePct < 0) return '中性';
    return '中性';
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
    } else if (_sortBy == 'volume_ratio') {
      items.sort((a, b) {
        final vrA = (a['quote'] as QuoteData).volumeRatio;
        final vrB = (b['quote'] as QuoteData).volumeRatio;
        return _sortAscending
            ? vrA.compareTo(vrB)
            : vrB.compareTo(vrA);
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

  Future<void> _loadAlerts() async {
    try {
      final alerts = await _dbService.getAlerts();
      if (mounted) {
        setState(() {
          _alertCodes = alerts.map((a) {
            // 标准化：去除可能的sh/sz前缀，统一为原始代码
            var code = a.code;
            if (code.startsWith('sh') || code.startsWith('sz')) {
              code = code.substring(2);
            }
            return code;
          }).toSet();
        });
      }
    } catch (_) {}
  }

  // ─── 持仓加载 (v2.33) ─────────────────────────────────────────

  Future<void> _loadPositions() async {
    try {
      final map = await _dbService.getPositionMap();
      if (mounted) {
        setState(() => _positionMap = map);
        // 持仓变化后刷新行情，确保持仓股票有最新价格
        _refreshQuotes();
      }
    } catch (_) {}
  }

  // ─── 精选板块选股 ──────────────────────────────────────────────

  Future<void> _runSectorPick() async {
    try {
      final sectors = await _apiClient.getHotSectors();
      if (sectors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取板块数据'), duration: Duration(seconds: 1)),
        );
        return;
      }
      final engine = SectorPickEngine.instance;
      _sectorSub?.cancel();
      _sectorSub = engine.progressStream.listen((p) {
        if (!mounted) return;
        if (p.status == SectorPickStatus.complete && p.picks != null && p.picks!.isNotEmpty) {
          _showPickResults(p.picks!);
          _sectorSub?.cancel();
        }
      });
      engine.pick(sectors);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在分析热门板块...'), duration: Duration(seconds: 1)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分析失败，请稍后重试'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _showPickResults(List<Map<String, dynamic>> picks) {
    if (!mounted || picks.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('精选标的', style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${picks.length}只', style: const TextStyle(color: _textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: picks.length,
                itemBuilder: (ctx, i) {
                  final p = picks[i];
                  final name = p['name'] ?? '';
                  final code = p['code'] ?? '';
                  final score = p['score'] is num ? (p['score'] as num).toInt() : 0;
                  final rec = p['recommendation'] ?? '';
                  return ListTile(
                    dense: true,
                    title: Text('$name($code)', style: const TextStyle(color: _textPrimary, fontSize: 14)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$score分 ', style: TextStyle(color: rec.contains('强烈') ? _accentColor : _textSecondary)),
                        Text(rec, style: const TextStyle(color: _textSecondary, fontSize: 12)),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _searchAndAddStockByName(name, code);
                    },
                  );
                },
              ),
            ),
            // 底部一键加自选
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('一键加自选', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      final items = picks.map((p) => Map<String, dynamic>.from(p)).toList();
                      final existing = await _dbService.getWatchlist();
                      final existingCodes = existing.map((e) => e.code).toSet();
                      final newItems = items
                          .where((p) => !existingCodes.contains(p['code']))
                          .map((p) => Map<String, dynamic>.from(p))
                          .toList();
                      if (newItems.isEmpty) {
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('所有精选标的已在自选中'), duration: Duration(seconds: 1)),
                          );
                        }
                        return;
                      }
                      final watchlistItems = newItems.map((p) => WatchlistItem(
                        code: p['code'] as String,
                        name: p['name'] as String,
                      )).toList();
                      await _dbService.batchAddToWatchlist(watchlistItems);
                      await _loadWatchlist();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已添加${newItems.length}只到自选'
                                '${items.length - newItems.length > 0 ? "，${items.length - newItems.length}只已在自选中" : ""}'),
                            backgroundColor: _accentColor,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchAndAddStockByName(String name, String code) async {
    final exists = _watchlist.any((w) => w.code == code);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 已在自选中'), duration: const Duration(seconds: 1)),
      );
      return;
    }
    await _dbService.addToWatchlist(code, name);
    await _loadWatchlist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name 已加入自选'), backgroundColor: _accentColor, duration: const Duration(seconds: 1)),
    );
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
            Text('1-10分 7维加权 大盘择时调整',
                style: TextStyle(color: _textSecondary, fontSize: 12)),
            SizedBox(height: 10),
            _ScoringRow(label: '8-10', desc: '强烈买入，多指标共振+资金流入'),
            SizedBox(height: 6),
            _ScoringRow(label: '7', desc: '买入，多数指标偏多'),
            SizedBox(height: 6),
            _ScoringRow(label: '6', desc: '谨慎买入，偏多但有分歧'),
            SizedBox(height: 6),
            _ScoringRow(label: '5', desc: '偏多观望，多空均衡'),
            SizedBox(height: 6),
            _ScoringRow(label: '4', desc: '偏空观望，空方略强'),
            SizedBox(height: 6),
            _ScoringRow(label: '3', desc: '谨慎卖出，偏空信号多'),
            SizedBox(height: 6),
            _ScoringRow(label: '2', desc: '卖出，空方主导'),
            SizedBox(height: 6),
            _ScoringRow(label: '1', desc: '强烈卖出，多指标共振偏空'),
            SizedBox(height: 12),
            Text('技术22% 资金13% 实时12% 共振12% 情绪8% 基本面23% 结构10%',
                style: TextStyle(color: _textSecondary, fontSize: 11)),
            Text('ST股票评分封顶5分，仅显示偏多观望',
                style: TextStyle(color: _textSecondary, fontSize: 11)),
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
          // TabBar
          Container(
            color: _cardColor,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              tabAlignment: TabAlignment.fill,
              indicatorColor: _accentColor,
              labelColor: _accentColor,
              unselectedLabelColor: _textSecondary,
              tabs: const [
                Tab(text: '自选'),
                Tab(text: '持仓'),
              ],
            ),
          ),
          // TabBarView
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWatchlistTab(),
                _buildPositionTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 自选Tab ───────────────────────────────────────────────────

  Widget _buildWatchlistTab() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildControlBar(),
        if (_oppLoading) _buildOppProgress(),
        Expanded(child: _buildList()),
        if (_isEditMode) _buildEditBottomBar(),
      ],
    );
  }

  // ─── 持仓Tab ───────────────────────────────────────────────────

  Widget _buildPositionTab() {
    return Column(
      children: [
        _buildPositionHeader(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildPositionList(),
                if (_portfolioAnalysisResult != null)
                  _buildPortfolioAnalysisResult(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPositionHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '持仓概览',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: _isPortfolioAnalyzing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                            ),
                          )
                        : const Icon(Icons.auto_awesome, color: _accentColor, size: 20),
                    onPressed: _isPortfolioAnalyzing ? null : _analyzePortfolio,
                    tooltip: 'AI持仓分析',
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, color: _accentColor, size: 20),
                    onPressed: _showBacktestDialog,
                    tooltip: '回测',
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file, color: _accentColor, size: 20),
                    onPressed: _importPositionsFromExcel,
                    tooltip: '导入Excel',
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: _accentColor, size: 20),
                    onPressed: () => _showAddPositionDialog(),
                    tooltip: '手动添加',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPositionStats(),
        ],
      ),
    );
  }

  Widget _buildPositionStats() {
    final positions = _positionMap.values.toList();
    if (positions.isEmpty) {
      return const Text(
        '暂无持仓数据',
        style: TextStyle(color: _textSecondary, fontSize: 14),
      );
    }

    double totalCost = 0;
    double totalMarketValue = 0;

    for (final pos in positions) {
      final quote = _quotes.firstWhere(
        (q) => q.code.endsWith(pos.code),
        orElse: () => QuoteData.empty(),
      );
      final currentPrice = quote.price > 0 ? quote.price : pos.avgPrice;
      totalCost += pos.quantity * pos.avgPrice;
      totalMarketValue += pos.quantity * currentPrice;
    }

    final totalPnl = totalMarketValue - totalCost;
    final totalPnlPct = totalCost > 0 ? (totalPnl / totalCost * 100) : 0;
    final pnlColor = totalPnl >= 0 ? _upColor : _downColor;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('总成本', totalCost.toStringAsFixed(2)),
            _buildStatItem('总市值', totalMarketValue.toStringAsFixed(2)),
            _buildStatItem(
              '总盈亏',
              '${totalPnl >= 0 ? '+' : ''}${totalPnl.toStringAsFixed(2)}',
              color: pnlColor,
            ),
            _buildStatItem(
              '收益率',
              '${totalPnlPct >= 0 ? '+' : ''}${totalPnlPct.toStringAsFixed(2)}%',
              color: pnlColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: _textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? _textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPositionList() {
    final positions = _positionMap.values.toList();
    if (positions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: _textSecondary),
            const SizedBox(height: 16),
            const Text(
              '暂无持仓',
              style: TextStyle(color: _textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击右上角 + 手动添加，或导入Excel文件',
              style: TextStyle(color: _textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPositions,
      color: _accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: positions.length,
        itemBuilder: (context, index) {
          final pos = positions[index];
          final quote = _quotes.firstWhere(
            (q) => q.code.endsWith(pos.code),
            orElse: () => QuoteData.empty(),
          );
          final opp = _oppMap[pos.code];
          return _buildPositionCard(pos, quote, opp);
        },
      ),
    );
  }

  Widget _buildPositionCard(Position pos, QuoteData quote, OpportunityResult? opp) {
    final currentPrice = quote.price > 0 ? quote.price : pos.avgPrice;
    final pnl = (currentPrice - pos.avgPrice) * pos.quantity;
    final pnlPct = pos.avgPrice > 0
        ? ((currentPrice - pos.avgPrice) / pos.avgPrice * 100)
        : 0.0;
    final pnlColor = pnl >= 0 ? _upColor : _downColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => QuoteScreen(
                code: pos.code,
                name: pos.name,
              ),
            ),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pos.name,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pos.code,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '¥${currentPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: quote.changePct >= 0 ? _upColor : _downColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: quote.changePct >= 0 ? _upColor : _downColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: _borderColor, height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildPositionDetail('持仓数量', '${pos.quantity}股'),
                  _buildPositionDetail('成本价', '¥${pos.avgPrice.toStringAsFixed(3)}'),
                  _buildPositionDetail(
                    '盈亏',
                    '${pnl >= 0 ? '+' : ''}¥${pnl.toStringAsFixed(2)}',
                    color: pnlColor,
                  ),
                  _buildPositionDetail(
                    '收益率',
                    '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                    color: pnlColor,
                  ),
                ],
              ),
              if (opp != null) ...[
                const SizedBox(height: 12),
                const Divider(color: _borderColor, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getRecommendationColor(opp.recommendation).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        opp.recommendation,
                        style: TextStyle(
                          color: _getRecommendationColor(opp.recommendation),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '评分 ${opp.score}',
                        style: const TextStyle(
                          color: _accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (opp.confluenceScore > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '共振${opp.confluenceScore}',
                          style: const TextStyle(
                            color: _accentColor,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (opp.topSignals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: opp.topSignals.take(3).map((s) {
                      final isBuy = s.startsWith('▲');
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isBuy ? _upColor : _downColor).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            color: isBuy ? _upColor : _downColor,
                            fontSize: 10,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getRecommendationColor(String recommendation) {
    if (recommendation.contains('强烈买入')) return _upColor;
    if (recommendation.contains('买入')) return const Color(0xFFFF8C00);
    if (recommendation.contains('卖出')) return _downColor;
    if (recommendation.contains('强烈卖出')) return const Color(0xFF8B0000);
    return _textSecondary;
  }

  Widget _buildPositionDetail(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color ?? _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 持仓导入和添加 ─────────────────────────────────────────────

  Future<void> _importPositionsFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final positions = <Position>[];
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel文件解析失败')),
          );
        }
        return;
      }

      final rows = sheet.rows;
      if (rows == null || rows.length < 8) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel文件格式不正确或数据为空')),
          );
        }
        return;
      }

      // 跳过前6行元信息，第7行是表头，第8行开始是数据
      for (var rowIndex = 7; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        if (row.length < 5) continue;

        final code = row[0]?.value?.toString() ?? '';
        final name = row[1]?.value?.toString() ?? '';
        final quantityStr = row[2]?.value?.toString() ?? '0';
        final avgPriceStr = row[5]?.value?.toString() ?? '0';

        if (code.isEmpty || name.isEmpty) continue;

        final quantity = int.tryParse(quantityStr) ?? 0;
        final avgPrice = double.tryParse(avgPriceStr) ?? 0.0;

        if (quantity > 0 && avgPrice > 0) {
          positions.add(Position(
            code: code,
            name: name,
            quantity: quantity,
            avgPrice: avgPrice,
          ));
        }
      }

      if (positions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到有效的持仓数据')),
          );
        }
        return;
      }

      // 批量添加到数据库
      for (final pos in positions) {
        await _dbService.addPosition(pos);
      }

      await _loadPositions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 ${positions.length} 条持仓记录')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _analyzePortfolio() async {
    if (_positionMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加持仓数据')),
      );
      return;
    }

    // 检查缓存（15分钟内不重复分析）
    if (_lastPortfolioAnalysisTime != null &&
        DateTime.now().difference(_lastPortfolioAnalysisTime!) < const Duration(minutes: 15) &&
        _portfolioAnalysisResult != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分析结果缓存中，15分钟内不重复分析')),
      );
      return;
    }

    setState(() => _isPortfolioAnalyzing = true);

    try {
      // 准备持仓数据
      final positions = <Map<String, dynamic>>[];
      double totalCost = 0;
      double totalMarketValue = 0;

      for (final pos in _positionMap.values) {
        final quote = _quotes.firstWhere(
          (q) => q.code.endsWith(pos.code),
          orElse: () => QuoteData.empty(),
        );
        final currentPrice = quote.price > 0 ? quote.price : pos.avgPrice;
        final cost = pos.quantity * pos.avgPrice;
        final marketValue = pos.quantity * currentPrice;
        final pnlPct = cost > 0 ? (marketValue - cost) / cost * 100 : 0.0;

        totalCost += cost;
        totalMarketValue += marketValue;

        positions.add({
          'code': pos.code,
          'name': pos.name,
          'quantity': pos.quantity,
          'avgPrice': pos.avgPrice,
          'currentPrice': currentPrice,
          'pnlPct': pnlPct,
        });
      }

      final totalPnlPct = totalCost > 0
          ? (totalMarketValue - totalCost) / totalCost * 100
          : 0.0;

      // 调用 AI 分析
      final aiLayer = AILayerProvider.instance;
      final result = await aiLayer.analyzePortfolio(
        positions: positions,
        totalCost: totalCost,
        totalMarketValue: totalMarketValue,
        totalPnlPct: totalPnlPct,
      );

      setState(() {
        _portfolioAnalysisResult = result;
        _lastPortfolioAnalysisTime = DateTime.now();
        _isPortfolioAnalyzing = false;
      });

      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失败: ${result.error}')),
        );
      }
    } catch (e) {
      setState(() => _isPortfolioAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分析失败: $e')),
      );
    }
  }

  Widget _buildPortfolioAnalysisResult() {
    if (_portfolioAnalysisResult == null) return const SizedBox.shrink();

    final result = _portfolioAnalysisResult!;
    final isError = result.error != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isError ? Colors.red.withOpacity(0.3) : _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.auto_awesome,
                color: isError ? Colors.red : _accentColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI持仓分析',
                style: TextStyle(
                  color: isError ? Colors.red : _accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (!isError && result.answer.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    // TODO: 实现复制功能
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isError)
            Text(
              result.error!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            )
          else
            Text(
              result.answer,
              style: const TextStyle(color: _textPrimary, fontSize: 14, height: 1.6),
            ),
        ],
      ),
    );
  }

  Future<void> _showBacktestDialog() async {
    final archives = await _dbService.getArchives();
    if (archives.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无历史留档数据，无法回测')),
        );
      }
      return;
    }

    // 按股票代码分组，取每只股票最早的留档记录
    final stockArchives = <String, ArchiveRecord>{};
    for (final archive in archives) {
      if (!stockArchives.containsKey(archive.code) ||
          archive.archivedAt.isBefore(stockArchives[archive.code]!.archivedAt)) {
        stockArchives[archive.code] = archive;
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          '回测分析',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '选择回测策略',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _buildStrategyButton('MACD金叉', context, stockArchives),
            const SizedBox(height: 8),
            _buildStrategyButton('MA金叉', context, stockArchives),
            const SizedBox(height: 8),
            _buildStrategyButton('KDJ超卖', context, stockArchives),
            const SizedBox(height: 8),
            _buildStrategyButton('RSI超卖', context, stockArchives),
            const SizedBox(height: 8),
            _buildStrategyButton('布林支撑', context, stockArchives),
            const SizedBox(height: 8),
            _buildStrategyButton('均线多头', context, stockArchives),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyButton(
    String strategy,
    BuildContext context,
    Map<String, ArchiveRecord> stockArchives,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () async {
          Navigator.pop(context);
          await _runBacktest(strategy, stockArchives);
        },
        child: Text(
          strategy,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Future<void> _runBacktest(
    String strategy,
    Map<String, ArchiveRecord> stockArchives,
  ) async {
    if (!mounted) return;

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '正在回测...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );

    try {
      final results = <String, BacktestResult>{};
      final klineData = <String, List<HistoryKline>>{};

      // 获取每只股票的历史K线数据
      for (final entry in stockArchives.entries) {
        final code = entry.key;
        final archive = entry.value;

        // 计算从留档日期到今天的天数
        final days = DateTime.now().difference(archive.archivedAt).inDays;
        if (days < 30) continue; // 至少需要30天数据

        final prefixedCode = _apiClient.addMarketPrefix(code);
        final klines = await _apiClient.getStockHistory(
          prefixedCode,
          days: days.clamp(30, 365),
        );

        if (klines.length >= 60) {
          klineData[code] = klines;
        }
      }

      if (klineData.isEmpty) {
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无足够的历史数据进行回测')),
          );
        }
        return;
      }

      // 对每只股票运行回测
      for (final entry in klineData.entries) {
        final code = entry.key;
        final klines = entry.value;

        BacktestResult? result;
        switch (strategy) {
          case 'MACD金叉':
            result = BacktestEngine.backtestMACDCross(klines);
            break;
          case 'MA金叉':
            result = BacktestEngine.backtestMACross(klines);
            break;
          case 'KDJ超卖':
            result = BacktestEngine.backtestKDJOversoldCross(klines);
            break;
          case 'RSI超卖':
            result = BacktestEngine.backtestRSIOversoldRecovery(klines);
            break;
          case '布林支撑':
            result = BacktestEngine.backtestBollSupport(klines);
            break;
          case '均线多头':
            result = BacktestEngine.backtestMAMultiHead(klines);
            break;
        }

        if (result != null) {
          results[code] = result;
        }
      }

      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        _showBacktestResults(strategy, results, stockArchives);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回测失败: $e')),
        );
      }
    }
  }

  void _showBacktestResults(
    String strategy,
    Map<String, BacktestResult> results,
    Map<String, ArchiveRecord> stockArchives,
  ) {
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无回测结果')),
      );
      return;
    }

    // 汇总统计
    int totalTrades = 0;
    int totalWins = 0;
    double totalReturn = 0;
    double maxDrawdown = 0;

    for (final result in results.values) {
      totalTrades += result.totalSignals;
      totalWins += result.winningTrades;
      totalReturn += result.totalReturn;
      if (result.maxDrawdown > maxDrawdown) {
        maxDrawdown = result.maxDrawdown;
      }
    }

    final winRate = totalTrades > 0 ? (totalWins / totalTrades * 100) : 0.0;
    final avgReturn = results.isNotEmpty ? (totalReturn / results.length) : 0.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$strategy 回测结果',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildBacktestStatRow('回测股票数', '${results.length}只'),
            _buildBacktestStatRow('总交易次数', '$totalTrades次'),
            _buildBacktestStatRow(
              '胜率',
              '${winRate.toStringAsFixed(1)}%',
              valueColor: winRate >= 50 ? _upColor : _downColor,
            ),
            _buildBacktestStatRow(
              '平均收益',
              '${avgReturn >= 0 ? '+' : ''}${avgReturn.toStringAsFixed(2)}%',
              valueColor: avgReturn >= 0 ? _upColor : _downColor,
            ),
            _buildBacktestStatRow(
              '最大回撤',
              '${maxDrawdown.toStringAsFixed(2)}%',
              valueColor: _downColor,
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            const Text(
              '个股详情',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final entry = results.entries.elementAt(index);
                  final code = entry.key;
                  final result = entry.value;
                  final archive = stockArchives[code];
                  final name = archive?.name ?? code;

                  return Card(
                    color: const Color(0xFF2A2A2A),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(
                        name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '交易${result.totalSignals}次 | 胜率${(result.winRate * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      trailing: Text(
                        '${result.totalReturn >= 0 ? '+' : ''}${result.totalReturn.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: result.totalReturn >= 0 ? _upColor : _downColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBacktestStatRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddPositionDialog() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    final avgPriceController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          '手动添加持仓',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '股票代码',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: '例如: 600519',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '股票名称',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: '例如: 贵州茅台',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '持仓数量',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: '例如: 100',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: avgPriceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '成本价格',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: '例如: 1800.50',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final code = codeController.text.trim();
              final name = nameController.text.trim();
              final quantityStr = quantityController.text.trim();
              final avgPriceStr = avgPriceController.text.trim();

              if (code.isEmpty || name.isEmpty || quantityStr.isEmpty || avgPriceStr.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请填写完整信息')),
                );
                return;
              }

              final quantity = int.tryParse(quantityStr);
              final avgPrice = double.tryParse(avgPriceStr);

              if (quantity == null || quantity <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('持仓数量必须大于0')),
                );
                return;
              }

              if (avgPrice == null || avgPrice <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('成本价格必须大于0')),
                );
                return;
              }

              final position = Position(
                code: code,
                name: name,
                quantity: quantity,
                avgPrice: avgPrice,
              );

              await _dbService.addPosition(position);
              await _loadPositions();

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('持仓添加成功')),
                );
              }
            },
            child: const Text('添加'),
          ),
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

  // ─── 控制栏：筛选 + 排序 → 操作按钮（两行布局） ────────────

  Widget _buildControlBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：筛选 + 排序
          Row(
            children: [
              const Text('筛选', style: TextStyle(color: _textSecondary, fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(flex: 3, child: _buildFilterDropdown()),
              const SizedBox(width: 8),
              const Text('排序', style: TextStyle(color: _textSecondary, fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(flex: 2, child: _buildSortDropdown()),
            ],
          ),
          const SizedBox(height: 6),
          // 第二行：操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.auto_awesome, _accentColor, '精选', _runSectorPick),
              _buildActionButton(
                _oppLoading ? Icons.hourglass_empty : Icons.refresh,
                _oppLoading ? _textSecondary.withOpacity(0.4) : _accentColor,
                _oppLoading ? '分析中' : '刷新分析',
                _oppLoading ? null : () => _oppEngine.analyze(),
              ),
              _buildActionButton(
                Icons.archive_outlined,
                _oppResults.isEmpty ? _textSecondary.withOpacity(0.4) : _accentColor,
                '归档',
                _oppResults.isEmpty ? null : _oneClickArchive,
              ),
              _buildActionButton(Icons.info_outline, _textSecondary, '评分', _showScoringInfo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _filterType != '全部' ? _accentColor.withOpacity(0.1) : _darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _filterType != '全部' ? _accentColor : _borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filterType,
          isDense: true,
          dropdownColor: _darkSurface,
          style: TextStyle(color: _filterType != '全部' ? _accentColor : _textPrimary, fontSize: 13),
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
          onChanged: (v) { if (v != null) setState(() => _filterType = v); },
        ),
      ),
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _sortBy != 'default' ? _accentColor.withOpacity(0.1) : _darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _sortBy != 'default' ? _accentColor : _borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _sortBy == 'change_pct' ? (_sortAscending ? '涨幅↑' : '涨幅↓')
              : _sortBy == 'score' ? (_sortAscending ? '评分↑' : '评分↓')
              : _sortBy == 'volume_ratio' ? (_sortAscending ? '量比↑' : '量比↓') : '默认',
          isDense: true,
          dropdownColor: _darkSurface,
          style: TextStyle(color: _sortBy != 'default' ? _accentColor : _textPrimary, fontSize: 13),
          items: const [
            DropdownMenuItem(value: '默认', child: Text('默认排序')),
            DropdownMenuItem(value: '涨幅↓', child: Text('涨幅降序')),
            DropdownMenuItem(value: '涨幅↑', child: Text('涨幅升序')),
            DropdownMenuItem(value: '评分↓', child: Text('评分降序')),
            DropdownMenuItem(value: '评分↑', child: Text('评分升序')),
            DropdownMenuItem(value: '量比↓', child: Text('量比降序')),
            DropdownMenuItem(value: '量比↑', child: Text('量比升序')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              if (v == '默认') { _sortBy = 'default'; }
              else if (v == '涨幅↓') { _sortBy = 'change_pct'; _sortAscending = false; }
              else if (v == '涨幅↑') { _sortBy = 'change_pct'; _sortAscending = true; }
              else if (v == '评分↓') { _sortBy = 'score'; _sortAscending = false; }
              else if (v == '评分↑') { _sortBy = 'score'; _sortAscending = true; }
              else if (v == '量比↓') { _sortBy = 'volume_ratio'; _sortAscending = false; }
              else { _sortBy = 'volume_ratio'; _sortAscending = true; }
            });
          },
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.1) : _darkSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: onTap != null ? color.withOpacity(0.3) : _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap != null ? color : _textSecondary.withOpacity(0.4), size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: onTap != null ? color : _textSecondary.withOpacity(0.4), fontSize: 12)),
          ],
        ),
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

    final pinnedCount = items.where((d) => (d['item'] as WatchlistItem).isPinned).length;
    final hasDivider = pinnedCount > 0 && pinnedCount < items.length;
    final totalCount = items.length + (hasDivider ? 1 : 0);

    return RefreshIndicator(
      color: _accentColor,
      backgroundColor: _cardColor,
      onRefresh: _loadWatchlist,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          // 置顶/普通分隔线
          if (hasDivider && index == pinnedCount) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: _borderColor.withOpacity(0.5)),
            );
          }

          final dataIndex = (hasDivider && index > pinnedCount) ? index - 1 : index;
          if (dataIndex >= items.length) return const SizedBox.shrink();

          final data = items[dataIndex];
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
    // 持仓查找 (v2.33)
    final position = _positionMap[item.code];
    final hasPosition = position != null && position.quantity > 0;

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
        onLongPress: () => _showItemMenu(item, codeWithPrefix),
        child: StockCard(
          name: item.isPinned
              ? '📌 ${item.name}'
              : (hasPosition ? '💼 ${item.name}' : item.name),
          code: codeWithPrefix,
          price: quote.price,
          changePct: quote.changePct,
          pe: quote.pe > 0 ? quote.pe : null,
          pb: quote.pb > 0 ? quote.pb : null,
          volumeRatio: quote.volumeRatio > 0 ? quote.volumeRatio : null,
          score: opp?.score,
          recommendation: opp?.recommendation,
          riskLevel: opp?.riskLevel,
          tags: tags.isNotEmpty ? tags : null,
          actions: actions.isNotEmpty ? actions : null,
          positionInfo: hasPosition && quote.price > 0
              ? PositionInfo(
                  quantity: position.quantity,
                  avgPrice: position.avgPrice,
                  currentPrice: quote.price,
                )
              : null,
          onTap: () => _onStockTap(codeWithPrefix, item.name),
          trailing: IconButton(
            icon: Icon(
              _alertCodes.contains(item.code) ? Icons.notifications_active : Icons.add_alert,
              color: _alertCodes.contains(item.code) ? _accentColor : _textSecondary,
              size: 22,
            ),
            onPressed: () => _alertCodes.contains(item.code)
                ? Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsScreen()))
                : _addAlert(item.code, item.name),
            tooltip: _alertCodes.contains(item.code) ? '查看预警' : '添加预警',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ),
    );
  }

  /// 长按弹出菜单
  void _showItemMenu(WatchlistItem item, String codeWithPrefix) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                item.name,
                style: const TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1, color: _borderColor),
            ListTile(
              leading: Icon(item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _accentColor, size: 22),
              title: Text(item.isPinned ? '取消置顶' : '置顶',
                  style: const TextStyle(color: _textPrimary, fontSize: 15)),
              onTap: () async {
                Navigator.pop(context);
                await _dbService.togglePin(item.code, !item.isPinned);
                _loadWatchlist();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_alert_outlined, color: _accentColor, size: 22),
              title: const Text('添加预警',
                  style: TextStyle(color: _textPrimary, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                _addAlert(item.code, item.name);
              },
            ),
            ListTile(
              leading: Icon(
                _positionMap[item.code] != null ? Icons.edit_note : Icons.account_balance_wallet_outlined,
                color: _accentColor, size: 22,
              ),
              title: Text(
                _positionMap[item.code] != null ? '编辑持仓' : '添加持仓',
                style: const TextStyle(color: _textPrimary, fontSize: 15),
              ),
              onTap: () {
                Navigator.pop(context);
                _showPositionDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist, color: _accentColor, size: 22),
              title: const Text('多选编辑',
                  style: TextStyle(color: _textPrimary, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isEditMode = true;
                  _selectedCodes.add(item.code);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
              title: const Text('移除自选',
                  style: TextStyle(color: Colors.red, fontSize: 15)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: this.context,
                  builder: (context) => AlertDialog(
                    backgroundColor: _cardColor,
                    title: const Text('确认删除', style: TextStyle(color: _textPrimary)),
                    content: Text('确定要从自选股移除 ${item.name} 吗？',
                        style: const TextStyle(color: _textSecondary)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消', style: TextStyle(color: _textSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) _removeFromWatchlist(item.code);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── 持仓管理对话框 (v2.33) ───────────────────────────────────

  void _showPositionDialog(WatchlistItem item) {
    final existing = _positionMap[item.code];
    final qtyCtrl = TextEditingController(text: existing?.quantity.toString() ?? '');
    final priceCtrl = TextEditingController(text: existing?.avgPrice.toStringAsFixed(3) ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          existing != null ? '编辑持仓 - ${item.name}' : '添加持仓 - ${item.name}',
          style: const TextStyle(color: _textPrimary, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: _textPrimary),
                decoration: const InputDecoration(
                  labelText: '持仓股数',
                  labelStyle: TextStyle(color: _textSecondary),
                  hintText: '如 1000',
                  hintStyle: TextStyle(color: _textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _borderColor)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: _textPrimary),
                decoration: const InputDecoration(
                  labelText: '持仓均价',
                  labelStyle: TextStyle(color: _textSecondary),
                  hintText: '如 10.50',
                  hintStyle: TextStyle(color: _textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _borderColor)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                style: const TextStyle(color: _textPrimary),
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  labelStyle: TextStyle(color: _textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _borderColor)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor)),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                await _dbService.deletePosition(existing.id!);
                if (mounted) {
                  Navigator.pop(ctx);
                  _loadPositions();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${item.name} 持仓已清空'),
                        backgroundColor: Colors.red, duration: const Duration(seconds: 1)),
                  );
                }
              },
              child: const Text('清空持仓', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final qty = int.tryParse(qtyCtrl.text.trim());
              final price = double.tryParse(priceCtrl.text.trim());
              if (qty == null || qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效的股数'), duration: Duration(seconds: 1)),
                );
                return;
              }
              if (price == null || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效的均价'), duration: Duration(seconds: 1)),
                );
                return;
              }
              if (existing != null) {
                await _dbService.updatePosition(Position(
                  id: existing.id,
                  code: existing.code,
                  name: existing.name,
                  quantity: qty,
                  avgPrice: price,
                  notes: notesCtrl.text.trim(),
                  createdAt: existing.createdAt,
                ));
              } else {
                await _dbService.addPosition(Position(
                  code: item.code,
                  name: item.name,
                  quantity: qty,
                  avgPrice: price,
                  notes: notesCtrl.text.trim(),
                ));
              }
              if (mounted) {
                Navigator.pop(ctx);
                _loadPositions();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.name} 持仓已${existing != null ? '更新' : '添加'}'),
                      backgroundColor: _accentColor, duration: const Duration(seconds: 1)),
                );
              }
            },
            child: const Text('保存', style: TextStyle(color: _accentColor)),
          ),
        ],
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
                  // 全选范围限定为当前筛选后的列表
                  final filteredCodes = _getFilteredAndSortedItems()
                      .map((d) => (d['item'] as WatchlistItem).code)
                      .toSet();
                  final allFilteredSelected = filteredCodes.isNotEmpty &&
                      filteredCodes.every((c) => _selectedCodes.contains(c));
                  if (allFilteredSelected) {
                    _selectedCodes.removeAll(filteredCodes);
                  } else {
                    _selectedCodes.addAll(filteredCodes);
                  }
                });
              },
              child: Text(
                () {
                  final filteredCodes = _getFilteredAndSortedItems()
                      .map((d) => (d['item'] as WatchlistItem).code)
                      .toSet();
                  final allFilteredSelected = filteredCodes.isNotEmpty &&
                      filteredCodes.every((c) => _selectedCodes.contains(c));
                  return allFilteredSelected ? '取消全选' : '全选';
                }(),
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
      builder: (_) => AlertCreateDialog(initialCode: code, initialName: name),
    ).then((result) {
      if (result != null) {
        _dbService.addAlert(result as AlertRule).then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('预警已添加')),
            );
            _loadAlerts();
          }
        });
      }
    });
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
