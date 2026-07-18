import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/signal_engine.dart';
import '../analysis/backtest_engine.dart';
import '../analysis/position_manager.dart';
import '../analysis/indicators.dart';
import '../models/short_term_decision.dart';
import '../widgets/short_term_decision_panel.dart';

// ─── 配色常量 ────────────────────────────────────────────────────────
const _kBg = Color(0xFF0D1117);
const _kCard = Color(0xFF161B22);
const _kAccent = Color(0xFF58A6FF);
const _kUp = Color(0xFFE74C3C);
const _kDown = Color(0xFF2ECC71);
const _kTextPrimary = Color(0xFFF0F6FC);
const _kTextSecondary = Color(0xFF8B949E);
const _kBorder = Color(0xFF30363D);
const _kOrange = Color(0xFFFF9800);

/// 策略定义
class _StrategyDef {
  final String id;
  final String name;
  final String desc;
  final IconData icon;

  const _StrategyDef({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
  });
}

/// 单只股票的分析结果
class _StockAnalysis {
  final StockInfo stock;
  final AnalysisResult? analysis;
  final QuoteData? quote;
  final Map<String, BacktestResult> backtestResults;
  final double positionRatio;
  final Map<String, Map<String, dynamic>> strategySignals;
  final String? error;

  _StockAnalysis({
    required this.stock,
    this.analysis,
    this.quote,
    this.backtestResults = const {},
    this.positionRatio = 0.5,
    this.strategySignals = const {},
    this.error,
  });
}

class QuantScreen extends StatefulWidget {
  const QuantScreen({super.key});

  @override
  State<QuantScreen> createState() => _QuantScreenState();
}

class _QuantScreenState extends State<QuantScreen> {
  final ApiClient _apiClient = ApiClient();

  // ─── 选股状态 ──────────────────────────────────────────────────
  final List<StockInfo> _selectedStocks = [];
  List<StockInfo> _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  // ─── 策略选择状态 ──────────────────────────────────────────────
  final Set<String> _selectedStrategies = {};

  // ─── 分析结果状态 ──────────────────────────────────────────────
  final List<_StockAnalysis> _analysisResults = [];
  bool _isAnalyzing = false;
  final Set<String> _expandedStocks = {};

  // ─── 策略列表 ──────────────────────────────────────────────────
  static const List<_StrategyDef> _strategies = [
    _StrategyDef(
      id: 'trend_following',
      name: '趋势跟踪',
      desc: 'MA5/MA20双均线交叉',
      icon: Icons.trending_up,
    ),
    _StrategyDef(
      id: 'mean_reversion',
      name: '均值回归',
      desc: 'RSI超卖+布林下轨',
      icon: Icons.sync_alt,
    ),
    _StrategyDef(
      id: 'macd_cross',
      name: 'MACD金叉',
      desc: 'DIF上穿DEA',
      icon: Icons.show_chart,
    ),
    _StrategyDef(
      id: 'kdj_oversold',
      name: 'KDJ超卖',
      desc: '超卖区金叉',
      icon: Icons.analytics,
    ),
    _StrategyDef(
      id: 'boll_breakout',
      name: '布林带突破',
      desc: '收口后突破上轨',
      icon: Icons.speed,
    ),
    _StrategyDef(
      id: 'ma_multihead',
      name: '均线多头',
      desc: 'MA5>MA10>MA20排列',
      icon: Icons.bar_chart,
    ),
    _StrategyDef(
      id: 'momentum',
      name: '动量策略',
      desc: '价格动量+量能确认',
      icon: Icons.bolt,
    ),
    _StrategyDef(
      id: 'volume_pullback',
      name: '缩量回调',
      desc: '上升趋势+缩量回撤',
      icon: Icons.trending_down,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedStrategies.addAll(_strategies.map((s) => s.id));
    _loadSavedStocks();
  }

  /// 从本地存储恢复上次选择的股票
  Future<void> _loadSavedStocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('quant_selected_stocks');
      if (saved == null || saved.isEmpty) return;
      final List<dynamic> list = jsonDecode(saved);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          _selectedStocks.add(StockInfo(
            code: item['code'] ?? '',
            name: item['name'] ?? '',
            display: item['display'] ?? '',
          ));
        }
      }
      if (_selectedStocks.isNotEmpty) setState(() {});
    } catch (_) {}
  }

  /// 保存当前选择到本地存储
  Future<void> _saveSelectedStocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _selectedStocks.map((s) => s.toJson()).toList();
      await prefs.setString('quant_selected_stocks', jsonEncode(data));
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ─── 搜索逻辑 ──────────────────────────────────────────────────

  Future<void> _onSearchChanged(String keyword) async {
    _debounceTimer?.cancel();
    if (keyword.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      try {
        final results = await _apiClient.searchStocks(keyword.trim());
        if (mounted) {
          setState(() {
            _searchResults = results.take(8).toList();
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _addStock(StockInfo stock) {
    if (_selectedStocks.any((s) => s.code == stock.code)) return;
    if (_selectedStocks.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('最多选择5只股票'), duration: Duration(seconds: 1)),
      );
      return;
    }
    setState(() {
      _selectedStocks.add(stock);
      _searchController.clear();
      _searchResults = [];
    });
    _saveSelectedStocks();
    _searchFocusNode.unfocus();
  }

  void _removeStock(String code) {
    setState(() {
      _selectedStocks.removeWhere((s) => s.code == code);
      _analysisResults.removeWhere((a) => a.stock.code == code);
      _expandedStocks.remove(code);
    });
    _saveSelectedStocks();
  }

  // ─── 分析逻辑 ──────────────────────────────────────────────────

  Future<void> _runAnalysis() async {
    if (_selectedStocks.isEmpty || _selectedStrategies.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResults.clear();
      _expandedStocks.clear();
    });

    // 并行分析所有股票
    final futures = _selectedStocks.map((stock) => _analyzeSingleStock(stock));
    final results = await Future.wait(futures);

    if (mounted) {
      setState(() {
        _analysisResults.addAll(results);
        _expandedStocks.addAll(
            results.where((r) => r.error == null).map((r) => r.stock.code));
        _isAnalyzing = false;
      });
    }
  }

  Future<_StockAnalysis> _analyzeSingleStock(StockInfo stock) async {
    try {
      final quote = await _apiClient.getRealtimeQuote(stock.code);
      final klines = await _apiClient.getStockHistory(stock.code, days: 120);
      final calculated = calcAllIndicators(klines);

      // 生成综合分析
      final analysis = generateAnalysis(calculated, quote);

      // 运行选中策略对应的回测
      final backtestResults = <String, BacktestResult>{};
      if (calculated.length >= 60) {
        if (_selectedStrategies.contains('trend_following') ||
            _selectedStrategies.contains('macd_cross')) {
          backtestResults['MACD金叉'] =
              BacktestEngine.backtestMACDCross(calculated);
        }
        if (_selectedStrategies.contains('trend_following') ||
            _selectedStrategies.contains('ma_multihead')) {
          backtestResults['MA金叉'] = BacktestEngine.backtestMACross(calculated);
        }
        if (_selectedStrategies.contains('kdj_oversold')) {
          backtestResults['KDJ超卖'] =
              BacktestEngine.backtestKDJOversoldCross(calculated);
        }
        if (_selectedStrategies.contains('mean_reversion')) {
          backtestResults['RSI超卖'] =
              BacktestEngine.backtestRSIOversoldRecovery(calculated);
        }
        if (_selectedStrategies.contains('boll_breakout')) {
          backtestResults['布林支撑'] =
              BacktestEngine.backtestBollSupport(calculated);
        }
        if (_selectedStrategies.contains('ma_multihead')) {
          backtestResults['均线多头'] =
              BacktestEngine.backtestMAMultiHead(calculated);
        }
      }

      // 计算仓位
      double positionRatio = 0.5;
      if (calculated.isNotEmpty) {
        positionRatio = PositionManager.calculatePosition(calculated.last);
      }

      // 为每个策略生成信号
      final strategySignals = _computeStrategySignals(calculated, quote);

      return _StockAnalysis(
        stock: stock,
        analysis: analysis,
        quote: quote,
        backtestResults: backtestResults,
        positionRatio: positionRatio,
        strategySignals: strategySignals,
      );
    } catch (e) {
      return _StockAnalysis(
        stock: stock,
        error: '分析失败: $e',
      );
    }
  }

  /// 计算各策略的信号
  Map<String, Map<String, dynamic>> _computeStrategySignals(
    List<HistoryKline> data,
    QuoteData? quote,
  ) {
    if (data.isEmpty) return {};
    final last = data[data.length - 1];
    final prev = data.length >= 2 ? data[data.length - 2] : last;
    final signals = <String, Map<String, dynamic>>{};

    // 趋势跟踪: MA5/MA20交叉
    if (_selectedStrategies.contains('trend_following')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (last.ma5 > 0 && last.ma20 > 0) {
        if (last.ma5 > last.ma20 && prev.ma5 <= prev.ma20) {
          signal = '买入';
          color = _kUp;
          detail = 'MA5上穿MA20金叉';
        } else if (last.ma5 < last.ma20 && prev.ma5 >= prev.ma20) {
          signal = '卖出';
          color = _kDown;
          detail = 'MA5下穿MA20死叉';
        } else if (last.ma5 > last.ma20) {
          signal = '偏多';
          color = _kUp;
          detail = 'MA5>MA20，趋势偏多';
        } else {
          signal = '偏空';
          color = _kDown;
          detail = 'MA5<MA20，趋势偏空';
        }
      }
      signals['trend_following'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // 均值回归: RSI超卖+布林下轨
    if (_selectedStrategies.contains('mean_reversion')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (last.rsi6 > 0 && last.bollLower > 0) {
        final rsiOversold = last.rsi6 < 30;
        final nearBollLower = last.close <= last.bollLower * 1.01;
        if (rsiOversold && nearBollLower) {
          signal = '买入';
          color = _kUp;
          detail = 'RSI=${last.rsi6.toStringAsFixed(1)}超卖+触及布林下轨';
        } else if (rsiOversold) {
          signal = '偏多';
          color = _kUp;
          detail = 'RSI=${last.rsi6.toStringAsFixed(1)}超卖，关注布林下轨';
        } else if (last.rsi6 > 70) {
          signal = '偏空';
          color = _kDown;
          detail = 'RSI=${last.rsi6.toStringAsFixed(1)}超买';
        } else {
          detail = 'RSI=${last.rsi6.toStringAsFixed(1)}，未到极端区域';
        }
      }
      signals['mean_reversion'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // MACD金叉
    if (_selectedStrategies.contains('macd_cross')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (last.macdDif != 0 || last.macdDea != 0) {
        if (last.macdDif > last.macdDea && prev.macdDif <= prev.macdDea) {
          signal = '买入';
          color = _kUp;
          detail = 'DIF上穿DEA金叉形成';
        } else if (last.macdDif < last.macdDea &&
            prev.macdDif >= prev.macdDea) {
          signal = '卖出';
          color = _kDown;
          detail = 'DIF下穿DEA死叉形成';
        } else if (last.macdHist > 0) {
          signal = '偏多';
          color = _kUp;
          detail = 'MACD柱状线>0，多头动能';
        } else {
          signal = '偏空';
          color = _kDown;
          detail = 'MACD柱状线<0，空头动能';
        }
      }
      signals['macd_cross'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // KDJ超卖
    if (_selectedStrategies.contains('kdj_oversold')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (last.k != 0 || last.d != 0) {
        if (last.k > last.d && prev.k <= prev.d && prev.k < 30) {
          signal = '买入';
          color = _kUp;
          detail = 'K=${last.k.toStringAsFixed(1)}超卖区金叉';
        } else if (last.k < 20) {
          signal = '偏多';
          color = _kUp;
          detail = 'K=${last.k.toStringAsFixed(1)}超卖区域';
        } else if (last.k > 80) {
          signal = '偏空';
          color = _kDown;
          detail = 'K=${last.k.toStringAsFixed(1)}超买区域';
        } else {
          detail =
              'K=${last.k.toStringAsFixed(1)} D=${last.d.toStringAsFixed(1)}';
        }
      }
      signals['kdj_oversold'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // 布林带突破
    if (_selectedStrategies.contains('boll_breakout')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (last.bollMid > 0) {
        final bandwidth =
            (last.bollUpper - last.bollLower) / last.bollMid * 100;
        if (last.close > last.bollUpper) {
          signal = '买入';
          color = _kUp;
          detail = '突破布林上轨(${last.bollUpper.toStringAsFixed(2)})';
        } else if (last.close < last.bollLower) {
          signal = '卖出';
          color = _kDown;
          detail = '跌破布林下轨(${last.bollLower.toStringAsFixed(2)})';
        } else if (bandwidth < 5) {
          detail = '带宽${bandwidth.toStringAsFixed(1)}%收窄蓄势中';
        } else {
          detail = '位于布林带中轨附近';
        }
      }
      signals['boll_breakout'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // 均线多头
    if (_selectedStrategies.contains('ma_multihead')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0) {
        final isMultiHead = last.ma5 > last.ma10 && last.ma10 > last.ma20;
        final wasMultiHead = prev.ma5 > prev.ma10 && prev.ma10 > prev.ma20;
        if (isMultiHead && !wasMultiHead) {
          signal = '买入';
          color = _kUp;
          detail = '均线多头排列刚形成';
        } else if (isMultiHead) {
          signal = '偏多';
          color = _kUp;
          detail = '均线多头排列持续中';
        } else if (!isMultiHead && wasMultiHead) {
          signal = '卖出';
          color = _kDown;
          detail = '均线多头排列瓦解';
        } else {
          detail = '均线未形成多头排列';
        }
      }
      signals['ma_multihead'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // 动量策略
    if (_selectedStrategies.contains('momentum')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (data.length >= 10) {
        final close5ago = data[data.length - 6].close;
        final momentum5d =
            close5ago > 0 ? (last.close / close5ago - 1) * 100 : 0.0;
        final volConfirm = last.volMa5 > 0 && last.volume > last.volMa5 * 1.2;
        if (momentum5d > 5 && volConfirm) {
          signal = '买入';
          color = _kUp;
          detail = '5日动量+${momentum5d.toStringAsFixed(1)}%，量能确认';
        } else if (momentum5d > 3) {
          signal = '偏多';
          color = _kUp;
          detail = '5日动量+${momentum5d.toStringAsFixed(1)}%';
        } else if (momentum5d < -5 && volConfirm) {
          signal = '卖出';
          color = _kDown;
          detail = '5日动量${momentum5d.toStringAsFixed(1)}%，放量下跌';
        } else if (momentum5d < -3) {
          signal = '偏空';
          color = _kDown;
          detail = '5日动量${momentum5d.toStringAsFixed(1)}%';
        } else {
          detail = '5日动量${momentum5d.toStringAsFixed(1)}%，方向不明';
        }
      }
      signals['momentum'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    // 缩量回调
    if (_selectedStrategies.contains('volume_pullback')) {
      String signal = '中性';
      String detail = '';
      Color color = _kTextSecondary;
      if (data.length >= 10 && last.ma5 > 0 && last.ma20 > 0) {
        final isUptrend = last.ma5 > last.ma20;
        final volShrink = last.volMa5 > 0 && last.volume < last.volMa5 * 0.7;
        final isPullback = last.close < last.open;
        if (isUptrend && volShrink && isPullback) {
          signal = '买入';
          color = _kUp;
          detail =
              '上升趋势中缩量回调，量比${(last.volume / (last.volMa5 > 0 ? last.volMa5 : 1)).toStringAsFixed(2)}';
        } else if (isUptrend && volShrink) {
          signal = '偏多';
          color = _kUp;
          detail = '上升趋势缩量整理中';
        } else if (!isUptrend) {
          detail = '非上升趋势，不适用';
        } else {
          detail = '回调量能未明显萎缩';
        }
      }
      signals['volume_pullback'] = {
        'signal': signal,
        'detail': detail,
        'color': color,
      };
    }

    return signals;
  }

  // ─── UI构建 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('量化分析',
            style: TextStyle(color: _kTextPrimary, fontSize: 18)),
        backgroundColor: _kCard,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kTextPrimary),
      ),
      body: Column(
        children: [
          // 搜索和选股区
          _buildSearchSection(),
          // 策略选择区
          _buildStrategySection(),
          // 分析按钮
          _buildAnalyzeButton(),
          const Divider(color: _kBorder, height: 1),
          // 结果区
          Expanded(child: _buildResultsSection()),
        ],
      ),
    );
  }

  // ─── 搜索选股区 ────────────────────────────────────────────────

  Widget _buildSearchSection() {
    return Container(
      color: _kCard,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择股票 (最多5只)',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          // 搜索框
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: const TextStyle(color: _kTextPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入股票代码或名称搜索...',
              hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search, color: _kTextSecondary, size: 20),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: _kTextSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchResults = []);
                          },
                        )
                      : null,
              filled: true,
              fillColor: _kBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          // 搜索结果下拉
          if (_searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: _kBorder, height: 1),
                itemBuilder: (context, index) {
                  final stock = _searchResults[index];
                  final alreadyAdded =
                      _selectedStocks.any((s) => s.code == stock.code);
                  return ListTile(
                    dense: true,
                    title: Text(
                      stock.name,
                      style: TextStyle(
                        color: alreadyAdded ? _kTextSecondary : _kTextPrimary,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      _displayCode(stock.code),
                      style:
                          const TextStyle(color: _kTextSecondary, fontSize: 12),
                    ),
                    trailing: alreadyAdded
                        ? const Text('已添加',
                            style:
                                TextStyle(color: _kTextSecondary, fontSize: 12))
                        : const Icon(Icons.add, color: _kAccent, size: 20),
                    onTap: alreadyAdded ? null : () => _addStock(stock),
                  );
                },
              ),
            ),
          // 已选股票chips
          if (_selectedStocks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedStocks.map((stock) {
                  return Chip(
                    label: Text(
                      '${stock.name}(${_displayCode(stock.code)})',
                      style:
                          const TextStyle(color: _kTextPrimary, fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    deleteIconColor: _kTextSecondary,
                    onDeleted: () => _removeStock(stock.code),
                    backgroundColor: _kBg,
                    side: const BorderSide(color: _kBorder),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 策略选择区 ────────────────────────────────────────────────

  Widget _buildStrategySection() {
    return Container(
      color: _kCard,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '选择策略',
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_selectedStrategies.length == _strategies.length) {
                      _selectedStrategies.clear();
                    } else {
                      _selectedStrategies.clear();
                      _selectedStrategies.addAll(_strategies.map((s) => s.id));
                    }
                  });
                },
                child: Text(
                  _selectedStrategies.length == _strategies.length
                      ? '取消全选'
                      : '全选',
                  style: const TextStyle(color: _kAccent, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 3.2,
            children: _strategies.map((strategy) {
              final selected = _selectedStrategies.contains(strategy.id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedStrategies.remove(strategy.id);
                    } else {
                      _selectedStrategies.add(strategy.id);
                    }
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? _kAccent.withValues(alpha: 0.15) : _kBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected ? _kAccent : _kBorder,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Icon(strategy.icon,
                          size: 14,
                          color: selected ? _kAccent : _kTextSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              strategy.name,
                              style: TextStyle(
                                color: selected ? _kAccent : _kTextPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              strategy.desc,
                              style: TextStyle(
                                color: _kTextSecondary,
                                fontSize: 9,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle,
                            color: _kAccent, size: 14),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── 分析按钮 ──────────────────────────────────────────────────

  Widget _buildAnalyzeButton() {
    final canAnalyze =
        _selectedStocks.isNotEmpty && _selectedStrategies.isNotEmpty;
    return Container(
      color: _kCard,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _isAnalyzing || !canAnalyze ? null : _runAnalysis,
          style: ElevatedButton.styleFrom(
            backgroundColor: canAnalyze ? _kAccent : _kBorder,
            foregroundColor: _kBg,
            disabledBackgroundColor: _kBorder,
            disabledForegroundColor: _kTextSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: _isAnalyzing
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: canAnalyze ? _kBg : _kTextSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '分析中 ${_analysisResults.length}/${_selectedStocks.length}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                )
              : Text(
                  canAnalyze
                      ? '开始分析 (${_selectedStocks.length}只股票 × ${_selectedStrategies.length}个策略)'
                      : '请选择股票和策略',
                  style: const TextStyle(fontSize: 14),
                ),
        ),
      ),
    );
  }

  // ─── 结果展示区 ────────────────────────────────────────────────

  Widget _buildResultsSection() {
    if (_analysisResults.isEmpty && !_isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.query_stats,
                size: 48, color: _kTextSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              '选择股票和策略后点击分析',
              style: TextStyle(color: _kTextSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _analysisResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _buildStockResultCard(_analysisResults[index]);
      },
    );
  }

  Widget _buildStockResultCard(_StockAnalysis result) {
    final isExpanded = _expandedStocks.contains(result.stock.code);

    if (result.error != null) {
      return Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${result.stock.name}(${_displayCode(result.stock.code)})',
                  style: const TextStyle(
                      color: _kTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.error!,
                style: const TextStyle(color: _kDown, fontSize: 13)),
          ],
        ),
      );
    }

    final analysis = result.analysis;
    final quote = result.quote;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          // 头部：股票名+评分+展开按钮
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedStocks.remove(result.stock.code);
                } else {
                  _expandedStocks.add(result.stock.code);
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              result.stock.name,
                              style: const TextStyle(
                                color: _kTextPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _displayCode(result.stock.code),
                              style: const TextStyle(
                                  color: _kTextSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                        if (quote != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                quote.price.toStringAsFixed(2),
                                style: TextStyle(
                                  color: quote.changePct >= 0 ? _kUp : _kDown,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: quote.changePct >= 0
                                      ? _kUp.withValues(alpha: 0.15)
                                      : _kDown.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    color: quote.changePct >= 0 ? _kUp : _kDown,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 综合评分
                  if (analysis != null)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getScoreColor(analysis.score)
                            .withValues(alpha: 0.15),
                        border: Border.all(
                          color: _getScoreColor(analysis.score),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${analysis.score}',
                          style: TextStyle(
                            color: _getScoreColor(analysis.score),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _kTextSecondary,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          // 展开内容
          if (isExpanded && analysis != null) ...[
            const Divider(color: _kBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 推荐和风险
                  _buildRecommendationRow(analysis),
                  const SizedBox(height: 12),
                  if (analysis.shortTermDecision != null) ...[
                    ShortTermDecisionPanel(
                      decision: analysis.shortTermDecision!,
                      recommendation: analysis.recommendationDecision ??
                          RecommendationDecision(
                            direction: analysis.shortTermDecision!.direction,
                            level: RecommendationLevel.neutralWatch,
                            label: analysis.recommendation,
                            legacyScore: analysis.score.clamp(1, 10),
                            actionable: analysis.score >= 6,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 各策略信号
                  _buildStrategySignalsSection(result),
                  const SizedBox(height: 12),
                  // 仓位建议
                  _buildPositionSection(result),
                  const SizedBox(height: 12),
                  // 回测结果
                  if (result.backtestResults.isNotEmpty) ...[
                    _buildBacktestSection(result),
                    const SizedBox(height: 12),
                  ],
                  // 风险等级
                  _buildRiskSection(analysis),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecommendationRow(AnalysisResult analysis) {
    return Row(
      children: [
        _buildInfoChip(
          '推荐',
          analysis.recommendation,
          _getRecommendationColor(analysis.recommendation),
        ),
        const SizedBox(width: 8),
        _buildInfoChip(
          '风险',
          analysis.riskLevel,
          _getRiskColor(analysis.riskLevel),
        ),
        const SizedBox(width: 8),
        _buildInfoChip(
          '置信度',
          '${(analysis.confidenceScore * 100).toStringAsFixed(0)}%',
          _kOrange,
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: _kTextSecondary, fontSize: 11)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildStrategySignalsSection(_StockAnalysis result) {
    final strategySignals = result.strategySignals;
    final selectedStrategies = _selectedStrategies.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '策略信号',
          style: TextStyle(
              color: _kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...selectedStrategies.map((strategyId) {
          final strategy = _strategies.firstWhere((s) => s.id == strategyId);
          final sig = strategySignals[strategyId];
          final signalText = sig?['signal'] as String? ?? '中性';
          final detailText = sig?['detail'] as String? ?? '暂无触发信号';
          final signalColor = sig?['color'] as Color? ?? _kTextSecondary;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    strategy.name,
                    style: const TextStyle(color: _kTextPrimary, fontSize: 12),
                  ),
                ),
                Container(
                  width: 44,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    signalText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: signalColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detailText,
                    style:
                        const TextStyle(color: _kTextSecondary, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPositionSection(_StockAnalysis result) {
    final position = result.positionRatio;
    final advice = PositionManager.getPositionAdvice(position);
    final analysis = result.analysis;

    String volLevel = '未知';
    if (analysis != null && result.quote != null) {
      final indicators = analysis.indicators;
      // indicators中存储的是ATR14原始值，需自行计算百分比
      if (indicators.containsKey('ATR14') && result.quote!.price > 0) {
        final atr14 = (indicators['ATR14'] as num).toDouble();
        final atrPct = atr14 / result.quote!.price * 100;
        volLevel = PositionManager.getVolatilityLevel(atrPct);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '仓位建议',
          style: TextStyle(
              color: _kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // 仓位条
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '建议仓位 ${(position * 100).round()}%',
                        style: TextStyle(
                          color: _getPositionColor(position),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        volLevel,
                        style: const TextStyle(
                            color: _kTextSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: position,
                      backgroundColor: _kBorder,
                      color: _getPositionColor(position),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          advice,
          style: const TextStyle(color: _kTextSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildBacktestSection(_StockAnalysis result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '历史回测',
          style: TextStyle(
              color: _kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...result.backtestResults.entries.map((entry) {
          final name = entry.key;
          final bt = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      color: _kAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildBacktestMetric(
                        '胜率',
                        '${(bt.winRate * 100).toStringAsFixed(1)}%',
                        bt.winRate >= 0.5 ? _kUp : _kDown),
                    _buildBacktestMetric(
                        '盈亏比',
                        bt.profitFactor > 0
                            ? bt.profitFactor.toStringAsFixed(2)
                            : 'N/A',
                        bt.profitFactor >= 1.5
                            ? _kUp
                            : bt.profitFactor >= 1.0
                                ? _kOrange
                                : _kDown),
                    _buildBacktestMetric(
                        '最大回撤',
                        '${(bt.maxDrawdown * 100).toStringAsFixed(1)}%',
                        bt.maxDrawdown < 0.1
                            ? _kUp
                            : bt.maxDrawdown < 0.2
                                ? _kOrange
                                : _kDown),
                    _buildBacktestMetric(
                        '总收益',
                        '${bt.totalReturn.toStringAsFixed(1)}%',
                        bt.totalReturn > 0 ? _kUp : _kDown),
                  ],
                ),
                Text(
                  '信号${bt.totalSignals}次 | 盈${bt.winningTrades}次 | 亏${bt.losingTrades}次',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 10),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBacktestMetric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: _kTextSecondary, fontSize: 10)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildRiskSection(AnalysisResult analysis) {
    if (analysis.riskFactors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '风险提示',
          style: TextStyle(
              color: _kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ...analysis.riskFactors.take(4).map((factor) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠ ',
                    style: TextStyle(color: _kOrange, fontSize: 11)),
                Expanded(
                  child: Text(
                    factor,
                    style:
                        const TextStyle(color: _kTextSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─── 辅助方法 ──────────────────────────────────────────────────

  Color _getScoreColor(double score) {
    if (score >= 8) return const Color(0xFF26a69a);
    if (score >= 7) return const Color(0xFF4caf50);
    if (score >= 6) return const Color(0xFF8bc34a);
    if (score >= 5) return const Color(0xFFffb74d);
    if (score >= 4) return const Color(0xFFff9800);
    if (score >= 3) return const Color(0xFFF44336);
    if (score >= 2) return const Color(0xFFe57373);
    return const Color(0xFFc62828);
  }

  Color _getRecommendationColor(String rec) {
    if (rec.contains('强烈买入')) return _kUp;
    if (rec.contains('买入')) return const Color(0xFF4CAF50);
    if (rec.contains('偏多')) return _kOrange;
    if (rec.contains('偏空')) return const Color(0xFFFF7043);
    if (rec.contains('卖出')) return _kDown;
    return _kTextSecondary;
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case '低':
        return _kDown;
      case '中等':
        return _kOrange;
      case '高':
        return _kUp;
      default:
        return _kTextSecondary;
    }
  }

  Color _getPositionColor(double position) {
    if (position >= 0.7) return _kUp;
    if (position >= 0.4) return _kOrange;
    return _kDown;
  }

  /// 从带前缀的代码中提取纯数字部分用于显示
  /// "sh600519" -> "600519", "sz000001" -> "000001"
  static String _displayCode(String code) {
    // 匹配常见的市场前缀 + 6位数字
    final match = RegExp(r'(?:sh|sz|bj)?(\d{6})').firstMatch(code);
    return match?.group(1) ?? code;
  }
}
