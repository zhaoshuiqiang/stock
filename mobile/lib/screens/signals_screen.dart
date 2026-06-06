import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../widgets/signal_card.dart';

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
      print('Load analysis failed: $e');
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
        : _code == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('请选择一只股票查看信号分析', style: textTheme.titleMedium),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Card(
                    margin: const EdgeInsets.all(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(
                            '$_name ($_code)',
                            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                                    color: _analysis!.score >= 60 ? upColor : downColor,
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
}
