import 'dart:async';
import 'package:flutter/material.dart';
import '../analysis/opportunity_engine.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'quote_screen.dart';

class OpportunityScreen extends StatefulWidget {
  const OpportunityScreen({super.key});

  @override
  State<OpportunityScreen> createState() => _OpportunityScreenState();
}

class _OpportunityScreenState extends State<OpportunityScreen> {
  final DatabaseService _dbService = DatabaseService();
  final OpportunityEngine _engine = OpportunityEngine.instance;
  StreamSubscription<OpportunityProgress>? _subscription;
  List<OpportunityResult> _opportunities = [];
  static const _buyRecommendations = ['强烈买入', '买入', '谨慎买入'];
  static const _sellRecommendations = ['卖出', '强烈卖出', '谨慎卖出'];
  static const _neutralRecommendations = ['观望'];

  String _filterType = '全部';
  bool _isAnalyzing = false;
  int _completedCount = 0;
  int _totalCount = 0;
  DateTime? _lastAnalyzed;

  @override
  void initState() {
    super.initState();
    _loadFromDb();
    // 如果引擎正在运行，订阅进度流并恢复状态
    if (_engine.isRunning) {
      _subscribeToProgress();
      _restoreProgress();
    }
  }

  @override
  void dispose() {
    // 不取消订阅，让引擎继续后台运行
    _subscription?.pause();
    super.dispose();
  }

  void _subscribeToProgress() {
    _subscription?.cancel();
    _subscription = _engine.progressStream.listen(_onProgress);
  }

  /// 从 latestProgress 恢复状态
  void _restoreProgress() {
    final lp = _engine.latestProgress;
    if (lp == null) return;
    setState(() {
      _isAnalyzing = true;
      _completedCount = lp.completedCount;
      _totalCount = lp.totalCount;
    });
  }

  void _onProgress(OpportunityProgress progress) {
    if (!mounted) return; // 仅跳过setState，不取消订阅
    switch (progress.status) {
      case OpportunityStatus.fetching:
        setState(() {
          _isAnalyzing = true;
        });
        break;
      case OpportunityStatus.analyzing:
        setState(() {
          _isAnalyzing = true;
          _completedCount = progress.completedCount;
          _totalCount = progress.totalCount;
        });
        break;
      case OpportunityStatus.saving:
        break;
      case OpportunityStatus.complete:
        _opportunities = progress.results ?? [];
        _lastAnalyzed = DateTime.now();
        setState(() {
          _isAnalyzing = false;
          _completedCount = progress.totalCount;
          _totalCount = progress.totalCount;
        });
        break;
      case OpportunityStatus.error:
        setState(() {
          _isAnalyzing = false;
        });
        if (progress.message != null) {
          _showSnack(progress.message!);
        }
        break;
      case OpportunityStatus.alreadyRunning:
      case OpportunityStatus.idle:
        break;
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Future<void> _loadFromDb() async {
    final results = await _dbService.getOpportunityResults();
    final lastTime = await _dbService.getOpportunityLastTime();
    if (mounted) {
      setState(() {
        _opportunities = results.map((r) => OpportunityResult.fromMap(r)).toList();
        _lastAnalyzed = lastTime;
      });
    }
  }

  Future<void> _refreshAnalysis() async {
    if (_isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _completedCount = 0;
    });

    _subscribeToProgress();
    // 引擎独立运行，不await
    _engine.analyze();
  }

  Future<void> _archiveOpportunity(OpportunityResult o) async {
    final record = ArchiveRecord(
      code: o.code,
      name: o.name,
      price: o.price,
      changePct: o.changePct,
      score: o.score,
      recommendation: o.recommendation,
      riskLevel: o.riskLevel,
      buySignalCount: o.buySignalCount,
      sellSignalCount: o.sellSignalCount,
      activeStrategyCount: o.activeStrategyCount,
      confluenceScore: o.confluenceScore,
      tradeLevelsJson: o.tradeLevels != null ? _encodeTradeLevels(o.tradeLevels!) : null,
      topSignals: o.topSignals.join('  '),
      archivedAt: DateTime.now(),
    );
    await _dbService.addArchive(record);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${o.name} 已留档')),
      );
    }
  }

  String _encodeTradeLevels(Map<String, dynamic> tradeLevels) {
    // 简单JSON编码
    final parts = tradeLevels.entries.map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}');
    return '{${parts.join(',')}}';
  }

  Future<void> _archiveAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('一键留档', style: TextStyle(color: Colors.white)),
        content: Text('确定将 ${_opportunities.length} 条推荐全部留档吗？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (confirmed != true) return;

    int successCount = 0;
    for (final o in _opportunities) {
      try {
        await _archiveOpportunity(o);
        successCount++;
      } catch (e) {
        // ignore
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已留档 $successCount/${_opportunities.length} 条')),
      );
    }
  }

  List<OpportunityResult> _getFilteredOpportunities() {
    switch (_filterType) {
      case '买入':
        return _opportunities.where((o) => _buyRecommendations.contains(o.recommendation)).toList();
      case '卖出':
        return _opportunities.where((o) => _sellRecommendations.contains(o.recommendation)).toList();
      case '观望':
        return _opportunities.where((o) => _neutralRecommendations.contains(o.recommendation)).toList();
      default:
        return _opportunities;
    }
  }

  void _showScoringInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('推荐评分逻辑说明', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoSection('综合评分公式', '总分 = K线评分×50% + 实时行情×30% + 共振评分×20%'),
              const SizedBox(height: 12),
              _buildInfoSection('K线评分（50%）', '由5个维度加权：\n• 信号评分(0-3)：按信号强度加权\n• 趋势评分(0-2)：MA排列+ADX趋势\n• 动量评分(0-2)：RSI区间+BIAS乖离\n• 量价评分(0-1.5)：量比+OBV趋势\n• 波动率评分(0-1.5)：ATR波动率评估'),
              const SizedBox(height: 12),
              _buildInfoSection('实时行情（30%）', '• 涨跌幅：温和上涨加分，超跌反弹加分\n• 资金流向：主力净流入加分\n• 换手率：适度活跃加分，过热减分'),
              const SizedBox(height: 12),
              _buildInfoSection('共振评分（20%）', '10维度多空共振：MA/MACD/RSI/KDJ/BOLL/量价/WR/CCI/背离/缺口\n看多维度越多，共振加分越高'),
              const SizedBox(height: 12),
              _buildInfoSection('ADX权重调整', '• ADX>25趋势市：趋势信号权重×1.2\n• ADX<20盘整市：震荡信号权重×1.2'),
              const SizedBox(height: 12),
              _buildInfoSection('推荐等级', '• 9-10分：强烈买入\n• 8分：买入\n• 7分：谨慎买入\n• 5-6分：观望\n• 4分：谨慎卖出\n• 3分：卖出\n• 1-2分：强烈卖出'),
              const SizedBox(height: 12),
              Text('※ 以上分析基于历史数据和技术指标，仅供参考，不构成投资建议', style: TextStyle(color: Colors.orange.withOpacity(0.8), fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
      ],
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--';
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    if (_opportunities.isEmpty && !_isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              '暂无分析数据',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击下方按钮分析自选股',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _refreshAnalysis,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('开始分析'),
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

    final filtered = _getFilteredOpportunities();
    final bullish = filtered.where((o) => _buyRecommendations.contains(o.recommendation)).toList();
    final bearish = filtered.where((o) => _sellRecommendations.contains(o.recommendation)).toList();
    final neutral = filtered.where((o) => _neutralRecommendations.contains(o.recommendation)).toList();

    return Column(
      children: [
        _buildStatusBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadFromDb();
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '机会与风险',
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _showScoringInfo,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue, size: 14),
                                SizedBox(width: 4),
                                Text('评分说明', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_opportunities.isNotEmpty)
                          GestureDetector(
                            onTap: _archiveAll,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bookmark, color: Colors.orange, size: 14),
                                  SizedBox(width: 4),
                                  Text('一键留档', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: ['全部', '买入', '卖出', '观望'].map((type) {
                      final isSelected = _filterType == type;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _filterType = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? Colors.blue : Colors.white24),
                            ),
                            child: Text(type, style: TextStyle(
                              color: isSelected ? Colors.blue : Colors.white70, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            )),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (bullish.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('看多机会', style: const TextStyle(color: Color(0xFFef5350), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  ...bullish.map((o) => _buildOpportunityItem(o, textTheme)),
                ],
                if (bullish.isNotEmpty && bearish.isNotEmpty)
                  const Divider(color: Colors.white12, height: 16),
                if (bearish.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('风险提示', style: const TextStyle(color: Color(0xFF26a69a), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  ...bearish.map((o) => _buildOpportunityItem(o, textTheme)),
                ],
                if ((bullish.isNotEmpty || bearish.isNotEmpty) && neutral.isNotEmpty)
                  const Divider(color: Colors.white12, height: 16),
                if (neutral.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('中性观望', style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  ...neutral.map((o) => _buildOpportunityItem(o, textTheme)),
                ],
              ],
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              '分析中 $_completedCount/$_totalCount',
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
            '共 ${_opportunities.length} 只',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
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
            onPressed: _isAnalyzing ? null : _refreshAnalysis,
            icon: _isAnalyzing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_isAnalyzing ? '分析中 $_completedCount/$_totalCount' : '刷新分析'),
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

  Widget _buildOpportunityItem(OpportunityResult o, TextTheme textTheme) {
    final recColor = o.recommendation == '强烈买入' || o.recommendation == '买入' || o.recommendation == '谨慎买入'
        ? const Color(0xFFef5350)
        : o.recommendation == '卖出' || o.recommendation == '强烈卖出' || o.recommendation == '谨慎卖出'
            ? const Color(0xFF26a69a)
            : Colors.orange;

    final isUp = o.changePct >= 0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuoteScreen(code: o.code, name: o.name),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0f3460),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: recColor.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(o.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Text(o.code, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            o.price.toStringAsFixed(2),
                            style: TextStyle(color: isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${isUp ? '+' : ''}${o.changePct.toStringAsFixed(2)}%',
                            style: TextStyle(color: isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: recColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: recColor.withOpacity(0.5)),
                      ),
                      child: Text(o.recommendation, style: TextStyle(color: recColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${o.score}分',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => _archiveOpportunity(o),
                  icon: const Icon(Icons.bookmark_border, color: Colors.white54, size: 20),
                  tooltip: '留档',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTag('买${o.buySignalCount}', const Color(0xFFef5350)),
                const SizedBox(width: 4),
                _buildTag('卖${o.sellSignalCount}', const Color(0xFF26a69a)),
                const SizedBox(width: 4),
                _buildTag('战法${o.activeStrategyCount}', const Color(0xFFFFC107)),
                const SizedBox(width: 4),
                _buildTag('共振${o.confluenceScore}/10', Colors.cyan),
                const SizedBox(width: 4),
                _buildTag('风险${o.riskLevel}', o.riskLevel == '高' ? Colors.red : o.riskLevel == '中高' ? Colors.orange : Colors.white38),
                if (o.tradeLevels != null && o.tradeLevels!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildTag('盈亏比${(o.tradeLevels!['risk_reward_ratio'] as num).toDouble().toStringAsFixed(1)}:1', Colors.white54),
                ],
              ],
            ),
            if (o.topSignals.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                o.topSignals.join('  '),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
