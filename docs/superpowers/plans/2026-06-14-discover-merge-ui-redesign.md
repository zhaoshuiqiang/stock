# UI重构：发现页面融合 + 自选升级 + 整体风格优化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将机会与探索界面融合为发现页面，自选界面全面升级，整体UI采用现代简约风格重新设计。

**Architecture:** 底部导航从6个Tab缩减为5个，新增DiscoverScreen融合原OpportunityScreen和ExploreScreen的功能，通过顶部胶囊Tab切换"自选分析"和"智能探索"两种模式。WatchlistScreen全面重构为卡片式布局，支持左滑删除、长按编辑、实时行情刷新。全局主题色彩从旧色系迁移到新色系。

**Tech Stack:** Flutter 3.0+ / Dart 3.0+，现有引擎(OpportunityEngine/ExploreEngine)和数据层(DatabaseService)保持不变。

---

## File Structure

| 操作 | 文件路径 | 职责 |
|------|---------|------|
| **创建** | `lib/screens/discover_screen.dart` | 发现页面（融合机会+探索） |
| **创建** | `lib/widgets/stock_card.dart` | 可复用股票卡片组件 |
| **创建** | `lib/widgets/capsule_tab_switcher.dart` | 胶囊Tab切换器组件 |
| **修改** | `lib/main.dart` | 导航5Tab + 新主题色 |
| **修改** | `lib/screens/watchlist_screen.dart` | 全面升级UI和交互 |
| **修改** | `lib/screens/home_screen.dart` | 主题色更新 |
| **修改** | `lib/core/app_version.dart` | 版本号→2.20.0 |
| **修改** | `lib/screens/update_log_screen.dart` | 新增v2.20.0更新日志 |
| **删除** | `lib/screens/opportunity_screen.dart` | 功能合并到DiscoverScreen |
| **删除** | `lib/screens/explore_screen.dart` | 功能合并到DiscoverScreen |

---

### Task 1: 创建胶囊Tab切换器组件

**Files:**
- Create: `lib/widgets/capsule_tab_switcher.dart`

- [ ] **Step 1: 创建CapsuleTabSwitcher组件**

```dart
import 'package:flutter/material.dart';

class CapsuleTabSwitcher extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabChanged;

  const CapsuleTabSwitcher({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = index == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF58A6FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF8B949E),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证文件创建成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/widgets/capsule_tab_switcher.dart`
Expected: No issues found

---

### Task 2: 创建可复用股票卡片组件

**Files:**
- Create: `lib/widgets/stock_card.dart`

- [ ] **Step 1: 创建StockCard组件**

```dart
import 'package:flutter/material.dart';

/// 统一的股票卡片组件，用于自选列表和发现页面
class StockCard extends StatelessWidget {
  final String name;
  final String code;
  final double price;
  final double changePct;
  final double? pe;
  final double? pb;
  final int? score;
  final String? recommendation;
  final String? riskLevel;
  final List<Widget>? tags;
  final List<Widget>? actions;
  final int? rank;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const StockCard({
    super.key,
    required this.name,
    required this.code,
    required this.price,
    required this.changePct,
    this.pe,
    this.pb,
    this.score,
    this.recommendation,
    this.riskLevel,
    this.tags,
    this.actions,
    this.rank,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  Color get _changeColor =>
      changePct > 0 ? const Color(0xFFE74C3C) :
      changePct < 0 ? const Color(0xFF2ECC71) :
      const Color(0xFF8B949E);

  Color get _recColor {
    if (recommendation == null) return const Color(0xFF8B949E);
    if (recommendation!.contains('强烈买入') || recommendation!.contains('买入')) {
      return const Color(0xFFE74C3C);
    }
    if (recommendation!.contains('卖出')) {
      return const Color(0xFF2ECC71);
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: recommendation != null
                ? _recColor.withOpacity(0.3)
                : const Color(0xFF30363D),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：排名 + 名称 + 推荐标签 + 尾部组件
            Row(
              children: [
                if (rank != null) ...[
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rank! <= 3
                          ? const Color(0xFF58A6FF).withOpacity(0.2)
                          : const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: rank! <= 3
                            ? const Color(0xFF58A6FF)
                            : const Color(0xFF8B949E),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFFF0F6FC),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (recommendation != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _recColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      recommendation!,
                      style: TextStyle(
                        color: _recColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            // 第二行：代码
            Text(
              code,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
            const SizedBox(height: 8),
            // 第三行：价格 + 涨跌幅 + PE/PB + 评分
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price > 0 ? '¥${price.toStringAsFixed(2)}' : '--',
                  style: TextStyle(
                    color: _changeColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _changeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: _changeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (pe != null && pe! > 0)
                  Text(
                    'PE:${pe!.toStringAsFixed(1)}',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                if (pe != null && pe! > 0 && pb != null && pb! > 0)
                  const SizedBox(width: 8),
                if (pb != null && pb! > 0)
                  Text(
                    'PB:${pb!.toStringAsFixed(1)}',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                if (score != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF58A6FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$score分',
                      style: const TextStyle(
                        color: Color(0xFF58A6FF),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // 第四行：信号标签（可选）
            if (tags != null && tags!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: tags!),
            ],
            // 第五行：操作按钮（可选）
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: actions!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 信号标签组件
class SignalTag extends StatelessWidget {
  final String text;
  final Color color;

  const SignalTag({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证文件创建成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/widgets/stock_card.dart`
Expected: No issues found

---

### Task 3: 创建发现页面（DiscoverScreen）

**Files:**
- Create: `lib/screens/discover_screen.dart`

- [ ] **Step 1: 创建DiscoverScreen**

这是核心文件，融合原OpportunityScreen和ExploreScreen。代码较长，分为自选分析Tab和智能探索Tab两部分。

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../analysis/opportunity_engine.dart';
import '../analysis/explore_engine.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/capsule_tab_switcher.dart';
import '../widgets/stock_card.dart';
import 'quote_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  // Tab状态
  int _currentTab = 0; // 0=自选分析, 1=智能探索

  // ===== 自选分析Tab状态 =====
  final OpportunityEngine _oppEngine = OpportunityEngine.instance;
  StreamSubscription<OpportunityProgress>? _oppSubscription;
  List<OpportunityResult> _opportunities = [];
  String _oppFilterType = '全部';
  bool _isOppAnalyzing = false;
  int _oppCompleted = 0;
  int _oppTotal = 0;
  DateTime? _oppLastAnalyzed;
  bool _isOppEditMode = false;
  Set<String> _oppSelectedCodes = {};

  static const _buyRecs = ['强烈买入', '买入', '谨慎买入'];
  static const _sellRecs = ['卖出', '强烈卖出', '谨慎卖出'];
  static const _neutralRecs = ['观望'];

  // ===== 智能探索Tab状态 =====
  final ExploreEngine _expEngine = ExploreEngine.instance;
  StreamSubscription<ExploreProgress>? _expSubscription;
  List<ExploreResult> _exploreResults = [];
  Set<String> _watchlistCodes = {};
  bool _isExpAnalyzing = false;
  bool _isExpLoading = false;
  String _expStatusText = '';
  int _expTotalStocks = 0;
  int _expAnalyzedStocks = 0;
  int _expFoundStocks = 0;
  String _expCurrentStock = '';
  DateTime? _expLastAnalyzed;
  String _expSortBy = 'score';
  bool _expSortAsc = false;
  String _expFilterType = '全部';

  // ===== 共享 =====
  final DatabaseService _dbService = DatabaseService();
  bool _analysisNeedsRefresh = false;

  @override
  void initState() {
    super.initState();
    _loadOppFromDb();
    _loadExpFromDb();
    _loadWatchlistCodes();
    // 恢复正在运行的引擎
    if (_oppEngine.isRunning) {
      _subscribeOppProgress();
      _restoreOppProgress();
    }
    if (_expEngine.isRunning) {
      _subscribeExpProgress();
      _restoreExpProgress();
    }
  }

  @override
  void dispose() {
    _oppSubscription?.pause();
    _expSubscription?.pause();
    super.dispose();
  }

  // ===== 自选分析：数据加载 =====

  Future<void> _loadOppFromDb() async {
    final results = await _dbService.getOpportunityResults();
    final lastTime = await _dbService.getOpportunityLastTime();
    if (mounted) {
      setState(() {
        _opportunities = results.map((r) => OpportunityResult.fromMap(r)).toList();
        _oppLastAnalyzed = lastTime;
      });
    }
  }

  void _subscribeOppProgress() {
    _oppSubscription?.cancel();
    _oppSubscription = _oppEngine.progressStream.listen(_onOppProgress);
  }

  void _restoreOppProgress() {
    final lp = _oppEngine.latestProgress;
    if (lp == null) return;
    setState(() {
      _isOppAnalyzing = true;
      _oppCompleted = lp.completedCount;
      _oppTotal = lp.totalCount;
    });
  }

  void _onOppProgress(OpportunityProgress progress) {
    if (!mounted) return;
    switch (progress.status) {
      case OpportunityStatus.fetching:
        setState(() => _isOppAnalyzing = true);
        break;
      case OpportunityStatus.analyzing:
        setState(() {
          _isOppAnalyzing = true;
          _oppCompleted = progress.completedCount;
          _oppTotal = progress.totalCount;
        });
        break;
      case OpportunityStatus.saving:
        break;
      case OpportunityStatus.complete:
        _opportunities = progress.results ?? [];
        _oppLastAnalyzed = DateTime.now();
        setState(() {
          _isOppAnalyzing = false;
          _oppCompleted = progress.totalCount;
          _oppTotal = progress.totalCount;
        });
        break;
      case OpportunityStatus.error:
        setState(() => _isOppAnalyzing = false);
        if (progress.message != null) _showSnack(progress.message!);
        break;
      case OpportunityStatus.alreadyRunning:
      case OpportunityStatus.idle:
        break;
    }
  }

  Future<void> _refreshOppAnalysis() async {
    if (_isOppAnalyzing) return;
    setState(() { _isOppAnalyzing = true; _oppCompleted = 0; });
    _subscribeOppProgress();
    _oppEngine.analyze();
  }

  List<OpportunityResult> _getFilteredOpportunities() {
    switch (_oppFilterType) {
      case '看多':
        return _opportunities.where((o) => _buyRecs.contains(o.recommendation)).toList();
      case '看空':
        return _opportunities.where((o) => _sellRecs.contains(o.recommendation)).toList();
      case '观望':
        return _opportunities.where((o) => _neutralRecs.contains(o.recommendation)).toList();
      default:
        return _opportunities;
    }
  }

  // ===== 自选分析：编辑模式 =====

  void _toggleOppEditMode() {
    setState(() {
      _isOppEditMode = !_isOppEditMode;
      if (!_isOppEditMode) _oppSelectedCodes.clear();
    });
  }

  Future<void> _deleteSelectedFromWatchlist() async {
    if (_oppSelectedCodes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('移出自选', style: TextStyle(color: Color(0xFFF0F6FC))),
        content: Text('确定将选中的${_oppSelectedCodes.length}只股票移出自选吗？',
            style: const TextStyle(color: Color(0xFF8B949E))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _dbService.batchRemoveFromWatchlist(_oppSelectedCodes.toList());
    setState(() {
      _isOppEditMode = false;
      _oppSelectedCodes.clear();
      _watchlistCodes.removeAll(_oppSelectedCodes);
    });
    _loadWatchlistCodes();
    _refreshOppAnalysis();
    _showSnack('已移出${_oppSelectedCodes.length}只股票');
  }

  // ===== 自选分析：留档 =====

  Future<void> _archiveOpportunity(OpportunityResult o) async {
    final record = ArchiveRecord(
      code: o.code, name: o.name, price: o.price, changePct: o.changePct,
      score: o.score, recommendation: o.recommendation, riskLevel: o.riskLevel,
      buySignalCount: o.buySignalCount, sellSignalCount: o.sellSignalCount,
      activeStrategyCount: o.activeStrategyCount, confluenceScore: o.confluenceScore,
      tradeLevelsJson: o.tradeLevels != null ? _encodeTradeLevels(o.tradeLevels!) : null,
      topSignals: o.topSignals.join('  '), archivedAt: DateTime.now(),
    );
    await _dbService.addArchive(record);
    if (mounted) _showSnack('${o.name} 已留档');
  }

  String _encodeTradeLevels(Map<String, dynamic> tl) {
    final parts = tl.entries.map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}');
    return '{${parts.join(',')}}';
  }

  Future<void> _archiveAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('一键留档', style: TextStyle(color: Color(0xFFF0F6FC))),
        content: Text('确定将 ${_opportunities.length} 条推荐全部留档吗？',
            style: const TextStyle(color: Color(0xFF8B949E))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    int count = 0;
    for (final o in _opportunities) {
      try { await _archiveOpportunity(o); count++; } catch (_) {}
    }
    if (mounted) _showSnack('已留档 $count/${_opportunities.length} 条');
  }

  // ===== 智能探索：数据加载 =====

  Future<void> _loadExpFromDb() async {
    final results = await _dbService.getExploreResults();
    final lastTime = await _dbService.getExploreLastTime();
    if (mounted) {
      setState(() {
        _exploreResults = results;
        _expLastAnalyzed = lastTime;
      });
    }
  }

  Future<void> _loadWatchlistCodes() async {
    final watchlist = await _dbService.getWatchlist();
    if (mounted) {
      setState(() {
        _watchlistCodes = watchlist.map((item) => item.code).toSet();
      });
    }
  }

  void _subscribeExpProgress() {
    _expSubscription?.cancel();
    _expSubscription = _expEngine.progressStream.listen(_onExpProgress);
  }

  void _restoreExpProgress() {
    final lp = _expEngine.latestProgress;
    if (lp == null) return;
    setState(() {
      _isExpAnalyzing = true;
      _isExpLoading = true;
      _expTotalStocks = lp.totalStocks;
      _expAnalyzedStocks = lp.analyzedStocks;
      _expFoundStocks = lp.foundStocks;
      _expCurrentStock = lp.currentStock ?? '';
      _expStatusText = _expProgressToText(lp);
    });
  }

  String _expProgressToText(ExploreProgress p) {
    switch (p.status) {
      case ExploreStatus.fetchingSectors: return '正在获取热门板块...';
      case ExploreStatus.fetchingStocks: return '正在获取板块成分股...';
      case ExploreStatus.analyzing: return '正在分析 $_expAnalyzedStocks/$_expTotalStocks';
      case ExploreStatus.saving: return '保存分析结果...';
      default: return '分析中...';
    }
  }

  void _onExpProgress(ExploreProgress progress) {
    if (!mounted) return;
    switch (progress.status) {
      case ExploreStatus.fetchingSectors:
        setState(() => _expStatusText = '正在获取热门板块...');
        break;
      case ExploreStatus.fetchingStocks:
        setState(() {
          _expStatusText = '正在获取板块成分股...';
          _expTotalStocks = progress.totalStocks;
        });
        break;
      case ExploreStatus.analyzing:
        setState(() {
          _expStatusText = '正在分析 $_expAnalyzedStocks/$_expTotalStocks';
          _expTotalStocks = progress.totalStocks;
          _expAnalyzedStocks = progress.analyzedStocks;
          _expFoundStocks = progress.foundStocks;
          _expCurrentStock = progress.currentStock ?? _expCurrentStock;
        });
        break;
      case ExploreStatus.saving:
        setState(() => _expStatusText = '保存分析结果...');
        break;
      case ExploreStatus.complete:
        _exploreResults = progress.results ?? [];
        _expLastAnalyzed = DateTime.now();
        setState(() {
          _isExpAnalyzing = false;
          _isExpLoading = false;
          _expStatusText = '';
          _expTotalStocks = progress.totalStocks;
          _expAnalyzedStocks = progress.analyzedStocks;
          _expFoundStocks = progress.foundStocks;
        });
        break;
      case ExploreStatus.error:
        setState(() {
          _isExpAnalyzing = false;
          _isExpLoading = _exploreResults.isEmpty;
          _expStatusText = progress.message ?? '分析失败';
        });
        if (progress.message != null) _showSnack(progress.message!);
        break;
      case ExploreStatus.alreadyRunning:
      case ExploreStatus.idle:
        break;
    }
  }

  Future<void> _startExplore() async {
    if (_isExpAnalyzing) return;
    setState(() {
      _isExpAnalyzing = true;
      _isExpLoading = true;
      _expStatusText = '正在获取板块数据...';
      _expTotalStocks = 0;
      _expAnalyzedStocks = 0;
      _expFoundStocks = 0;
      _expCurrentStock = '';
    });
    _subscribeExpProgress();
    _expEngine.explore();
  }

  List<ExploreResult> get _sortedExploreResults {
    final sorted = List<ExploreResult>.from(_exploreResults);
    // 先筛选
    var filtered = sorted;
    if (_expFilterType == '买入') {
      filtered = sorted.where((r) => _buyRecs.contains(r.recommendation)).toList();
    } else if (_expFilterType == '观望') {
      filtered = sorted.where((r) => _neutralRecs.contains(r.recommendation)).toList();
    }
    // 再排序
    switch (_expSortBy) {
      case 'score':
        filtered.sort((a, b) => _expSortAsc ? a.score.compareTo(b.score) : b.score.compareTo(a.score));
        break;
      case 'change':
        filtered.sort((a, b) => _expSortAsc ? a.changePct.compareTo(b.changePct) : b.changePct.compareTo(a.changePct));
        break;
      case 'name':
        filtered.sort((a, b) => _expSortAsc ? a.name.compareTo(b.name) : b.name.compareTo(a.name));
        break;
    }
    return filtered;
  }

  // ===== 智能探索：加自选 =====

  Future<void> _toggleWatchlist(ExploreResult item) async {
    final isIn = _watchlistCodes.contains(item.code);
    if (isIn) {
      await _dbService.removeFromWatchlist(item.code);
      setState(() => _watchlistCodes.remove(item.code));
      _showSnack('已从自选移除：${item.name}');
    } else {
      await _dbService.addToWatchlist(item.code, item.name);
      setState(() {
        _watchlistCodes.add(item.code);
        _analysisNeedsRefresh = true;
      });
      _showSnack('已加入自选：${item.name}');
    }
  }

  Future<void> _batchAddToWatchlist() async {
    final notAdded = _exploreResults.where((r) => !_watchlistCodes.contains(r.code)).toList();
    if (notAdded.isEmpty) {
      _showSnack('所有股票已在自选中');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('一键加自选', style: TextStyle(color: Color(0xFFF0F6FC))),
        content: Text('确定将 ${notAdded.length} 只股票加入自选吗？',
            style: const TextStyle(color: Color(0xFF8B949E))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('加入', style: TextStyle(color: Color(0xFF58A6FF))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final items = notAdded.map((r) => WatchlistItem(code: r.code, name: r.name, addedAt: DateTime.now())).toList();
    await _dbService.batchAddToWatchlist(items);
    setState(() {
      _watchlistCodes.addAll(notAdded.map((r) => r.code));
      _analysisNeedsRefresh = true;
    });
    _showSnack('已加入 ${notAdded.length} 只股票到自选');
  }

  // ===== Tab切换同步 =====

  void _onTabChanged(int index) {
    setState(() => _currentTab = index);
    if (index == 0 && _analysisNeedsRefresh) {
      _analysisNeedsRefresh = false;
      _loadOppFromDb();
    }
    if (index == 1) {
      _loadWatchlistCodes();
    }
  }

  // ===== 工具方法 =====

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--';
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showScoringInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('推荐评分逻辑说明', style: TextStyle(color: Color(0xFFF0F6FC), fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoSection('综合评分公式', '总分 = K线评分×50% + 实时行情×30% + 共振评分×20%'),
              const SizedBox(height: 12),
              _infoSection('K线评分（50%）', '由5个维度加权：\n• 信号评分(0-3)：按信号强度加权\n• 趋势评分(0-2)：MA排列+ADX趋势\n• 动量评分(0-2)：RSI区间+BIAS乖离\n• 量价评分(0-1.5)：量比+OBV趋势\n• 波动率评分(0-1.5)：ATR波动率评估'),
              const SizedBox(height: 12),
              _infoSection('实时行情（30%）', '• 涨跌幅：温和上涨加分，超跌反弹加分\n• 资金流向：主力净流入加分\n• 换手率：适度活跃加分，过热减分'),
              const SizedBox(height: 12),
              _infoSection('共振评分（20%）', '10维度多空共振：MA/MACD/RSI/KDJ/BOLL/量价/WR/CCI/背离/缺口'),
              const SizedBox(height: 12),
              _infoSection('推荐等级', '• 9-10分：强烈买入\n• 8分：买入\n• 7分：谨慎买入\n• 5-6分：观望\n• 4分：谨慎卖出\n• 3分：卖出\n• 1-2分：强烈卖出'),
              const SizedBox(height: 12),
              Text('※ 以上分析仅供参考，不构成投资建议',
                  style: TextStyle(color: Colors.orange.withOpacity(0.8), fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: Color(0xFF58A6FF))),
          ),
        ],
      ),
    );
  }

  Widget _infoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, height: 1.5)),
      ],
    );
  }

  // ===== Build =====

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CapsuleTabSwitcher(
          tabs: const ['自选分析', '智能探索'],
          currentIndex: _currentTab,
          onTabChanged: _onTabChanged,
        ),
        Expanded(
          child: _currentTab == 0 ? _buildOppTab() : _buildExpTab(),
        ),
      ],
    );
  }

  // ===== 自选分析Tab =====

  Widget _buildOppTab() {
    if (_opportunities.isEmpty && !_isOppAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: const Color(0xFF58A6FF).withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text('暂无分析数据', style: TextStyle(color: Color(0xFF8B949E), fontSize: 16)),
            const SizedBox(height: 8),
            const Text('点击下方按钮分析自选股', style: TextStyle(color: Color(0xFF30363D), fontSize: 13)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _refreshOppAnalysis,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('开始分析'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF58A6FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    final filtered = _getFilteredOpportunities();

    return Column(
      children: [
        _buildOppStatusBar(),
        _buildOppFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadOppFromDb,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildOppCard(filtered[index]),
            ),
          ),
        ),
        if (_isOppEditMode) _buildOppEditBar(),
        if (!_isOppEditMode) _buildOppBottomBar(),
      ],
    );
  }

  Widget _buildOppStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF161B22),
      child: Row(
        children: [
          if (_isOppAnalyzing) ...[
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF))),
            const SizedBox(width: 8),
            Text('分析中 $_oppCompleted/$_oppTotal',
                style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13)),
          ] else ...[
            const Icon(Icons.access_time, color: Color(0xFF8B949E), size: 14),
            const SizedBox(width: 4),
            Text('分析时间：${_formatTime(_oppLastAnalyzed)}',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
          ],
          const Spacer(),
          Text('共 ${_opportunities.length} 只',
              style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildOppFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF0D1117),
      child: Row(
        children: [
          ...['全部', '看多', '看空', '观望'].map((type) {
            final isSelected = _oppFilterType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _oppFilterType = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF58A6FF).withOpacity(0.2) : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF30363D)),
                  ),
                  child: Text(type, style: TextStyle(
                    color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF8B949E),
                    fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  )),
                ),
              ),
            );
          }),
          const Spacer(),
          if (_opportunities.isNotEmpty) ...[
            GestureDetector(
              onTap: _toggleOppEditMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _isOppEditMode ? const Color(0xFFE74C3C).withOpacity(0.15) : const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _isOppEditMode ? const Color(0xFFE74C3C) : const Color(0xFF30363D)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_isOppEditMode ? Icons.check : Icons.edit, color: _isOppEditMode ? const Color(0xFFE74C3C) : const Color(0xFF8B949E), size: 14),
                  const SizedBox(width: 4),
                  Text(_isOppEditMode ? '完成' : '编辑',
                      style: TextStyle(color: _isOppEditMode ? const Color(0xFFE74C3C) : const Color(0xFF8B949E), fontSize: 12)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _archiveAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bookmark, color: Colors.orange, size: 14),
                  SizedBox(width: 4),
                  Text('一键留档', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _showScoringInfo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF58A6FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.5)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline, color: Color(0xFF58A6FF), size: 14),
                  SizedBox(width: 4),
                  Text('评分说明', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOppCard(OpportunityResult o) {
    return Stack(
      children: [
        StockCard(
          name: o.name,
          code: o.code,
          price: o.price,
          changePct: o.changePct,
          score: o.score,
          recommendation: o.recommendation,
          tags: [
            SignalTag(text: '买${o.buySignalCount}', color: const Color(0xFFE74C3C)),
            SignalTag(text: '卖${o.sellSignalCount}', color: const Color(0xFF2ECC71)),
            SignalTag(text: '战法${o.activeStrategyCount}', color: const Color(0xFFFFC107)),
            SignalTag(text: '共振${o.confluenceScore}/10', color: Colors.cyan),
            SignalTag(text: '风险${o.riskLevel}',
                color: o.riskLevel == '高' ? Colors.red : o.riskLevel == '中高' ? Colors.orange : const Color(0xFF8B949E)),
          ],
          onTap: _isOppEditMode ? null : () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => QuoteScreen(code: o.code, name: o.name),
            ));
          },
        ),
        if (_isOppEditMode)
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Checkbox(
              value: _oppSelectedCodes.contains(o.code),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _oppSelectedCodes.add(o.code);
                  } else {
                    _oppSelectedCodes.remove(o.code);
                  }
                });
              },
              fillColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? const Color(0xFF58A6FF) : const Color(0xFF8B949E)),
            ),
          ),
        if (!_isOppEditMode)
          Positioned(
            right: 4, top: 4,
            child: IconButton(
              onPressed: () => _archiveOpportunity(o),
              icon: const Icon(Icons.bookmark_border, color: Color(0xFF8B949E), size: 18),
              tooltip: '留档',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ),
      ],
    );
  }

  Widget _buildOppEditBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text('已选${_oppSelectedCodes.length}只',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14)),
            const Spacer(),
            TextButton(
              onPressed: _oppSelectedCodes.isEmpty ? null : () {
                final allCodes = _opportunities.map((o) => o.code).toSet();
                setState(() {
                  _oppSelectedCodes = _oppSelectedCodes.length == allCodes.length ? {} : allCodes;
                });
              },
              child: Text(
                _oppSelectedCodes.length == _opportunities.length ? '取消全选' : '全选',
                style: TextStyle(color: _oppSelectedCodes.isEmpty ? const Color(0xFF30363D) : const Color(0xFF8B949E)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _oppSelectedCodes.isEmpty ? null : _deleteSelectedFromWatchlist,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE74C3C),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE74C3C).withOpacity(0.3),
              ),
              child: Text('移出自选(${_oppSelectedCodes.length})'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOppBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isOppAnalyzing ? null : _refreshOppAnalysis,
            icon: _isOppAnalyzing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_isOppAnalyzing ? '分析中 $_oppCompleted/$_oppTotal' : '刷新分析'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A6FF),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF58A6FF).withOpacity(0.4),
              disabledForegroundColor: Colors.white70,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  // ===== 智能探索Tab =====

  Widget _buildExpTab() {
    if (_isExpLoading && _exploreResults.isEmpty) {
      return _buildExpLoadingView();
    }
    if (_exploreResults.isEmpty) {
      return _buildExpEmptyView();
    }
    return _buildExpResultsView();
  }

  Widget _buildExpLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 48, height: 48,
            child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF58A6FF))),
          const SizedBox(height: 24),
          Text(_expStatusText, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 16)),
          if (_expTotalStocks > 0) ...[
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _expTotalStocks > 0 ? _expAnalyzedStocks / _expTotalStocks : null,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF21262D),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF58A6FF)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('已筛选 $_expFoundStocks 只',
                style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13)),
            if (_expCurrentStock.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_expCurrentStock, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildExpEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore, size: 64, color: const Color(0xFF58A6FF).withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text('点击下方按钮开始智能选股', style: TextStyle(color: Color(0xFF8B949E), fontSize: 16)),
          const SizedBox(height: 8),
          const Text('将自动扫描沪深主板优质标的', style: TextStyle(color: Color(0xFF30363D), fontSize: 13)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _startExplore,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('开始探索'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A6FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpResultsView() {
    final sorted = _sortedExploreResults;
    final notAddedCount = _exploreResults.where((r) => !_watchlistCodes.contains(r.code)).length;

    return Column(
      children: [
        _buildExpStatusBar(),
        _buildExpSortBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadExpFromDb,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: sorted.length,
              itemBuilder: (context, index) => _buildExpCard(sorted[index], index),
            ),
          ),
        ),
        _buildExpBottomBar(notAddedCount),
      ],
    );
  }

  Widget _buildExpStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF161B22),
      child: Row(
        children: [
          if (_isExpAnalyzing) ...[
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF))),
            const SizedBox(width: 8),
            Text('分析中 $_expAnalyzedStocks/$_expTotalStocks',
                style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13)),
          ] else ...[
            const Icon(Icons.access_time, color: Color(0xFF8B949E), size: 14),
            const SizedBox(width: 4),
            Text('分析时间：${_formatTime(_expLastAnalyzed)}',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
          ],
          const Spacer(),
          Text('共 ${_exploreResults.length} 只优质标的',
              style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildExpSortBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF0D1117),
      child: Row(
        children: [
          ...['全部', '买入', '观望'].map((type) {
            final isSelected = _expFilterType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _expFilterType = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF58A6FF).withOpacity(0.2) : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF30363D)),
                  ),
                  child: Text(type, style: TextStyle(
                    color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF8B949E),
                    fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  )),
                ),
              ),
            );
          }),
          const Spacer(),
          _buildExpSortChip('评分', 'score'),
          const SizedBox(width: 6),
          _buildExpSortChip('涨幅', 'change'),
          const SizedBox(width: 6),
          _buildExpSortChip('名称', 'name'),
        ],
      ),
    );
  }

  Widget _buildExpSortChip(String label, String key) {
    final isActive = _expSortBy == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_expSortBy == key) {
            _expSortAsc = !_expSortAsc;
          } else {
            _expSortBy = key;
            _expSortAsc = false;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF58A6FF).withOpacity(0.2) : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? const Color(0xFF58A6FF).withOpacity(0.5) : const Color(0xFF30363D)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            color: isActive ? const Color(0xFF58A6FF) : const Color(0xFF8B949E),
            fontSize: 12, fontWeight: FontWeight.w600,
          )),
          if (isActive) ...[
            const SizedBox(width: 2),
            Icon(_expSortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                color: const Color(0xFF58A6FF), size: 12),
          ],
        ]),
      ),
    );
  }

  Widget _buildExpCard(ExploreResult item, int index) {
    final isIn = _watchlistCodes.contains(item.code);
    return StockCard(
      name: item.name,
      code: item.code,
      price: item.price,
      changePct: item.changePct,
      pe: item.pe,
      pb: item.pb,
      score: item.score,
      recommendation: item.recommendation,
      rank: index + 1,
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => QuoteScreen(code: item.code, name: item.name),
        ));
      },
      actions: [
        GestureDetector(
          onTap: () => _toggleWatchlist(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isIn ? const Color(0xFF58A6FF).withOpacity(0.15) : const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isIn ? const Color(0xFF58A6FF).withOpacity(0.5) : const Color(0xFF30363D)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isIn ? Icons.star : Icons.star_outline,
                  color: isIn ? const Color(0xFF58A6FF) : const Color(0xFF8B949E), size: 14),
              const SizedBox(width: 4),
              Text(isIn ? '已加自选' : '加自选',
                  style: TextStyle(color: isIn ? const Color(0xFF58A6FF) : const Color(0xFF8B949E), fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(
              builder: (context) => QuoteScreen(code: item.code, name: item.name),
            ));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.visibility, color: Color(0xFF8B949E), size: 14),
              SizedBox(width: 4),
              Text('查看详情', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildExpBottomBar(int notAddedCount) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isExpAnalyzing ? null : _startExplore,
                  icon: _isExpAnalyzing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isExpAnalyzing ? '分析中...' : '开始智能选股'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF58A6FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF58A6FF).withOpacity(0.4),
                    disabledForegroundColor: Colors.white70,
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            if (notAddedCount > 0 && !_isExpAnalyzing) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _batchAddToWatchlist,
                  icon: const Icon(Icons.star, size: 18),
                  label: Text('一键加自选($notAddedCount)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证文件创建成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/screens/discover_screen.dart`
Expected: No issues found

---

### Task 4: 重构自选界面（WatchlistScreen）

**Files:**
- Modify: `lib/screens/watchlist_screen.dart`

- [ ] **Step 1: 重写WatchlistScreen**

全面升级为卡片式布局，支持左滑删除、长按编辑、实时行情刷新、筛选排序。

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/stock_card.dart';
import 'quote_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> with WidgetsBindingObserver {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();

  List<WatchlistItem> _watchlist = [];
  List<QuoteData> _quotes = [];
  bool _isLoading = true;

  // 排序
  String _sortBy = 'default'; // default, change_pct, score, name
  bool _sortAscending = false;

  // 筛选
  String _filterType = '全部'; // 全部, 看多, 看空, 观望

  // 编辑模式
  bool _isEditMode = false;
  Set<String> _selectedCodes = {};

  // 实时刷新
  Timer? _refreshTimer;

  static const _buyRecs = ['强烈买入', '买入', '谨慎买入'];
  static const _sellRecs = ['卖出', '强烈卖出', '谨慎卖出'];
  static const _neutralRecs = ['观望'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWatchlist();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshQuotes();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshQuotes();
    });
  }

  Future<void> _loadWatchlist() async {
    setState(() => _isLoading = true);
    try {
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isEmpty) {
        setState(() { _watchlist = watchlist; _quotes = []; });
      } else {
        final codes = watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
        final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
        final results = await Future.wait(futures);
        final quotes = results.where((q) => q != null).cast<QuoteData>().toList();
        setState(() { _watchlist = watchlist; _quotes = quotes; });
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _refreshQuotes() async {
    if (_watchlist.isEmpty) return;
    try {
      final codes = _watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
      final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
      final results = await Future.wait(futures);
      final quotes = results.where((q) => q != null).cast<QuoteData>().toList();
      if (mounted) setState(() => _quotes = quotes);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _getFilteredAndSorted() {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _watchlist.length; i++) {
      final item = _watchlist[i];
      final codeWithPrefix = _apiClient.addMarketPrefix(item.code);
      final quote = _quotes.firstWhere(
        (q) => q.code == codeWithPrefix,
        orElse: () => QuoteData.empty(),
      );
      items.add({'item': item, 'quote': quote, 'codeWithPrefix': codeWithPrefix});
    }

    // 筛选（基于涨跌幅简单判断，无分析结果时显示全部）
    var filtered = items;
    if (_filterType == '看多') {
      filtered = items.where((d) => (d['quote'] as QuoteData).changePct > 0).toList();
    } else if (_filterType == '看空') {
      filtered = items.where((d) => (d['quote'] as QuoteData).changePct < 0).toList();
    } else if (_filterType == '观望') {
      filtered = items.where((d) => (d['quote'] as QuoteData).changePct == 0).toList();
    }

    // 排序
    switch (_sortBy) {
      case 'change_pct':
        filtered.sort((a, b) => _sortAscending
            ? (a['quote'] as QuoteData).changePct.compareTo((b['quote'] as QuoteData).changePct)
            : (b['quote'] as QuoteData).changePct.compareTo((a['quote'] as QuoteData).changePct));
        break;
      case 'name':
        filtered.sort((a, b) => _sortAscending
            ? (a['item'] as WatchlistItem).name.compareTo((b['item'] as WatchlistItem).name)
            : (b['item'] as WatchlistItem).name.compareTo((a['item'] as WatchlistItem).name));
        break;
      case 'default':
      default:
        break;
    }
    return filtered;
  }

  void _removeFromWatchlist(String code) async {
    await _dbService.removeFromWatchlist(code);
    _loadWatchlist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从自选股移除')),
      );
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) _selectedCodes.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedCodes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('确认删除', style: TextStyle(color: Color(0xFFF0F6FC))),
        content: Text('确定要删除选中的${_selectedCodes.length}只股票吗？',
            style: const TextStyle(color: Color(0xFF8B949E))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dbService.batchRemoveFromWatchlist(_selectedCodes.toList());
      setState(() { _isEditMode = false; _selectedCodes.clear(); });
      _loadWatchlist();
    }
  }

  void _searchAndAddStock(String keyword) async {
    if (keyword.isEmpty) return;
    final results = await _apiClient.searchStocks(keyword);
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到该股票')));
      return;
    }
    if (results.length == 1) {
      final stock = results.first;
      await _dbService.addToWatchlist(stock.code, stock.name);
      _loadWatchlist();
      _searchController.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加 ${stock.name} 到自选股')));
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('选择股票', style: TextStyle(color: Color(0xFFF0F6FC))),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final stock = results[index];
                return ListTile(
                  title: Text(stock.name, style: const TextStyle(color: Color(0xFFF0F6FC))),
                  subtitle: Text(stock.code, style: const TextStyle(color: Color(0xFF8B949E))),
                  onTap: () async {
                    await _dbService.addToWatchlist(stock.code, stock.name);
                    Navigator.pop(context);
                    _loadWatchlist();
                    _searchController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已添加 ${stock.name} 到自选股')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ],
        ),
      );
    }
  }

  void _addAlert(String code, String name) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController priceController = TextEditingController();
        String conditionType = 'price_above';
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: Text('添加预警: $name', style: const TextStyle(color: Color(0xFFF0F6FC))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: conditionType,
                items: const [
                  DropdownMenuItem(value: 'price_above', child: Text('价格高于')),
                  DropdownMenuItem(value: 'price_below', child: Text('价格低于')),
                  DropdownMenuItem(value: 'change_above', child: Text('涨幅超过')),
                  DropdownMenuItem(value: 'change_below', child: Text('跌幅超过')),
                ],
                onChanged: (value) => conditionType = value!,
                dropdownColor: const Color(0xFF161B22),
                style: const TextStyle(color: Color(0xFFF0F6FC)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '预警值',
                  filled: true,
                  fillColor: Color(0xFF21262D),
                ),
                style: const TextStyle(color: Color(0xFFF0F6FC)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                final threshold = double.tryParse(priceController.text);
                if (threshold != null) {
                  await _dbService.addAlert(AlertRule(
                    code: code, name: name, conditionType: conditionType,
                    thresholdValue: threshold, enabled: true,
                  ));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('预警已添加')));
                }
              },
              child: const Text('确认', style: TextStyle(color: Color(0xFF58A6FF))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF58A6FF)));
    }

    final items = _getFilteredAndSorted();

    return Column(
      children: [
        // 搜索栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0D1117),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Color(0xFFF0F6FC)),
                  decoration: InputDecoration(
                    hintText: '搜索股票名称或代码',
                    hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF8B949E)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF58A6FF)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                  ),
                  onSubmitted: _searchAndAddStock,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _searchAndAddStock(_searchController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF58A6FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text('添加'),
              ),
            ],
          ),
        ),
        // 筛选/排序栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0D1117),
          child: Row(
            children: [
              Text('共 ${_watchlist.length} 只',
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
              const SizedBox(width: 8),
              ...['全部', '看多', '看空', '观望'].map((type) {
                final isSelected = _filterType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterType = type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF58A6FF).withOpacity(0.2) : const Color(0xFF21262D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF30363D)),
                      ),
                      child: Text(type, style: TextStyle(
                        color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF8B949E),
                        fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                  ),
                );
              }),
              const Spacer(),
              // 排序按钮
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_sortBy == 'change_pct') {
                      _sortAscending = !_sortAscending;
                    } else {
                      _sortBy = 'change_pct';
                      _sortAscending = false;
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _sortBy == 'change_pct' ? const Color(0xFF58A6FF).withOpacity(0.2) : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _sortBy == 'change_pct' ? const Color(0xFF58A6FF) : const Color(0xFF30363D)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sort, size: 14,
                        color: _sortBy == 'change_pct' ? const Color(0xFF58A6FF) : const Color(0xFF8B949E)),
                    const SizedBox(width: 4),
                    Text(_sortBy == 'change_pct' ? '涨跌幅' : '排序',
                        style: TextStyle(fontSize: 11,
                            color: _sortBy == 'change_pct' ? const Color(0xFF58A6FF) : const Color(0xFF8B949E))),
                    if (_sortBy == 'change_pct') ...[
                      const SizedBox(width: 2),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 12, color: const Color(0xFF58A6FF)),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: _watchlist.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_outline, size: 64, color: const Color(0xFF58A6FF).withOpacity(0.2)),
                      const SizedBox(height: 16),
                      const Text('暂无自选股', style: TextStyle(color: Color(0xFF8B949E), fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('在上方搜索框输入股票名称或代码添加', style: TextStyle(color: Color(0xFF30363D), fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWatchlist,
                  color: const Color(0xFF58A6FF),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final data = items[index];
                      final item = data['item'] as WatchlistItem;
                      final quote = data['quote'] as QuoteData;
                      final codeWithPrefix = data['codeWithPrefix'] as String;

                      if (_isEditMode) {
                        return _buildEditCard(item, quote, codeWithPrefix);
                      } else {
                        return _buildSwipeCard(item, quote, codeWithPrefix);
                      }
                    },
                  ),
                ),
        ),
        // 编辑模式底部栏
        if (_isEditMode) _buildEditBar(),
      ],
    );
  }

  Widget _buildSwipeCard(WatchlistItem item, QuoteData quote, String codeWithPrefix) {
    return Dismissible(
      key: Key(item.code),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text('移出自选', style: TextStyle(color: Color(0xFFF0F6FC))),
            content: Text('确定将 ${item.name} 移出自选吗？',
                style: const TextStyle(color: Color(0xFF8B949E))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移出', style: TextStyle(color: Color(0xFFE74C3C))),
              ),
            ],
          ),
        );
        return confirmed == true;
      },
      onDismissed: (_) => _removeFromWatchlist(item.code),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE74C3C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: StockCard(
        name: item.name,
        code: item.code.substring(2),
        price: quote.price,
        changePct: quote.changePct,
        pe: quote.pe > 0 ? quote.pe : null,
        pb: quote.pb > 0 ? quote.pb : null,
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (context) => QuoteScreen(code: codeWithPrefix, name: item.name),
        )),
        onLongPress: _toggleEditMode,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            onPressed: () => _addAlert(codeWithPrefix, item.name),
            icon: const Icon(Icons.add_alert, color: Color(0xFF58A6FF), size: 20),
            tooltip: '添加预警',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ]),
      ),
    );
  }

  Widget _buildEditCard(WatchlistItem item, QuoteData quote, String codeWithPrefix) {
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
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF58A6FF) : const Color(0xFF30363D),
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedCodes.add(item.code);
                  } else {
                    _selectedCodes.remove(item.code);
                  }
                });
              },
              fillColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? const Color(0xFF58A6FF) : const Color(0xFF8B949E)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(item.code.substring(2), style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(quote.price.toStringAsFixed(2),
                    style: TextStyle(
                      color: quote.changePct >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
                      fontSize: 20, fontWeight: FontWeight.bold,
                    )),
                Text(
                  '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: quote.changePct >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text('已选${_selectedCodes.length}只',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14)),
            const Spacer(),
            TextButton(
              onPressed: _selectedCodes.isEmpty ? null : () {
                final allCodes = _watchlist.map((w) => w.code).toSet();
                setState(() {
                  _selectedCodes = _selectedCodes.length == allCodes.length ? {} : allCodes;
                });
              },
              child: Text(
                _selectedCodes.length == _watchlist.length ? '取消全选' : '全选',
                style: TextStyle(color: _selectedCodes.isEmpty ? const Color(0xFF30363D) : const Color(0xFF8B949E)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _selectedCodes.isEmpty ? null : _deleteSelected,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE74C3C),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE74C3C).withOpacity(0.3),
              ),
              child: Text('删除选中(${_selectedCodes.length})'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证文件修改成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/screens/watchlist_screen.dart`
Expected: No issues found

---

### Task 5: 更新main.dart - 导航5Tab + 新主题色

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 修改main.dart**

主要变更：
1. 删除OpportunityScreen和ExploreScreen的import
2. 新增DiscoverScreen的import
3. 底部导航从6个改为5个
4. 更新主题色彩为新色系
5. 更新AppBar actions（探索Tab的帮助按钮移到DiscoverScreen内部）

```dart
import 'package:flutter/material.dart';
import 'package:stock_analyzer/core/navigator_key.dart';
import 'package:stock_analyzer/screens/home_screen.dart';
import 'package:stock_analyzer/screens/watchlist_screen.dart';
import 'package:stock_analyzer/screens/news_screen.dart';
import 'package:stock_analyzer/screens/discover_screen.dart';
import 'package:stock_analyzer/screens/archive_screen.dart';
import 'package:stock_analyzer/screens/alerts_screen.dart';
import 'package:stock_analyzer/screens/update_log_screen.dart';
import 'package:stock_analyzer/services/notification_service.dart';

const String appVersion = 'v2.20.0';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  await notificationService.init();
  if (await notificationService.isEnabled()) {
    notificationService.startPolling();
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (index == 0) {
      _homeKey.currentState?.onTabVisible();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(key: _homeKey),
      const WatchlistScreen(),
      const DiscoverScreen(),
      const NewsScreen(),
      const ArchiveScreen(),
    ];

    final titles = [
      '首页',
      '自选',
      '发现',
      '资讯',
      '留档',
    ];

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '股票分析助手',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          elevation: 0,
          titleTextStyle: TextStyle(color: Color(0xFFF0F6FC), fontSize: 18, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Color(0xFFF0F6FC)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF0D1117),
          selectedItemColor: Color(0xFF58A6FF),
          unselectedItemColor: Color(0xFF8B949E),
          type: BottomNavigationBarType.fixed,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF0F6FC)),
          bodyMedium: TextStyle(color: Color(0xFFF0F6FC)),
          titleLarge: TextStyle(color: Color(0xFFF0F6FC)),
          titleMedium: TextStyle(color: Color(0xFFF0F6FC)),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF161B22),
          contentTextStyle: TextStyle(color: Color(0xFFF0F6FC)),
        ),
      ),
      home: Builder(builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(titles[_currentIndex]),
          actions: _currentIndex == 0
            ? [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AlertsScreen()),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const UpdateLogScreen()),
                      );
                    },
                  ),
                ]
            : null,
        ),
        body: pages[_currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.star),
              label: '自选',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: '发现',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.article),
              label: '资讯',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bookmark),
              label: '留档',
            ),
          ],
        ),
      )),
    );
  }
}
```

- [ ] **Step 2: 验证修改成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/main.dart`
Expected: No issues found

---

### Task 6: 更新首页主题色

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: 更新HomeScreen中的硬编码颜色**

将所有旧色值替换为新色值：
- `0xFF1a1a2e` → `0xFF0D1117`（背景）
- `0xFF16213e` → `0xFF161B22`（卡片）
- `0xFF0f3460` → `0xFF161B22`（AppBar/状态栏）
- `Colors.orange` → `Color(0xFF58A6FF)`（强调色，部分保留orange用于留档/精选等特殊按钮）
- `Colors.blue` → `Color(0xFF58A6FF)`

由于home_screen.dart较长，主要修改颜色常量。使用全局搜索替换：
- `const Color(0xFF1a1a2e)` → `const Color(0xFF0D1117)`
- `const Color(0xFF16213e)` → `const Color(0xFF161B22)`
- `const Color(0xFF0f3460)` → `const Color(0xFF161B22)`

- [ ] **Step 2: 验证修改成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/screens/home_screen.dart`
Expected: No issues found

---

### Task 7: 更新版本号和更新日志

**Files:**
- Modify: `lib/core/app_version.dart`
- Modify: `lib/screens/update_log_screen.dart`

- [ ] **Step 1: 更新app_version.dart**

将版本号从 `2.19.2` 改为 `2.20.0`：

```dart
class AppVersion {
  static const String version = '2.20.0';
  static const String buildNumber = '1';
}
```

- [ ] **Step 2: 在update_log_screen.dart的updates列表最前面添加v2.20.0条目**

```dart
{
  'version': 'v2.20.0',
  'date': '2026-06-14',
  'changes': [
    '融合机会与探索界面为"发现"页面，顶部Tab切换自选分析/智能探索',
    '自选分析Tab新增编辑模式，可多选后批量移出自选',
    '智能探索Tab新增"一键加自选"按钮，批量添加优质标的',
    '自选界面全面升级：卡片式布局、左滑删除、长按编辑、实时行情刷新',
    '整体UI重新设计：现代简约风格，新色彩体系，胶囊Tab切换器',
    '底部导航从6个Tab精简为5个（首页/自选/发现/资讯/留档）',
  ],
},
```

- [ ] **Step 3: 验证修改成功**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze lib/core/app_version.dart lib/screens/update_log_screen.dart`
Expected: No issues found

---

### Task 8: 删除旧页面文件

**Files:**
- Delete: `lib/screens/opportunity_screen.dart`
- Delete: `lib/screens/explore_screen.dart`

- [ ] **Step 1: 删除opportunity_screen.dart**

Run: 删除 `d:\MyProjects\stock\mobile\lib\screens\opportunity_screen.dart`

- [ ] **Step 2: 删除explore_screen.dart**

Run: 删除 `d:\MyProjects\stock\mobile\lib\screens\explore_screen.dart`

- [ ] **Step 3: 确认没有其他文件引用已删除的页面**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze`
Expected: No issues found（main.dart已不再import这两个文件）

---

### Task 9: 全局主题色一致性检查

**Files:**
- Modify: 所有仍使用旧色值的文件

- [ ] **Step 1: 搜索所有Dart文件中的旧色值**

搜索以下旧色值，确保所有文件都已更新：
- `0xFF1a1a2e` → `0xFF0D1117`
- `0xFF16213e` → `0xFF161B22`
- `0xFF0f3460` → `0xFF161B22`

需要检查的文件（除已处理的main.dart/home_screen.dart/watchlist_screen.dart/discover_screen.dart外）：
- `lib/screens/news_screen.dart`
- `lib/screens/archive_screen.dart`
- `lib/screens/quote_screen.dart`
- `lib/screens/sector_screen.dart`
- `lib/screens/alerts_screen.dart`
- `lib/screens/update_log_screen.dart`
- 其他可能使用硬编码颜色的文件

- [ ] **Step 2: 逐文件替换旧色值**

对每个包含旧色值的文件，执行颜色替换。

- [ ] **Step 3: 验证所有文件无分析错误**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze`
Expected: No issues found

---

### Task 10: 编译验证

- [ ] **Step 1: 运行flutter analyze确认无错误**

Run: `cd d:\MyProjects\stock\mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 2: 编译APK验证**

Run: `cd d:\MyProjects\stock\mobile && flutter build apk --release`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: 复制APK到项目根目录**

Run: `copy build\app\outputs\flutter-apk\app-release.apk ..\..\stock-analyzer-v2.20.0.apk`
Expected: 文件复制成功

---

### Task 11: 提交Git

- [ ] **Step 1: 查看所有变更**

Run: `git status`
Run: `git diff --stat`

- [ ] **Step 2: 提交所有变更**

```bash
git add lib/widgets/capsule_tab_switcher.dart lib/widgets/stock_card.dart lib/screens/discover_screen.dart lib/screens/watchlist_screen.dart lib/main.dart lib/screens/home_screen.dart lib/core/app_version.dart lib/screens/update_log_screen.dart
git rm lib/screens/opportunity_screen.dart lib/screens/explore_screen.dart
git commit -m "feat: v2.20.0 - UI重构(发现页面融合+自选升级+现代简约风格)"
```

- [ ] **Step 3: 验证提交成功**

Run: `git log --oneline -3`
Expected: 看到新的commit

---

## Self-Review Checklist

**1. Spec coverage:**
- 导航6→5Tab: Task 5 ✓
- 发现页面融合(自选分析+智能探索): Task 3 ✓
- 自选分析编辑模式(批量移出自选): Task 3 ✓
- 智能探索一键加自选: Task 3 ✓
- 自选界面卡片式布局: Task 4 ✓
- 左滑删除: Task 4 ✓
- 长按编辑: Task 4 ✓
- 实时行情刷新(30s): Task 4 ✓
- 筛选排序增强: Task 4 ✓
- 新色彩体系: Task 5, 6, 9 ✓
- 胶囊Tab切换器: Task 1 ✓
- 版本号+更新日志: Task 7 ✓
- 删除旧文件: Task 8 ✓
- 编译验证: Task 10 ✓
- Git提交: Task 11 ✓

**2. Placeholder scan:** 无TBD/TODO/待实现占位符 ✓

**3. Type consistency:** 所有组件接口一致（StockCard参数、CapsuleTabSwitcher参数） ✓
