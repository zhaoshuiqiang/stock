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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: '输入股票名称或代码',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
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
                  ? const Center(child: Text('请输入关键词搜索'))
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
                                        Text(stock.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        Text(stock.code, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 16),
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
