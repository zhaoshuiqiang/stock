import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../storage/database_service.dart';
import '../widgets/signal_card.dart';
import '../widgets/technical_indicators_panel.dart';
import '../widgets/strategy_panel.dart';
import '../core/trading_session.dart';

const _kChartLeftReservedSize = 42.0;

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
  Timer? _pollingTimer;
  Timer? _analysisRefreshTimer;
  QuoteData? _quote;
  List<HistoryKline> _klines = [];
  AnalysisResult? _analysis;
  bool _isLoading = true;
  bool _isAnalysisRefreshing = false;
  bool _isFavorite = false;
  bool _isRealtime = false;
  bool _isMarketOpen = true;
  double? _lastChangePct;
  String _lastUpdateTime = '';
  TabController? _tabController;
  int _updateCount = 0; // 轮询更新计数，用于控制分析刷新频率
  // 分时图数据：key=分钟偏移量(0~239), value=价格
  Map<int, double> _timeshareData = {};
  // 分时图均价数据：key=分钟偏移量, value=均价
  Map<int, double> _timeshareAvgData = {};
  double _timeshareTotalAmount = 0; // 累计成交额
  double _timeshareTotalVolume = 0; // 累计成交量(手)
  int? _selectedKlineIndex;
  bool _showFibonacci = false;
  bool _showBoll = false;
  Map<String, dynamic>? _techAnalysis;
  bool _timeshareLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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

  void _showStockSearchDialog() async {
    final controller = TextEditingController();
    List<StockInfo> searchResults = [];
    List<WatchlistItem> watchlist = [];
    bool searching = false;

    watchlist = await _dbService.getWatchlist();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> doSearch(String keyword) async {
              if (keyword.isEmpty) {
                setDialogState(() { searchResults = []; searching = false; });
                return;
              }
              setDialogState(() { searching = true; });
              try {
                final results = await _apiClient.searchStocks(keyword);
                setDialogState(() { searchResults = results; searching = false; });
              } catch (_) {
                setDialogState(() { searching = false; });
              }
            }

            void switchStock(String code, String name) {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => QuoteScreen(code: code, name: name),
                ),
              );
            }

            return Dialog(
              backgroundColor: const Color(0xFF1a1a2e),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '输入股票代码或名称',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        suffixIcon: searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF0f3460),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => doSearch(v),
                      onSubmitted: (v) => doSearch(v),
                    ),
                    const SizedBox(height: 12),
                    if (searchResults.isEmpty && !searching) ...[
                      if (watchlist.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('自选股', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: watchlist.length,
                            itemBuilder: (_, i) {
                              final item = watchlist[i];
                              final isCurrent = item.code == widget.code;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: isCurrent ? const Color(0xFFef5350) : Colors.white38,
                                  size: 20,
                                ),
                                title: Text(item.name, style: TextStyle(
                                  color: isCurrent ? Colors.white54 : Colors.white,
                                  fontSize: 14,
                                )),
                                subtitle: Text(item.code, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                onTap: isCurrent ? null : () => switchStock(item.code, item.name),
                              );
                            },
                          ),
                        ),
                      ] else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('输入关键词搜索股票', style: TextStyle(color: Colors.white38)),
                          ),
                        ),
                    ] else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (_, i) {
                            final stock = searchResults[i];
                            return ListTile(
                              dense: true,
                              title: Text(stock.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                              subtitle: Text(stock.code, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              onTap: () => switchStock(stock.code, stock.name),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _startRealtime() {
    _isMarketOpen = TradingSession.isInTradingSession();
    int pollCount = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!TradingSession.isInTradingSession()) {
        if (_isMarketOpen || _isRealtime) {
          setState(() {
            _isMarketOpen = false;
            _isRealtime = false;
          });
        }
        // 收盘后停止轮询
        if (TradingSession.isMarketClosed()) {
          _pollingTimer?.cancel();
        }
        return;
      }
      _isMarketOpen = true;
      pollCount++;

      // 每30秒（第6次轮询）刷新完整分时数据，填补轮询可能遗漏的数据点
      if (pollCount % 6 == 0) {
        final timeshareResult = await _apiClient.getTimeshareData(widget.code, bypassCache: true);
        if (timeshareResult != null && mounted) {
          setState(() {
            final apiPrices = timeshareResult['prices'] ?? {};
            final apiAvgs = timeshareResult['avgs'] ?? {};
            // API数据作为基础，轮询数据覆盖同一分钟槽位
            _timeshareData = {...apiPrices, ..._timeshareData};
            _timeshareAvgData = {...apiAvgs, ..._timeshareAvgData};
            _timeshareLoadFailed = false;
          });
        }
      }

      final quote = await _apiClient.getRealtimeQuote(widget.code);
      if (quote != null) {
        _handleQuoteUpdate(quote);
      }
    });

    // 分析模块独立刷新定时器：30秒周期
    _analysisRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshAnalysis();
    });
  }

  Future<void> _refreshAnalysis() async {
    if (!TradingSession.isInTradingSession()) return;

    setState(() { _isAnalysisRefreshing = true; });

    try {
      // Fetch fresh klines bypassing cache
      final klines = await _apiClient.getStockHistory(widget.code, days: 120, bypassCache: true);
      if (klines.isEmpty) return;

      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, _quote);

      // Recalculate tech analysis
      final tech = <String, dynamic>{};
      final sr = calcSupportResistance(calculated);
      tech['support_levels'] = sr['support'] ?? [];
      tech['resistance_levels'] = sr['resistance'] ?? [];
      if (_showFibonacci) {
        tech['fibonacci'] = calcFibonacci(calculated);
      }

      setState(() {
        _klines = calculated;
        _analysis = analysis;
        _techAnalysis = tech;
        _isAnalysisRefreshing = false;
      });
    } catch (e) {
      print('Refresh analysis failed: $e');
      setState(() { _isAnalysisRefreshing = false; });
    }
  }

  void _handleQuoteUpdate(QuoteData quote) {
    if (quote.code == widget.code) {
      setState(() {
        // 合并数据：保留原有PE/PB等字段，更新价格和主力资金字段
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
            // 主力资金：如果轮询返回了有效数据则更新，否则保留原值
            mainInflow: quote.mainInflow > 0 ? quote.mainInflow : _quote!.mainInflow,
            mainOutflow: quote.mainOutflow > 0 ? quote.mainOutflow : _quote!.mainOutflow,
            mainNetFlow: quote.mainNetFlow != 0 ? quote.mainNetFlow : _quote!.mainNetFlow,
            mainNetFlowRate: quote.mainNetFlowRate != 0 ? quote.mainNetFlowRate : _quote!.mainNetFlowRate,
          );
        } else {
          _quote = quote;
        }
        _isRealtime = true;
        _lastUpdateTime = DateFormat('HH:mm:ss').format(DateTime.now());
        
        // 分时图：按交易时间分钟映射价格
        _addTimesharePoint(quote.price, quote.volume, quote.amount);

        // 更新分析结果中的quote引用，使分析页显示最新价格
        _updateCount++;

        // 检测涨跌幅显著变化（超过1%），触发即时完整分析刷新
        final changeDiff = _lastChangePct != null
            ? (quote.changePct - _lastChangePct!).abs()
            : 0.0;
        _lastChangePct = quote.changePct;

        if (_analysis != null) {
          if ((_updateCount % 5 == 0 || changeDiff > 1.0) && _klines.isNotEmpty) {
            // 每5次轮询（约30秒）重新生成完整分析，确保风险与机会实时更新
            try {
              _analysis = generateAnalysis(_klines, _quote);
            } catch (e) {
              // 重新生成失败时仅更新quote引用
              _analysis = AnalysisResult(
                quote: _quote,
                indicators: _analysis!.indicators,
                signals: _analysis!.signals,
                score: _analysis!.score,
                recommendation: _analysis!.recommendation,
                riskLevel: _analysis!.riskLevel,
                riskFactors: _analysis!.riskFactors,
                suggestions: _analysis!.suggestions,
                tradeLevels: _analysis!.tradeLevels,
                confluenceScore: _analysis!.confluenceScore,
                confluenceDetails: _analysis!.confluenceDetails,
                reasons: _analysis!.reasons,
                opportunities: _analysis!.opportunities,
              );
            }
          } else {
            // 非刷新周期仅更新quote引用
            _analysis = AnalysisResult(
              quote: _quote,
              indicators: _analysis!.indicators,
              signals: _analysis!.signals,
              score: _analysis!.score,
              recommendation: _analysis!.recommendation,
              riskLevel: _analysis!.riskLevel,
              riskFactors: _analysis!.riskFactors,
              suggestions: _analysis!.suggestions,
              tradeLevels: _analysis!.tradeLevels,
              confluenceScore: _analysis!.confluenceScore,
              confluenceDetails: _analysis!.confluenceDetails,
              reasons: _analysis!.reasons,
              opportunities: _analysis!.opportunities,
            );
          }
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
      print('[_loadData] quote=${quote?.name} price=${quote?.price}, klines=${klines.length}');
      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, quote);
      print('[_loadData] calculated=${calculated.length}, analysis.score=${analysis.score}, signals=${analysis.signals.length}');

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

      // 加载分时线历史数据（盘后也能显示全天走势）
      final timeshareResult = await _apiClient.getTimeshareData(widget.code);

      // 判断是否在交易时段
      final now = DateTime.now();
      final isWeekday = now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
      final totalMin = now.hour * 60 + now.minute;
      final isTradingHour = isWeekday && totalMin >= (9 * 60 + 30) && totalMin <= 15 * 60;

      setState(() {
        _quote = quote;
        _klines = calculated;
        _analysis = analysis;
        _techAnalysis = tech;
        if (timeshareResult != null) {
          _timeshareData = timeshareResult['prices'] ?? {};
          _timeshareAvgData = timeshareResult['avgs'] ?? {};
          _timeshareLoadFailed = false;
        } else if (isTradingHour) {
          // 交易时段分时数据加载失败，设置降级标志
          _timeshareLoadFailed = true;
        }
      });
    } catch (e, stackTrace) {
      print('Load data failed for ${widget.code}: $e');
      print('Stack trace: $stackTrace');
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
            icon: const Icon(Icons.search),
            onPressed: _showStockSearchDialog,
          ),
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
              Tab(text: '战法'),
              Tab(text: '分析'),
              Tab(text: '指标'),
            ],
          ),
          if (_isAnalysisRefreshing)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRealtimeChart(),
                _buildKlineChart(),
                _buildSignalList(),
                StrategyPanel(klines: _klines, signals: _analysis?.signals ?? []),
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
              if (_isRealtime || !_isMarketOpen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isMarketOpen ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isMarketOpen ? '交易中' : TradingSession.getSessionStatus(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
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

  /// 将当前时间转换为交易分钟偏移量
  /// 9:30 -> 0, 9:31 -> 1, ... 11:30 -> 120, 13:00 -> 121, ... 15:00 -> 239
  int? _timeToMinuteOffset(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final totalMinutes = hour * 60 + minute;

    // 上午盘 9:30 ~ 11:30 (共120分钟, offset 0~119)
    const morningStart = 9 * 60 + 30; // 570
    const morningEnd = 11 * 60 + 30;  // 690
    // 下午盘 13:00 ~ 15:00 (共120分钟, offset 120~239)
    const afternoonStart = 13 * 60;    // 780
    const afternoonEnd = 15 * 60;      // 900

    if (totalMinutes >= morningStart && totalMinutes <= morningEnd) {
      return totalMinutes - morningStart; // 0 ~ 120
    } else if (totalMinutes > morningEnd && totalMinutes < afternoonStart) {
      // 午休期间的数据归到上午最后一分钟
      return 120;
    } else if (totalMinutes >= afternoonStart && totalMinutes <= afternoonEnd) {
      return 120 + (totalMinutes - afternoonStart); // 121 ~ 240
    }
    return null; // 非交易时间
  }

  /// 对K线数据进行降采样，减少渲染数据点数量
  List<HistoryKline> _downsampleKlines(List<HistoryKline> klines, int maxPoints) {
    if (klines.length <= maxPoints) return klines;

    final step = klines.length / maxPoints;
    final result = <HistoryKline>[];
    for (var i = 0.0; i < klines.length; i += step) {
      final index = i.toInt().clamp(0, klines.length - 1);
      result.add(klines[index]);
    }
    // Always include the last data point
    if (result.last != klines.last) {
      result.add(klines.last);
    }
    return result;
  }

  /// 将分钟偏移量转换为时间字符串
  String _minuteOffsetToTime(int offset) {
    if (offset <= 120) {
      final totalMinutes = 9 * 60 + 30 + offset;
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    } else {
      final totalMinutes = 13 * 60 + (offset - 121);
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
  }

  /// 添加分时图数据点
  void _addTimesharePoint(double price, double volume, double amount) {
    final now = DateTime.now();
    final offset = _timeToMinuteOffset(now);
    if (offset == null) return; // 非交易时间不记录
    
    // 限制范围
    final clampedOffset = offset.clamp(0, 239);
    _timeshareData[clampedOffset] = price;
    
    // 计算均价 = 累计成交额 / 累计成交量
    // 注意：每次轮询返回的是当日累计值，直接用当前值
    if (amount > 0 && volume > 0) {
      _timeshareAvgData[clampedOffset] = amount / (volume * 100); // 成交额(元) / 成交量(股)
    }
  }

  Widget _buildRealtimeChart() {
    final preClose = _quote?.preClose ?? 0;
    final currentPrice = _quote?.price ?? 0;

    if (_timeshareData.isEmpty && _timeshareLoadFailed) {
      return Center(child: Text('分时历史数据加载失败，仅显示实时数据', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)));
    }
    if (_timeshareData.isEmpty) {
      return Center(child: Text('暂无分时数据', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)));
    }

    // 构建价格线数据点（按分钟偏移量排序）
    final sortedKeys = _timeshareData.keys.toList()..sort();
    final priceSpots = sortedKeys.map((k) => FlSpot(k.toDouble(), _timeshareData[k]!)).toList();
    
    // 构建均价线数据点
    final avgSortedKeys = _timeshareAvgData.keys.toList()..sort();
    final avgSpots = avgSortedKeys.map((k) => FlSpot(k.toDouble(), _timeshareAvgData[k]!)).toList();

    // Y轴以昨收价为中心，上下对称
    double maxDeviation = 0;
    for (final price in _timeshareData.values) {
      final dev = (price - preClose).abs();
      if (dev > maxDeviation) maxDeviation = dev;
    }
    // 确保最小偏差
    if (maxDeviation < 0.01) maxDeviation = preClose * 0.01;
    // 上下各留10%余量
    final padding = maxDeviation * 0.1;
    final displayMinY = preClose - maxDeviation - padding;
    final displayMaxY = preClose + maxDeviation + padding;

    // 涨跌颜色
    final isUp = currentPrice >= preClose;
    final priceColor = isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a);

    // 昨收价参考线
    List<HorizontalLine> horizontalLines = [];
    if (preClose > 0) {
      horizontalLines.add(HorizontalLine(
        y: preClose,
        color: Colors.white24,
        strokeWidth: 0.5,
        dashArray: [4, 4],
        label: HorizontalLineLabel(
          show: true,
          alignment: Alignment.topRight,
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          style: const TextStyle(color: Colors.white38, fontSize: 9),
          labelResolver: (line) => '昨收${preClose.toStringAsFixed(2)}',
        ),
      ));
    }

    // X轴时间标签：9:30, 10:00, 10:30, 11:00, 11:30/13:00, 13:30, 14:00, 14:30, 15:00
    // 对应offset: 0, 30, 60, 90, 120, 150, 180, 210, 240
    final timeLabels = {0: '9:30', 30: '10:00', 60: '10:30', 90: '11:00', 120: '11:30/13:00', 150: '13:30', 180: '14:00', 210: '14:30', 240: '15:00'};

    // 涨跌幅百分比（右侧Y轴）
    final maxPctChange = preClose > 0 ? ((displayMaxY - preClose) / preClose * 100) : 0.0;
    final minPctChange = preClose > 0 ? ((displayMinY - preClose) / preClose * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('分时图', style: TextStyle(color: Colors.grey, fontSize: 12)),
                if (_isRealtime || !_isMarketOpen)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isMarketOpen ? Colors.green : Colors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _isMarketOpen ? '交易中' : TradingSession.getSessionStatus(),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 240,
                minY: displayMinY,
                maxY: displayMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: 30, // 每30分钟一条竖线
                  horizontalInterval: (displayMaxY - displayMinY) / 4,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 0.5),
                  getDrawingVerticalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 0.5),
                ),
                extraLinesData: ExtraLinesData(horizontalLines: horizontalLines),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) {
                        final pct = preClose > 0 ? (value - preClose) / preClose * 100 : 0.0;
                        Color c = Colors.white38;
                        if (value > preClose) c = const Color(0xFFef5350);
                        if (value < preClose) c = const Color(0xFF26a69a);
                        return Text(
                          '${value.toStringAsFixed(2)}\n${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                          style: TextStyle(color: c, fontSize: 9),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) {
                        final pct = preClose > 0 ? (value - preClose) / preClose * 100 : 0.0;
                        Color c = Colors.white38;
                        if (pct > 0) c = const Color(0xFFef5350);
                        if (pct < 0) c = const Color(0xFF26a69a);
                        return Text(
                          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                          style: TextStyle(color: c, fontSize: 9),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: 30,
                      getTitlesWidget: (value, meta) {
                        final key = value.toInt();
                        if (timeLabels.containsKey(key)) {
                          return Text(
                            timeLabels[key]!,
                            style: const TextStyle(color: Colors.white38, fontSize: 9),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final offset = spot.x.toInt();
                        final timeStr = _minuteOffsetToTime(offset.clamp(0, 239));
                        final pct = preClose > 0 ? (spot.y - preClose) / preClose * 100 : 0.0;
                        return LineTooltipItem(
                          '$timeStr  ${spot.y.toStringAsFixed(2)}  ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                          TextStyle(color: spot.y >= preClose ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  // 价格线
                  LineChartBarData(
                    spots: priceSpots,
                    isCurved: false,
                    color: priceColor,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: priceColor.withOpacity(0.08),
                    ),
                  ),
                  // 均价线（黄色）
                  if (avgSpots.isNotEmpty)
                    LineChartBarData(
                      spots: avgSpots,
                      isCurved: false,
                      color: Colors.yellow.withOpacity(0.7),
                      barWidth: 1,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
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
                    child: inflowRatio >= 0.05
                        ? Text(
                            '${(inflowRatio * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                            overflow: TextOverflow.clip,
                            softWrap: false,
                          )
                        : null,
                  ),
                ),
                Expanded(
                  flex: (outflowRatio * 1000).round().clamp(1, 1000),
                  child: Container(
                    height: 20,
                    color: const Color(0xFF26a69a),
                    alignment: Alignment.center,
                    child: outflowRatio >= 0.05
                        ? Text(
                            '${(outflowRatio * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                            overflow: TextOverflow.clip,
                            softWrap: false,
                          )
                        : null,
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
    if (_klines.isEmpty)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('K线数据加载失败', style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadData,
              child: const Text('点击重试'),
            ),
          ],
        ),
      );

    // Downsample klines for display when there are too many data points
    final displayKlines = _klines.length > 200 ? _downsampleKlines(_klines, 200) : _klines;
    final chartData = displayKlines;
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

    Widget bollToggle = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showBoll = !_showBoll;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _showBoll ? const Color(0xFF00BCD4) : const Color(0xFF16213e),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _showBoll ? const Color(0xFF00BCD4) : Colors.white24),
          ),
          child: Text(
            'BOLL',
            style: TextStyle(
              color: _showBoll ? Colors.white : Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );

    // 选中K线的数据展示
    Widget? selectedInfo;
    if (_selectedKlineIndex != null && _selectedKlineIndex! < displayKlines.length) {
      final k = displayKlines[_selectedKlineIndex!];
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
              bollToggle,
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
              final barTotalWidth = chartWidth / displayKlines.length;
              final index = (localPos.dx - 56) ~/ barTotalWidth;
              if (index >= 0 && index < displayKlines.length) {
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
                      if (displayKlines.any((k) => k.ma5 > 0))
                        LineChartBarData(
                          spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma5)).toList(),
                          isCurved: false,
                          color: Colors.yellow,
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                        ),
                      if (displayKlines.any((k) => k.ma10 > 0))
                        LineChartBarData(
                          spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma10)).toList(),
                          isCurved: false,
                          color: Colors.orange,
                          barWidth: 1,
                          dotData: const FlDotData(show: false),
                        ),
                      if (displayKlines.any((k) => k.ma20 > 0))
                        LineChartBarData(
                          spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.ma20)).toList(),
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
                      showBoll: _showBoll,
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
                  const Text('成交量', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 16),
                  Container(width: 8, height: 2, color: Colors.yellow),
                  const SizedBox(width: 4),
                  const Text('MA5', style: TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 2, color: Colors.cyan),
                  const SizedBox(width: 4),
                  const Text('MA10', style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
            Container(
              height: 80,
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _VolumeHistogramPainter(displayKlines),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(left: _kChartLeftReservedSize),
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          gridData: const FlGridData(show: false),
                          titlesData: FlTitlesData(
                            show: true,
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: _kChartLeftReservedSize,
                                getTitlesWidget: (value, meta) => Text(
                                  _formatVolume(value),
                                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                                ),
                              ),
                            ),
                            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            if (displayKlines.any((k) => k.volMa5 > 0))
                              LineChartBarData(
                                spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.volMa5)).toList(),
                                isCurved: false,
                                color: Colors.yellow,
                                barWidth: 1,
                                dotData: const FlDotData(show: false),
                              ),
                            if (displayKlines.any((k) => k.volMa10 > 0))
                              LineChartBarData(
                                spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.volMa10)).toList(),
                                isCurved: false,
                                color: Colors.cyan,
                                barWidth: 1,
                                dotData: const FlDotData(show: false),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              for (final d in displayKlines) {
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
                              reservedSize: _kChartLeftReservedSize,
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
                            spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.macdDif)).toList(),
                            isCurved: false,
                            color: Colors.red,
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.macdDea)).toList(),
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
                        padding: const EdgeInsets.only(left: _kChartLeftReservedSize),
                        child: CustomPaint(
                          painter: _MacdHistogramPainter(displayKlines, macdAbsMax: macdAbsMax),
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
                        reservedSize: _kChartLeftReservedSize,
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
                      spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.rsi6)).toList(),
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
        Builder(builder: (_) {
          final kdjData = displayKlines.where((k) => k.k > 0).toList();
          if (kdjData.isEmpty) return const SizedBox.shrink();
          final jValues = kdjData.map((k) => k.j).toList();
          final minJ = jValues.reduce((a, b) => a < b ? a : b);
          final maxJ = jValues.reduce((a, b) => a > b ? a : b);
          final kdjMinY = minJ < 0 ? minJ - 5 : 0.0;
          final kdjMaxY = maxJ > 100 ? maxJ + 5 : 100.0;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    const Text('KDJ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, color: Colors.deepOrange),
                    const SizedBox(width: 4),
                    const Text('K', style: TextStyle(color: Colors.white, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, color: Colors.cyan),
                    const SizedBox(width: 4),
                    const Text('D', style: TextStyle(color: Colors.white, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, color: Colors.purpleAccent),
                    const SizedBox(width: 4),
                    const Text('J', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
              Container(
                height: 100,
                padding: const EdgeInsets.all(8),
                child: LineChart(
                  LineChartData(
                    minY: kdjMinY,
                    maxY: kdjMaxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) {
                        if (value == 20 || value == 80) {
                          return const FlLine(color: Colors.white24, strokeWidth: 1, dashArray: [5, 5]);
                        }
                        if (value == 50) {
                          return const FlLine(color: Colors.white12, strokeWidth: 0.5, dashArray: [2, 4]);
                        }
                        return FlLine(color: Colors.white10, strokeWidth: 0.5);
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: _kChartLeftReservedSize,
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
                        spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.k)).toList(),
                        isCurved: false,
                        color: Colors.deepOrange,
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.d)).toList(),
                        isCurved: false,
                        color: Colors.cyan,
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: displayKlines.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.j)).toList(),
                        isCurved: false,
                        color: Colors.purpleAccent,
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildSignalList() {
    if (_analysis == null || _analysis!.signals.isEmpty)
      return Center(
        child: Text('暂无分析数据', style: TextStyle(color: Colors.white54)),
      );

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
        if (analysis.signals.where((s) => s.type == 'buy').isNotEmpty)
          Card(
            margin: const EdgeInsets.all(8),
            color: const Color(0xFF16213e),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('机会识别', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFef5350))),
                  const SizedBox(height: 8),
                  for (final signal in analysis.signals.where((s) => s.type == 'buy').take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.trending_up, color: Color(0xFFef5350), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(signal.indicator, style: textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                                Text(signal.desc.isNotEmpty ? signal.desc : signal.description, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text('注：机会识别基于技术指标，仅供参考', style: textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11)),
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
        if (analysis.tradeLevels != null && analysis.tradeLevels!.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(8),
            color: const Color(0xFF16213e),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('交易计划', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  _buildTradeLevelRow('入场区间',
                      '${(analysis.tradeLevels!['entry_low'] as double).toStringAsFixed(2)} - ${(analysis.tradeLevels!['entry_high'] as double).toStringAsFixed(2)}',
                      Colors.white),
                  const SizedBox(height: 6),
                  _buildTradeLevelRow('目标价位',
                      '${(analysis.tradeLevels!['target'] as double).toStringAsFixed(2)}',
                      const Color(0xFFef5350)),
                  const SizedBox(height: 6),
                  _buildTradeLevelRow('止损价位',
                      '${(analysis.tradeLevels!['stop_loss'] as double).toStringAsFixed(2)}',
                      const Color(0xFF26a69a)),
                  const SizedBox(height: 6),
                  _buildTradeLevelRow('盈亏比',
                      '${(analysis.tradeLevels!['risk_reward_ratio'] as double).toStringAsFixed(1)}:1',
                      (analysis.tradeLevels!['risk_reward_ratio'] as double) >= 2 ? const Color(0xFFef5350) : Colors.orange),
                ],
              ),
            ),
          ),
        if (analysis.confluenceDetails.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(8),
            color: const Color(0xFF16213e),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('多指标共振', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(
                        '看多 ${analysis.confluenceScore}/8',
                        style: TextStyle(
                          color: analysis.confluenceScore >= 5 ? const Color(0xFFef5350) : analysis.confluenceScore >= 3 ? Colors.orange : const Color(0xFF26a69a),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: analysis.confluenceScore / 8,
                      backgroundColor: const Color(0xFF26a69a).withOpacity(0.3),
                      valueColor: AlwaysStoppedAnimation(
                        analysis.confluenceScore >= 5 ? const Color(0xFFef5350) : Colors.orange,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: analysis.confluenceDetails.map((d) {
                      final name = d['name'] as String;
                      final bull = d['bull'] as bool;
                      final bear = d['bear'] as bool;
                      final weighted = d['weighted'] as bool? ?? false;
                      Color color;
                      String label;
                      if (bull) {
                        color = const Color(0xFFef5350);
                        label = '$name ✓${weighted ? " ×2" : ""}';
                      } else if (bear) {
                        color = const Color(0xFF26a69a);
                        label = '$name ✗';
                      } else {
                        color = Colors.white38;
                        label = '$name —';
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: color.withOpacity(0.4)),
                        ),
                        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTradeLevelRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.bold)),
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
      peAnalysis = '市盈率为负，公司处于亏损状态，需关注基本面';
      peColor = Colors.red;
    } else if (pe < 15) {
      peAnalysis = '市盈率较低，估值相对便宜，具有一定安全边际';
      peColor = Colors.green;
    } else if (pe < 30) {
      peAnalysis = '市盈率适中，估值处于合理区间';
      peColor = Colors.orange;
    } else if (pe < 60) {
      peAnalysis = '市盈率偏高，市场给予较高预期，注意业绩兑现风险';
      peColor = Colors.red;
    } else {
      peAnalysis = '市盈率极高，估值泡沫风险较大，谨慎参与';
      peColor = Colors.red;
    }

    String pbAnalysis;
    Color pbColor;
    if (pb <= 0) {
      pbAnalysis = '市净率为负，资不抵债，风险极高';
      pbColor = Colors.red;
    } else if (pb < 1) {
      pbAnalysis = '市净率低于1（破净），股价低于每股净资产';
      pbColor = Colors.green;
    } else if (pb < 3) {
      pbAnalysis = '市净率适中，估值合理';
      pbColor = Colors.orange;
    } else if (pb < 6) {
      pbAnalysis = '市净率偏高，关注资产质量和盈利能力';
      pbColor = Colors.red;
    } else {
      pbAnalysis = '市净率很高，资产溢价较大，注意回调风险';
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
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0f3460).withOpacity(0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '注：估值分析仅供参考，不同行业估值标准差异较大，需结合行业特点综合判断',
            style: textTheme.bodySmall?.copyWith(color: Colors.grey[400], fontSize: 11),
          ),
        ),
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
    // 腾讯API返回的成交量单位是手(1手=100股)
    final volumeInGu = volumeInShou * 100; // 转换为股
    if (volumeInGu.abs() >= 1e8) {
      return '${(volumeInGu / 1e8).toStringAsFixed(2)}亿股';
    } else if (volumeInGu.abs() >= 1e4) {
      return '${(volumeInGu / 1e4).toStringAsFixed(2)}万股';
    }
    return '${volumeInGu.toStringAsFixed(0)}股';
  }

  String _formatAmount(double amount) {
    // 成交额单位已经是元（api_client中已从万元转为元）
    if (amount.abs() >= 1e8) {
      return '${(amount / 1e8).toStringAsFixed(2)}亿';
    } else if (amount.abs() >= 1e4) {
      return '${(amount / 1e4).toStringAsFixed(2)}万';
    }
    return '${amount.toStringAsFixed(0)}元';
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _pollingTimer?.cancel();
    _analysisRefreshTimer?.cancel();
    _timeshareData.clear();
    _timeshareAvgData.clear();
    _analysis = null;
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
  final bool showBoll;

  final Paint _upPaint = Paint()..color = const Color(0xFFef5350);
  final Paint _downPaint = Paint()..color = const Color(0xFF26a69a);
  final Paint _linePaint = Paint()..strokeWidth = 1;
  final Paint _selectedPaint = Paint()..color = Colors.white.withOpacity(0.2);
  final Paint _bollUpperPaint = Paint()
    ..color = const Color(0xFF00BCD4)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final Paint _bollMidPaint = Paint()
    ..color = Colors.white54
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;
  final Paint _bollFillPaint = Paint()
    ..color = const Color(0xFF00BCD4).withOpacity(0.05)
    ..style = PaintingStyle.fill;

  _KlinePainter(
    this.data, {
    this.selectedIndex,
    this.supportLevels = const [],
    this.resistanceLevels = const [],
    this.fibonacciLevels,
    required this.minPrice,
    required this.maxPrice,
    this.showBoll = false,
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

    if (showBoll) {
      _drawBollBands(canvas, size, padding, chartWidth, chartHeight, priceRange, barWidth, gap);
    }
  }

  void _drawBollBands(Canvas canvas, Size size, double padding, double chartWidth,
      double chartHeight, double priceRange, double barWidth, double gap) {
    if (priceRange == 0) return;

    final upperPath = Path();
    final midPath = Path();
    final lowerPath = Path();
    final fillPath = Path();
    var started = false;

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      if (d.bollUpper == 0) continue;

      final x = padding + i * (barWidth + gap) + barWidth / 2;
      final upperY = chartHeight - ((d.bollUpper - minPrice) / priceRange) * chartHeight;
      final midY = chartHeight - ((d.bollMid - minPrice) / priceRange) * chartHeight;
      final lowerY = chartHeight - ((d.bollLower - minPrice) / priceRange) * chartHeight;

      if (!started) {
        upperPath.moveTo(x, upperY);
        midPath.moveTo(x, midY);
        lowerPath.moveTo(x, lowerY);
        fillPath.moveTo(x, upperY);
        started = true;
      } else {
        upperPath.lineTo(x, upperY);
        midPath.lineTo(x, midY);
        lowerPath.lineTo(x, lowerY);
        fillPath.lineTo(x, upperY);
      }
    }

    if (!started) return;

    for (int i = data.length - 1; i >= 0; i--) {
      final d = data[i];
      if (d.bollLower == 0) continue;
      final x = padding + i * (barWidth + gap) + barWidth / 2;
      final lowerY = chartHeight - ((d.bollLower - minPrice) / priceRange) * chartHeight;
      fillPath.lineTo(x, lowerY);
    }
    fillPath.close();

    canvas.drawPath(fillPath, _bollFillPaint);
    canvas.drawPath(upperPath, _bollUpperPaint);
    canvas.drawPath(midPath, _bollMidPaint);
    canvas.drawPath(lowerPath, _bollUpperPaint);
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
    oldDelegate.fibonacciLevels != fibonacciLevels ||
    oldDelegate.showBoll != showBoll;
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

    final barTotalWidth = size.width / data.length;
    final barWidth = barTotalWidth * 0.6;
    final zeroY = size.height / 2;

    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), _axisPaint);

    for (int i = 0; i < data.length; i++) {
      final hist = data[i].macdHist;
      if (hist == 0) continue;
      final x = i * barTotalWidth + barTotalWidth / 2;
      final h = (hist / macdAbsMax) * zeroY;
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

class _VolumeHistogramPainter extends CustomPainter {
  final List<HistoryKline> data;

  final Paint _upPaint = Paint()..color = const Color(0xFFef5350);
  final Paint _downPaint = Paint()..color = const Color(0xFF26a69a);

  _VolumeHistogramPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    double maxVol = 0;
    for (final d in data) {
      if (d.volume > maxVol) maxVol = d.volume;
    }
    if (maxVol == 0) return;

    final barTotalWidth = size.width / data.length;
    final barWidth = barTotalWidth * 0.6;

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      if (d.volume == 0) continue;
      final x = i * barTotalWidth + barTotalWidth / 2;
      final h = (d.volume / maxVol) * size.height;
      final paint = d.close >= d.open ? _upPaint : _downPaint;

      canvas.drawRect(
        Rect.fromLTWH(x - barWidth / 2, size.height - h, barWidth, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VolumeHistogramPainter oldDelegate) => oldDelegate.data != data;
}
