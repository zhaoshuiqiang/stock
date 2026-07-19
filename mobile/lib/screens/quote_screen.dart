import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/market_context_provider.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../analysis/decision_calibration_service.dart';
import '../analysis/backtest_engine.dart';
import '../analysis/limit_up_analyzer.dart';
import '../storage/database_service.dart';
import '../widgets/signal_card.dart';
import '../widgets/technical_indicators_panel.dart';
import '../widgets/strategy_panel.dart';
import '../widgets/trading_dashboard.dart';
import '../core/trading_session.dart';
import '../analysis/intraday_level_analyzer.dart';
import '../analysis/sector_rotation.dart';
import '../analysis/ai_layer.dart';
import '../analysis/archive_service.dart';
import '../core/ai_config.dart';

const _kChartLeftReservedSize = 42.0;

// ─── 颜色常量 ──────────────────────────────────────────
const Color _kUpColor = Color(0xFFef5350); // A股上涨红
const Color _kDownColor = Color(0xFF26a69a); // A股下跌绿
const Color _kCardColor = Color(0xFF161B22); // 卡片背景
const Color _kLimitUpGold = Color(0xFFFFB000); // 涨停金
const Color _kBgColor = Color(0xFF0D1117); // 主背景
const Color _kTextSecondary = Color(0xFF8B949E); // 次要文字
const Color _kStrongRed = Color(0xFFE74C3C); // 强红
const Color _kOrange = Color(0xFFE67E22); // 橙色
const Color _kBollColor = Color(0xFF00BCD4); // BOLL紫青
const Color _kGoldCross = Color(0xFFFFD700); // 黄金交叉

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

class QuoteScreenState extends State<QuoteScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ApiClient _apiClient = ApiClient();
  final DecisionCalibrationService _calibrationService =
      DecisionCalibrationService();
  final DatabaseService _dbService = DatabaseService();
  Timer? _pollingTimer;
  Timer? _analysisRefreshTimer;
  QuoteData? _quote;
  List<HistoryKline> _klines = [];
  AnalysisResult? _analysis;
  Position? _heldPosition;
  List<Map<String, dynamic>>? _scoreTrend; // v3.13: 评分趋势数据
  MarketContext? _marketContext;
  bool _isLoading = true;
  bool _isAnalysisRefreshing = false;
  bool _isFavorite = false;
  bool _isRealtime = false;
  bool _isMarketOpen = true;
  double? _lastChangePct;
  String _lastUpdateTime = '';
  TabController? _tabController;
  int _updateCount = 0; // 轮询更新计数，用于控制分析刷新频率
  // AI分析状态
  String? _aiStatus;
  int _aiProgress = 0;
  bool _isAIAnalyzing = false;
  // 模板分析和自定义提问状态
  AnalysisTemplate _selectedTemplate = AnalysisTemplate.debate;
  final List<AIChatResult> _chatHistory = [];
  final TextEditingController _questionController = TextEditingController();
  bool _isAsking = false;
  // 重试倒计时
  int _retryCountdown = 0;
  Timer? _retryTimer;
  // 分时图数据：key=分钟偏移量(0~239), value=价格
  Map<int, double> _timeshareData = {};
  // 分时图均价数据：key=分钟偏移量, value=均价
  Map<int, double> _timeshareAvgData = {};
  // 分时图分钟成交量：key=分钟偏移量, value=成交量(股)
  Map<int, double> _timeshareMinuteVolumes = {};
  // 分时低吸高抛分析结果
  IntradayLevelResult? _intradayLevelResult;
  // 已弹窗提醒过的信号 minuteOffset（避免重复提醒）
  final Set<int> _notifiedSignalOffsets = {};
  int _lastAnalyzedOffset = -1;
  // 用于计算每分钟成交量的累积基准
  double _lastCumulativeVolume = 0;
  // 分时累计量的日期标记，跨日重置
  String? _lastTimeshareDate;
  int? _selectedKlineIndex;
  bool _showFibonacci = false;
  bool _showBoll = false;
  Map<String, dynamic>? _techAnalysis;
  bool _timeshareLoadFailed = false;
  // 打板池缓存的 limitUpAnalysis（含真实首封时间），优先于 analyzeFromDaily 的结果
  // 保证 K线图页与打板梯队页的次日溢价等显示一致
  LimitUpAnalysis? _limitUpAnalysisFromPool;

  /// 当前生效的打板分析：优先用打板池缓存（有首封时间更准确），无则回退到日K推断
  LimitUpAnalysis? get _effectiveLimitUpAnalysis =>
      _limitUpAnalysisFromPool ?? _analysis?.limitUpAnalysis;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 7, vsync: this);
    _loadHeldPosition();
    _loadData();
    _checkFavorite();
    _startRealtime();
  }

  Future<void> _checkFavorite() async {
    _isFavorite = await _dbService.isInWatchlist(widget.code);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleFavorite() async {
    setState(() {
      _isFavorite = !_isFavorite;
    });

    if (_isFavorite) {
      await _dbService.addToWatchlist(widget.code, widget.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加到自选股')),
      );
    } else {
      await _dbService.removeFromWatchlist(widget.code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从自选股移除')),
      );
    }
  }

  Future<void> _archiveCurrent() async {
    if (_analysis == null) return;
    final result = await ArchiveService.archiveStock(
      code: widget.code,
      name: widget.name,
      analysis: _analysis,
      db: _dbService,
    );
    if (!mounted) return;
    final msg = result.archived
        ? (result.captured ? '已留档（含命中率跟踪）' : '已留档')
        : '30天内同向已留档，无需重复';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                setDialogState(() {
                  searchResults = [];
                  searching = false;
                });
                return;
              }
              setDialogState(() {
                searching = true;
              });
              try {
                final results = await _apiClient.searchStocks(keyword);
                setDialogState(() {
                  searchResults = results;
                  searching = false;
                });
              } catch (_) {
                setDialogState(() {
                  searching = false;
                });
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
              backgroundColor: _kBgColor,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
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
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white54),
                        suffixIcon: searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              )
                            : null,
                        filled: true,
                        fillColor: _kCardColor,
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
                          child: Text('自选股',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
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
                                  isCurrent
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isCurrent ? _kUpColor : Colors.white38,
                                  size: 20,
                                ),
                                title: Text(item.name,
                                    style: TextStyle(
                                      color: isCurrent
                                          ? Colors.white54
                                          : Colors.white,
                                      fontSize: 14,
                                    )),
                                subtitle: Text(item.code,
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                                onTap: isCurrent
                                    ? null
                                    : () => switchStock(item.code, item.name),
                              );
                            },
                          ),
                        ),
                      ] else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('输入关键词搜索股票',
                                style: TextStyle(color: Colors.white38)),
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
                              title: Text(stock.name,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              subtitle: Text(stock.code,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12)),
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
        final timeshareResult =
            await _apiClient.getTimeshareData(widget.code, bypassCache: true);
        if (timeshareResult != null && mounted) {
          // ─── 在 setState 外执行 VWAP 重算和分时分析（耗时操作），避免 build 期间卡顿 ───
          final apiPrices = timeshareResult['prices'] ?? {};
          final apiVolumes = timeshareResult['volumes'] ?? <int, double>{};
          final apiAmounts = timeshareResult['amounts'] ?? <int, double>{};
          // API数据作为基础，轮询数据覆盖同一分钟槽位
          _timeshareData = {...apiPrices, ..._timeshareData};
          // 重新计算累计VWAP
          final preCloseVal = _quote?.preClose ?? 0;
          final sortedOffsets = _timeshareData.keys.toList()..sort();
          double cumAmount = 0;
          double cumVolume = 0;
          _timeshareAvgData.clear();
          for (final offset in sortedOffsets) {
            cumAmount += apiAmounts[offset] ?? 0;
            cumVolume += apiVolumes[offset] ?? 0;
            if (cumVolume > 0) {
              _timeshareAvgData[offset] = cumAmount / (cumVolume * 100);
            } else {
              _timeshareAvgData[offset] = preCloseVal;
            }
          }
          // 保存分钟成交量
          _timeshareMinuteVolumes = Map<int, double>.from(apiVolumes);
          // VWAP累计计算完成
          _timeshareLoadFailed = false;
          _lastAnalyzedOffset = -1; // 强制重新分析
          _analyzeIntradayLevels(); // 在setState外分析，数据已就绪
          // setState 仅触发重建
          setState(() {});
        }
      }

      final validatedQuote =
          await _apiClient.getRealtimeQuoteWithValidation(widget.code);
      if (!mounted) return;
      if (validatedQuote != null) {
        _handleQuoteUpdate(validatedQuote.quote);
      }
    });

    // 分析模块独立刷新定时器：60秒周期（降低频率减少卡顿）
    _analysisRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _refreshAnalysis();
    });
  }

  Future<void> _refreshAnalysis() async {
    if (!TradingSession.isInTradingSession()) return;

    setState(() {
      _isAnalysisRefreshing = true;
    });

    try {
      // Fetch fresh klines bypassing cache
      final klines = await _apiClient.getStockHistory(widget.code, days: 120);
      if (klines.isEmpty) {
        if (mounted)
          setState(() {
            _isAnalysisRefreshing = false;
          });
        return;
      }
      if (!mounted) return;

      final calculated = calcAllIndicators(klines);
      final marketContext = await MarketContextProvider.getMarketContext();
      var analysis = generateAnalysis(
        calculated,
        _quote,
        marketContext: marketContext,
        enableAsyncSideEffects: false,
        onAIUpdate: (aiReasons) {
          if (mounted) {
            setState(() {
              _isAIAnalyzing = false;
            });
          }
        },
      );
      try {
        analysis = await _calibrationService.enrich(
          analysis,
          asOfTradeDate: calculated.last.date,
        );
      } catch (e) {
        debugPrint('QuoteScreen.calibration refresh: $e');
      }

      // Recalculate tech analysis
      final tech = <String, dynamic>{};
      final sr = calcSupportResistance(calculated);
      tech['support_levels'] = sr['support'] ?? [];
      tech['resistance_levels'] = sr['resistance'] ?? [];
      if (_showFibonacci) {
        tech['fibonacci'] = calcFibonacci(calculated);
      }

      if (!mounted) return;
      setState(() {
        _klines = calculated;
        _analysis = analysis;
        _marketContext = marketContext;
        _techAnalysis = tech;
        _isAnalysisRefreshing = false;
      });
      _refreshLimitUpAnalysisFromPool(); // 异步用打板池缓存覆盖
      // v3.13: 异步加载评分趋势（不阻塞分析刷新）
      _loadScoreTrend();
    } catch (e) {
      if (mounted)
        setState(() {
          _isAnalysisRefreshing = false;
        });
    }
  }

  /// 从打板池缓存加载该股票的 LimitUpAnalysis（含真实首封时间），
  /// 保证与打板梯队页显示一致。打板池存裸6位代码，需去掉市场前缀。
  Future<void> _refreshLimitUpAnalysisFromPool() async {
    try {
      final code = widget.code;
      final bareCode = (code.startsWith('sh') ||
              code.startsWith('sz') ||
              code.startsWith('bj'))
          ? code.substring(2)
          : code;
      final poolAnalysis = await _dbService.getLimitUpAnalysisByCode(bareCode);
      if (mounted && poolAnalysis != null) {
        setState(() => _limitUpAnalysisFromPool = poolAnalysis);
      }
    } catch (e) {
      debugPrint('_refreshLimitUpAnalysisFromPool failed: $e');
    }
  }

  /// v3.13: 加载评分趋势数据
  Future<void> _loadScoreTrend() async {
    try {
      final trend = await _dbService.getScoreTrend(widget.code);
      if (mounted) {
        setState(() => _scoreTrend = trend);
      }
    } catch (e) {
      debugPrint('_loadScoreTrend failed: $e');
    }
  }

  Future<void> _handleQuoteUpdate(QuoteData quote) async {
    if (!mounted) return;
    if (quote.code != widget.code) return;

    // ─── 在 setState 外执行耗时计算，避免 build 期间阻塞 UI ───

    // 1. 合并数据：保留原有PE/PB等字段，更新价格和主力资金字段
    final QuoteData mergedQuote;
    if (_quote != null) {
      final prev = _quote!;
      final newHigh = quote.high > 0 ? quote.high : prev.high;
      final newLow = quote.low > 0 ? quote.low : prev.low;
      final newPreClose = quote.preClose > 0 ? quote.preClose : prev.preClose;
      mergedQuote = QuoteData(
        code: prev.code,
        name: prev.name,
        price: quote.price,
        change: quote.change,
        changePct: quote.changePct,
        open: quote.open > 0 ? quote.open : prev.open,
        high: newHigh,
        low: newLow,
        preClose: newPreClose,
        volume: quote.volume > 0 ? quote.volume : prev.volume,
        amount: quote.amount > 0 ? quote.amount : prev.amount,
        amplitude:
            newPreClose > 0 ? (newHigh - newLow) / newPreClose * 100 : 0.0,
        turnover: quote.turnover > 0 ? quote.turnover : prev.turnover,
        pe: prev.pe,
        pb: prev.pb,
        totalMarketCap: prev.totalMarketCap,
        circulatingMarketCap: prev.circulatingMarketCap,
        mainInflow: quote.mainInflow != 0 ? quote.mainInflow : prev.mainInflow,
        mainOutflow:
            quote.mainOutflow != 0 ? quote.mainOutflow : prev.mainOutflow,
        mainNetFlow:
            quote.mainNetFlow != 0 ? quote.mainNetFlow : prev.mainNetFlow,
        mainNetFlowRate: quote.mainNetFlowRate != 0
            ? quote.mainNetFlowRate
            : prev.mainNetFlowRate,
        volumeRatio:
            quote.volumeRatio > 0 ? quote.volumeRatio : prev.volumeRatio,
      );
    } else {
      mergedQuote = quote;
    }

    // 2. 检测涨跌幅显著变化（超过1%），触发即时完整分析刷新
    _updateCount++;
    final changeDiff = _lastChangePct != null
        ? (quote.changePct - _lastChangePct!).abs()
        : 0.0;
    _lastChangePct = quote.changePct;

    // 3. 在 setState 外执行完整分析管道（耗时操作），避免 build 期间卡顿
    AnalysisResult? newAnalysis;
    if (_analysis != null &&
        (_updateCount % 5 == 0 || changeDiff > 1.0) &&
        _klines.isNotEmpty) {
      try {
        newAnalysis = generateAnalysis(
          _klines,
          mergedQuote,
          marketContext: _marketContext,
          enableAsyncSideEffects: false,
        );
        newAnalysis = await _calibrationService.enrich(
          newAnalysis,
          asOfTradeDate: _klines.last.date,
        );
      } catch (e) {
        debugPrint('generateAnalysis 失败: $e');
      }
    }

    // 4. setState 内仅做轻量赋值
    setState(() {
      _quote = mergedQuote;
      _isRealtime = true;
      _lastUpdateTime = DateFormat('HH:mm:ss').format(DateTime.now());

      // 分时图：按交易时间分钟映射价格
      _addTimesharePoint(quote.price, quote.volume, quote.amount);

      if (newAnalysis != null) {
        _analysis = newAnalysis;
      } else if (_analysis != null) {
        // 非刷新周期或重算失败：仅更新 quote 引用，保留所有已有分析字段
        _analysis = _analysis!.copyWith(quote: mergedQuote);
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 并行加载所有数据（不再串行等待）
      final results = await Future.wait([
        _apiClient.getRealtimeQuoteWithValidation(widget.code),
        _apiClient.getStockHistory(widget.code, days: 120),
        _apiClient.getStockSector(widget.code),
        _apiClient.getHotSectors(),
        _apiClient.getTimeshareData(widget.code),
        MarketContextProvider.getMarketContext(),
      ]);

      var quote = (results[0] as ValidatedQuoteData?)?.quote;
      final klines = results[1] as List<HistoryKline>;
      final sectorName = results[2] as String;
      final hotSectors = results[3] as List<SectorInfo>;
      final timeshareResult = results[4] as Map<String, dynamic>?;
      final marketContext = results[5] as MarketContext;

      final calculated = calcAllIndicators(klines);

      final sectorData = hotSectors
          .map((s) => SectorData(
                name: s.name,
                code: s.code,
                changePct: s.changePct,
                limitUpCount: s.stockCount,
                mainNetFlow: 0,
              ))
          .toList();
      final sectorRotationResult =
          SectorRotation.analyze(sectorList: sectorData);

      if (quote != null) {
        quote = QuoteData(
          code: quote.code,
          name: quote.name,
          price: quote.price,
          open: quote.open,
          high: quote.high,
          low: quote.low,
          preClose: quote.preClose,
          volume: quote.volume,
          amount: quote.amount,
          change: quote.change,
          changePct: quote.changePct,
          amplitude: quote.amplitude,
          turnover: quote.turnover,
          pe: quote.pe,
          pb: quote.pb,
          totalMarketCap: quote.totalMarketCap,
          circulatingMarketCap: quote.circulatingMarketCap,
          mainInflow: quote.mainInflow,
          mainOutflow: quote.mainOutflow,
          mainNetFlow: quote.mainNetFlow,
          mainNetFlowRate: quote.mainNetFlowRate,
          sectorName: sectorName,
        );
      }

      var analysis = generateAnalysis(
        calculated,
        quote,
        marketContext: marketContext,
        sectorName: sectorName,
        sectorAnalysis: sectorRotationResult.topSectors,
        enableAsyncSideEffects: false,
      );
      try {
        analysis = await _calibrationService.enrich(
          analysis,
          asOfTradeDate: calculated.last.date,
        );
      } catch (e) {
        debugPrint('QuoteScreen.calibration load: $e');
      }

      // 计算支撑压力位和斐波那契
      final tech = <String, dynamic>{};
      final sr = calcSupportResistance(calculated);
      tech['support_levels'] = sr['support'] ?? [];
      tech['resistance_levels'] = sr['resistance'] ?? [];
      if (_showFibonacci) {
        tech['fibonacci'] = calcFibonacci(calculated);
      }

      if (!mounted) return;

      setState(() {
        _quote = quote;
        _klines = calculated;
        _analysis = analysis;
        _marketContext = marketContext;
        _techAnalysis = tech;
        if (timeshareResult != null) {
          _timeshareData = timeshareResult['prices'] ?? {};
          // 计算累计VWAP：按分钟偏移量顺序累加成交量和成交额
          final volumes = timeshareResult['volumes'] ?? <int, double>{};
          final amounts = timeshareResult['amounts'] ?? <int, double>{};
          _timeshareMinuteVolumes = Map<int, double>.from(volumes);
          final preCloseVal = quote?.preClose ?? 0;
          final sortedOffsets = _timeshareData.keys.toList()..sort();
          double cumAmount = 0;
          double cumVolume = 0;
          _timeshareAvgData.clear();
          for (final offset in sortedOffsets) {
            cumAmount += amounts[offset] ?? 0;
            cumVolume += volumes[offset] ?? 0;
            if (cumVolume > 0) {
              _timeshareAvgData[offset] = cumAmount / (cumVolume * 100);
            } else {
              _timeshareAvgData[offset] = preCloseVal;
            }
          }
          // VWAP累计计算完成
          _timeshareLoadFailed = false;
          _lastAnalyzedOffset = -1; // 强制重新分析
          _analyzeIntradayLevels(); // 在setState内分析
        } else {
          // 分时数据加载失败，设置降级标志（不限交易时段）
          _timeshareLoadFailed = true;
        }
      });
      _refreshLimitUpAnalysisFromPool(); // 异步用打板池缓存覆盖
      // v3.13: 异步加载评分趋势
      _loadScoreTrend();
    } catch (e) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: '留档',
            onPressed: _analysis?.shortTermDecision != null ? _archiveCurrent : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_quote != null) _buildQuoteHeader(_quote!, color),
          TabBar(
            controller: _tabController,
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            labelStyle: const TextStyle(fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: const [
              Tab(text: '实时'),
              Tab(text: 'K线'),
              Tab(text: '信号'),
              Tab(text: '战法'),
              Tab(text: '决策'),
              Tab(text: 'AI'),
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
                StrategyPanel(
                    klines: _klines,
                    signals: _analysis?.signals ?? [],
                    marketStructure: _analysis?.marketStructure),
                _buildDashboard(),
                _buildAIAnalysisTab(),
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
                style: textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(width: 8),
              if (_isRealtime || !_isMarketOpen)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  Text('开盘',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(quote.open.toStringAsFixed(2),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('最高',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(quote.high.toStringAsFixed(2),
                      style: textTheme.bodyMedium?.copyWith(color: Colors.red)),
                ],
              ),
              Column(
                children: [
                  Text('最低',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(quote.low.toStringAsFixed(2),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.green)),
                ],
              ),
              Column(
                children: [
                  Text('昨收',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(quote.preClose.toStringAsFixed(2),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.white)),
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
                  Text('成交量',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(_formatVolume(quote.volume),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('成交额',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(_formatAmount(quote.amount),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('市盈率',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(quote.pe.toStringAsFixed(1),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ],
              ),
              Column(
                children: [
                  Text('市净率',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[400])),
                  Text(quote.pb.toStringAsFixed(2),
                      style:
                          textTheme.bodyMedium?.copyWith(color: Colors.white)),
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
                  const Text('总市值',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(_formatMarketCap(quote.totalMarketCap),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              Column(
                children: [
                  const Text('流通市值',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(_formatMarketCap(quote.circulatingMarketCap),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              Column(
                children: [
                  const Text('换手率',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('${quote.turnover.toStringAsFixed(2)}%',
                      style: TextStyle(
                          color: quote.turnover > 10
                              ? Colors.orange
                              : Colors.white,
                          fontSize: 13)),
                ],
              ),
              Column(
                children: [
                  const Text('振幅',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('${quote.amplitude.toStringAsFixed(2)}%',
                      style: TextStyle(
                          color: quote.amplitude > 5
                              ? Colors.orange
                              : Colors.white,
                          fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kCardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('主力资金',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('净流入',
                            style: textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[400])),
                        Text(
                          '${quote.mainNetFlow >= 0 ? '+' : ''}${_formatAmount(quote.mainNetFlow)}',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: mainNetFlowColor),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text('净流入率',
                            style: textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[400])),
                        Text(
                          '${quote.mainNetFlowRate >= 0 ? '+' : ''}${quote.mainNetFlowRate.toStringAsFixed(2)}%',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: mainNetFlowColor),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text('主力流入',
                            style: textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[400])),
                        Text(_formatAmount(quote.mainInflow),
                            style: textTheme.bodyMedium
                                ?.copyWith(color: Colors.white)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('主力流出',
                            style: textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[400])),
                        Text(_formatAmount(quote.mainOutflow),
                            style: textTheme.bodyMedium
                                ?.copyWith(color: Colors.white)),
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

  /// 对K线数据进行降采样，减少渲染数据点数量
  List<HistoryKline> _downsampleKlines(
      List<HistoryKline> klines, int maxPoints) {
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
    if (offset < 120) {
      final totalMinutes = 9 * 60 + 30 + offset;
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    } else {
      final totalMinutes = 13 * 60 + (offset - 120);
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
  }

  /// 添加分时图数据点
  /// [volume] 和 [amount] 是当日累计值，内部计算每分钟差值
  void _addTimesharePoint(double price, double volume, double amount) {
    final now = DateTime.now();
    // 检测日期变更，重置累计量
    final today = now.toUtc().add(const Duration(hours: 8));
    final todayStr = today.toIso8601String().substring(0, 10);
    if (_lastTimeshareDate != null && _lastTimeshareDate != todayStr) {
      _lastCumulativeVolume = 0;
    }
    _lastTimeshareDate = todayStr;
    final offset = IntradayLevelAnalyzer.timeToMinuteOffset(now);
    if (offset == null) return; // 非交易时间不记录

    // 限制范围
    final clampedOffset = offset.clamp(0, 240);
    _timeshareData[clampedOffset] = price;

    // 计算每分钟成交量（从累积值差值）
    if (volume > 0 && volume > _lastCumulativeVolume) {
      _timeshareMinuteVolumes[clampedOffset] = volume - _lastCumulativeVolume;
    }
    _lastCumulativeVolume = volume;

    // 计算均价 = 累计成交额 / (累计成交量 * 100)
    if (amount > 0 && volume > 0) {
      _timeshareAvgData[clampedOffset] = amount / (volume * 100);
    }
  }

  /// 分时低吸高抛分析
  void _analyzeIntradayLevels() {
    if (_timeshareData.isEmpty) return;
    final now = DateTime.now();
    final currentOffset = IntradayLevelAnalyzer.timeToMinuteOffset(now) ?? 240;

    // 下午开盘时强制重新分析（午休后offset都是120，需特殊处理）
    if (now.hour >= 13 && _lastAnalyzedOffset < 120) {
      _lastAnalyzedOffset = -1;
    }

    // 避免同一分钟重复分析
    if (currentOffset == _lastAnalyzedOffset && _intradayLevelResult != null)
      return;
    _lastAnalyzedOffset = currentOffset;

    try {
      final oldResult = _intradayLevelResult;
      _intradayLevelResult = IntradayLevelAnalyzer.analyze(
        prices: _timeshareData,
        volumes: _timeshareMinuteVolumes,
        vwapData: _timeshareAvgData,
        preClose: _quote?.preClose ?? 0,
        openPrice: _quote?.open ?? 0,
        dayHigh: _quote?.high ?? 0,
        dayLow: _quote?.low ?? 0,
        currentOffset: currentOffset,
        estimatedAmplitude: _quote?.amplitude,
      );
      // 检测新增高置信度信号并弹窗提醒
      _notifyNewIntradaySignals(oldResult);
    } catch (_) {
      // 分析失败不阻塞UI
    }
  }

  /// 检测新增的高置信度做T信号，弹窗提醒
  void _notifyNewIntradaySignals(IntradayLevelResult? oldResult) {
    final result = _intradayLevelResult;
    if (result == null || !mounted) return;

    final newSignals = <IntradayLevelPoint>[];
    // 检查买入信号（低吸）
    for (final s in result.buySignals) {
      if (!s.isHighConfidence) continue;
      if (_notifiedSignalOffsets.contains(s.minuteOffset)) continue;
      final isNew = oldResult == null ||
          !oldResult.buySignals.any((o) => o.minuteOffset == s.minuteOffset);
      if (isNew) {
        newSignals.add(s);
        _notifiedSignalOffsets.add(s.minuteOffset);
      }
    }
    // 检查卖出信号（高抛）
    for (final s in result.sellSignals) {
      if (!s.isHighConfidence) continue;
      if (_notifiedSignalOffsets.contains(s.minuteOffset)) continue;
      final isNew = oldResult == null ||
          !oldResult.sellSignals.any((o) => o.minuteOffset == s.minuteOffset);
      if (isNew) {
        newSignals.add(s);
        _notifiedSignalOffsets.add(s.minuteOffset);
      }
    }
    if (newSignals.isEmpty) return;

    // 延迟到帧结束后显示 SnackBar（避免在 setState 内调用 ScaffoldMessenger）
    final s = newSignals.first;
    final isBuy = s.direction == IntradayDirection.buy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${isBuy ? "低吸信号" : "高抛信号"}: ${s.shortLabel} ¥${s.price.toStringAsFixed(2)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 4),
          backgroundColor:
              isBuy ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
        ),
      );
    });
  }

  Widget _buildRealtimeChart() {
    final preClose = _quote?.preClose ?? 0;
    final currentPrice = _quote?.price ?? 0;

    if (_timeshareData.isEmpty && _timeshareLoadFailed) {
      return Center(
          child: Text('分时历史数据加载失败，仅显示实时数据',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)));
    }
    if (_timeshareData.isEmpty) {
      return Center(
          child: Text('暂无分时数据',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)));
    }

    // 构建价格线数据点（按分钟偏移量排序）
    final sortedKeys = _timeshareData.keys.toList()..sort();
    final priceSpots = sortedKeys
        .map((k) => FlSpot(k.toDouble(), _timeshareData[k]!))
        .toList();

    // 构建均价线数据点
    final avgSortedKeys = _timeshareAvgData.keys.toList()..sort();
    final avgSpots = avgSortedKeys
        .map((k) => FlSpot(k.toDouble(), _timeshareAvgData[k]!))
        .toList();

    // 分时低吸高抛分析（在数据加载时已触发，此处仅消费结果）
    final signalResult = _intradayLevelResult;
    final buySpots = <FlSpot>[];
    final sellSpots = <FlSpot>[];
    final buySpotSignals = <IntradayLevelPoint>[];
    final sellSpotSignals = <IntradayLevelPoint>[];
    if (signalResult != null) {
      for (final s in signalResult.buySignals) {
        final price = _timeshareData[s.minuteOffset];
        if (price != null) {
          buySpots.add(FlSpot(s.minuteOffset.toDouble(), price));
          buySpotSignals.add(s);
        }
      }
      for (final s in signalResult.sellSignals) {
        final price = _timeshareData[s.minuteOffset];
        if (price != null) {
          sellSpots.add(FlSpot(s.minuteOffset.toDouble(), price));
          sellSpotSignals.add(s);
        }
      }
    }

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
    final priceColor = isUp ? _kUpColor : _kDownColor;

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
    final timeLabels = {
      0: '9:30',
      30: '10:00',
      60: '10:30',
      90: '11:00',
      120: '11:30/13:00',
      150: '13:30',
      180: '14:00',
      210: '14:30',
      240: '15:00'
    };

    // 涨跌幅百分比（右侧Y轴）- 用于参考线标注

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('分时图',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                if (_isRealtime || !_isMarketOpen)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.white10, strokeWidth: 0.5),
                  getDrawingVerticalLine: (value) =>
                      FlLine(color: Colors.white10, strokeWidth: 0.5),
                ),
                extraLinesData:
                    ExtraLinesData(horizontalLines: horizontalLines),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) {
                        final pct = preClose > 0
                            ? (value - preClose) / preClose * 100
                            : 0.0;
                        Color c = Colors.white38;
                        if (value > preClose) c = _kUpColor;
                        if (value < preClose) c = _kDownColor;
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
                        final pct = preClose > 0
                            ? (value - preClose) / preClose * 100
                            : 0.0;
                        Color c = Colors.white38;
                        if (pct > 0) c = _kUpColor;
                        if (pct < 0) c = _kDownColor;
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
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 9),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final offset = spot.x.toInt();
                        final timeStr =
                            _minuteOffsetToTime(offset.clamp(0, 239));
                        final pct = preClose > 0
                            ? (spot.y - preClose) / preClose * 100
                            : 0.0;
                        return LineTooltipItem(
                          '$timeStr  ${spot.y.toStringAsFixed(2)}  ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                          TextStyle(
                              color:
                                  spot.y >= preClose ? _kUpColor : _kDownColor,
                              fontSize: 12),
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
                  // 低吸信号标记（绿色圆点）
                  if (buySpots.isNotEmpty)
                    LineChartBarData(
                      spots: buySpots,
                      isCurved: false,
                      color: Colors.transparent,
                      barWidth: 0,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, x, barData, spotIndex) {
                          final isHigh = spotIndex < buySpotSignals.length
                              ? buySpotSignals[spotIndex].isHighConfidence
                              : false;
                          return FlDotCirclePainter(
                            radius: isHigh ? 5.5 : 4.5,
                            color: Colors.greenAccent,
                            strokeWidth: isHigh ? 2.0 : 1.5,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  // 高抛信号标记（红色圆点）
                  if (sellSpots.isNotEmpty)
                    LineChartBarData(
                      spots: sellSpots,
                      isCurved: false,
                      color: Colors.transparent,
                      barWidth: 0,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, x, barData, spotIndex) {
                          final isHigh = spotIndex < sellSpotSignals.length
                              ? sellSpotSignals[spotIndex].isHighConfidence
                              : false;
                          return FlDotCirclePainter(
                            radius: isHigh ? 5.5 : 4.5,
                            color: Colors.redAccent,
                            strokeWidth: isHigh ? 2.0 : 1.5,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                ],
              ),
            ),
          ),
          _buildIntradayLevelPanel(),
          _buildMainFundFlowBar(),
        ],
      ),
    );
  }

  /// 分时低吸高抛信号摘要面板
  Widget _buildIntradayLevelPanel() {
    final result = _intradayLevelResult;
    if (result == null ||
        (result.buySignals.isEmpty && result.sellSignals.isEmpty)) {
      return const SizedBox.shrink();
    }

    final buyItems = result.buySignals.take(2).toList();
    final sellItems = result.sellSignals.take(2).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('日内做T信号',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
              const Spacer(),
              Builder(builder: (context) {
                final trendLabel = result.trend == IntradayTrend.bullish
                    ? '偏多'
                    : result.trend == IntradayTrend.bearish
                        ? '偏空'
                        : '震荡';
                final trendColor = result.trend == IntradayTrend.bullish
                    ? _kUpColor
                    : result.trend == IntradayTrend.bearish
                        ? _kDownColor
                        : Colors.grey;
                return Text(
                  trendLabel,
                  style: TextStyle(color: trendColor, fontSize: 10),
                );
              }),
            ],
          ),
          if (buyItems.isNotEmpty || sellItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (buyItems.isNotEmpty)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.arrow_upward,
                                  color: Colors.greenAccent, size: 12),
                              SizedBox(width: 2),
                              Text('低吸',
                                  style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          ...buyItems.map((s) => _buildSignalChip(s)),
                        ],
                      ),
                    ),
                  if (buyItems.isNotEmpty && sellItems.isNotEmpty)
                    const SizedBox(width: 8),
                  if (sellItems.isNotEmpty)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.arrow_downward,
                                  color: Colors.redAccent, size: 12),
                              SizedBox(width: 2),
                              Text('高抛',
                                  style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          ...sellItems.map((s) => _buildSignalChip(s)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSignalChip(IntradayLevelPoint signal) {
    final isBuy = signal.direction == IntradayDirection.buy;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: isBuy
                  ? Colors.greenAccent.withOpacity(0.15)
                  : Colors.redAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
              border: signal.isHighConfidence
                  ? Border.all(
                      color: isBuy
                          ? Colors.greenAccent.withOpacity(0.5)
                          : Colors.redAccent.withOpacity(0.5),
                      width: 0.5)
                  : null,
            ),
            child: Text(
              signal.shortLabel,
              style: TextStyle(
                color: isBuy ? Colors.greenAccent : Colors.redAccent,
                fontSize: 9,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            signal.price.toStringAsFixed(2),
            style: TextStyle(
              color: isBuy ? Colors.green : Colors.red,
              fontSize: 10,
              fontWeight:
                  signal.isHighConfidence ? FontWeight.bold : FontWeight.normal,
            ),
          ),
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
    if (total == 0) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kCardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('主力资金数据加载中...',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      );
    }

    final inflowRatio = inflow / total;
    final outflowRatio = outflow / total;
    final netFlow = quote.mainNetFlow;
    final isBuyDominant = netFlow >= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('主力买卖力度',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                '${isBuyDominant ? '买入' : '卖出'}主导 ${(inflowRatio * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: isBuyDominant ? _kUpColor : _kDownColor,
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
                    color: _kUpColor,
                    alignment: Alignment.center,
                    child: inflowRatio >= 0.05
                        ? Text(
                            '${(inflowRatio * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
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
                    color: _kDownColor,
                    alignment: Alignment.center,
                    child: outflowRatio >= 0.05
                        ? Text(
                            '${(outflowRatio * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
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
                style: const TextStyle(color: _kUpColor, fontSize: 11),
              ),
              Text(
                '净流量 ${netFlow >= 0 ? "+" : ""}${_formatAmount(netFlow)}',
                style: TextStyle(
                  color: netFlow >= 0 ? _kUpColor : _kDownColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '流出 ${_formatAmount(outflow)}',
                style: const TextStyle(color: _kDownColor, fontSize: 11),
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
            const Text('K线数据加载失败',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadData,
              child: const Text('点击重试'),
            ),
          ],
        ),
      );

    // Downsample klines for display when there are too many data points
    final displayKlines =
        _klines.length > 200 ? _downsampleKlines(_klines, 200) : _klines;
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
          // 在 setState 外执行 calcFibonacci 计算，避免 build 期间卡顿
          final newShowFibonacci = !_showFibonacci;
          if (newShowFibonacci && _klines.isNotEmpty) {
            final fib = calcFibonacci(_klines);
            setState(() {
              _showFibonacci = true;
              if (_techAnalysis != null) {
                _techAnalysis!['fibonacci'] = fib;
              } else {
                _techAnalysis = {'fibonacci': fib};
              }
            });
          } else if (!newShowFibonacci) {
            setState(() {
              _showFibonacci = false;
              if (_techAnalysis != null) {
                // 关闭时清除斐波那契数据，避免继续绘制
                _techAnalysis!.remove('fibonacci');
              }
            });
          } else {
            setState(() {
              _showFibonacci = newShowFibonacci;
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _showFibonacci ? _kDownColor : _kCardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: _showFibonacci ? _kDownColor : Colors.white24),
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
            color: _showBoll ? _kBollColor : _kCardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _showBoll ? _kBollColor : Colors.white24),
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
    if (_selectedKlineIndex != null &&
        _selectedKlineIndex! < displayKlines.length) {
      final k = displayKlines[_selectedKlineIndex!];
      final isUp = k.close >= k.open;
      final color = isUp ? Colors.red : Colors.green;
      selectedInfo = Container(
        padding: const EdgeInsets.all(8),
        color: _kCardColor,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    '${k.date.year}-${k.date.month.toString().padLeft(2, '0')}-${k.date.day.toString().padLeft(2, '0')}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.grey)),
                Text('开${k.open.toStringAsFixed(2)}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.white)),
                Text('高${k.high.toStringAsFixed(2)}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.red)),
                Text('低${k.low.toStringAsFixed(2)}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.green)),
                Text('收${k.close.toStringAsFixed(2)}',
                    style: textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('量${_formatVolume(k.volume)}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.white)),
                Text('额${_formatAmount(k.amount)}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.white)),
                Text(
                    '涨跌${k.change >= 0 ? '+' : ''}${k.change.toStringAsFixed(2)}',
                    style: textTheme.bodySmall?.copyWith(color: color)),
                Text(
                    '幅${k.changePct >= 0 ? '+' : ''}${k.changePct.toStringAsFixed(2)}%',
                    style: textTheme.bodySmall?.copyWith(color: color)),
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
                      gridData: FlGridData(
                          show: true,
                          getDrawingHorizontalLine: (value) =>
                              FlLine(color: Colors.white10)),
                      titlesData: FlTitlesData(
                        show: true,
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 56,
                            getTitlesWidget: (value, meta) => Text(
                                value.toStringAsFixed(2),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 10)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        if (displayKlines.any((k) => k.ma5 > 0))
                          LineChartBarData(
                            spots: displayKlines
                                .asMap()
                                .entries
                                .where((e) => e.value.ma5 > 0)
                                .map((e) =>
                                    FlSpot(e.key.toDouble(), e.value.ma5))
                                .toList(),
                            isCurved: false,
                            color: Colors.yellow,
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                        if (displayKlines.any((k) => k.ma10 > 0))
                          LineChartBarData(
                            spots: displayKlines
                                .asMap()
                                .entries
                                .where((e) => e.value.ma10 > 0)
                                .map((e) =>
                                    FlSpot(e.key.toDouble(), e.value.ma10))
                                .toList(),
                            isCurved: false,
                            color: Colors.orange,
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                        if (displayKlines.any((k) => k.ma20 > 0))
                          LineChartBarData(
                            spots: displayKlines
                                .asMap()
                                .entries
                                .where((e) => e.value.ma20 > 0)
                                .map((e) =>
                                    FlSpot(e.key.toDouble(), e.value.ma20))
                                .toList(),
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
                        resistanceLevels:
                            _techAnalysis?['resistance_levels'] ?? [],
                        fibonacciLevels: _techAnalysis?['fibonacci']?['levels'],
                        minPrice: minPrice,
                        maxPrice: maxPrice,
                        showBoll: _showBoll,
                        code: widget.code,
                        limitUpAnalysis: _effectiveLimitUpAnalysis,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        // 打板信息浮层卡片（仅在存在涨停分析时渲染）
        _buildLimitUpSummaryCard(),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  const Text('成交量',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 16),
                  Container(width: 8, height: 2, color: Colors.yellow),
                  const SizedBox(width: 4),
                  const Text('MA5',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 2, color: Colors.cyan),
                  const SizedBox(width: 4),
                  const Text('MA10',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
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
                      padding:
                          const EdgeInsets.only(left: _kChartLeftReservedSize),
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
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 9),
                                ),
                              ),
                            ),
                            bottomTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            if (displayKlines.any((k) => k.volMa5 > 0))
                              LineChartBarData(
                                spots: displayKlines
                                    .asMap()
                                    .entries
                                    .map((e) => FlSpot(
                                        e.key.toDouble(), e.value.volMa5))
                                    .toList(),
                                isCurved: false,
                                color: Colors.yellow,
                                barWidth: 1,
                                dotData: const FlDotData(show: false),
                              ),
                            if (displayKlines.any((k) => k.volMa10 > 0))
                              LineChartBarData(
                                spots: displayKlines
                                    .asMap()
                                    .entries
                                    .map((e) => FlSpot(
                                        e.key.toDouble(), e.value.volMa10))
                                    .toList(),
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
                  const Text('MACD',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: Colors.red),
                  const SizedBox(width: 4),
                  const Text('DIF',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: Colors.blue),
                  const SizedBox(width: 4),
                  const Text('DEA',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: _kUpColor),
                  const SizedBox(width: 4),
                  const Text('MACD柱',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
            Builder(builder: (_) {
              double macdAbsMax = 0;
              for (final d in displayKlines) {
                if (d.macdDif.abs() > macdAbsMax) macdAbsMax = d.macdDif.abs();
                if (d.macdDea.abs() > macdAbsMax) macdAbsMax = d.macdDea.abs();
                if (d.macdHist.abs() > macdAbsMax)
                  macdAbsMax = d.macdHist.abs();
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
                        gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) => FlLine(
                                color: Colors.white10, strokeWidth: 0.5)),
                        titlesData: FlTitlesData(
                          show: true,
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: _kChartLeftReservedSize,
                              getTitlesWidget: (value, meta) => Text(
                                  value.toStringAsFixed(2),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10)),
                            ),
                          ),
                          bottomTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: displayKlines
                                .asMap()
                                .entries
                                .map((e) =>
                                    FlSpot(e.key.toDouble(), e.value.macdDif))
                                .toList(),
                            isCurved: false,
                            color: Colors.red,
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: displayKlines
                                .asMap()
                                .entries
                                .map((e) =>
                                    FlSpot(e.key.toDouble(), e.value.macdDea))
                                .toList(),
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
                        padding: const EdgeInsets.only(
                            left: _kChartLeftReservedSize),
                        child: CustomPaint(
                          painter: _MacdHistogramPainter(displayKlines,
                              macdAbsMax: macdAbsMax),
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
                  const Text('RSI6',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(width: 8),
                  Container(width: 8, height: 8, color: Colors.orange),
                  const SizedBox(width: 16),
                  const Text('超买70',
                      style: TextStyle(color: Colors.white24, fontSize: 10)),
                  const SizedBox(width: 8),
                  const Text('超卖30',
                      style: TextStyle(color: Colors.white24, fontSize: 10)),
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
                        return const FlLine(
                            color: Colors.white24,
                            strokeWidth: 1,
                            dashArray: [5, 5]);
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
                        getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10)),
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: displayKlines
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value.rsi6))
                          .toList(),
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
                    const Text('KDJ',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, color: Colors.deepOrange),
                    const SizedBox(width: 4),
                    const Text('K',
                        style: TextStyle(color: Colors.white, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, color: Colors.cyan),
                    const SizedBox(width: 4),
                    const Text('D',
                        style: TextStyle(color: Colors.white, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, color: Colors.purpleAccent),
                    const SizedBox(width: 4),
                    const Text('J',
                        style: TextStyle(color: Colors.white, fontSize: 10)),
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
                          return const FlLine(
                              color: Colors.white24,
                              strokeWidth: 1,
                              dashArray: [5, 5]);
                        }
                        if (value == 50) {
                          return const FlLine(
                              color: Colors.white12,
                              strokeWidth: 0.5,
                              dashArray: [2, 4]);
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
                          getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ),
                      ),
                      bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: displayKlines
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value.k))
                            .toList(),
                        isCurved: false,
                        color: Colors.deepOrange,
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: displayKlines
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value.d))
                            .toList(),
                        isCurved: false,
                        color: Colors.cyan,
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: displayKlines
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value.j))
                            .toList(),
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

    // v3.23: 传入validatedSignals用于展示对抗论点
    final validated = _analysis!.validatedSignals ?? [];
    final validatedMap = <String, ValidatedSignal>{};
    for (final vs in validated) {
      // 用 "indicator|signal" 组合键确保唯一性，避免同名信号覆盖
      validatedMap['${vs.signal.indicator}|${vs.signal.signal}'] = vs;
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _analysis!.signals.length,
      itemBuilder: (context, index) {
        final signal = _analysis!.signals[index];
        return SignalCard(
          signal: signal,
          validatedSignal: validatedMap['${signal.indicator}|${signal.signal}'],
        );
      },
    );
  }

  Future<void> _loadHeldPosition() async {
    try {
      final map = await _dbService.getPositionMap();
      if (mounted) setState(() => _heldPosition = map[widget.code]);
    } catch (e) {
      debugPrint('QuoteScreen._loadHeldPosition: $e');
    }
  }

  Widget _buildDashboard() {
    return TradingDashboard(
      quote: _quote,
      analysis: _analysis,
      isRefreshing: _isAnalysisRefreshing,
      lastUpdateTime: _lastUpdateTime,
      scoreTrend: _scoreTrend,
      onRefresh: () => _refreshAnalysis(),
      position: _heldPosition,
    );
  }

  /// AI分析独立Tab页
  Widget _buildAIAnalysisTab() {
    final aiAvailable = AILayerProvider.instance.isAvailable;
    final allAI =
        _analysis?.reasons.where((r) => r.startsWith('AI')).toList() ?? [];
    final unavailable = allAI.where((r) => r.startsWith('AI分析暂不可用')).toList();
    final aiReasons = allAI.where((r) => !r.startsWith('AI分析暂不可用')).toList();
    final hasAIResults = aiReasons.isNotEmpty;
    final showAnalyzeButton = !hasAIResults && !_isAIAnalyzing;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部状态卡片
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: const Color(0xFF58A6FF).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy,
                        size: 18, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 6),
                    Text(
                      _quote != null ? 'AI分析 · ${_quote!.name}' : 'AI分析',
                      style: const TextStyle(
                        color: Color(0xFFF0F6FC),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          size: 18, color: Color(0xFF8B949E)),
                      onPressed: _showAPIProviderDialog,
                      padding: const EdgeInsets.all(4),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    if (!aiAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B949E).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '未启用',
                          style:
                              TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                        ),
                      )
                    else if (_isAIAnalyzing)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF58A6FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '分析中',
                          style:
                              TextStyle(color: Color(0xFF58A6FF), fontSize: 11),
                        ),
                      )
                    else if (hasAIResults)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '已完成',
                          style:
                              TextStyle(color: Color(0xFF2ECC71), fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // 主操作按钮
                if (showAnalyzeButton && aiAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _analyzeAI,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('开始AI分析'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF58A6FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  )
                else if (!aiAvailable)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Color(0xFF8B949E), size: 24),
                        SizedBox(height: 6),
                        Text(
                          'AI层未启用',
                          style: TextStyle(
                              color: Color(0xFFF0F6FC),
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '请检查API Key配置或网络连接',
                          style:
                              TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                // 进度显示
                if (_isAIAnalyzing) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF58A6FF)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _aiStatus ?? 'AI分析中...',
                          style: const TextStyle(
                              color: Color(0xFF58A6FF), fontSize: 12),
                        ),
                      ),
                      Text(
                        '$_aiProgress%',
                        style: const TextStyle(
                            color: Color(0xFF8B949E), fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _aiProgress / 100,
                    backgroundColor: const Color(0xFF21262D),
                    color: const Color(0xFF58A6FF),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 5,
                  ),
                ],
              ],
            ),
          ),
          // 错误提示
          if (unavailable.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE74C3C).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: const Color(0xFFE74C3C).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Color(0xFFE74C3C)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '分析失败',
                          style: TextStyle(
                            color: Color(0xFFE74C3C),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          unavailable.first.replaceFirst('AI分析暂不可用：', ''),
                          style: const TextStyle(
                              color: Color(0xFF8B949E),
                              fontSize: 12,
                              height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        if (aiAvailable) _buildRetryButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // AI分析结果
          if (hasAIResults) ...[
            const SizedBox(height: 10),
            ...aiReasons.map((reason) {
              if (reason.startsWith('AI分析结论')) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF58A6FF).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF58A6FF).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.flag, size: 14, color: Color(0xFF58A6FF)),
                          SizedBox(width: 4),
                          Text(
                            '分析结论',
                            style: TextStyle(
                              color: Color(0xFF58A6FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reason.replaceFirst('AI分析结论: ', ''),
                        style: const TextStyle(
                          color: Color(0xFFF0F6FC),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
              } else if (reason.startsWith('AI理由')) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right,
                          size: 14, color: Color(0xFF58A6FF)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reason.replaceFirst('AI理由: ', ''),
                          style: const TextStyle(
                              color: Color(0xFFC9D1D9),
                              fontSize: 12,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                );
              } else if (reason.startsWith('AI风险提示')) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE74C3C).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning,
                          size: 14, color: Color(0xFFE74C3C)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reason.replaceFirst('AI风险提示: ', ''),
                          style: const TextStyle(
                              color: Color(0xFFE74C3C),
                              fontSize: 12,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(reason,
                    style: const TextStyle(
                        color: Color(0xFF8B949E), fontSize: 12)),
              );
            }),
            const SizedBox(height: 12),
            // 重新分析按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isAIAnalyzing ? null : _analyzeAI,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('重新分析', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF58A6FF),
                  side: const BorderSide(color: Color(0xFF30363D)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
          // ─── 预设模板分析 ───────────────────────────
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.view_module, size: 14, color: Color(0xFF8B949E)),
                SizedBox(width: 4),
                Text(
                  '专题分析',
                  style: TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          // 模板选择器
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: AnalysisTemplate.values.map((t) {
              final selected = t == _selectedTemplate;
              return ChoiceChip(
                label: Text(t.label,
                    style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? const Color(0xFFF0F6FC)
                            : const Color(0xFF8B949E))),
                selected: selected,
                onSelected: (_isAsking || _isAIAnalyzing)
                    ? null
                    : (v) {
                        if (v) setState(() => _selectedTemplate = t);
                      },
                selectedColor: const Color(0xFF58A6FF),
                backgroundColor: const Color(0xFF21262D),
                side: BorderSide(
                    color: selected
                        ? const Color(0xFF58A6FF)
                        : const Color(0xFF30363D)),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // 当前模板描述
          Text(
            _selectedTemplate.description,
            style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          // 执行模板分析按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _isAsking || _isAIAnalyzing ? null : _runTemplateAnalysis,
              icon: _isAsking && _aiStatus == _selectedTemplate.label
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 14),
              label: Text(_isAsking && _aiStatus == _selectedTemplate.label
                  ? '分析中...'
                  : '执行$_selectedTemplate.label'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2EA043),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                textStyle: const TextStyle(fontSize: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          // ─── 聊天历史 ────────────────────────────────
          if (_chatHistory.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._chatHistory.map((r) => _buildChatBubble(r)),
          ],
          // 提问中的占位气泡（首次提问、history 还没添加时）
          if (_isAsking &&
              _aiStatus != _selectedTemplate.label &&
              _chatHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF58A6FF)))),
            ),
          // ─── 自定义提问输入框 ─────────────────────────
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 14, color: Color(0xFF58A6FF)),
                    SizedBox(width: 4),
                    Text(
                      '自定义提问',
                      style: TextStyle(
                          color: Color(0xFF58A6FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 快捷问题
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    '现在能买吗?',
                    '压力位和支撑位在哪?',
                    '资金流向如何?',
                    '适合做T吗?',
                  ]
                      .map((q) => ActionChip(
                            label: Text(q,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF8B949E))),
                            backgroundColor: const Color(0xFF21262D),
                            side: const BorderSide(color: Color(0xFF30363D)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onPressed: (_isAsking || _isAIAnalyzing)
                                ? null
                                : () {
                                    _questionController.text = q;
                                    _askQuestion();
                                  },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _questionController,
                  maxLines: 3,
                  minLines: 1,
                  enabled: !_isAsking && !_isAIAnalyzing,
                  style:
                      const TextStyle(color: Color(0xFFF0F6FC), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '输入你的问题，如：现在能买吗？',
                    hintStyle:
                        const TextStyle(color: Color(0xFF484F58), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF58A6FF)),
                    ),
                  ),
                  onSubmitted: (_) => _askQuestion(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_isAsking || _isAIAnalyzing)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF58A6FF)))
                    else
                      const Icon(Icons.info_outline,
                          size: 12, color: Color(0xFF484F58)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        (_isAsking || _isAIAnalyzing)
                            ? 'AI思考中...'
                            : 'AI会基于当前股票数据回答你的问题',
                        style: TextStyle(
                            color: (_isAsking || _isAIAnalyzing)
                                ? const Color(0xFF58A6FF)
                                : const Color(0xFF484F58),
                            fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_isAsking || _isAIAnalyzing) ? null : _askQuestion,
                      icon: const Icon(Icons.send, size: 14),
                      label: const Text('发送', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF58A6FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// 构造聊天气泡
  Widget _buildChatBubble(AIChatResult r) {
    final hasError = r.error != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasError
            ? const Color(0xFFE74C3C).withOpacity(0.06)
            : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: hasError
                ? const Color(0xFFE74C3C).withOpacity(0.3)
                : const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户问题
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.person_outline,
                  size: 13, color: Color(0xFF58A6FF)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  r.question,
                  style: const TextStyle(
                      color: Color(0xFF58A6FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // AI回答
          if (hasError)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    size: 13, color: Color(0xFFE74C3C)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.error!,
                    style: const TextStyle(
                        color: Color(0xFFE74C3C), fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.smart_toy, size: 13, color: Color(0xFF2EA043)),
                const SizedBox(width: 4),
                Expanded(
                  child: SelectableText(
                    r.answer,
                    style: const TextStyle(
                        color: Color(0xFFC9D1D9), fontSize: 12, height: 1.6),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 执行模板分析
  Future<void> _runTemplateAnalysis() async {
    if (_isAsking || _isAIAnalyzing || _klines.isEmpty || _quote == null)
      return;
    final ai = AILayerProvider.instance;
    if (!ai.isAvailable) return;

    final template = _selectedTemplate;
    final quote = _quote!;
    final techData = _buildTechDataMap();

    setState(() {
      _isAsking = true;
      _aiStatus = template.label;
    });

    try {
      final result = await ai.analyzeByTemplate(
        template: template,
        stockCode: quote.code,
        stockName: quote.name,
        technicalData: techData,
        newsTitles: const [],
      );
      setState(() {
        _chatHistory.add(result);
        _isAsking = false;
        _aiStatus = null;
      });
    } catch (e) {
      setState(() {
        _chatHistory.add(AIChatResult.withError(template.label, '分析异常: $e'));
        _isAsking = false;
        _aiStatus = null;
      });
    }
  }

  /// 自定义提问
  Future<void> _askQuestion() async {
    final q = _questionController.text.trim();
    if (q.isEmpty || _isAsking || _isAIAnalyzing || _quote == null) return;
    final ai = AILayerProvider.instance;
    if (!ai.isAvailable) {
      setState(() {
        _chatHistory.add(AIChatResult.withError(q, 'AI层未启用，请检查配置'));
      });
      return;
    }

    final quote = _quote!;
    final techData = _buildTechDataMap();
    _questionController.clear();

    setState(() {
      _isAsking = true;
      _aiStatus = '思考中';
    });

    try {
      final result = await ai.askCustomQuestion(
        question: q,
        stockCode: quote.code,
        stockName: quote.name,
        technicalData: techData,
        newsTitles: const [],
      );
      setState(() {
        _chatHistory.add(result);
        _isAsking = false;
        _aiStatus = null;
      });
    } catch (e) {
      setState(() {
        _chatHistory.add(AIChatResult.withError(q, '提问失败: $e'));
        _isAsking = false;
        _aiStatus = null;
      });
    }
  }

  /// 构造技术面数据Map（供AI分析）
  Map<String, dynamic> _buildTechDataMap() {
    if (_analysis == null || _quote == null) return {};
    final a = _analysis!;
    final q = _quote!;
    return {
      '综合评分': a.score,
      '推荐': a.recommendation,
      '价格': q.price.toStringAsFixed(2),
      '涨跌幅': '${q.changePct.toStringAsFixed(2)}%',
      '成交量': q.volume,
      '换手率': '${q.turnover.toStringAsFixed(2)}%',
      'PE': q.pe.toStringAsFixed(1),
      'PB': q.pb.toStringAsFixed(1),
      '总市值': '${(q.totalMarketCap / 100000000).toStringAsFixed(1)}亿',
      '共振评分': a.confluenceScore,
      '市场结构': a.marketStructure?.structure.toString() ?? 'N/A',
      '主力净流入': '${(q.mainNetFlow / 10000).toStringAsFixed(0)}万',
    };
  }

  Future<void> _analyzeAI() async {
    if (_isAIAnalyzing || _isAsking || _klines.isEmpty || _quote == null)
      return;

    setState(() {
      _isAIAnalyzing = true;
      _aiStatus = 'AI分析开始...';
      _aiProgress = 0;
    });

    try {
      final calculated = calcAllIndicators(_klines);
      final analysis = generateAnalysis(
        calculated,
        _quote,
        marketContext: _marketContext,
        enableAsyncSideEffects: false,
        onAIUpdate: (aiReasons) {
          if (mounted) {
            setState(() {
              _isAIAnalyzing = false;
            });
          }
        },
        onAIProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _aiStatus = status;
              _aiProgress = progress;
            });
          }
        },
        autoTriggerAI: true,
      );

      if (mounted) {
        setState(() {
          _analysis = analysis;
        });
      }
    } catch (e) {
      debugPrint('AI分析失败: $e');
      if (mounted) {
        setState(() {
          _isAIAnalyzing = false;
          _aiStatus = '分析失败';
        });
        final msg = e.toString();
        final match = RegExp(r'请(\d+)秒后重试').firstMatch(msg);
        if (match != null) {
          _startRetryCountdown(int.parse(match.group(1)!));
        }
      }
    }
  }

  Future<void> _showAPIProviderDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentProviderName = prefs.getString('ai_provider') ?? 'zhipu';
    final currentProvider = AIProvider.fromString(currentProviderName);
    AIProvider? selectedProvider = currentProvider;

    await showDialog<void>(
      context: context,
      builder: (context) {
        String? testResult;
        bool isTesting = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: const Text(
                '选择AI分析引擎',
                style: TextStyle(color: Color(0xFFF0F6FC), fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...AIProvider.values.map((provider) {
                    return RadioListTile<AIProvider>(
                      title: Text(provider.label,
                          style: const TextStyle(color: Color(0xFFF0F6FC))),
                      subtitle: Text(provider.defaultModel,
                          style: const TextStyle(
                              color: Color(0xFF8B949E), fontSize: 12)),
                      value: provider,
                      groupValue: selectedProvider,
                      onChanged: (value) {
                        setState(() {
                          selectedProvider = value;
                          testResult = null;
                        });
                      },
                      activeColor: const Color(0xFF58A6FF),
                    );
                  }).toList(),
                  if (testResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        testResult!,
                        style: TextStyle(
                          color: testResult!.contains('成功')
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFFE74C3C),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isTesting
                      ? null
                      : () async {
                          if (selectedProvider == null) return;
                          setState(() {
                            isTesting = true;
                            testResult = '正在测试${selectedProvider!.label}...';
                          });
                          final result =
                              await _testAPIConnection(selectedProvider!);
                          setState(() {
                            isTesting = false;
                            testResult = result;
                          });
                        },
                  child: isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('测试连接',
                          style: TextStyle(color: Color(0xFF8B949E))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消',
                      style: TextStyle(color: Color(0xFF8B949E))),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedProvider != null) {
                      await prefs.setString(
                          'ai_provider', selectedProvider!.name);
                    }
                    Navigator.pop(context);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已保存设置，重启应用生效')),
                      );
                    }
                  },
                  child: const Text('确定',
                      style: TextStyle(color: Color(0xFF58A6FF))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String> _testAPIConnection(AIProvider provider) async {
    final apiKey = AIConfig.getApiKeyForProvider(provider);

    if (apiKey.isEmpty) {
      return 'API Key为空，请配置环境变量';
    }

    final client = http.Client();
    try {
      final request = {
        'model': provider.defaultModel,
        'messages': [
          {'role': 'user', 'content': 'test'}
        ],
        'max_tokens': 10,
      };

      if (provider == AIProvider.zhipu) {
        request['thinking'] = {'type': 'disabled'};
      }

      final response = await client
          .post(
            Uri.parse(provider.endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(request),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>?;
          final content = message?['content'];
          if (content != null && content is String && content.isNotEmpty) {
            return '${provider.label}连接成功！';
          }
        }
        return '${provider.label}返回空结果，请检查配置';
      } else if (response.statusCode == 429) {
        return '${provider.label}请求过于频繁（429）';
      } else if (response.statusCode == 401) {
        return '${provider.label}API Key无效（401）';
      } else if (response.statusCode == 403) {
        return '${provider.label}权限不足（403）';
      } else if (response.statusCode >= 500) {
        return '${provider.label}服务器错误（${response.statusCode}）';
      } else {
        return '${provider.label}连接失败: ${response.statusCode}';
      }
    } on TimeoutException {
      return '${provider.label}连接超时，可能网络不可达';
    } catch (e) {
      return '${provider.label}连接异常: $e';
    }
  }

  void _startRetryCountdown(int seconds) {
    _retryTimer?.cancel();
    setState(() => _retryCountdown = seconds);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_retryCountdown > 0) {
        setState(() => _retryCountdown--);
      } else {
        timer.cancel();
        _retryTimer = null;
      }
    });
  }

  Widget _buildRetryButton() {
    if (_retryCountdown > 0) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.timer, size: 14),
        label: Text('${_retryCountdown}秒后重试',
            style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE74C3C).withOpacity(0.1),
          foregroundColor: const Color(0xFFE74C3C).withOpacity(0.6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: _analyzeAI,
      icon: const Icon(Icons.refresh, size: 14),
      label: const Text('重试', style: TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE74C3C).withOpacity(0.2),
        foregroundColor: const Color(0xFFE74C3C),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(0, 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
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

  String _formatMarketCap(double value) {
    if (value <= 0) return '--';
    // 自动修正：市值<1亿大概率是单位错误(万元未转元)，×10000恢复
    if (value < 1e8 && value > 0) value *= 10000;
    if (value.abs() >= 1e12) {
      return '${(value / 1e12).toStringAsFixed(2)}万亿';
    } else {
      return '${(value / 1e8).toStringAsFixed(2)}亿';
    }
  }

  /// 打板信息浮层卡片：连板数 + 板型 + 时间评级 + 次日溢价/质量
  Widget _buildLimitUpSummaryCard() {
    final a = _effectiveLimitUpAnalysis;
    if (a == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kLimitUpGold, width: 0.5),
      ),
      child: Row(children: [
        _buildLimitUpBadge('${a.consecutiveDays}连板', _kLimitUpGold),
        const SizedBox(width: 8),
        if (a.boardType.isNotEmpty) ...[
          _buildLimitUpBadge(a.boardType, _boardTypeColor(a.boardType)),
          const SizedBox(width: 8),
        ],
        if (a.timeGrade.isNotEmpty && a.timeGrade != '未知') ...[
          _buildLimitUpBadge(a.timeGrade, _timeGradeColor(a.timeGrade)),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('次日溢价 ${(a.premiumProb * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 12,
                  color: _kLimitUpGold,
                  fontWeight: FontWeight.w600)),
          Text('质量 ${a.qualityScore.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 10, color: _kTextSecondary)),
        ]),
      ]),
    );
  }

  Widget _buildLimitUpBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }

  Color _boardTypeColor(String boardType) {
    switch (boardType) {
      case '一字板':
        return _kStrongRed;
      case 'T字板':
        return _kOrange;
      case '换手板':
        return _kLimitUpGold;
      default:
        return _kTextSecondary;
    }
  }

  Color _timeGradeColor(String timeGrade) {
    if (timeGrade.contains('竞价')) return _kLimitUpGold;
    if (timeGrade.contains('早盘')) return _kStrongRed;
    if (timeGrade.contains('上午')) return _kOrange;
    return _kTextSecondary; // 尾盘
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
      _analysisRefreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startRealtime();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiClient.dispose();
    _tabController?.dispose();
    _questionController.dispose();
    _retryTimer?.cancel();
    _pollingTimer?.cancel();
    _analysisRefreshTimer?.cancel();
    _timeshareData.clear();
    _timeshareAvgData.clear();
    _timeshareMinuteVolumes.clear();
    _intradayLevelResult = null;
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
  final String code;
  final LimitUpAnalysis? limitUpAnalysis;

  final Paint _upPaint = Paint()..color = _kUpColor;
  final Paint _downPaint = Paint()..color = _kDownColor;
  final Paint _linePaint = Paint()..strokeWidth = 1;
  final Paint _selectedPaint = Paint()..color = Colors.white.withOpacity(0.2);
  final Paint _bollUpperPaint = Paint()
    ..color = _kBollColor
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final Paint _bollMidPaint = Paint()
    ..color = Colors.white54
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;
  final Paint _bollFillPaint = Paint()
    ..color = _kBollColor.withOpacity(0.05)
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
    required this.code,
    this.limitUpAnalysis,
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
      _drawDashedLine(
          canvas, Offset(padding, y), Offset(size.width, y), _kDownColor);
      _drawPriceLabel(canvas, size, level, y, _kDownColor);
    }

    // 绘制阻力位（红色虚线）并标注价格
    for (final level in resistanceLevels) {
      final y = chartHeight - ((level - minPrice) / priceRange) * chartHeight;
      _drawDashedLine(
          canvas, Offset(padding, y), Offset(size.width, y), _kUpColor);
      _drawPriceLabel(canvas, size, level, y, _kUpColor);
    }

    // 绘制斐波那契回撤位并标注价格和比例
    if (fibonacciLevels != null) {
      for (final entry in fibonacciLevels!.entries) {
        final level = entry.value;
        final ratio = entry.key;
        final y = chartHeight - ((level - minPrice) / priceRange) * chartHeight;
        final isGolden = ratio == '61.8%';
        final color = isGolden ? _kGoldCross : Colors.white54;
        _drawDashedLine(
            canvas, Offset(padding, y), Offset(size.width, y), color);
        _drawFibonacciLabel(canvas, size, level, ratio, y, color);
      }
    }

    // 价格范围为0时（如停牌），绘制水平线
    if (priceRange == 0) {
      final y = chartHeight / 2;
      for (int i = 0; i < data.length; i++) {
        final x = padding + i * (barWidth + gap) + barWidth / 2;
        canvas.drawLine(Offset(x, y - 1), Offset(x, y + 1),
            _linePaint..color = Colors.white54);
      }
      return;
    }

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final isUp = d.close >= d.open;
      final paint = isUp ? _upPaint : _downPaint;
      _linePaint.color = paint.color;

      final x = padding + i * (barWidth + gap) + barWidth / 2;
      final highY =
          chartHeight - ((d.high - minPrice) / priceRange) * chartHeight;
      final lowY =
          chartHeight - ((d.low - minPrice) / priceRange) * chartHeight;
      final openY =
          chartHeight - ((d.open - minPrice) / priceRange) * chartHeight;
      final closeY =
          chartHeight - ((d.close - minPrice) / priceRange) * chartHeight;

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
      _drawBollBands(canvas, size, padding, chartWidth, chartHeight, priceRange,
          barWidth, gap);
    }

    // 打板标识层：涨停三角 + 连板数 + 一字板矩形
    _drawLimitUpMarks(canvas, size, padding, chartWidth, chartHeight, barWidth,
        gap, priceRange);
  }

  void _drawBollBands(
      Canvas canvas,
      Size size,
      double padding,
      double chartWidth,
      double chartHeight,
      double priceRange,
      double barWidth,
      double gap) {
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
      final upperY =
          chartHeight - ((d.bollUpper - minPrice) / priceRange) * chartHeight;
      final midY =
          chartHeight - ((d.bollMid - minPrice) / priceRange) * chartHeight;
      final lowerY =
          chartHeight - ((d.bollLower - minPrice) / priceRange) * chartHeight;

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
      final lowerY =
          chartHeight - ((d.bollLower - minPrice) / priceRange) * chartHeight;
      fillPath.lineTo(x, lowerY);
    }
    fillPath.close();

    canvas.drawPath(fillPath, _bollFillPaint);
    canvas.drawPath(upperPath, _bollUpperPaint);
    canvas.drawPath(midPath, _bollMidPaint);
    canvas.drawPath(lowerPath, _bollUpperPaint);
  }

  /// 涨停近似判定阈值：主板9.5%，创业板/科创板20%，北交所30%
  double _limitPctForCode() {
    final isStar = code.startsWith('688');
    final isChiNext = code.startsWith('30');
    final isBse = code.startsWith('8') || code.startsWith('43');
    return isBse ? 0.30 : (isStar || isChiNext ? 0.20 : 0.095);
  }

  /// 打板标识层：在涨停K线上方绘制三角标记、连板数、一字板矩形
  void _drawLimitUpMarks(
      Canvas canvas,
      Size size,
      double padding,
      double chartWidth,
      double chartHeight,
      double barWidth,
      double gap,
      double priceRange) {
    if (data.isEmpty || priceRange == 0) return;
    final limitPct = _limitPctForCode();
    for (var i = 1; i < data.length; i++) {
      final k = data[i];
      final prev = data[i - 1];
      if (!KlineValidator.isLimitUp(k, prev, limitPct)) continue;

      final x = padding + i * (barWidth + gap) + barWidth / 2;
      final color = _limitUpMarkColor(i, limitPct);

      // 涨停三角标记（位于K线最高价上方）
      final highY =
          chartHeight - ((k.high - minPrice) / priceRange) * chartHeight;
      final y = highY - 8;
      final path = Path()
        ..moveTo(x, y - 6)
        ..lineTo(x - 5, y + 2)
        ..lineTo(x + 5, y + 2)
        ..close();
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);

      // 连板数（仅2连板及以上显示）
      final consec = _countConsecutiveLimitUps(i, limitPct);
      if (consec >= 2) {
        final tp = TextPainter(
          text: TextSpan(
              text: '$consec',
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.bold)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - 18));
      }

      // 一字板特殊标记：金色小矩形
      if (KlineValidator.isYiZiBan(k, prev, limitPct)) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y - 14), width: 14, height: 8),
          Paint()
            ..color = _kLimitUpGold
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  /// 统计截至索引 i（含）的连续涨停天数
  int _countConsecutiveLimitUps(int i, double limitPct) {
    int count = 0;
    for (var j = i; j >= 1; j--) {
      if (KlineValidator.isLimitUp(data[j], data[j - 1], limitPct)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// 打板标记颜色：炸板红 / 龙头金 / 高度红 / 首板橙
  Color _limitUpMarkColor(int i, double limitPct) {
    final k = data[i];
    final prev = data[i - 1];
    final upPrice = KlineValidator.limitUpPrice(prev.close, limitPct);
    // 炸板：盘中触及涨停但收盘未封住
    if (k.high >= upPrice * 0.999 && k.close < upPrice * 0.999) {
      return _kStrongRed;
    }
    final analysis = limitUpAnalysis;
    if (analysis == null) return _kOrange;
    if (analysis.consecutiveDays >= 4) return _kLimitUpGold;
    if (analysis.consecutiveDays == 3) return _kStrongRed;
    return _kOrange;
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

  void _drawPriceLabel(
      Canvas canvas, Size size, double price, double y, Color color) {
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

  void _drawFibonacciLabel(Canvas canvas, Size size, double price, String ratio,
      double y, Color color) {
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
      oldDelegate.showBoll != showBoll ||
      oldDelegate.code != code ||
      oldDelegate.limitUpAnalysis != limitUpAnalysis;
}

class _MacdHistogramPainter extends CustomPainter {
  final List<HistoryKline> data;
  final double macdAbsMax;

  final Paint _upPaint = Paint()..color = _kUpColor;
  final Paint _downPaint = Paint()..color = _kDownColor;
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

  final Paint _upPaint = Paint()..color = _kUpColor;
  final Paint _downPaint = Paint()..color = _kDownColor;

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
  bool shouldRepaint(_VolumeHistogramPainter oldDelegate) =>
      oldDelegate.data != data;
}
