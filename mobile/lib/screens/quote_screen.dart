import 'dart:ui' as ui;
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
import '../widgets/technical_indicators_panel.dart';

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
  List<FlSpot> _realtimeSpots = [];
  int? _selectedKlineIndex;
  bool _showFibonacci = false;
  Map<String, dynamic>? _techAnalysis;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
        // 合并数据：保留原有PE/PB/主力资金等字段，只更新价格相关字段
        if (_quote != null) {
          _quote = QuoteData(
            code: _quote!.code,
            name: _quote!.name,
            price: quote.price,
            change: quote.change,
            changePct: quote.changePct,
            open: quote.open > 0 ? quote.open : _quote!.open,
            high: quote.high > 0 ? quote.high : _quote!.high,
            low: quote.low > 0 ? quote.low : _quote!.low,
            preClose: quote.preClose > 0 ? quote.preClose : _quote!.preClose,
            volume: quote.volume > 0 ? quote.volume : _quote!.volume,
            amount: quote.amount > 0 ? quote.amount : _quote!.amount,
            amplitude: _quote!.amplitude,
            turnover: _quote!.turnover,
            pe: _quote!.pe,
            pb: _quote!.pb,
            totalMarketCap: _quote!.totalMarketCap,
            circulatingMarketCap: _quote!.circulatingMarketCap,
            mainInflow: _quote!.mainInflow,
            mainOutflow: _quote!.mainOutflow,
            mainNetFlow: _quote!.mainNetFlow,
            mainNetFlowRate: _quote!.mainNetFlowRate,
          );
        } else {
          _quote = quote;
        }
        _isRealtime = true;
        _lastUpdateTime = DateFormat('HH:mm:ss').format(DateTime.now());
        
        _realtimeSpots.add(FlSpot(_realtimeSpots.length.toDouble(), quote.price));
        if (_realtimeSpots.length > 30) {
          _realtimeSpots.removeAt(0);
        }
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final quote = await _apiClient.getRealtimeQuote(widget.code);
      final mainFundFlow = await _apiClient.getMainFundFlow(widget.code);
      final klines = await _apiClient.getStockHistory(widget.code, days: 120);
      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, quote);

      if (quote != null && mainFundFlow != null) {
        quote.mainInflow = mainFundFlow.mainInflow;
        quote.mainOutflow = mainFundFlow.mainOutflow;
        quote.mainNetFlow = mainFundFlow.mainNetFlow;
        quote.mainNetFlowRate = mainFundFlow.mainNetFlowRate;
      }

      // 计算支撑压力位和斐波那契
      final tech = <String, dynamic>{};
      final sr = calcSupportResistance(calculated);
      tech['support_levels'] = sr['support'] ?? [];
      tech['resistance_levels'] = sr['resistance'] ?? [];
      if (_showFibonacci) {
        tech['fibonacci'] = calcFibonacci(calculated);
      }

      setState(() {
        _quote = quote;
        _klines = calculated;
        _analysis = analysis;
        _techAnalysis = tech;
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
              Tab(text: '实时'),
              Tab(text: 'K线'),
              Tab(text: '信号'),
              Tab(text: '分析'),
              Tab(text: '指标'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRealtimeChart(),
                _buildKlineChart(),
                _buildSignalList(),
                _buildAnalysis(),
                TechnicalIndicatorsPanel(klines: _klines),
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
    final mainNetFlowColor = quote.mainNetFlow >= 0 ? Colors.red : Colors.green;

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
                  Text(quote.open.toStringAsFixed(2), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
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
                  Text(quote.preClose.toStringAsFixed(2), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
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
                  Text(_formatVolume(quote.volume), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('成交额', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(_formatAmount(quote.amount), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('市盈率', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(quote.pe.toStringAsFixed(1), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('市净率', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                  Text(quote.pb.toStringAsFixed(2), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0f3460),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('主力资金', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('净流入', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                        Text(
                          '${quote.mainNetFlow >= 0 ? '+' : ''}${_formatAmount(quote.mainNetFlow)}',
                          style: textTheme.bodyMedium?.copyWith(color: mainNetFlowColor),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text('净流入率', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                        Text(
                          '${quote.mainNetFlowRate >= 0 ? '+' : ''}${quote.mainNetFlowRate.toStringAsFixed(2)}%',
                          style: textTheme.bodyMedium?.copyWith(color: mainNetFlowColor),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text('主力流入', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                        Text(_formatAmount(quote.mainInflow), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('主力流出', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                        Text(_formatAmount(quote.mainOutflow), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeChart() {
    if (_realtimeSpots.isEmpty) {
      return Center(child: Text('等待实时数据...', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)));
    }

    final prices = _realtimeSpots.map((s) => s.y).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    // 确保Y轴范围至少有0.5的间距，避免价格不变时显示横线
    final displayMinY = minPrice - (priceRange > 0.5 ? priceRange * 00.05 : 0.25);
    final displayMaxY = maxPrice + (priceRange > 0.5 ? priceRange * 0.05 : 0.25);
    final isUp = _realtimeSpots.length >= 2 && _realtimeSpots.last.y >= _realtimeSpots[_realtimeSpots.length - 2].y;
    final color = isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a);

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('实时行情', style: TextStyle(color: Colors.grey, fontSize: 12)),
                if (_isRealtime)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('实时', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: displayMinY,
                maxY: displayMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 0.5),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (_realtimeSpots.length / 5).ceil().toDouble(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _realtimeSpots.length) return const SizedBox.shrink();
                        return Text('${idx + 1}', style: const TextStyle(color: Colors.white38, fontSize: 9));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.toStringAsFixed(2)}',
                          TextStyle(color: color, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _realtimeSpots,
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildMainFundFlowBar(),
        ],
      ),
    );
  }

  Widget _buildMainFundFlowBar() {
    final quote = _quote;
    if (quote == null) return const SizedBox.shrink();

    final inflow = quote.mainInflow.abs();
    final outflow = quote.mainOutflow.abs();
    final total = inflow + outflow;
    if (total == 0) return const SizedBox.shrink();

    final inflowRatio = inflow / total;
    final outflowRatio = outflow / total;
    final netFlow = quote.mainNetFlow;
    final isBuyDominant = netFlow >= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0f3460),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('主力买卖力度', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                '${isBuyDominant ? '买入' : '卖出'}主导 ${(inflowRatio * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: isBuyDominant ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: (inflowRatio * 1000).round().clamp(1, 1000),
                  child: Container(
                    height: 20,
                    color: const Color(0xFFef5350),
                    alignment: Alignment.center,
                    child: Text(
                      '${(inflowRatio * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(
                  flex: (outflowRatio * 1000).round().clamp(1, 1000),
                  child: Container(
                    height: 20,
                    color: const Color(0xFF26a69a),
                    alignment: Alignment.center,
                    child: Text(
                      '${(outflowRatio * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '流入 ${_formatAmount(inflow)}',
                style: const TextStyle(color: Color(0xFFef5350), fontSize: 11),
              ),
              Text(
                '净流量 ${netFlow >= 0 ? "+" : ""}${_formatAmount(netFlow)}',
                style: TextStyle(
                  color: netFlow >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '流出 ${_formatAmount(outflow)}',
                style: const TextStyle(color: Color(0xFF26a69a), fontSize: 11),
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

    final chartData = _klines;
    final prices = chartData.expand((d) => [d.high, d.low]).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    final textTheme = Theme.of(context).textTheme;

    // 斐波那契切换按钮
    Widget fibonacciToggle = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showFibonacci = !_showFibonacci;
            if (_showFibonacci && _klines.isNotEmpty) {
              final fib = calcFibonacci(_klines);
              if (_techAnalysis != null) {
                _techAnalysis!['fibonacci'] = fib;
              } else {
                _techAnalysis = {'fibonacci': fib};
              }
            }
            _loadData();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _showFibonacci ? const Color(0xFF26a69a) : const Color(0xFF16213e),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _showFibonacci ? const Color(0xFF26a69a) : Colors.white24),
          ),
          child: Text(
            '斐波那契',
            style: TextStyle(
              color: _showFibonacci ? Colors.white : Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );

    // 选中K线的数据展示
    Widget? selectedInfo;
    if (_selectedKlineIndex != null && _selectedKlineIndex! < _klines.length) {
      final k = _klines[_selectedKlineIndex!];
      final isUp = k.close >= k.open;
      final color = isUp ? Colors.red : Colors.green;
      selectedInfo = Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xFF0f3460),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${k.date.year}-${k.date.month.toString().padLeft(2, '0')}-${k.date.day.toString().padLeft(2, '0')}',
                  style: textTheme.bodySmall?.copyWith(color: Colors.grey)),
                Text('开${k.open.toStringAsFixed(2)}', style: textTheme.bodySmall?.copyWith(color: Colors.white)),
                Text('高${k.high.toStringAsFixed(2)}', style: textTheme.bodySmall?.copyWith(color: Colors.red)),
                Text('低${k.low.toStringAsFixed(2)}', style: textTheme.bodySmall?.copyWith(color: Colors.green)),
                Text('收${k.close.toStringAsFixed(2)}', style: textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('量${_formatVolume(k.volume)}', style: textTheme.bodySmall?.copyWith(color: Colors.white)),
                Text('额${_formatAmount(k.amount)}', style: textTheme.bodySmall?.copyWith(color: Colors.white)),
                Text('涨跌${k.change >= 0 ? '+' : ''}${k.change.toStringAsFixed(2)}', style: textTheme.bodySmall?.copyWith(color: color)),
                Text('幅${k.changePct >= 0 ? '+' : ''}${k.changePct.toStringAsFixed(2)}%', style: textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (selectedInfo != null) selectedInfo,
        // 斐波那契按钮行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              fibonacciToggle,
            ],
          ),
        ),
        Container(
          height: 300,
          padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
          child: LayoutBuilder(builder: (context, constraints) {
              return GestureDetector(
            onTapDown: (details) {
              final localPos = details.localPosition;
              final chartWidth = constraints.maxWidth - 56;
              final barTotalWidth = chartWidth / _klines.length;
              final index = (localPos.dx - 56) ~/ barTotalWidth;
              if (index >= 0 && index < _klines.length) {
                setState(() {
                  _selectedKlineIndex = index;
                });
              }
            },
            child: Stack(
              children: [
                LineChart(
                  LineChartData(
                    minY: minPrice - priceRange * 0.05,
                    maxY: maxPrice + priceRange * 0.05,
                    gridData: FlGridData(show: true, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10)),
                    titlesData: FlTitlesData(
                      show: true,
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 56,
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
                      if (_klines.any((k) => k.ma5 > 0))
                        LineChartBarData(
                          spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma5)).toList(),
                          isCurved: false,
                          color: Colors.yellow,
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                        ),
                      if (_klines.any((k) => k.ma10 > 0))
                        LineChartBarData(
                          spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma10)).toList(),
                          isCurved: false,
                          color: Colors.orange,
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                        ),
                      if (_klines.any((k) => k.ma20 > 0))
                        LineChartBarData(
                          spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma20)).toList(),
                          isCurved: false,
                          color: Colors.purpleAccent,
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                        ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _KlinePainter(
                      chartData,
                      selectedIndex: _selectedKlineIndex,
                      supportLevels: _techAnalysis?['support_levels'] ?? [],
                      resistanceLevels: _techAnalysis?['resistance_levels'] ?? [],
                      fibonacciLevels: _techAnalysis?['fibonacci']?['levels'],
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                    ),
                  ),
                ),

              ],
            ),
            );
          }),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  const Text('MACD', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: Colors.red),
                  const SizedBox(width: 4),
                  const Text('DIF', style: TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: Colors.blue),
                  const SizedBox(width: 4),
                  const Text('DEA', style: TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: const Color(0xFFef5350)),
                  const SizedBox(width: 4),
                  const Text('MACD柱', style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
            Builder(builder: (_) {
              double macdAbsMax = 0;
              for (final d in _klines) {
                if (d.macdDif.abs() > macdAbsMax) macdAbsMax = d.macdDif.abs();
                if (d.macdDea.abs() > macdAbsMax) macdAbsMax = d.macdDea.abs();
                if (d.macdHist.abs() > macdAbsMax) macdAbsMax = d.macdHist.abs();
              }
              if (macdAbsMax == 0) macdAbsMax = 0.01;
              final paddedMax = macdAbsMax * 1.1;
              return Container(
                height: 100,
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    LineChart(
                      LineChartData(
                        minY: -paddedMax,
                        maxY: paddedMax,
                        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 0.5)),
                        titlesData: FlTitlesData(
                          show: true,
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
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
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: _klines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.macdDea)).toList(),
                            isCurved: false,
                            color: Colors.blue,
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 42),
                        child: CustomPaint(
                          painter: _MacdHistogramPainter(_klines, macdAbsMax: macdAbsMax),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  const Text('RSI6', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: Colors.orange),
                  const SizedBox(width: 16),
                  const Text('超买70', style: TextStyle(color: Colors.white24, fontSize: 10)),
                  const SizedBox(width: 8),
                  const Text('超卖30', style: TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      if (value == 30 || value == 70) {
                        return const FlLine(color: Colors.white24, strokeWidth: 1, dashArray: [5, 5]);
                      }
                      return FlLine(color: Colors.white10, strokeWidth: 0.5);
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
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
                      barWidth: 1,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    final quote = _quote;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Card(
          margin: const EdgeInsets.all(8),
          color: const Color(0xFF16213e),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('综合评分', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0f3460),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          analysis.score.toString(),
                          style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          analysis.recommendation,
                          style: textTheme.titleLarge?.copyWith(
                            color: analysis.score >= 60 ? const Color(0xFFef5350) : const Color(0xFF26a69a),
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
          color: const Color(0xFF16213e),
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
                  Text('风险因素:', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
                  for (final factor in analysis.riskFactors)
                    Text('- $factor', style: textTheme.bodyMedium?.copyWith(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        if (quote != null)
          Card(
            margin: const EdgeInsets.all(8),
            color: const Color(0xFF16213e),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('估值分析', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  _buildValuationAnalysis(quote),
                ],
              ),
            ),
          ),
        if (quote != null && quote.mainNetFlow != 0)
          Card(
            margin: const EdgeInsets.all(8),
            color: const Color(0xFF16213e),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('资金流向分析', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  _buildFundFlowAnalysis(quote),
                ],
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.all(8),
          color: const Color(0xFF16213e),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('操作建议:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                for (final suggestion in analysis.suggestions)
                  Text('- $suggestion', style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ),
        if (analysis.indicators.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(8),
            color: const Color(0xFF16213e),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('指标摘要:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  for (final entry in analysis.indicators.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key, style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
                          Text(entry.value.toString(), style: textTheme.bodyMedium?.copyWith(color: Colors.white)),
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

  Widget _buildValuationAnalysis(QuoteData quote) {
    final textTheme = Theme.of(context).textTheme;
    final pe = quote.pe;
    final pb = quote.pb;

    String peAnalysis;
    Color peColor;
    if (pe <= 0) {
      peAnalysis = '市盈率为负，可能处于亏损状态';
      peColor = Colors.red;
    } else if (pe < 10) {
      peAnalysis = '市盈率偏低，估值相对便宜';
      peColor = Colors.green;
    } else if (pe < 20) {
      peAnalysis = '市盈率适中，估值合理';
      peColor = Colors.orange;
    } else if (pe < 30) {
      peAnalysis = '市盈率偏高，估值有溢价';
      peColor = Colors.red;
    } else {
      peAnalysis = '市盈率很高，估值风险较大';
      peColor = Colors.red;
    }

    String pbAnalysis;
    Color pbColor;
    if (pb < 1) {
      pbAnalysis = '市净率低于1，股价低于净资产';
      pbColor = Colors.green;
    } else if (pb < 2) {
      pbAnalysis = '市净率适中，估值合理';
      pbColor = Colors.orange;
    } else if (pb < 4) {
      pbAnalysis = '市净率偏高，关注资产质量';
      pbColor = Colors.red;
    } else {
      pbAnalysis = '市净率很高，泡沫风险较大';
      pbColor = Colors.red;
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('市盈率(PE)', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            Text(pe.toStringAsFixed(1), style: textTheme.bodyMedium?.copyWith(color: peColor)),
          ],
        ),
        const SizedBox(height: 4),
        Text(peAnalysis, style: textTheme.bodySmall?.copyWith(color: peColor)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('市净率(PB)', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            Text(pb.toStringAsFixed(2), style: textTheme.bodyMedium?.copyWith(color: pbColor)),
          ],
        ),
        const SizedBox(height: 4),
        Text(pbAnalysis, style: textTheme.bodySmall?.copyWith(color: pbColor)),
      ],
    );
  }

  Widget _buildFundFlowAnalysis(QuoteData quote) {
    final textTheme = Theme.of(context).textTheme;
    final netFlow = quote.mainNetFlow;
    final netFlowRate = quote.mainNetFlowRate;
    final isInflow = netFlow >= 0;
    final color = isInflow ? const Color(0xFFef5350) : const Color(0xFF26a69a);

    String flowAnalysis;
    if (isInflow) {
      if (netFlowRate > 5) {
        flowAnalysis = '主力资金大幅流入，看好后市';
      } else if (netFlowRate > 2) {
        flowAnalysis = '主力资金持续流入，有资金关注';
      } else {
        flowAnalysis = '主力资金小幅流入，观望为主';
      }
    } else {
      if (netFlowRate < -5) {
        flowAnalysis = '主力资金大幅流出，谨慎观望';
      } else if (netFlowRate < -2) {
        flowAnalysis = '主力资金持续流出，注意风险';
      } else {
        flowAnalysis = '主力资金小幅流出，波动正常';
      }
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('主力净流入', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            Text(
              '${isInflow ? '+' : ''}${_formatAmount(netFlow)}',
              style: textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('净流入率', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            Text(
              '${isInflow ? '+' : ''}${netFlowRate.toStringAsFixed(2)}%',
              style: textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(flowAnalysis, style: textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }

  String _formatVolume(double volumeInShou) {
    final volumeInWanShou = volumeInShou / 10000;
    if (volumeInWanShou.abs() >= 10000) {
      return '${(volumeInWanShou / 10000).toStringAsFixed(2)}亿手';
    } else if (volumeInWanShou.abs() >= 1) {
      return '${volumeInWanShou.toStringAsFixed(2)}万手';
    }
    return '${volumeInWanShou.toStringAsFixed(2)}万手';
  }

  String _formatAmount(double amount) {
    if (amount.abs() >= 1e8) {
      return '${(amount / 1e8).toStringAsFixed(2)}亿元';
    } else if (amount.abs() >= 1e4) {
      return '${(amount / 1e4).toStringAsFixed(0)}万元';
    }
    return '${amount.toStringAsFixed(0)}元';
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _wsClient.unsubscribe(widget.code);
    super.dispose();
  }
}

class _KlinePainter extends CustomPainter {
  final List<HistoryKline> data;
  final int? selectedIndex;
  final List<double> supportLevels;
  final List<double> resistanceLevels;
  final Map<String, double>? fibonacciLevels;
  final double minPrice;
  final double maxPrice;
  
  final Paint _upPaint = Paint()..color = const Color(0xFFef5350);
  final Paint _downPaint = Paint()..color = const Color(0xFF26a69a);
  final Paint _linePaint = Paint()..strokeWidth = 1;
  final Paint _selectedPaint = Paint()..color = Colors.white.withOpacity(0.2);

  _KlinePainter(
    this.data, {
    this.selectedIndex,
    this.supportLevels = const [],
    this.resistanceLevels = const [],
    this.fibonacciLevels,
    required this.minPrice,
    required this.maxPrice,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final priceRange = maxPrice - minPrice;
    final padding = 56.0;
    final chartWidth = size.width - padding;
    final chartHeight = size.height;
    final barWidth = chartWidth / data.length * 0.6;
    final gap = chartWidth / data.length * 0.4;

    // 绘制支撑位（绿色虚线）并标注价格
    for (final level in supportLevels) {
      final y = chartHeight - ((level - minPrice) / priceRange) * chartHeight;
      _drawDashedLine(canvas, Offset(padding, y), Offset(size.width, y), const Color(0xFF26a69a));
      _drawPriceLabel(canvas, size, level, y, const Color(0xFF26a69a));
    }

    // 绘制阻力位（红色虚线）并标注价格
    for (final level in resistanceLevels) {
      final y = chartHeight - ((level - minPrice) / priceRange) * chartHeight;
      _drawDashedLine(canvas, Offset(padding, y), Offset(size.width, y), const Color(0xFFef5350));
      _drawPriceLabel(canvas, size, level, y, const Color(0xFFef5350));
    }

    // 绘制斐波那契回撤位并标注价格和比例
    if (fibonacciLevels != null) {
      for (final entry in fibonacciLevels!.entries) {
        final level = entry.value;
        final ratio = entry.key;
        final y = chartHeight - ((level - minPrice) / priceRange) * chartHeight;
        final isGolden = ratio == '61.8%';
        final color = isGolden ? const Color(0xFFFFD700) : Colors.white54;
        _drawDashedLine(canvas, Offset(padding, y), Offset(size.width, y), color);
        _drawFibonacciLabel(canvas, size, level, ratio, y, color);
      }
    }

    // 价格范围为0时（如停牌），绘制水平线
    if (priceRange == 0) {
      final y = chartHeight / 2;
      for (int i = 0; i < data.length; i++) {
        final x = padding + i * (barWidth + gap) + barWidth / 2;
        canvas.drawLine(Offset(x, y - 1), Offset(x, y + 1), _linePaint..color = Colors.white54);
      }
      return;
    }

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final isUp = d.close >= d.open;
      final paint = isUp ? _upPaint : _downPaint;
      _linePaint.color = paint.color;

      final x = padding + i * (barWidth + gap) + barWidth / 2;
      final highY = chartHeight - ((d.high - minPrice) / priceRange) * chartHeight;
      final lowY = chartHeight - ((d.low - minPrice) / priceRange) * chartHeight;
      final openY = chartHeight - ((d.open - minPrice) / priceRange) * chartHeight;
      final closeY = chartHeight - ((d.close - minPrice) / priceRange) * chartHeight;

      // 选中K线高亮
      if (selectedIndex == i) {
        canvas.drawRect(
          Rect.fromLTWH(x - barWidth, 0, barWidth * 2, chartHeight),
          _selectedPaint,
        );
      }

      canvas.drawLine(Offset(x, highY), Offset(x, lowY), _linePaint);

      final bodyTop = isUp ? closeY : openY;
      final bodyBottom = isUp ? openY : closeY;
      final bodyLeft = x - barWidth / 2;

      if (isUp) {
        canvas.drawRect(
          Rect.fromLTWH(bodyLeft, bodyTop, barWidth, bodyBottom - bodyTop),
          paint,
        );
      } else {
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 1;
        canvas.drawRect(
          Rect.fromLTWH(bodyLeft, bodyTop, barWidth, bodyBottom - bodyTop),
          paint,
        );
        paint.style = PaintingStyle.fill;
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Color color) {
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final total = end.dx - start.dx;
    var offset = 0.0;
    while (offset < total) {
      canvas.drawLine(
        Offset(start.dx + offset, start.dy),
        Offset(start.dx + offset + dashWidth, start.dy),
        paint,
      );
      offset += dashWidth + dashSpace;
    }
  }

  void _drawPriceLabel(Canvas canvas, Size size, double price, double y, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: price.toStringAsFixed(2),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    
    // 在右侧绘制价格标签，带背景
    final x = size.width - textPainter.width - 8;
    final bgRect = Rect.fromLTWH(x - 2, y - textPainter.height / 2 - 2, 
                                  textPainter.width + 4, textPainter.height + 4);
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.7);
    canvas.drawRect(bgRect, bgPaint);
    
    textPainter.paint(canvas, Offset(x, y - textPainter.height / 2));
  }

  void _drawFibonacciLabel(Canvas canvas, Size size, double price, String ratio, double y, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$ratio ${price.toStringAsFixed(2)}',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    
    // 在左侧绘制斐波那契标签，带背景
    final x = 60.0; // padding是56，留点边距
    final bgRect = Rect.fromLTWH(x - 2, y - textPainter.height / 2 - 2, 
                                  textPainter.width + 4, textPainter.height + 4);
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.7);
    canvas.drawRect(bgRect, bgPaint);
    
    textPainter.paint(canvas, Offset(x, y - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(_KlinePainter oldDelegate) => 
    oldDelegate.data != data || 
    oldDelegate.selectedIndex != selectedIndex ||
    oldDelegate.supportLevels != supportLevels || 
    oldDelegate.resistanceLevels != resistanceLevels || 
    oldDelegate.fibonacciLevels != fibonacciLevels;
}

class _MacdHistogramPainter extends CustomPainter {
  final List<HistoryKline> data;
  final double macdAbsMax;

  final Paint _upPaint = Paint()..color = const Color(0xFFef5350);
  final Paint _downPaint = Paint()..color = const Color(0xFF26a69a);
  final Paint _axisPaint = Paint()
    ..color = Colors.white24
    ..strokeWidth = 0.5;

  _MacdHistogramPainter(this.data, {required this.macdAbsMax});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final absMax = macdAbsMax == 0 ? 0.01 : macdAbsMax;
    final barTotalWidth = size.width / data.length;
    final barWidth = barTotalWidth * 0.6;
    final zeroY = size.height / 2;
    final halfHeight = size.height / 2;

    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), _axisPaint);

    for (int i = 0; i < data.length; i++) {
      final hist = data[i].macdHist;
      if (hist == 0) continue;
      final x = i * barTotalWidth + barTotalWidth / 2;
      final h = (hist / absMax) * halfHeight;
      final paint = hist >= 0 ? _upPaint : _downPaint;

      if (hist >= 0) {
        canvas.drawRect(
          Rect.fromLTWH(x - barWidth / 2, zeroY - h, barWidth, h),
          paint,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(x - barWidth / 2, zeroY, barWidth, h.abs()),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MacdHistogramPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.macdAbsMax != macdAbsMax;
}
