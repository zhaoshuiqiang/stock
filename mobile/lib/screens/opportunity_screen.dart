import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../analysis/strategy_engine.dart';
import '../storage/database_service.dart';
import '../core/trading_session.dart';
import 'quote_screen.dart';

class _StockOpportunity {
  final String code;
  final String name;
  final double price;
  final double changePct;
  final int score;
  final String recommendation;
  final String riskLevel;
  final int buySignalCount;
  final int sellSignalCount;
  final int activeStrategyCount;
  final int confluenceScore;
  final Map<String, dynamic>? tradeLevels;
  final List<String> topSignals;

  _StockOpportunity({
    required this.code,
    required this.name,
    required this.price,
    required this.changePct,
    required this.score,
    required this.recommendation,
    required this.riskLevel,
    required this.buySignalCount,
    required this.sellSignalCount,
    required this.activeStrategyCount,
    required this.confluenceScore,
    this.tradeLevels,
    this.topSignals = const [],
  });
}

class OpportunityScreen extends StatefulWidget {
  const OpportunityScreen({super.key});

  @override
  State<OpportunityScreen> createState() => _OpportunityScreenState();
}

class _OpportunityScreenState extends State<OpportunityScreen> {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  List<_StockOpportunity> _opportunities = [];
  bool _isLoading = true;
  int _completedCount = 0;
  int _totalCount = 0;
  Map<String, QuoteData> _lastQuotes = {};
  Map<String, DateTime> _lastAnalysisTime = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadOpportunities();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (TradingSession.isInTradingSession()) {
        _loadOpportunities();
      }
    });
  }

  Future<void> _loadOpportunities() async {
    setState(() {
      _isLoading = true;
      _completedCount = 0;
    });

    try {
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isEmpty) {
        setState(() {
          _isLoading = false;
          _opportunities = [];
          _totalCount = 0;
        });
        return;
      }

      setState(() {
        _totalCount = watchlist.length;
      });

      // Batch fetch all quotes first (single HTTP request)
      final prefixedCodes = watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
      List<QuoteData> batchQuotes;
      try {
        batchQuotes = await _apiClient.getBatchRealtimeQuotes(prefixedCodes);
      } catch (e) {
        // ignore
        batchQuotes = [];
      }

      // Build a map of code -> QuoteData for quick lookup
      final quoteMap = <String, QuoteData>{};
      for (final q in batchQuotes) {
        quoteMap[q.code] = q;
      }

      // Batch analysis with concurrency limit of 5
      const batchSize = 5;
      final results = <_StockOpportunity?>[];
      for (int i = 0; i < watchlist.length; i += batchSize) {
        final batch = watchlist.sublist(i, (i + batchSize).clamp(0, watchlist.length));
        final batchResults = await Future.wait(
          batch.map((item) async {
            try {
              final prefixedCode = _apiClient.addMarketPrefix(item.code);
              QuoteData? quote = quoteMap[prefixedCode];
              // Fallback to individual quote if batch didn't return this stock
              if (quote == null) {
                try {
                  quote = await _apiClient.getRealtimeQuote(prefixedCode);
                } catch (e) {
                  // ignore
                }
              }

              // Incremental analysis: skip re-analysis if price unchanged and within 30s
              final now = DateTime.now();
              final lastTime = _lastAnalysisTime[prefixedCode];
              final timeExpired = lastTime == null || now.difference(lastTime).inSeconds > 30;

              if (!timeExpired && _lastQuotes.containsKey(prefixedCode)) {
                final lastQuote = _lastQuotes[prefixedCode]!;
                if (quote != null && quote.price == lastQuote.price && quote.changePct == lastQuote.changePct) {
                  final existing = _opportunities.where((o) => o.code == item.code).toList();
                  if (existing.isNotEmpty) {
                    return existing.first;
                  }
                }
              }
              if (quote != null) {
                _lastQuotes[prefixedCode] = quote;
              }
              _lastAnalysisTime[prefixedCode] = now;

              final klines = await _apiClient.getStockHistory(prefixedCode, days: 120, bypassCache: TradingSession.isInTradingSession());
              if (klines.isEmpty) {
                return null;
              }

              final calculated = calcAllIndicators(klines);
              final signals = detectSignals(calculated);
              final analysis = generateAnalysis(calculated, quote);
              final strategies = evaluateStrategies(calculated, signals);
              final activeStrategies = strategies.where((s) => s.isActive).length;

              final last = calculated.last;
              final topSignals = signals.take(2).map((s) =>
                  '${s.type == 'buy' ? '▲' : '▼'}${s.signal}').toList();

              return _StockOpportunity(
                code: item.code,
                name: item.name,
                price: quote?.price ?? last.close,
                changePct: quote?.changePct ?? last.changePct,
                score: analysis.score,
                recommendation: analysis.recommendation,
                riskLevel: analysis.riskLevel,
                buySignalCount: signals.where((s) => s.type == 'buy').length,
                sellSignalCount: signals.where((s) => s.type == 'sell').length,
                activeStrategyCount: activeStrategies,
                confluenceScore: analysis.confluenceScore,
                tradeLevels: analysis.tradeLevels,
                topSignals: topSignals,
              );
            } catch (e) {
              // ignore
              return null;
            }
          }),
        );
        results.addAll(batchResults);
      }
      final opportunities = results.whereType<_StockOpportunity>().toList();
      opportunities.sort((a, b) => b.score.compareTo(a.score));

      setState(() {
        _completedCount = _totalCount;
        _opportunities = opportunities;
        _isLoading = false;
      });
    } catch (e) {
      // ignore
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _archiveOpportunity(_StockOpportunity o) async {
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
      tradeLevelsJson: o.tradeLevels != null ? jsonEncode(o.tradeLevels) : null,
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
              _buildInfoSection('综合评分公式', '总分 = K线评分×55% + 实时行情×25% + 共振评分×20%'),
              const SizedBox(height: 12),
              _buildInfoSection('K线评分（55%）', '由5个维度加权：\n• 信号评分(0-30)：按信号强度加权\n• 趋势评分(0-20)：MA排列+ADX趋势\n• 动量评分(0-20)：RSI区间+BIAS乖离\n• 量价评分(0-15)：量比+OBV趋势\n• 波动率评分(0-15)：ATR波动率评估'),
              const SizedBox(height: 12),
              _buildInfoSection('实时行情（25%）', '• 涨跌幅：温和上涨加分，超跌反弹加分\n• 资金流向：主力净流入加分\n• 换手率：适度活跃加分，过热减分'),
              const SizedBox(height: 12),
              _buildInfoSection('共振评分（20%）', '7维度多空共振：MA/MACD/RSI/KDJ/BOLL/量价/背离\n看多维度越多，共振加分越高'),
              const SizedBox(height: 12),
              _buildInfoSection('ADX权重调整', '• ADX>25趋势市：趋势信号权重×1.2\n• ADX<20盘整市：震荡信号权重×1.2'),
              const SizedBox(height: 12),
              _buildInfoSection('推荐等级', '• 80-100分：强烈买入\n• 65-79分：买入\n• 40-64分：观望\n• 25-39分：卖出\n• 0-24分：强烈卖出'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    if (_isLoading && _opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              _totalCount > 0 ? '分析中 $_completedCount/$_totalCount' : '加载中...',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _totalCount > 0 ? '分析失败，请下拉刷新重试' : '暂无自选股，请先添加自选',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            IconButton(
              onPressed: _loadOpportunities,
              icon: const Icon(Icons.refresh, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final bullish = _opportunities.where((o) => o.recommendation == '强烈买入' || o.recommendation == '买入' || o.recommendation == '谨慎买入').toList();
    final bearish = _opportunities.where((o) => o.recommendation == '卖出' || o.recommendation == '强烈卖出' || o.recommendation == '谨慎卖出').toList();
    final neutral = _opportunities.where((o) => o.recommendation == '观望').toList();

    return RefreshIndicator(
      onRefresh: _loadOpportunities,
      child: ListView(
        padding: const EdgeInsets.all(8),
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
                  const SizedBox(width: 8),
                  if (_isLoading)
                    Text(
                      '$_completedCount/$_totalCount',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    )
                  else
                    GestureDetector(
                      onTap: _loadOpportunities,
                      child: const Icon(Icons.refresh, color: Colors.white54, size: 20),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
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
    );
  }

  Widget _buildOpportunityItem(_StockOpportunity o, TextTheme textTheme) {
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
                _buildTag('共振${o.confluenceScore}/8', Colors.cyan),
                const SizedBox(width: 4),
                _buildTag('风险${o.riskLevel}', o.riskLevel == '高' ? Colors.red : o.riskLevel == '中高' ? Colors.orange : Colors.white38),
                if (o.tradeLevels != null && o.tradeLevels!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildTag('盈亏比${(o.tradeLevels!['risk_reward_ratio'] as double).toStringAsFixed(1)}:1', Colors.white54),
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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
