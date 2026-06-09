import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../storage/database_service.dart';
import '../core/trading_session.dart';


class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  List<ArchiveRecord> _archives = [];
  bool _isLoading = true;
  Map<String, QuoteData> _currentQuotes = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadArchives();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (TradingSession.isInTradingSession()) {
        _refreshCurrentPrices();
      }
    });
  }

  Future<void> _loadArchives() async {
    final archives = await _dbService.getArchives();
    setState(() {
      _archives = archives;
      _isLoading = false;
    });
    _refreshCurrentPrices();
  }

  Future<void> _refreshCurrentPrices() async {
    for (final archive in _archives) {
      final prefixedCode = _apiClient.addMarketPrefix(archive.code);
      final quote = await _apiClient.getRealtimeQuote(prefixedCode);
      if (quote != null && mounted) {
        setState(() {
          _currentQuotes[archive.code] = quote;
        });
      }
    }
  }

  Future<void> _reanalyze(ArchiveRecord record) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final prefixedCode = _apiClient.addMarketPrefix(record.code);
      final klines = await _apiClient.getStockHistory(prefixedCode, days: 120);
      final quote = await _apiClient.getRealtimeQuote(prefixedCode);

      if (klines.isEmpty) {
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取数据')));
        return;
      }

      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, quote);

      if (mounted) Navigator.pop(context);

      if (mounted) _showReanalysisDialog(record, analysis, quote);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分析失败: $e')));
    }
  }

  void _showReanalysisDialog(ArchiveRecord record, AnalysisResult currentAnalysis, QuoteData? currentQuote) {
    final currentPrice = currentQuote?.price ?? 0;
    final currentChangePct = currentQuote?.changePct ?? 0;
    final priceChange = currentPrice - record.price;
    final priceChangePct = record.price > 0 ? (priceChange / record.price * 100) : 0.0;

    String reliability;
    Color reliabilityColor;
    final wasBuy = record.recommendation.contains('买入');
    final wasSell = record.recommendation.contains('卖出');

    if (wasBuy && priceChange < 0) {
      reliability = '推荐偏差';
      reliabilityColor = const Color(0xFF26a69a);
    } else if (wasSell && priceChange > 0) {
      reliability = '推荐偏差';
      reliabilityColor = const Color(0xFFef5350);
    } else {
      reliability = '推荐合理';
      reliabilityColor = Colors.orange;
    }

    showDialog(context: context, builder: (context) => Dialog(
      backgroundColor: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${record.name} 重新分析', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildCompareRow('推荐', record.recommendation, currentAnalysis.recommendation),
            _buildCompareRow('评分', '${record.score}', '${currentAnalysis.score}'),
            _buildCompareRow('风险', record.riskLevel, currentAnalysis.riskLevel),
            _buildCompareRow('价格', record.price.toStringAsFixed(2), currentPrice.toStringAsFixed(2)),
            _buildCompareRow('涨跌幅', '${record.changePct.toStringAsFixed(2)}%', '${currentChangePct.toStringAsFixed(2)}%'),
            const Divider(color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('价格变动', style: TextStyle(color: Colors.white54, fontSize: 13)),
                Text(
                  '${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePct >= 0 ? '+' : ''}${priceChangePct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: priceChange >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: reliabilityColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: reliabilityColor.withOpacity(0.5)),
              ),
              child: Text(reliability, style: TextStyle(color: reliabilityColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      ),
    ));
  }

  Widget _buildCompareRow(String label, String oldValue, String newValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(oldValue, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Icon(Icons.arrow_forward, color: Colors.white24, size: 16),
          Text(newValue, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _deleteArchive(ArchiveRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除 ${record.name} 的留档记录吗？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && record.id != null) {
      await _dbService.deleteArchive(record.id!);
      _loadArchives();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_archives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('暂无留档记录', style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('在"机会"页面中点击留档按钮保存推荐', style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadArchives,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _archives.length,
        itemBuilder: (context, index) {
          final record = _archives[index];
          final currentQuote = _currentQuotes[record.code];
          final currentPrice = currentQuote?.price ?? 0;
          final currentChangePct = currentQuote?.changePct ?? 0;
          final priceChange = currentPrice > 0 ? currentPrice - record.price : 0.0;

          final wasBuy = record.recommendation.contains('买入');
          final wasSell = record.recommendation.contains('卖出');
          String reliabilityLabel = '';
          Color reliabilityColor = Colors.transparent;
          if (currentPrice > 0) {
            if (wasBuy && priceChange < 0) {
              reliabilityLabel = '偏差';
              reliabilityColor = const Color(0xFF26a69a);
            } else if (wasSell && priceChange > 0) {
              reliabilityLabel = '偏差';
              reliabilityColor = const Color(0xFFef5350);
            } else if (wasBuy || wasSell) {
              reliabilityLabel = '合理';
              reliabilityColor = Colors.orange;
            }
          }

          final recColor = record.recommendation.contains('买入')
              ? const Color(0xFFef5350)
              : record.recommendation.contains('卖出')
                  ? const Color(0xFF26a69a)
                  : Colors.orange;

          return InkWell(
            onLongPress: () => _deleteArchive(record),
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
                                Text(record.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Text(record.code, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('留档: ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                Text(record.price.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(DateFormat('MM/dd HH:mm').format(record.archivedAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                            if (currentPrice > 0) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text('现价: ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  Text(currentPrice.toStringAsFixed(2), style: TextStyle(
                                    color: currentChangePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                                    fontSize: 12, fontWeight: FontWeight.bold,
                                  )),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${currentChangePct >= 0 ? "+" : ""}${currentChangePct.toStringAsFixed(2)}%',
                                    style: TextStyle(color: currentChangePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 11),
                                  ),
                                  if (reliabilityLabel.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: reliabilityColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(reliabilityLabel, style: TextStyle(color: reliabilityColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
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
                            child: Text(record.recommendation, style: TextStyle(color: recColor, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 4),
                          Text('${record.score}分', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTag('买${record.buySignalCount}', const Color(0xFFef5350)),
                      const SizedBox(width: 4),
                      _buildTag('卖${record.sellSignalCount}', const Color(0xFF26a69a)),
                      const SizedBox(width: 4),
                      _buildTag('战法${record.activeStrategyCount}', const Color(0xFFFFC107)),
                      const SizedBox(width: 4),
                      _buildTag('共振${record.confluenceScore}/8', Colors.cyan),
                      const SizedBox(width: 4),
                      _buildTag('风险${record.riskLevel}', record.riskLevel == '高' ? Colors.red : record.riskLevel == '中高' ? Colors.orange : Colors.white38),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _reanalyze(record),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.withOpacity(0.5)),
                          ),
                          child: const Text('重新分析', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
