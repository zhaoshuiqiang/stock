import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'quote_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final ApiClient _apiClient = ApiClient();
  List<QuoteData> _quotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final codes = [
        'sh000001',
        'sz399001',
        'sz399006',
        'sh600519',
        'sz000858',
        'sh601318',
        'sz000001',
        'sh600036',
      ];

      final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
      final results = await Future.wait(futures);

      setState(() {
        _quotes = results.where((q) => q != null).cast<QuoteData>().toList();
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
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        '今日大盘',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      const Text(
                        '热门股票',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ..._quotes
                          .where((q) => !['sh000001', 'sz399001', 'sz399006'].contains(q.code))
                          .map((quote) => _buildStockItem(quote)),
                    ],
                  ),
                ),
              ),
            ],
          );
  }

  Widget _buildMarketItem(String name, String code) {
    final quote = _quotes.firstWhere((q) => q.code == code, orElse: () => QuoteData.empty());
    final isUp = quote.change >= 0;
    final color = isUp ? Colors.red : Colors.green;

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
          Text(name, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          Text(quote.price.toStringAsFixed(2), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${isUp ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
            style: TextStyle(fontSize: 14, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStockItem(QuoteData quote) {
    final isUp = quote.change >= 0;
    final color = isUp ? Colors.red : Colors.green;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuoteScreen(code: quote.code, name: quote.name),
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
                  Text(quote.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(quote.code, style: const TextStyle(fontSize: 12, color: Colors.grey[400])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(quote.price.toStringAsFixed(2), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  '${isUp ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 14, color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
