import 'dart:async';

import 'package:flutter/material.dart';

import '../analysis/opportunity_engine.dart';
import '../analysis/explore_engine.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/capsule_tab_switcher.dart';
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

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  int _currentTab = 0;

  // ─── 自选分析状态 ──────────────────────────────────────────────
  final OpportunityEngine _oppEngine = OpportunityEngine.instance;
  final ExploreEngine _exploreEngine = ExploreEngine.instance;
  final DatabaseService _dbService = DatabaseService();

  List<OpportunityResult> _oppResults = [];
  bool _oppLoading = false;
  String _oppFilter = '全部'; // 全部 / 看多 / 看空 / 观望
  bool _oppEditMode = false;
  final Set<String> _oppSelected = {};

  StreamSubscription<OpportunityProgress>? _oppSub;

  // ─── 智能探索状态 ──────────────────────────────────────────────
  List<ExploreResult> _exploreResults = [];
  bool _exploreLoading = false;
  String _exploreSort = '评分'; // 评分 / 涨幅 / 名称
  String _exploreFilter = '全部'; // 全部 / 买入 / 观望
  Set<String> _watchlistCodes = {};

  StreamSubscription<ExploreProgress>? _exploreSub;

  // ─── 生命周期 ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadOppFromDb();
    _loadExploreFromDb();
    _loadWatchlistCodes();

    // 订阅自选分析进度
    _oppSub = _oppEngine.progressStream.listen(_onOppProgress);
    if (_oppEngine.latestProgress != null) {
      _onOppProgress(_oppEngine.latestProgress!);
    }

    // 订阅智能探索进度
    _exploreSub = _exploreEngine.progressStream.listen(_onExploreProgress);
    if (_exploreEngine.latestProgress != null) {
      _onExploreProgress(_exploreEngine.latestProgress!);
    }
  }

  @override
  void dispose() {
    // pause on dispose, not cancel — engine is singleton and keeps running
    _oppSub?.pause();
    _exploreSub?.pause();
    super.dispose();
  }

  // ─── 数据加载 ──────────────────────────────────────────────────

  Future<void> _loadOppFromDb() async {
    final maps = await _dbService.getOpportunityResults();
    if (mounted) {
      setState(() {
        _oppResults = maps.map((m) => OpportunityResult.fromMap(m)).toList();
      });
    }
  }

  Future<void> _loadExploreFromDb() async {
    final results = await _dbService.getExploreResults();
    if (mounted) {
      setState(() {
        _exploreResults = results;
      });
    }
  }

  Future<void> _loadWatchlistCodes() async {
    final list = await _dbService.getWatchlist();
    if (mounted) {
      setState(() {
        _watchlistCodes = list.map((e) => e.code).toSet();
      });
    }
  }

  // ─── 自选分析进度回调 ──────────────────────────────────────────

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

  // ─── 智能探索进度回调 ──────────────────────────────────────────

  void _onExploreProgress(ExploreProgress p) {
    if (!mounted) return;
    setState(() {
      switch (p.status) {
        case ExploreStatus.fetchingSectors:
        case ExploreStatus.fetchingStocks:
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

  // ─── 自选分析：过滤 ────────────────────────────────────────────

  List<OpportunityResult> get _filteredOppResults {
    switch (_oppFilter) {
      case '看多':
        return _oppResults
            .where((r) => r.recommendation.contains('买入') || r.recommendation.contains('强烈买入'))
            .toList();
      case '看空':
        return _oppResults
            .where((r) => r.recommendation.contains('卖出'))
            .toList();
      case '观望':
        return _oppResults
            .where((r) =>
                !r.recommendation.contains('买入') &&
                !r.recommendation.contains('卖出'))
            .toList();
      default:
        return _oppResults;
    }
  }

  // ─── 智能探索：排序 + 过滤 ────────────────────────────────────

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
      tradeLevelsJson: r.tradeLevels != null
          ? r.tradeLevels.toString()
          : null,
      topSignals: r.topSignals.join('  '),
      archivedAt: DateTime.now(),
    );
    await _dbService.addArchive(record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${r.name} 已归档'),
          backgroundColor: _kAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ─── 自选分析：批量留档 ──────────────────────────────────────────

  Future<void> _batchArchiveOppItems() async {
    final toArchive = _filteredOppResults;
    if (toArchive.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('确认留档', style: TextStyle(color: _kTextPrimary)),
        content: Text(
          '确定要将 ${toArchive.length} 只股票的分析结果留档吗？',
          style: const TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认', style: TextStyle(color: _kAccent)),
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
        tradeLevelsJson: r.tradeLevels != null
            ? r.tradeLevels.toString()
            : null,
        topSignals: r.topSignals.join('  '),
        archivedAt: DateTime.now(),
      );
      await _dbService.addArchive(record);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已归档 ${toArchive.length} 只股票'),
          backgroundColor: _kAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ─── 自选分析：批量移出自选 ─────────────────────────────────────

  Future<void> _batchRemoveFromWatchlist() async {
    if (_oppSelected.isEmpty) return;
    await _dbService.batchRemoveFromWatchlist(_oppSelected.toList());
    setState(() {
      _oppEditMode = false;
      _oppSelected.clear();
    });
    _loadWatchlistCodes();
    // 重新分析自选
    _oppEngine.analyze();
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

  // ─── 评分信息弹窗 ──────────────────────────────────────────────

  void _showScoringInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('评分说明', style: TextStyle(color: _kTextPrimary)),
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
            child: const Text('知道了', style: TextStyle(color: _kAccent)),
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
            // Tab 切换器
            CapsuleTabSwitcher(
              tabs: const ['自选分析', '智能探索'],
              currentIndex: _currentTab,
              onTabChanged: (i) => setState(() => _currentTab = i),
            ),
            // 内容区
            Expanded(
              child: _currentTab == 0 ? _buildOppTab() : _buildExploreTab(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 自选分析 Tab
  // ═══════════════════════════════════════════════════════════════

  Widget _buildOppTab() {
    final filtered = _filteredOppResults;
    return Column(
      children: [
        // 筛选条 + 操作按钮
        _buildOppHeader(),
        // 进度条
        if (_oppLoading) _buildOppProgress(),
        // 列表
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(
                  icon: Icons.analytics_outlined,
                  text: _oppResults.isEmpty ? '暂无自选分析数据' : '当前筛选无结果',
                  actionText: _oppResults.isEmpty ? '开始分析' : null,
                  onAction: _oppResults.isEmpty
                      ? () => _oppEngine.analyze()
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildOppCard(filtered[i], i + 1),
                ),
        ),
        // 编辑模式底部操作栏
        if (_oppEditMode) _buildOppEditBar(),
      ],
    );
  }

  Widget _buildOppHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 筛选 chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['全部', '看多', '看空', '观望'].map((f) {
                  final selected = _oppFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: selected,
                      onSelected: (_) => setState(() => _oppFilter = f),
                      selectedColor: _kAccent.withOpacity(0.2),
                      backgroundColor: const Color(0xFF21262D),
                      labelStyle: TextStyle(
                        color: selected ? _kAccent : _kTextSecondary,
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: selected ? _kAccent : Colors.transparent,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // 留档按钮
          IconButton(
            icon: const Icon(Icons.archive_outlined, color: _kTextSecondary, size: 20),
            onPressed: _batchArchiveOppItems,
            tooltip: '留档当前筛选',
          ),
          // 评分说明按钮
          IconButton(
            icon: const Icon(Icons.info_outline, color: _kTextSecondary, size: 20),
            onPressed: _showScoringInfo,
            tooltip: '评分说明',
          ),
          // 编辑模式切换
          IconButton(
            icon: Icon(
              _oppEditMode ? Icons.check : Icons.edit_outlined,
              color: _oppEditMode ? _kAccent : _kTextSecondary,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _oppEditMode = !_oppEditMode;
                if (!_oppEditMode) _oppSelected.clear();
              });
            },
            tooltip: _oppEditMode ? '完成' : '编辑',
          ),
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh, color: _kTextSecondary, size: 20),
            onPressed: _oppLoading ? null : () => _oppEngine.analyze(),
            tooltip: '刷新分析',
          ),
        ],
      ),
    );
  }

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

  Widget _buildOppCard(OpportunityResult r, int rank) {
    final isSelected = _oppSelected.contains(r.code);

    // 信号标签
    final tags = <Widget>[];
    for (final s in r.topSignals.take(3)) {
      final isBuy = s.startsWith('▲');
      tags.add(SignalTag(
        text: s,
        color: isBuy ? _kUp : _kDown,
      ));
    }
    if (r.confluenceScore > 0) {
      tags.add(SignalTag(
        text: '共振${r.confluenceScore}',
        color: _kAccent,
      ));
    }

    // 操作按钮
    final actions = <Widget>[];
    if (!_oppEditMode) {
      actions.addAll([
        TextButton.icon(
          icon: const Icon(Icons.archive_outlined, size: 16),
          label: const Text('归档', style: TextStyle(fontSize: 12)),
          onPressed: () => _archiveOppItem(r),
          style: TextButton.styleFrom(
            foregroundColor: _kTextSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]);
    }

    return GestureDetector(
      onTap: () {
        if (_oppEditMode) {
          setState(() {
            if (isSelected) {
              _oppSelected.remove(r.code);
            } else {
              _oppSelected.add(r.code);
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuoteScreen(code: r.code, name: r.name),
            ),
          );
        }
      },
      onLongPress: () {
        if (!_oppEditMode) {
          setState(() {
            _oppEditMode = true;
            _oppSelected.add(r.code);
          });
        }
      },
      child: Row(
        children: [
          if (_oppEditMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Checkbox(
                value: isSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _oppSelected.add(r.code);
                    } else {
                      _oppSelected.remove(r.code);
                    }
                  });
                },
                activeColor: _kAccent,
                checkColor: Colors.white,
              ),
            ),
          Expanded(
            child: StockCard(
              name: r.name,
              code: r.code,
              price: r.price,
              changePct: r.changePct,
              score: r.score,
              recommendation: r.recommendation,
              riskLevel: r.riskLevel,
              rank: rank,
              tags: tags.isNotEmpty ? tags : null,
              actions: actions.isNotEmpty ? actions : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOppEditBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Text(
            '已选择 ${_oppSelected.length} 只',
            style: const TextStyle(color: _kTextSecondary, fontSize: 14),
          ),
          const Spacer(),
          TextButton(
            onPressed: _oppSelected.isEmpty ? null : _batchRemoveFromWatchlist,
            style: TextButton.styleFrom(
              foregroundColor: _kDown,
            ),
            child: const Text('移出自选'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _oppEditMode = false;
                _oppSelected.clear();
              });
            },
            child: const Text('取消', style: TextStyle(color: _kTextSecondary)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 智能探索 Tab
  // ═══════════════════════════════════════════════════════════════

  Widget _buildExploreTab() {
    final processed = _processedExploreResults;
    return Column(
      children: [
        // 排序 + 筛选条
        _buildExploreHeader(),
        // 进度条
        if (_exploreLoading) _buildExploreProgress(),
        // 列表
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
        // 一键加自选
        if (!_exploreLoading && processed.isNotEmpty) _buildExploreBottomBar(),
      ],
    );
  }

  Widget _buildExploreHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 排序下拉框
          const Text('排序', style: TextStyle(color: _kTextSecondary, fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _exploreSort,
                  isDense: true,
                  iconEnabledColor: _kTextSecondary,
                  dropdownColor: const Color(0xFF21262D),
                  style: const TextStyle(color: _kTextPrimary, fontSize: 13),
                  items: ['评分', '涨幅', '名称'].map((s) {
                    return DropdownMenuItem(value: s, child: Text(s));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _exploreSort = v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 筛选下拉框
          const Text('筛选', style: TextStyle(color: _kTextSecondary, fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _exploreFilter,
                  isDense: true,
                  iconEnabledColor: _kTextSecondary,
                  dropdownColor: const Color(0xFF21262D),
                  style: const TextStyle(color: _kTextPrimary, fontSize: 13),
                  items: ['全部', '买入', '观望'].map((f) {
                    return DropdownMenuItem(value: f, child: Text(f));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _exploreFilter = v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 刷新
          IconButton(
            icon: const Icon(Icons.refresh, color: _kTextSecondary, size: 20),
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

  Widget _buildExploreCard(ExploreResult r, int rank) {
    final isInWatchlist = _watchlistCodes.contains(r.code);

    // 信号标签
    final tags = <Widget>[];
    if (r.confluenceScore > 0) {
      tags.add(SignalTag(text: '共振${r.confluenceScore}', color: _kAccent));
    }
    if (r.sector.isNotEmpty) {
      tags.add(SignalTag(text: r.sector, color: _kTextSecondary));
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
            color: _kAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _kAccent,
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
            style: const TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
