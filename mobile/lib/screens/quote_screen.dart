import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/websocket_client.dart';
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
  final WebSocketClient _wsClient = WebSocketClient();
  QuoteData? _quote;
  List<HistoryKline> _klines = [];
  AnalysisResult? _analysis;
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _isRealtime = false;
  String _lastUpdateTime = '';
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _checkFavorite();
    _startRealtime();
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

  void _startRealtime() {
    _wsClient.onQuoteUpdate = _handleQuoteUpdate;
    _wsClient.connect();
    _wsClient.subscribe(widget.code);
  }

  void _handleQuoteUpdate(QuoteData quote) {
    if (quote.code == widget.code) {
      setState(() {
        _quote = quote;
        _isRealtime = true;
        _lastUpdateTime = DateFormat('HH:mm:ss').format(DateTime.now());
      });
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
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                quote.price.toStringAsFixed(2),
                style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(width: 8),
              if (_isRealtime)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '实时',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_lastUpdateTime.isNotEmpty)
            Text(
              '更新: $_lastUpdateTime',
              style: textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${quote.change >= 0 ? '+' : ''}${quote.change.toStringAsFixed(2)}',
                style: textTheme.titleLarge?.copyWith(color: color),
              ),
              const SizedBox(width: 12),
              Text(
                '(${quote.change >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%)',
                style: textTheme.titleLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text('开盘', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(quote.open.toStringAsFixed(2), style: textTheme.bodyMedium),
                ],
              ),
              Column(
                children: [
                  Text('最高', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(quote.high.toStringAsFixed(2), style: textTheme.bodyMedium?.copyWith(color: Colors.red)),
                ],
              ),
              Column(
                children: [
                  Text('最低', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(quote.low.toStringAsFixed(2), style: textTheme.bodyMedium?.copyWith(color: Colors.green)),
                ],
              ),
              Column(
                children: [
                  Text('昨收', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(quote.preClose.toStringAsFixed(2), style: textTheme.bodyMedium),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text('成交量', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text('${(quote.volume / 10000).toStringAsFixed(0)}万', style: textTheme.bodyMedium),
                ],
              ),
              Column(
                children: [
                  Text('成交额', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text('${(quote.amount / 10000).toStringAsFixed(0)}万', style: textTheme.bodyMedium),
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
      return Center(child: Text('暂无数据', style: Theme.of(context).textTheme.bodyMedium));
    }

    return ListView(
      children: [
        Container(
          height: 300,
          padding: const EdgeInsets.all(8),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10)),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
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
              gridData: FlGridData(show: true, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10)),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                ),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
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
              gridData: FlGridData(show: true, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10)),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                ),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
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
      return Center(child: Text('暂无信号', style: Theme.of(context).textTheme.bodyMedium));
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
      return Center(child: Text('暂无分析数据', style: Theme.of(context).textTheme.bodyMedium));
    }

    final analysis = _analysis!;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('综合评分', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).cardColor,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          analysis.score.toString(),
                          style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          analysis.recommendation,
                          style: textTheme.titleLarge?.copyWith(
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
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: analysis.riskLevel == '高' ? Colors.red : analysis.riskLevel == '中等' ? Colors.orange : Colors.green,
                  ),
                ),
                if (analysis.riskFactors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('风险因素:', style: textTheme.bodyMedium),
                  for (final factor in analysis.riskFactors)
                    Text('- $factor', style: textTheme.bodyMedium?.copyWith(color: Colors.red)),
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
                Text('操作建议:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final suggestion in analysis.suggestions)
                  Text('- $suggestion', style: textTheme.bodyMedium),
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
                  Text('指标摘要:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final entry in analysis.indicators.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key, style: textTheme.bodyMedium),
                          Text(entry.value.toString(), style: textTheme.bodyMedium),
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

  @override
  void dispose() {
    _tabController?.dispose();
    _wsClient.unsubscribe(widget.code);
    super.dispose();
  }
}
