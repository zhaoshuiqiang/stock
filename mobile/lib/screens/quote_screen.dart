import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../storage/database_service.dart';
import '../widgets/signal_card.dart';

class QuoteScreen extends StatefulWidget {
  final String code;
  final String name;

  const QuoteScreen({
    super.key,
    required this.code,
    required this.name,
  });

  @override
  State<QuoteScreen> createState() => QuoteScreenState();
}

class QuoteScreenState extends State<QuoteScreen> with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  QuoteData? _quote;
  List<HistoryKline> _klines = [];
  AnalysisResult? _analysis;
  bool _isLoading = true;
  bool _isFavorite = false;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    _isFavorite = await _dbService.isInWatchlist(widget.code);
    setState(() {});
  }

  Future<void> _toggleFavorite() async {
    setState(() {
      _isFavorite = !_isFavorite;
    });

    if (_isFavorite) {
      await _dbService.addToWatchlist(widget.code, widget.name);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加到自选股')),
      );
    } else {
      await _dbService.removeFromWatchlist(widget.code);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从自选股移除')),
      );
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final quote = await _apiClient.getRealtimeQuote(widget.code);
      final klines = await _apiClient.getStockHistory(widget.code, days: 120);
      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, quote);

      setState(() {
        _quote = quote;
        _klines = calculated;
        _analysis = analysis;
      });
    } catch (e) {
      print('Load data failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isUp = _quote != null && _quote!.change >= 0;
    final color = isUp ? Colors.red : Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.name} (${widget.code})'),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : null,
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_quote != null) _buildQuoteHeader(_quote!, color),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'K线'),
              Tab(text: '信号'),
              Tab(text: '分析'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildKlineChart(),
                _buildSignalList(),
                _buildAnalysis(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadData,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildQuoteHeader(QuoteData quote, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                quote.price.toStringAsFixed(2),
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${quote.change >= 0 ? '+' : ''}${quote.change.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 18, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                '(${quote.change >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%)',
                style: TextStyle(fontSize: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text('开盘', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(quote.open.toStringAsFixed(2), style: const TextStyle(fontSize: 14)),
                ],
              ),
              Column(
                children: [
                  const Text('最高', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(quote.high.toStringAsFixed(2), style: TextStyle(fontSize: 14, color: Colors.red)),
                ],
              ),
              Column(
                children: [
                  const Text('最低', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(quote.low.toStringAsFixed(2), style: TextStyle(fontSize: 14, color: Colors.green)),
                ],
              ),
              Column(
                children: [
                  const Text('昨收', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(quote.preClose.toStringAsFixed(2), style: const TextStyle(fontSize: 14)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKlineChart() {
    if (_klines.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return ListView(
      children: [
        Container(
          height: 300,
          padding: const EdgeInsets.all(8),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: true),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.close)).toList(),
                  isCurved: false,
                  color: Colors.blue,
                  barWidth: 2,
                ),
                if (_klines.any((k) => k.ma5 > 0))
                  LineChartBarData(
                    spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma5)).toList(),
                    isCurved: false,
                    color: Colors.red,
                    barWidth: 1.5,
                  ),
                if (_klines.any((k) => k.ma10 > 0))
                  LineChartBarData(
                    spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma10)).toList(),
                    isCurved: false,
                    color: Colors.blue,
                    barWidth: 1.5,
                  ),
                if (_klines.any((k) => k.ma20 > 0))
                  LineChartBarData(
                    spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma20)).toList(),
                    isCurved: false,
                    color: Colors.green,
                    barWidth: 1.5,
                  ),
              ],
            ),
          ),
        ),
        Container(
          height: 100,
          padding: const EdgeInsets.all(8),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: true),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.macdDif)).toList(),
                  isCurved: false,
                  color: Colors.red,
                  barWidth: 2,
                ),
                LineChartBarData(
                  spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.macdDea)).toList(),
                  isCurved: false,
                  color: Colors.blue,
                  barWidth: 2,
                ),
              ],
            ),
          ),
        ),
        Container(
          height: 100,
          padding: const EdgeInsets.all(8),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: true),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.rsi6)).toList(),
                  isCurved: false,
                  color: Colors.orange,
                  barWidth: 2,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignalList() {
    if (_analysis == null || _analysis!.signals.isEmpty) {
      return const Center(child: Text('暂无信号'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _analysis!.signals.length,
      itemBuilder: (context, index) {
        final signal = _analysis!.signals[index];
        return SignalCard(signal: signal);
      },
    );
  }

  Widget _buildAnalysis() {
    if (_analysis == null) {
      return const Center(child: Text('暂无分析数据'));
    }

    final analysis = _analysis!;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('综合评分', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[200],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          analysis.score.toString(),
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          analysis.recommendation,
                          style: TextStyle(
                            fontSize: 18,
                            color: analysis.score >= 60 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  '风险等级: ${analysis.riskLevel}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: analysis.riskLevel == '高' ? Colors.red : analysis.riskLevel == '中等' ? Colors.orange : Colors.green,
                  ),
                ),
                if (analysis.riskFactors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('风险因素:'),
                  for (final factor in analysis.riskFactors)
                    Text('- $factor', style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('操作建议:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final suggestion in analysis.suggestions)
                  Text('- $suggestion'),
              ],
            ),
          ),
        ),
        if (analysis.indicators.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text('指标摘要:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final entry in analysis.indicators.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key),
                          Text(entry.value.toString()),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
