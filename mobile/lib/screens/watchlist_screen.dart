import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'quote_screen.dart';
import 'search_screen.dart';

class WatchlistScreen extends StatefulWidget {
  final Function(String)? onStockSelected;

  const WatchlistScreen({
    super.key,
    this.onStockSelected,
  });

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  List<WatchlistItem> _watchlist = [];
  List<QuoteData> _quotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final watchlist = await _dbService.getWatchlist();

      if (watchlist.isEmpty) {
        setState(() {
          _watchlist = watchlist;
          _quotes = [];
        });
      } else {
        final codes = watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
        final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
        final results = await Future.wait(futures);
        final quotes = results.where((q) => q != null).cast<QuoteData>().toList();

        setState(() {
          _watchlist = watchlist;
          _quotes = quotes;
        });
      }
    } catch (e) {
      print('Load watchlist failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onStockTap(String code, String name) {
    if (widget.onStockSelected != null) {
      widget.onStockSelected!(code);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuoteScreen(code: code, name: name),
      ),
    );
  }

  void _removeFromWatchlist(String code) async {
    await _dbService.removeFromWatchlist(code);
    _loadWatchlist();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已从自选股移除')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final upColor = isDark ? const Color(0xFFef5350) : const Color(0xFFc62828);
    final downColor = isDark ? const Color(0xFF26a69a) : const Color(0xFF2e7d32);

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _watchlist.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Text('暂无自选股', style: textTheme.titleMedium),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SearchScreen(onStockSelected: widget.onStockSelected),
                            ),
                          );
                        },
                        child: const Text('去添加'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _watchlist.length,
                itemBuilder: (context, index) {
                  final item = _watchlist[index];
                  final codeWithPrefix = _apiClient.addMarketPrefix(item.code);
                  final quote = _quotes.firstWhere((q) => q.code == codeWithPrefix, orElse: () => QuoteData.empty());
                  final isUp = quote.change >= 0;
                  final color = isUp ? upColor : downColor;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _onStockTap(codeWithPrefix, item.name),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                  Text(item.code, style: textTheme.bodyMedium?.copyWith(color: isDark ? Colors.grey[500] : Colors.grey[600])),
                                ],
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(quote.price.toStringAsFixed(2), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              Text(
                                '${isUp ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                                style: textTheme.bodyMedium?.copyWith(color: color),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: Icon(Icons.delete, color: isDark ? const Color(0xFFef5350) : const Color(0xFFc62828)),
                            onPressed: () => _removeFromWatchlist(item.code),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
  }
}
