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
  List<HistoryKline> _klines = [];
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
      _code = code;
    });

    try {
      final quote = await _apiClient.getRealtimeQuote(code);
      if (quote != null) {
        setState(() {
          _name = quote.name;
        });
      }

      final klines = await _apiClient.getStockHistory(code, days: 120);
      final calculated = calcAllIndicators(klines);
      final analysis = generateAnalysis(calculated, quote);

      setState(() {
        _klines = calculated;
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
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _code == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('请选择一只股票查看信号分析'),
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
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          if (_analysis != null)
                            Column(
                              children: [
                                Text(
                                  '综合评分: ${_analysis!.score}',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '操作建议: ${_analysis!.recommendation}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _analysis!.score >= 60 ? Colors.red : Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '风险等级: ${_analysis!.riskLevel}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _analysis!.riskLevel == '高' ? Colors.red : Colors.orange,
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
                    const Card(
                      margin: EdgeInsets.all(8),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: Text('暂无信号')),
                      ),
                    ),
                  if (_analysis != null && _analysis!.suggestions.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            const Text('操作建议:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ..._analysis!.suggestions.map((s) => Text('- $s')),
                          ],
                        ),
                      ),
                    ),
                ],
              );
  }
}
