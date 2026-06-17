import 'dart:async';

import 'package:flutter/material.dart';

import '../analysis/explore_engine.dart';
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

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

class DiscoverScreenState extends State<DiscoverScreen> {
  final ExploreEngine _exploreEngine = ExploreEngine.instance;
  final DatabaseService _dbService = DatabaseService();

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
    _loadExploreFromDb();
    _loadWatchlistCodes();

    // 订阅智能探索进度
    _exploreSub = _exploreEngine.progressStream.listen(_onExploreProgress);
    if (_exploreEngine.latestProgress != null) {
      _onExploreProgress(_exploreEngine.latestProgress!);
    }
  }

  @override
  void dispose() {
    _exploreSub?.cancel();
    super.dispose();
  }

  /// 切回发现Tab时刷新自选状态
  void onTabVisible() {
    _loadWatchlistCodes();
  }

  // ─── 数据加载 ──────────────────────────────────────────────────

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

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final processed = _processedExploreResults;
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
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
        ),
      ),
    );
  }

  Widget _buildExploreHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 排序
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
          // 筛选
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
