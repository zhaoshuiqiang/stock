import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'quote_screen.dart';
import 'sector_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final ApiClient _apiClient = ApiClient();
  List<QuoteData> _quotes = [];
  List<SectorInfo> _sectors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final codes = ['sh000001', 'sz399001', 'sz399006'];
      final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
      final results = await Future.wait(futures);

      final sectors = await _apiClient.getHotSectors();

      setState(() {
        _quotes = results.where((q) => q != null).cast<QuoteData>().toList();
        _sectors = sectors;
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () async {
              await _loadData();
            },
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          '今日大盘',
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildMarketItem('上证指数', 'sh000001'),
                            _buildMarketItem('深证成指', 'sz399001'),
                            _buildMarketItem('创业板指', 'sz399006'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          '热门板块',
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        if (_sectors.isEmpty)
                          const Text('暂无板块数据', style: TextStyle(color: Colors.white38))
                        else
                          ..._sectors.take(20).map((sector) => _buildSectorItem(sector)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildMarketItem(String name, String code) {
    final quote = _quotes.firstWhere((q) => q.code == code, orElse: () => QuoteData.empty());
    final isUp = quote.change >= 0;
    final color = isUp ? Colors.red : Colors.green;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuoteScreen(code: code, name: name),
          ),
        );
      },
      child: Column(
        children: [
          Text(name, style: textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(quote.price.toStringAsFixed(2), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${isUp ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
            style: textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSectorItem(SectorInfo sector) {
    final isUp = sector.changePct >= 0;
    final color = isUp ? Colors.red : Colors.green;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SectorScreen(
              sectorName: sector.name,
              sectorCode: sector.code,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sector.name, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('领涨: ${sector.leadStockName}', style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                ],
              ),
            ),
            Text(
              '${isUp ? '+' : ''}${sector.changePct.toStringAsFixed(2)}%',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
