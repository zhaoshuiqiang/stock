import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';

class TrendSignalScreen extends StatefulWidget {
  final String code;
  final String name;
  final List<HistoryKline>? data;

  const TrendSignalScreen({super.key, required this.code, required this.name, this.data});

  @override
  State<TrendSignalScreen> createState() => _TrendSignalScreenState();
}

class _TrendSignalScreenState extends State<TrendSignalScreen> {
  List<String> stabilization = [];
  List<String> top = [];
  List<String> bottom = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    if (widget.data != null && widget.data!.length >= 20) {
      final processed = calcAllIndicators(widget.data!);
      final signals = detectTrendSignals(processed);
      setState(() {
        stabilization = List<String>.from(signals['stabilization'] ?? []);
        top = List<String>.from(signals['top'] ?? []);
        bottom = List<String>.from(signals['bottom'] ?? []);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0f3460),
      padding: const EdgeInsets.all(16),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '趋势信号分析',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (stabilization.isNotEmpty) _buildSignalSection('企稳信号', stabilization, Colors.blue),
                if (stabilization.isNotEmpty) const SizedBox(height: 12),
                if (top.isNotEmpty) _buildSignalSection('见顶信号', top, Colors.red),
                if (top.isNotEmpty) const SizedBox(height: 12),
                if (bottom.isNotEmpty) _buildSignalSection('见底信号', bottom, Colors.green),
                if (stabilization.isEmpty && top.isEmpty && bottom.isEmpty)
                  const Center(
                    child: Text(
                      '暂无趋势信号',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSignalSection(String title, List<String> signals, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                ' $title (${signals.length}个)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...signals.map((signal) => Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Row(
                  children: [
                    const Text('· ', style: TextStyle(color: Colors.white54)),
                    Text(signal, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}