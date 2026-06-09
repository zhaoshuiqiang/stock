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
    });

    try {
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isEmpty) {
        setState(() {
          _isLoading = false;
          _opportunities = [];
        });
        return;
      }

      final results = <_StockOpportunity>[];

      for (final item in watchlist) {
        try {
          final prefixedCode = _apiClient.addMarketPrefix(item.code);
          final klines = await _apiClient.getStockHistory(prefixedCode, days: 120);
          final quote = await _apiClient.getRealtimeQuote(prefixedCode);

          if (klines.isEmpty) continue;

          final calculated = calcAllIndicators(klines);
          final signals = detectSignals(calculated);
          final analysis = generateAnalysis(calculated, quote);
          final strategies = evaluateStrategies(calculated, signals);
          final activeStrategies = strategies.where((s) => s.isActive).length;

          final last = calculated.last;
          final topSignals = signals.take(2).map((s) =>
              '${s.type == 'buy' ? '▲' : '▼'}${s.signal}').toList();

          results.add(_StockOpportunity(
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
          ));
        } catch (e) {
          print('Failed to analyze ${item.code}: $e');
        }
      }

      results.sort((a, b) => b.score.compareTo(a.score));

      setState(() {
        _opportunities = results;
        _isLoading = false;
      });
    } catch (e) {
      print('Load opportunities failed: $e');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    if (_isLoading && _opportunities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('暂无自选股，请先添加自选', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            IconButton(
              onPressed: _loadOpportunities,
              icon: const Icon(Icons.refresh, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final bullish = _opportunities.where((o) => o.recommendation == '强烈买入' || o.recommendation == '买入').toList();
    final bearish = _opportunities.where((o) => o.recommendation == '卖出' || o.recommendation == '强烈卖出').toList();
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
              if (_isLoading)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                GestureDetector(
                  onTap: _loadOpportunities,
                  child: const Icon(Icons.refresh, color: Colors.white54, size: 20),
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
    final recColor = o.recommendation == '强烈买入' || o.recommendation == '买入'
        ? const Color(0xFFef5350)
        : o.recommendation == '卖出' || o.recommendation == '强烈卖出'
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
