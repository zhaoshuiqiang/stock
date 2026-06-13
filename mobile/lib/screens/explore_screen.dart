import 'package:flutter/material.dart';
import '../analysis/explore_engine.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'quote_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final DatabaseService _dbService = DatabaseService();
  ExploreEngine? _engine;
  List<ExploreResult> _results = [];
  bool _isLoading = false;
  bool _isAnalyzing = false;
  String _statusText = '';
  int _totalStocks = 0;
  int _analyzedStocks = 0;
  int _foundStocks = 0;
  String _currentStock = '';
  DateTime? _lastAnalyzed;
  String _sortBy = 'score';
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    _loadFromDb();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _loadFromDb() async {
    final results = await _dbService.getExploreResults();
    final lastTime = await _dbService.getExploreLastTime();
    if (mounted) {
      setState(() {
        _results = results;
        _lastAnalyzed = lastTime;
      });
    }
  }

  List<ExploreResult> get _sortedResults {
    final sorted = List<ExploreResult>.from(_results);
    switch (_sortBy) {
      case 'score':
        sorted.sort((a, b) => _sortAsc
            ? a.score.compareTo(b.score)
            : b.score.compareTo(a.score));
        break;
      case 'change':
        sorted.sort((a, b) => _sortAsc
            ? a.changePct.compareTo(b.changePct)
            : b.changePct.compareTo(a.changePct));
        break;
      case 'name':
        sorted.sort((a, b) => _sortAsc
            ? a.name.compareTo(b.name)
            : b.name.compareTo(a.name));
        break;
    }
    return sorted;
  }

  Future<void> _startExplore() async {
    if (_isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _isLoading = true;
      _statusText = '正在获取板块数据...';
      _totalStocks = 0;
      _analyzedStocks = 0;
      _foundStocks = 0;
      _currentStock = '';
    });

    _engine = ExploreEngine();
    final stream = _engine!.explore();

    await for (final progress in stream) {
      if (!mounted) break;

      switch (progress.status) {
        case ExploreStatus.fetchingSectors:
          setState(() => _statusText = '正在获取热门板块...');
          break;
        case ExploreStatus.fetchingStocks:
          setState(() {
            _statusText = '正在获取板块成分股...';
            _totalStocks = progress.totalStocks;
          });
          break;
        case ExploreStatus.analyzing:
          setState(() {
            _statusText = '正在分析 $_analyzedStocks/$_totalStocks';
            _totalStocks = progress.totalStocks;
            _analyzedStocks = progress.analyzedStocks;
            _foundStocks = progress.foundStocks;
            _currentStock = progress.currentStock ?? _currentStock;
          });
          break;
        case ExploreStatus.saving:
          setState(() => _statusText = '保存分析结果...');
          break;
        case ExploreStatus.complete:
          _results = progress.results ?? [];
          _lastAnalyzed = DateTime.now();
          setState(() {
            _isAnalyzing = false;
            _isLoading = false;
            _statusText = '';
            _totalStocks = progress.totalStocks;
            _analyzedStocks = progress.analyzedStocks;
            _foundStocks = progress.foundStocks;
          });
          break;
        case ExploreStatus.error:
          setState(() {
            _isAnalyzing = false;
            _isLoading = _results.isEmpty;
            _statusText = progress.message ?? '分析失败';
          });
          if (mounted && progress.message != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(progress.message!)),
            );
          }
          break;
        case ExploreStatus.alreadyRunning:
          break;
        case ExploreStatus.idle:
          break;
      }
    }
  }

  Future<void> _toggleWatchlist(ExploreResult item) async {
    final isIn = await _dbService.isInWatchlist(item.code);
    if (isIn) {
      await _dbService.removeFromWatchlist(item.code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从自选移除：${item.name}')),
        );
      }
    } else {
      await _dbService.addToWatchlist(item.code, item.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入自选：${item.name}')),
        );
      }
    }
    // 刷新结果以更新自选状态
    await _loadFromDb();
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Color _recColor(String recommendation) {
    if (recommendation.contains('强烈')) return const Color(0xFFef5350);
    if (recommendation.contains('买入')) return Colors.orange;
    return const Color(0xFF26a69a);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading && _results.isEmpty
          ? _buildLoadingView()
          : _results.isEmpty
              ? _buildEmptyView()
              : _buildResultsView(),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            _statusText,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          if (_totalStocks > 0) ...[
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _totalStocks > 0 ? _analyzedStocks / _totalStocks : null,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已筛选 $_foundStocks 只',
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
            if (_currentStock.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _currentStock,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text(
            '点击下方按钮开始智能选股',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            '将自动扫描沪深主板优质标的',
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _startExplore,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('开始探索'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    final sorted = _sortedResults;

    return Column(
      children: [
        // 状态栏
        _buildStatusBar(),
        // 排序栏
        _buildSortBar(),
        // 结果列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadFromDb();
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                return _buildResultCard(sorted[index], index);
              },
            ),
          ),
        ),
        // 底部操作栏
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF0f3460),
      child: Row(
        children: [
          if (_isAnalyzing) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
            ),
            const SizedBox(width: 8),
            Text(
              '分析中 $_analyzedStocks/$_totalStocks',
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ] else ...[
            const Icon(Icons.access_time, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text(
              '分析时间：${_formatTime(_lastAnalyzed)}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
          const Spacer(),
          Text(
            '共 ${_results.length} 只优质标的',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF16213e),
      child: Row(
        children: [
          _buildSortChip('评分', 'score'),
          const SizedBox(width: 8),
          _buildSortChip('涨幅', 'change'),
          const SizedBox(width: 8),
          _buildSortChip('名称', 'name'),
          const Spacer(),
          if (!_isAnalyzing)
            GestureDetector(
              onTap: _startExplore,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: Colors.orange, size: 14),
                    SizedBox(width: 4),
                    Text('刷新', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, String key) {
    final isActive = _sortBy == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_sortBy == key) {
            _sortAsc = !_sortAsc;
          } else {
            _sortBy = key;
            _sortAsc = false;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.orange.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? Colors.orange.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: isActive ? Colors.orange : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.orange, size: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ExploreResult item, int index) {
    final recColor = _recColor(item.recommendation);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuoteScreen(code: item.code, name: item.name),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0f3460),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: recColor.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 排名
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index < 3 ? Colors.orange.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: index < 3 ? Colors.orange : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 名称和代码
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.code,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // 推荐标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: recColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.recommendation,
                    style: TextStyle(color: recColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 价格和评分信息
            Row(
              children: [
                // 价格
                Text(
                  item.price > 0 ? '¥${item.price.toStringAsFixed(2)}' : '--',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                // 涨跌幅
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.changePct >= 0
                        ? const Color(0xFFef5350).withOpacity(0.15)
                        : const Color(0xFF26a69a).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${item.changePct >= 0 ? '+' : ''}${item.changePct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: item.changePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                // PE/PB
                if (item.pe > 0)
                  Text(
                    'PE:${item.pe.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                if (item.pe > 0 && item.pb > 0) const SizedBox(width: 8),
                if (item.pb > 0)
                  Text(
                    'PB:${item.pb.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                const SizedBox(width: 12),
                // 评分
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${item.score}分',
                    style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 操作按钮
            Row(
              children: [
                _buildActionButton(
                  icon: Icons.star_outline,
                  label: '加自选',
                  onTap: () => _toggleWatchlist(item),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.visibility,
                  label: '查看详情',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QuoteScreen(code: item.code, name: item.name),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing ? null : _startExplore,
            icon: _isAnalyzing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_isAnalyzing ? '分析中...' : '开始智能选股'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.orange.withOpacity(0.4),
              disabledForegroundColor: Colors.white70,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}