import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'quote_screen.dart';

class SearchScreen extends StatefulWidget {
  final Function(String)? onStockSelected;

  const SearchScreen({
    super.key,
    this.onStockSelected,
  });

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _controller = TextEditingController();
  List<StockInfo> _results = [];
  bool _isLoading = false;

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _results = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _apiClient.searchStocks(keyword);
      setState(() {
        _results = results;
      });
    } catch (e) {
      print('Search failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearch() {
    _search(_controller.text);
  }

  void _onStockTap(StockInfo stock) {
    if (widget.onStockSelected != null) {
      widget.onStockSelected!(stock.code);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuoteScreen(code: stock.code, name: stock.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: '输入股票名称或代码',
                    hintStyle: textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    filled: true,
                    fillColor: theme.cardColor,
                  ),
                  onSubmitted: (_) => _onSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _onSearch,
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? Center(child: Text('请输入关键词搜索', style: textTheme.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final stock = _results[index];

                        return InkWell(
                          onTap: () => _onStockTap(stock),
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(stock.name, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                        Text(stock.code, style: textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios, size: 16, color: theme.dividerColor),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
