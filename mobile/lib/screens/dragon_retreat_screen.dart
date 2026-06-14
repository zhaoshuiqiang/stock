import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';

class DragonRetreatScreen extends StatefulWidget {
  final String code;
  final String name;
  final List<HistoryKline>? data;

  const DragonRetreatScreen({super.key, required this.code, required this.name, this.data});

  @override
  State<DragonRetreatScreen> createState() => _DragonRetreatScreenState();
}

class _DragonRetreatScreenState extends State<DragonRetreatScreen> {
  Map<String, dynamic>? dragonRetreat;
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
      dragonRetreat = detectDragonRetreat(processed);
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.all(16),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : dragonRetreat == null || !(dragonRetreat?['found'] ?? false)
              ? _buildNotFound()
              : _buildFound(),
    );
  }

  Widget _buildNotFound() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, color: Colors.white38, size: 48),
          SizedBox(height: 16),
          Text(
            '未发现龙回头形态',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFound() {
    final level = dragonRetreat?['level'] ?? '未知';
    final pullbackPct = dragonRetreat?['pullback_pct'] ?? 0.0;
    
    Color levelColor;
    switch (level) {
      case '强势':
        levelColor = Colors.green;
        break;
      case '一般':
        levelColor = Colors.orange;
        break;
      default:
        levelColor = Colors.blue;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '龙回头形态识别',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '形态状态: ',
                    style: TextStyle(color: Colors.white70),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      level,
                      style: TextStyle(color: levelColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '回调幅度',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                '${pullbackPct.toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '建议关注区间: ',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                '当前价格突破回调最低点3%可关注',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}