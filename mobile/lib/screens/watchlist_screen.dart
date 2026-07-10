import 'dart:async';
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/websocket_client.dart';
import '../analysis/opportunity_engine.dart';
import '../analysis/ai_layer.dart';
import '../analysis/backtest_engine.dart';
import '../analysis/portfolio_snapshot_service.dart';
import '../core/ai_config.dart';
import '../core/stock_code_utils.dart';
import '../core/trading_session.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../analysis/sector_pick_engine.dart';
import '../widgets/stock_card.dart';
import '../widgets/alert_dialog.dart';
import 'quote_screen.dart';
import 'alerts_screen.dart';
import 'portfolio_chart_screen.dart';

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
  double _totalAssets = 0;
  double _availableCash = 0;

  // ─── AI 持仓分析状态 ──────────────────────────────────────────
  bool _isPortfolioAnalyzing = false;
  AIChatResult? _portfolioAnalysisResult;
  DateTime? _lastPortfolioAnalysisTime;

  // ─── 持仓3秒轮询状态 (v3.1) ──────────────────────────────────
  final QuotePollingClient _pollingClient = QuotePollingClient();
  bool _isPositionPolling = false;
  Timer? _sessionCheckTimer;
  final PortfolioSnapshotService _snapshotService = PortfolioSnapshotService();

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
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    _loadWatchlist();
    _startRefreshTimer();
    _loadOppFromDb();
    _loadAlerts();
    _loadPositions();

    // v3.1: 启动交易时段检查（30秒一次，控制3秒轮询启停 + 收盘快照）
    _startSessionCheck();

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
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _sessionCheckTimer?.cancel();
    _stopPositionPolling();
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
      _stopPositionPolling(); // v3.1: 暂停持仓3秒轮询
    } else if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      _loadWatchlist();
      _loadPositions();
      _maybeStartPositionPolling(); // v3.1: 恢复持仓3秒轮询
      _recordSnapshotIfNeeded(); // v3.1: 收盘后补录快照
    }
  }

  // ─── 持仓3秒轮询 (v3.1) ─────────────────────────────────────────

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _maybeStartPositionPolling();
  }

  void _startSessionCheck() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _maybeStartPositionPolling();
      // 收盘后自动停止轮询并记录快照
      if (!TradingSession.isInTradingSession() && _isPositionPolling) {
        _stopPositionPolling();
      }
      _recordSnapshotIfNeeded();
    });
  }

  /// 启动持仓3秒轮询（仅交易时段 + 持仓Tab可见 + 有持仓）
  void _maybeStartPositionPolling() {
    final shouldPoll = _positionMap.isNotEmpty &&
        _tabController.index == 1 &&
        TradingSession.isInTradingSession();

    if (shouldPoll && !_isPositionPolling) {
      _startPositionPolling();
    } else if (!shouldPoll && _isPositionPolling) {
      _stopPositionPolling();
    }
  }

  void _startPositionPolling() {
    _isPositionPolling = true;
    final codes = _positionMap.values
        .map((p) => _apiClient.addMarketPrefix(p.code))
        .toSet();
    _pollingClient.subscribeAll(codes);
    _pollingClient.setInterval(const Duration(seconds: 3));
    _pollingClient.onQuoteUpdate = _onQuoteUpdate;
    _pollingClient.connect();
  }

  void _stopPositionPolling() {
    if (!_isPositionPolling) return;
    _isPositionPolling = false;
    _pollingClient.disconnect();
    _pollingClient.onQuoteUpdate = null;
  }

  /// 行情更新回调 —— 合并到 _quotes 并刷新UI
  void _onQuoteUpdate(QuoteData quote) {
    if (!mounted) return;

    final idx = _quotes.indexWhere((q) => q.code == quote.code);
    if (idx >= 0) {
      _quotes[idx] = quote;
    } else {
      _quotes.add(quote);
    }

    // 仅持仓Tab可见时才刷新
    if (_tabController.index == 1) {
      setState(() {});
    }
  }

  /// 收盘后自动记录持仓快照
  void _recordSnapshotIfNeeded() {
    if (_positionMap.isEmpty) return;
    if (TradingSession.isInTradingSession()) return;
    _snapshotService.recordIfNeeded(
      positionMap: _positionMap,
      totalAssets: _totalAssets,
      availableCash: _availableCash,
    );
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
    } catch (e) {
      debugPrint('[Watchlist] 刷新行情失败: $e');
    }
  }

  Future<void> _loadWatchlist() async {
    try {
      final watchlist = await _dbService.getWatchlist();
      if (!mounted) return;
      setState(() {
        _watchlist = watchlist;
        _isLoading = false;
      });
      if (watchlist.isNotEmpty) {
        _refreshQuotes();
      }
    } catch (e) {
      debugPrint('[Watchlist] 加载自选失败: $e');
      if (!mounted) return;
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
    final map = <String, OpportunityResult>{};
    for (final r in _oppResults) {
      final normalized = StockCodeUtils.normalizeForArchive(r.code);
      map[r.code] = r;
      map[normalized] = r;
      map[StockCodeUtils.stripMarketPrefix(normalized)] = r;
    }
    _oppMap = map;
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
      final normalizedCode = StockCodeUtils.normalizeForArchive(item.code);
      final quote = _quotes.firstWhere(
        (q) => q.code == codeWithPrefix,
        orElse: () => QuoteData.empty(),
      );
      final opp = _oppMap[item.code] ??
          _oppMap[normalizedCode] ??
          _oppMap[StockCodeUtils.stripMarketPrefix(normalizedCode)];
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
      code: StockCodeUtils.normalizeForArchive(r.code),
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
    final selectedCodes =
        _selectedCodes.map(StockCodeUtils.normalizeForArchive).toSet();
    final seenCodes = <String>{};
    final toArchive = _oppResults.where((r) {
      final normalized = StockCodeUtils.normalizeForArchive(r.code);
      return selectedCodes.contains(normalized) && seenCodes.add(normalized);
    }).toList();
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
        code: StockCodeUtils.normalizeForArchive(r.code),
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
    if (!mounted) return;
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
    final seenCodes = <String>{};
    for (final r in _oppResults) {
      final normalized = StockCodeUtils.normalizeForArchive(r.code);
      if (!seenCodes.add(normalized)) continue;
      final record = ArchiveRecord(
        code: normalized,
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
    } catch (e) {
      debugPrint('[Watchlist] 加载预警失败: $e');
    }
  }

  // ─── 持仓加载 (v2.33) ─────────────────────────────────────────

  Future<void> _loadPositions() async {
    try {
      final map = await _dbService.getPositionMap();
      if (mounted) {
        setState(() => _positionMap = map);
        // 持仓变化后刷新行情，确保持仓股票有最新价格
        _refreshQuotes();
        // v3.1: 持仓加载后尝试启动3秒轮询 + 收盘快照
        _maybeStartPositionPolling();
        _recordSnapshotIfNeeded();
      }
    } catch (e) {
      debugPrint('[Watchlist] 加载持仓失败: $e');
    }
  }

  /// 规范化股票代码：去除 sh/sz/bj 前缀，返回纯数字代码
  String _normalizeCode(String code) {
    return code.replaceFirst(RegExp(r'^(sh|sz|bj)', caseSensitive: false), '');
  }

  /// 按 code 查找持仓，双向兼容 watchlist/positions 中带 sh/sz/bj 前缀的记录
  Position? _findPosition(String code) {
    final exact = _positionMap[code];
    if (exact != null) return exact;
    final normalized = _positionMap[_normalizeCode(code)];
    if (normalized != null) return normalized;
    final target = _normalizeCode(code);
    for (final p in _positionMap.values) {
      if (_normalizeCode(p.code) == target) return p;
    }
    return null;
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
    } catch (e) {
      debugPrint('[Watchlist] 板块选股失败: $e');
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
        _buildPortfolioAnalysisResult(),
        Expanded(child: _buildPositionList()),
      ],
    );
  }

  Widget _buildPositionHeader() {
    // 计算汇总数据
    double totalCost = 0;
    double totalMarketValue = 0;
    double totalPnl = 0;
    double totalTodayPnl = 0;
    double totalYesterdayMarketValue = 0;
    int holdingDays = 0;

    for (final pos in _positionMap.values) {
      final quote = _quotes.firstWhere(
        (q) => q.code.endsWith(pos.code),
        orElse: () => QuoteData.empty(),
      );
      // v3.2: 始终从实时行情计算盈亏，不使用DB中可能过期的存储值
      final currentPrice = quote.price > 0 ? quote.price : (pos.latestPrice > 0 ? pos.latestPrice : pos.avgPrice);
      final cost = pos.quantity * pos.avgPrice;
      final marketValue = pos.quantity * currentPrice;
      final pnl = marketValue - cost;
      final todayPnl = quote.preClose > 0
          ? pos.quantity * (currentPrice - quote.preClose)
          : 0.0;

      totalCost += cost;
      totalMarketValue += marketValue;
      totalPnl += pnl;
      totalTodayPnl += todayPnl;

      // v3.2: 始终用实时行情计算昨日市值（todayPnl 为实时计算值）
      if (quote.preClose > 0) {
        totalYesterdayMarketValue += pos.quantity * quote.preClose;
      } else {
        totalYesterdayMarketValue += (marketValue - todayPnl);
      }

      // 持仓天数（取最早买入日期）
      if (pos.buyDate != null) {
        final days = DateTime.now().difference(pos.buyDate!).inDays;
        if (days > holdingDays) holdingDays = days;
      }
    }

    final totalPnlPct = totalCost > 0 ? totalPnl / totalCost * 100 : 0.0;
    final totalTodayPnlPct = totalYesterdayMarketValue > 0
        ? totalTodayPnl / totalYesterdayMarketValue * 100
        : 0.0;

    return Column(
      children: [
        // 标题栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _cardColor,
            border: Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '持仓',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.show_chart, color: _accentColor, size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PortfolioChartScreen(
                            positionMap: _positionMap,
                          ),
                        ),
                      );
                    },
                    tooltip: '收益率趋势',
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: _textSecondary, size: 20),
                    onPressed: _showAIProviderDialog,
                    tooltip: 'AI模型设置',
                  ),
                  IconButton(
                    icon: _isPortfolioAnalyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accentColor,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, color: _accentColor, size: 20),
                    onPressed: _isPortfolioAnalyzing ? null : _analyzePortfolio,
                    tooltip: 'AI分析持仓',
                  ),
                  IconButton(
                    icon: const Icon(Icons.bar_chart, color: _accentColor, size: 20),
                    onPressed: _showBacktestDialog,
                    tooltip: '回测分析',
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file, color: _accentColor, size: 20),
                    onPressed: _importPositionsFromExcel,
                    tooltip: '导入持仓Excel',
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
        ),
        // 盈亏汇总卡片（v3.1 重设计：累计盈亏 vs 当日盈亏 卡片化）
        if (_positionMap.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            decoration: BoxDecoration(
              color: _cardColor,
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildPnlCard(
                        '累计盈亏', totalPnl, totalPnlPct,
                        icon: Icons.trending_up,
                        subtitle: '自持仓起累计',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPnlCard(
                        '当日盈亏', totalTodayPnl, totalTodayPnlPct,
                        icon: Icons.today,
                        subtitle: '今日浮动收益',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 辅助信息行（合并去重）
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildAuxStat('持仓成本', '¥${totalCost.toStringAsFixed(0)}'),
                      _buildAuxStat('持仓市值', '¥${totalMarketValue.toStringAsFixed(0)}'),
                      if (_totalAssets > 0)
                        _buildAuxStat('总资产', '¥${_totalAssets.toStringAsFixed(0)}'),
                      if (_availableCash > 0)
                        _buildAuxStat('可用资金', '¥${_availableCash.toStringAsFixed(0)}'),
                      if (holdingDays > 0)
                        _buildAuxStat('持仓天数', '$holdingDays天'),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 盈亏主卡片 —— 背景色强化区分累计 vs 当日
  Widget _buildPnlCard(String label, double pnl, double pnlPct,
      {required IconData icon, required String subtitle}) {
    final color = pnl >= 0 ? _upColor : _downColor;
    final bgColor = pnl >= 0
        ? const Color(0xFF2A1010)
        : const Color(0xFF0F2A18);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: _textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${pnl >= 0 ? '+' : ''}¥${pnl.toStringAsFixed(2)}',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
            style: TextStyle(color: color, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: _textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  /// 辅助信息项
  Widget _buildAuxStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _textSecondary, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
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
          return Dismissible(
            key: Key(pos.code),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Text(
                    '删除',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
            onDismissed: (direction) async {
              await _dbService.deletePosition(pos.id!);
              await _loadPositions();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已删除 ${pos.name}')),
                );
              }
            },
            child: _buildPositionCard(pos, quote, opp),
          );
        },
      ),
    );
  }

  Widget _buildPositionCard(Position pos, QuoteData quote, OpportunityResult? opp) {
    final currentPrice = quote.price > 0 ? quote.price : (pos.latestPrice > 0 ? pos.latestPrice : pos.avgPrice);

    // v3.2: 始终从实时行情计算盈亏，不使用DB中可能过期的存储值
    final pnl = (currentPrice - pos.avgPrice) * pos.quantity;
    final pnlPct = pos.avgPrice > 0
        ? ((currentPrice - pos.avgPrice) / pos.avgPrice * 100)
        : 0.0;
    final pnlColor = pnl >= 0 ? _upColor : _downColor;

    final todayPnl = quote.preClose > 0
        ? pos.quantity * (currentPrice - quote.preClose)
        : 0.0;
    final todayPnlPct = quote.preClose > 0 && quote.price > 0
        ? (currentPrice - quote.preClose) / quote.preClose * 100
        : 0.0;
    final todayPnlColor = todayPnl >= 0 ? _upColor : _downColor;

    final holdingDays = pos.buyDate != null
        ? DateTime.now().difference(pos.buyDate!).inDays
        : 0;
    final marketValue = pos.quantity * currentPrice;

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
                code: _apiClient.addMarketPrefix(pos.code),
                name: pos.name,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 行1：名称 + 现价涨跌幅（突出）
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
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              pos.code,
                              style: const TextStyle(color: _textSecondary, fontSize: 11),
                            ),
                            if (holdingDays > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '持仓$holdingDays天',
                                style: TextStyle(
                                  color: _textSecondary.withOpacity(0.7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
                        onPressed: () => _showEditPositionDialog(pos),
                        visualDensity: VisualDensity.compact,
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
                          Text(
                            '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: quote.changePct >= 0 ? _upColor : _downColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 盈亏区（分组强化，浅色背景条）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _darkSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPnlDetail('浮动盈亏', pnl, pnlPct, pnlColor),
                    ),
                    Container(width: 1, height: 32, color: _borderColor),
                    Expanded(
                      child: _buildPnlDetail('当日盈亏', todayPnl, todayPnlPct, todayPnlColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 辅助信息行（降级显示）
              Row(
                children: [
                  _buildPositionDetail('持仓', '${pos.quantity}股'),
                  _buildPositionDetail('成本', '¥${pos.avgPrice.toStringAsFixed(3)}'),
                  _buildPositionDetail('市值', '¥${marketValue.toStringAsFixed(0)}'),
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

  /// 盈亏详情（卡片内紧凑展示：金额+百分比）
  Widget _buildPnlDetail(String label, double pnl, double pnlPct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _textSecondary, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          '${pnl >= 0 ? '+' : ''}¥${pnl.toStringAsFixed(2)}',
          style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        Text(
          '${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
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
      final tableKeys = excel.tables.keys.toList();
      if (tableKeys.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel文件中未找到工作表')),
          );
        }
        return;
      }

      final sheet = excel.tables[tableKeys.first];
      if (sheet == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel工作表解析失败')),
          );
        }
        return;
      }

      final rows = sheet.rows;
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel文件为空')),
          );
        }
        return;
      }

      debugPrint('Excel导入: 总行数=${rows.length}');

      // 解析资产汇总数据
      for (var i = 0; i < rows.length && i < 10; i++) {
        final row = rows[i];
        if (row.isNotEmpty) {
          final firstCell = row[0]?.value?.toString() ?? '';
          if (firstCell.contains('资产')) {
            // 这是资产汇总表头行，下一行是数据
            if (i + 1 < rows.length) {
              final dataRow = rows[i + 1];
              // 动态查找列位置
              int availableCol = -1, totalAssetsCol = -1;
              for (var j = 0; j < row.length; j++) {
                final header = row[j]?.value?.toString() ?? '';
                if (header.contains('可用')) {
                  availableCol = j;
                } else if (header.contains('总资产')) {
                  totalAssetsCol = j;
                }
              }
              if (availableCol >= 0 && availableCol < dataRow.length) {
                _availableCash = double.tryParse(dataRow[availableCol]?.value?.toString() ?? '0') ?? 0;
              }
              if (totalAssetsCol >= 0 && totalAssetsCol < dataRow.length) {
                _totalAssets = double.tryParse(dataRow[totalAssetsCol]?.value?.toString() ?? '0') ?? 0;
              }
            }
            break;
          }
        }
      }

      // 查找表头行（包含"证券代码"的行）
      int headerRowIndex = -1;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.isNotEmpty) {
          final firstCell = row[0]?.value?.toString() ?? '';
          if (firstCell.contains('证券代码') || firstCell.contains('代码')) {
            headerRowIndex = i;
            break;
          }
        }
      }

      if (headerRowIndex == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到表头行（证券代码）')),
          );
        }
        return;
      }

      debugPrint('Excel导入: 表头行索引=$headerRowIndex');

      // 解析表头，动态查找列位置（从最精确到最宽泛匹配，避免误匹配）
      final headerRow = rows[headerRowIndex];
      int codeCol = -1, nameCol = -1, quantityCol = -1, balanceCol = -1;
      int avgPriceCol = -1, latestPriceCol = -1, floatPnlCol = -1;
      int pnlPctCol = -1, marketValueCol = -1, todayPnlCol = -1;
      int todayPnlPctCol = -1;
      for (var i = 0; i < headerRow.length; i++) {
        final header = _parseCellValue(headerRow[i]);
        if (header.isEmpty) continue;
        
        // 精确匹配优先
        if (header == '证券代码' || header == '代码') {
          codeCol = i;
        } else if (header == '证券名称' || header == '名称') {
          nameCol = i;
        } else if (header == '拥股数量' || header == '持仓数量') {
          quantityCol = i;
        } else if (header == '股票余额' || header == '持仓余额') {
          balanceCol = i;
        } else if (header == '盈亏成本' || header == '成本价' || header == '持仓成本') {
          avgPriceCol = i;
        } else if (header == '最新价' || header == '现价' || header == '当前价') {
          latestPriceCol = i;
        } else if (header == '浮动盈亏') {
          floatPnlCol = i;
        } else if (header == '盈亏比例' || header == '盈亏比') {
          pnlPctCol = i;
        } else if (header == '当日盈亏') {
          todayPnlCol = i;
        } else if (header == '当日盈亏比例' || header == '当日盈亏比') {
          todayPnlPctCol = i;
        } else if (header == '证券市值' || header == '市值' || header == '持仓市值') {
          marketValueCol = i;
        }
      }

      if (codeCol == -1 || nameCol == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到必需的列（证券代码/证券名称）')),
          );
        }
        return;
      }

      debugPrint('Excel导入: codeCol=$codeCol nameCol=$nameCol quantityCol=$quantityCol balanceCol=$balanceCol avgPriceCol=$avgPriceCol latestPriceCol=$latestPriceCol floatPnlCol=$floatPnlCol pnlPctCol=$pnlPctCol todayPnlCol=$todayPnlCol todayPnlPctCol=$todayPnlPctCol marketValueCol=$marketValueCol');

      // 从表头下一行开始读取数据
      for (var rowIndex = headerRowIndex + 1; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        if (row.isEmpty) continue;

        // 获取单元格值，处理不同类型
        final codeCell = codeCol < row.length ? row[codeCol] : null;
        final nameCell = nameCol < row.length ? row[nameCol] : null;
        final balanceCell = balanceCol >= 0 && balanceCol < row.length ? row[balanceCol] : null;
        final quantityCell = quantityCol >= 0 && quantityCol < row.length ? row[quantityCol] : null;
        final avgPriceCell = avgPriceCol >= 0 && avgPriceCol < row.length ? row[avgPriceCol] : null;
        final latestPriceCell = latestPriceCol >= 0 && latestPriceCol < row.length ? row[latestPriceCol] : null;
        final floatPnlCell = floatPnlCol >= 0 && floatPnlCol < row.length ? row[floatPnlCol] : null;
        final pnlPctCell = pnlPctCol >= 0 && pnlPctCol < row.length ? row[pnlPctCol] : null;
        final todayPnlCell = todayPnlCol >= 0 && todayPnlCol < row.length ? row[todayPnlCol] : null;
        final todayPnlPctCell = todayPnlPctCol >= 0 && todayPnlPctCol < row.length ? row[todayPnlPctCol] : null;
        final marketValueCell = marketValueCol >= 0 && marketValueCol < row.length ? row[marketValueCol] : null;

        final code = _parseCellValue(codeCell);
        final name = _parseCellValue(nameCell);
        final balanceStr = _parseCellValue(balanceCell);
        final quantityStr = _parseCellValue(quantityCell);
        final avgPriceStr = _parseCellValue(avgPriceCell);
        final latestPriceStr = _parseCellValue(latestPriceCell);
        final floatPnlStr = _parseCellValue(floatPnlCell);
        final pnlPctStr = _parseCellValue(pnlPctCell);
        final todayPnlStr = _parseCellValue(todayPnlCell);
        final todayPnlPctStr = _parseCellValue(todayPnlPctCell);
        final marketValueStr = _parseCellValue(marketValueCell);

        debugPrint('Excel导入: 行$rowIndex code=$code name=$name balance=$balanceStr quantity=$quantityStr avgPrice=$avgPriceStr latestPrice=$latestPriceStr floatPnl=$floatPnlStr pnlPct=$pnlPctStr todayPnl=$todayPnlStr todayPnlPct=$todayPnlPctStr marketValue=$marketValueStr');

        if (code.isEmpty || name.isEmpty) continue;
        
        // 跳过合计行
        if (code.contains('合计') || name.contains('合计')) continue;

        // 优先使用拥股数量（实际持仓）；列存在时以其值为准（0=已清仓），
        // 仅当拥股数量列缺失或为空时才回退到股票余额
        int quantity = 0;
        if (quantityCol >= 0 && quantityStr.isNotEmpty) {
          quantity = int.tryParse(quantityStr) ?? 0;
        } else if (balanceStr.isNotEmpty) {
          quantity = int.tryParse(balanceStr) ?? 0;
        }

        // 获取盈亏成本
        double avgPrice = double.tryParse(avgPriceStr) ?? 0.0;
        final latestPrice = double.tryParse(latestPriceStr) ?? 0.0;

        // 如果盈亏成本为0，尝试从最新价和浮动盈亏反推成本价
        // 公式: avgPrice = (latestPrice * quantity - floatPnl) / quantity
        final floatPnlRaw = double.tryParse(floatPnlStr) ?? 0.0;
        if (avgPrice <= 0 && quantity > 0 && latestPrice > 0) {
          avgPrice = (latestPrice * quantity - floatPnlRaw) / quantity;
          debugPrint('Excel导入: 行$rowIndex 反推成本价=$avgPrice (latestPrice=$latestPrice quantity=$quantity floatPnl=$floatPnlRaw)');
        }

        // 解析盈亏比例（去掉%号）
        double pnlPct = 0.0;
        if (pnlPctStr.isNotEmpty && pnlPctStr != '--') {
          pnlPct = double.tryParse(pnlPctStr.replaceAll('%', '').trim()) ?? 0.0;
        }

        // 解析当日盈亏
        double todayPnl = double.tryParse(todayPnlStr.trim()) ?? 0.0;

        // 解析当日盈亏比例（去掉%号）
        double todayPnlPct = 0.0;
        if (todayPnlPctStr.isNotEmpty && todayPnlPctStr != '--') {
          todayPnlPct = double.tryParse(todayPnlPctStr.replaceAll('%', '').trim()) ?? 0.0;
        }
        
        // 解析市值
        final marketValue = double.tryParse(marketValueStr) ?? 0.0;

        if (code.isNotEmpty && name.isNotEmpty) {
          positions.add(Position(
            code: code,
            name: name,
            quantity: quantity,
            avgPrice: avgPrice,
            floatPnl: floatPnlRaw,
            pnlPct: pnlPct,
            marketValue: marketValue,
            todayPnl: todayPnl,
            todayPnlPct: todayPnlPct,
            latestPrice: latestPrice,
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
      
      // 数据验证：检查关键字段
      final warnings = <String>[];
      int validCount = 0;
      int zeroQuantityCount = 0;
      int zeroCostCount = 0;
      for (final pos in positions) {
        if (pos.quantity > 0) {
          validCount++;
          if (pos.avgPrice <= 0) {
            zeroCostCount++;
          }
        } else {
          zeroQuantityCount++;
        }
      }
      if (zeroQuantityCount > 0) {
        warnings.add('$zeroQuantityCount 只股票持仓数量为0（已清仓）');
      }
      if (zeroCostCount > 0) {
        warnings.add('$zeroCostCount 只股票成本价为0（已从盈亏反推）');
      }

      // 导入前确认（显示详细信息）
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _cardColor,
          title: const Text('确认导入', style: TextStyle(color: _textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将导入 ${positions.length} 只股票（其中有效持仓 $validCount 只）',
                style: const TextStyle(color: _textPrimary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                '导入将清除现有持仓数据并替换为新数据。',
                style: TextStyle(color: _textSecondary, fontSize: 12),
              ),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '⚠️ 注意事项：',
                  style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('• $w', style: const TextStyle(color: Colors.orange, fontSize: 11)),
                )),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消', style: TextStyle(color: _textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认导入', style: TextStyle(color: _accentColor)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      debugPrint('Excel导入: 确认导入，开始清空现有数据');
      
      // 批量添加到数据库（先清除现有数据）
      await _dbService.deleteAllPositions();
      debugPrint('Excel导入: 已清空现有数据');
      
      for (final pos in positions) {
        await _dbService.addPosition(pos);
        debugPrint('Excel导入: 添加持仓 ${pos.code} ${pos.name} 数量=${pos.quantity} 成本=${pos.avgPrice}');
      }

      await _loadPositions();
      debugPrint('Excel导入: 重新加载持仓，当前持仓数=${_positionMap.length}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 ${positions.length} 条持仓记录')),
        );
      }
    } catch (e) {
      debugPrint('Excel导入失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  String _parseCellValue(dynamic cell) {
    if (cell == null) return '';
    if (cell is String) return cell.trim();
    if (cell is num) return cell.toString();

    // excel 4.x: cell 是 Data 类型，cell.value 是 CellValue? 子类
    final value = cell.value;
    if (value == null) return '';

    // 直接的 String/num（兼容旧版本）
    if (value is String) return value.trim();
    if (value is num) return value.toString();

    // CellValue 子类：TextCellValue/IntCellValue/DoubleCellValue 等
    // 这些类的 toString() 已返回纯文本值
    return value.toString().trim();
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

      if (!mounted) return;
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
      debugPrint('[Watchlist] AI持仓分析失败: $e');
      if (!mounted) return;
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.42,
      ),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isError ? Colors.red.withOpacity(0.3) : _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('复制', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result.answer));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              TextButton.icon(
                icon: const Icon(Icons.close, size: 16),
                label: const Text('清除', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  setState(() {
                    _portfolioAnalysisResult = null;
                    _lastPortfolioAnalysisTime = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isError)
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  result.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  result.answer,
                  style: const TextStyle(color: _textPrimary, fontSize: 14, height: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showBacktestDialog() async {
    if (_positionMap.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无持仓数据，无法回测')),
        );
      }
      return;
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
            _buildStrategyButton('MACD金叉', context),
            const SizedBox(height: 8),
            _buildStrategyButton('MA金叉', context),
            const SizedBox(height: 8),
            _buildStrategyButton('KDJ超卖', context),
            const SizedBox(height: 8),
            _buildStrategyButton('RSI超卖', context),
            const SizedBox(height: 8),
            _buildStrategyButton('布林支撑', context),
            const SizedBox(height: 8),
            _buildStrategyButton('均线多头', context),
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
          await _runBacktest(strategy);
        },
        child: Text(
          strategy,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Future<void> _runBacktest(String strategy) async {
    if (!mounted) return;

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

      for (final pos in _positionMap.values) {
        debugPrint('回测: 持仓 ${pos.code} ${pos.name} 数量=${pos.quantity}');
        if (pos.quantity <= 0) {
          debugPrint('回测: 持仓 ${pos.code} 数量为0，跳过');
          continue;
        }

        final prefixedCode = _apiClient.addMarketPrefix(pos.code);
        debugPrint('回测: 获取 ${prefixedCode} 历史K线');
        final klines = await _apiClient.getStockHistory(
          prefixedCode,
          days: 180,
        );
        debugPrint('回测: ${prefixedCode} 获取到 ${klines.length} 条K线数据');

        if (klines.length >= 60) {
          klineData[pos.code] = klines;
        }
      }

      if (klineData.isEmpty) {
        debugPrint('回测: 无足够的历史数据进行回测');
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无足够的历史数据进行回测')),
          );
        }
        return;
      }

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
        Navigator.pop(context);
        _showBacktestResults(strategy, results);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回测失败: $e')),
        );
      }
    }
  }

  void _showBacktestResults(String strategy, Map<String, BacktestResult> results) {
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
                  final pos = _findPosition(code);
                  final name = pos?.name ?? code;

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

  Future<void> _showAIProviderDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentProviderName = prefs.getString('ai_provider') ?? 'zhipu';
    final currentProvider = AIProvider.fromString(currentProviderName);
    AIProvider? selectedProvider = currentProvider;

    await showDialog<void>(
      context: context,
      builder: (context) {
        String? testResult;
        bool isTesting = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: _cardColor,
              title: const Text(
                '选择AI分析引擎',
                style: TextStyle(color: _textPrimary, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...AIProvider.values.map((provider) {
                    return RadioListTile<AIProvider>(
                      title: Text(provider.label, style: const TextStyle(color: _textPrimary)),
                      subtitle: Text(provider.defaultModel, style: TextStyle(color: _textSecondary, fontSize: 12)),
                      value: provider,
                      groupValue: selectedProvider,
                      onChanged: (value) {
                        setState(() {
                          selectedProvider = value;
                          testResult = null;
                        });
                      },
                      activeColor: _accentColor,
                    );
                  }).toList(),
                  if (testResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        testResult!,
                        style: TextStyle(
                          color: testResult!.contains('成功') ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isTesting
                      ? null
                      : () async {
                          if (selectedProvider == null) return;
                          setState(() {
                            isTesting = true;
                            testResult = '正在测试${selectedProvider!.label}...';
                          });
                          final result = await _testAPIConnection(selectedProvider!);
                          setState(() {
                            isTesting = false;
                            testResult = result;
                          });
                        },
                  child: isTesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('测试连接', style: TextStyle(color: _textSecondary)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: _textSecondary)),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedProvider == null) return;
                    await prefs.setString('ai_provider', selectedProvider!.name);
                    // 重新初始化AILayerProvider
                    final apiKey = AIConfig.getApiKeyForProvider(selectedProvider!);
                    if (apiKey.isNotEmpty) {
                      AILayerProvider.set(
                        ChatCompletionLayer(
                          apiKey: apiKey,
                          provider: selectedProvider!,
                        ),
                      );
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已切换到${selectedProvider!.label}')),
                      );
                    }
                  },
                  child: const Text('确定', style: TextStyle(color: _accentColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String> _testAPIConnection(AIProvider provider) async {
    final apiKey = AIConfig.getApiKeyForProvider(provider);
    if (apiKey.isEmpty) return 'API Key为空，请检查配置';

    try {
      final response = await HttpClient().postUrl(Uri.parse(provider.endpoint))
        ..headers.set('Content-Type', 'application/json')
        ..headers.set('Authorization', 'Bearer $apiKey');
      final request = await response;
      final body = '{"model": "${provider.defaultModel}", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5}';
      request.write(body);
      final responseBody = await request.close();
      if (responseBody.statusCode == 200) {
        return '${provider.label}连接成功！';
      } else if (responseBody.statusCode == 429) {
        return '${provider.label}请求过于频繁（429）';
      } else if (responseBody.statusCode == 401) {
        return '${provider.label}API Key无效（401）';
      } else if (responseBody.statusCode == 403) {
        return '${provider.label}权限不足（403）';
      } else {
        return '${provider.label}连接失败: ${responseBody.statusCode}';
      }
    } catch (e) {
      return '${provider.label}连接异常: $e';
    }
  }

  Future<void> _showAddPositionDialog() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    final avgPriceController = TextEditingController();
    bool isSearching = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
                  onChanged: (value) async {
                    if (value.length >= 6) {
                      setState(() => isSearching = true);
                      try {
                        final results = await _apiClient.searchStocks(value);
                        if (results.isNotEmpty) {
                          final stock = results.first;
                          setState(() {
                            nameController.text = stock.name;
                          });
                        }
                      } catch (e) {
                        debugPrint('[Watchlist] 搜索股票失败: $e');
                      }
                      setState(() => isSearching = false);
                    } else {
                      setState(() => nameController.text = '');
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  enabled: false,
                  style: const TextStyle(color: Colors.white70),
                  decoration: InputDecoration(
                    labelText: '股票名称',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: isSearching ? '搜索中...' : '输入代码自动获取',
                    hintStyle: const TextStyle(color: Colors.white38),
                    suffixIcon: isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
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

                final existing = _findPosition(code);
                if (existing != null) {
                  await _dbService.updatePosition(existing.copyWith(
                    quantity: quantity,
                    avgPrice: avgPrice,
                  ));
                } else {
                  await _dbService.addPosition(position);
                }
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
      ),
    );
  }

  Future<void> _showEditPositionDialog(Position pos) async {
    final quantityController = TextEditingController(text: pos.quantity.toString());
    final avgPriceController = TextEditingController(text: pos.avgPrice.toStringAsFixed(3));

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          '编辑持仓 - ${pos.name}',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                enabled: false,
                style: const TextStyle(color: Colors.white70),
                decoration: InputDecoration(
                  labelText: '股票代码',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: pos.code,
                  hintStyle: const TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: false,
                style: const TextStyle(color: Colors.white70),
                decoration: InputDecoration(
                  labelText: '股票名称',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: pos.name,
                  hintStyle: const TextStyle(color: Colors.white38),
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
              final quantityStr = quantityController.text.trim();
              final avgPriceStr = avgPriceController.text.trim();

              if (quantityStr.isEmpty || avgPriceStr.isEmpty) {
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

              await _dbService.updatePosition(pos.copyWith(
                quantity: quantity,
                avgPrice: avgPrice,
              ));
              await _loadPositions();

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('持仓编辑成功')),
                );
              }
            },
            child: const Text('保存'),
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
    // 持仓查找 (v2.33) - 兼容 watchlist 中带 sh/sz/bj 前缀的 code
    final position = _findPosition(item.code);
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
              : item.name,
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
          positionInfo: hasPosition
              ? PositionInfo(
                  quantity: position.quantity,
                  avgPrice: position.avgPrice,
                  currentPrice: quote.price > 0 ? quote.price : position.latestPrice,
                  floatPnl: position.floatPnl != 0 ? position.floatPnl : null,
                  pnlPct: position.pnlPct != 0 ? position.pnlPct : null,
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
                _findPosition(item.code) != null ? Icons.edit_note : Icons.account_balance_wallet_outlined,
                color: _accentColor, size: 22,
              ),
              title: Text(
                _findPosition(item.code) != null ? '编辑持仓' : '添加持仓',
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
    final existing = _findPosition(item.code);
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
                await _dbService.updatePosition(existing.copyWith(
                  quantity: qty,
                  avgPrice: price,
                  notes: notesCtrl.text.trim(),
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
