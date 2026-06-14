import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../widgets/signal_card.dart';
import 'search_screen.dart';

class SignalsScreen extends StatefulWidget {
  final String? selectedCode;

  const SignalsScreen({
    super.key,
    this.selectedCode,
  });

  @override
  State<SignalsScreen> createState() => SignalsScreenState();
}

class SignalsScreenState extends State<SignalsScreen> {
  final ApiClient _apiClient = ApiClient();
  String? _code;
  String? _name;
  AnalysisResult? _analysis;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedCode != null) {
      _loadAnalysis(widget.selectedCode!);
    }
  }

  @override
  void didUpdateWidget(SignalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCode != null && widget.selectedCode != _code) {
      _loadAnalysis(widget.selectedCode!);
    }
  }

  Future<void> _loadAnalysis(String code) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final codeWithPrefix = _apiClient.addMarketPrefix(code);
      setState(() {
        _code = codeWithPrefix;
      });
      final quote = await _apiClient.getRealtimeQuote(codeWithPrefix);
      if (quote != null) {
        setState(() {
          _name = quote.name;
        });
      }

      final klines = await _apiClient.getStockHistory(codeWithPrefix, days: 120);
      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, quote);

      setState(() {
        _analysis = analysis;
      });
    } catch (e) {
      debugPrint('Load analysis failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final upColor = isDark ? const Color(0xFFef5350) : const Color(0xFFc62828);
    final downColor = isDark ? const Color(0xFF26a69a) : const Color(0xFF2e7d32);
    final orangeColor = isDark ? const Color(0xFFff9800) : const Color(0xFFe65100);

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Card(
                margin: const EdgeInsets.all(8),
                color: const Color(0xFF161B22),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _showStockSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _code != null ? '$_name ($_code)' : '搜索股票',
                                  style: textTheme.bodyMedium?.copyWith(color: Colors.white),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_analysis != null)
                        Column(
                          children: [
                            Text(
                              '综合评分: ${_analysis!.score}',
                              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '操作建议: ${_analysis!.recommendation}',
                              style: textTheme.titleMedium?.copyWith(
                                color: _analysis!.score >= 6 ? upColor : downColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '风险等级: ${_analysis!.riskLevel}',
                              style: textTheme.bodyLarge?.copyWith(
                                color: _analysis!.riskLevel == '高' ? upColor : orangeColor,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (_analysis != null && _analysis!.signals.isNotEmpty)
                ..._analysis!.signals.map((signal) => SignalCard(signal: signal)),
              if (_analysis != null && _analysis!.signals.isEmpty)
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(child: Text('暂无信号', style: textTheme.bodyMedium)),
                  ),
                ),
              if (_analysis != null && _analysis!.suggestions.isNotEmpty)
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text('操作建议:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ..._analysis!.suggestions.map((s) => Text('- $s', style: textTheme.bodyMedium)),
                      ],
                    ),
                  ),
                ),
            ],
          );
  }

  void _showStockSearch() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen(selectMode: true)),
    );
    if (result != null && result is StockInfo) {
      _loadAnalysis(result.code);
    }
  }
}
