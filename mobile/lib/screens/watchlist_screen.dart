import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'quote_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  List<WatchlistItem> _watchlist = [];
  List<QuoteData> _quotes = [];
  bool _isLoading = true;
  
  // 排序相关状态
  String _sortBy = 'default'; // 'default', 'change_pct'
  bool _sortAscending = false; // false=降序(从高到低), true=升序(从低到高)

  // 批量删除相关状态
  bool _isEditMode = false;
  Set<String> _selectedCodes = {};

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
      // ignore
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onStockTap(String code, String name) {
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

  // 切换排序方式
  void _toggleSort() {
    setState(() {
      if (_sortBy == 'change_pct') {
        // 如果已经是涨跌幅排序，切换升序/降序
        _sortAscending = !_sortAscending;
      } else {
        // 切换到涨跌幅排序，默认降序（从高到低）
        _sortBy = 'change_pct';
        _sortAscending = false;
      }
    });
  }

  // 获取排序后的股票列表
  List<Map<String, dynamic>> _getSortedWatchlist() {
    // 将watchlist和quotes组合成map列表
    final items = <Map<String, dynamic>>[];
    
    for (var i = 0; i < _watchlist.length; i++) {
      final item = _watchlist[i];
      final codeWithPrefix = _apiClient.addMarketPrefix(item.code);
      final quote = _quotes.firstWhere(
        (q) => q.code == codeWithPrefix,
        orElse: () => QuoteData.empty(),
      );
      
      items.add({
        'item': item,
        'quote': quote,
        'codeWithPrefix': codeWithPrefix,
      });
    }
    
    // 根据排序规则排序
    if (_sortBy == 'change_pct') {
      items.sort((a, b) {
        final changeA = a['quote'].changePct;
        final changeB = b['quote'].changePct;
        
        if (_sortAscending) {
          return changeA.compareTo(changeB); // 升序：从低到高
        } else {
          return changeB.compareTo(changeA); // 降序：从高到低
        }
      });
    }
    
    return items;
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
        : Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: textTheme.bodyLarge?.copyWith(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '搜索股票',
                          hintStyle: textTheme.bodyMedium?.copyWith(color: Colors.grey),
                          border: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          filled: true,
                          fillColor: const Color(0xFF16213e),
                        ),
                        onSubmitted: _searchAndAddStock,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _searchAndAddStock(_searchController.text),
                      child: const Text('添加'),
                    ),
                  ],
                ),
              ),
              // 排序按钮行
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      '共 ${_watchlist.length} 只股票',
                      style: textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                    const Spacer(),
                    // 编辑按钮
                    if (_watchlist.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isEditMode = !_isEditMode;
                            if (!_isEditMode) _selectedCodes.clear();
                          });
                        },
                        child: Text(_isEditMode ? '完成' : '编辑', style: const TextStyle(color: Colors.white70)),
                      ),
                    const SizedBox(width: 4),
                    // 排序按钮
                    InkWell(
                      onTap: _toggleSort,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _sortBy == 'change_pct' 
                              ? const Color(0xFF0f3460) 
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _sortBy == 'change_pct' 
                                ? Colors.blue 
                                : Colors.grey.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sort,
                              size: 16,
                              color: _sortBy == 'change_pct' 
                                  ? Colors.blue 
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sortBy == 'change_pct' 
                                  ? '涨跌幅' 
                                  : '默认排序',
                              style: TextStyle(
                                fontSize: 13,
                                color: _sortBy == 'change_pct' 
                                    ? Colors.blue 
                                    : Colors.grey,
                                fontWeight: _sortBy == 'change_pct' 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                              ),
                            ),
                            if (_sortBy == 'change_pct') ...[
                              const SizedBox(width: 4),
                              Icon(
                                _sortAscending 
                                    ? Icons.arrow_upward 
                                    : Icons.arrow_downward,
                                size: 14,
                                color: Colors.blue,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_watchlist.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Text('暂无自选股', style: textTheme.titleMedium),
                        const SizedBox(height: 16),
                        Text('在上方搜索框输入股票名称或代码添加', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                ..._getSortedWatchlist().map((data) {
                  final item = data['item'] as WatchlistItem;
                  final quote = data['quote'] as QuoteData;
                  final codeWithPrefix = data['codeWithPrefix'] as String;
                  final isUp = quote.changePct >= 0;
                  final color = isUp ? upColor : downColor;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFF16213e),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          if (_isEditMode)
                            Checkbox(
                              value: _selectedCodes.contains(item.code),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedCodes.add(item.code);
                                  } else {
                                    _selectedCodes.remove(item.code);
                                  }
                                });
                              },
                              fillColor: WidgetStateProperty.resolveWith((states) =>
                                  states.contains(WidgetState.selected) ? Colors.orange : Colors.white38),
                            ),
                          Expanded(
                            child: InkWell(
                              onTap: _isEditMode
                                  ? () {
                                      setState(() {
                                        if (_selectedCodes.contains(item.code)) {
                                          _selectedCodes.remove(item.code);
                                        } else {
                                          _selectedCodes.add(item.code);
                                        }
                                      });
                                    }
                                  : () => _onStockTap(codeWithPrefix, item.name),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                                  Text(item.code.substring(2), style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(quote.price.toStringAsFixed(2), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                              Text(
                                '${isUp ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                                style: textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (!_isEditMode) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_alert, color: Colors.blue),
                              onPressed: () => _addAlert(codeWithPrefix, item.name),
                              tooltip: '添加预警',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Color(0xFFef5350)),
                              onPressed: () => _removeFromWatchlist(item.code),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
              ),
              if (_isEditMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1a1a2e),
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Text('已选${_selectedCodes.length}只', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const Spacer(),
                        TextButton(
                          onPressed: _selectedCodes.isEmpty ? null : () {
                            final allCodes = _watchlist.map((w) => w.code).toSet();
                            if (_selectedCodes.length == allCodes.length) {
                              setState(() => _selectedCodes.clear());
                            } else {
                              setState(() => _selectedCodes = allCodes);
                            }
                          },
                          child: Text(
                            _selectedCodes.length == _watchlist.length ? '取消全选' : '全选',
                            style: TextStyle(color: _selectedCodes.isEmpty ? Colors.white24 : Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _selectedCodes.isEmpty ? null : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF1a1a2e),
                                title: const Text('确认删除', style: TextStyle(color: Colors.white)),
                                content: Text('确定要删除选中的${_selectedCodes.length}只股票吗？', style: const TextStyle(color: Colors.white70)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await DatabaseService().batchRemoveFromWatchlist(_selectedCodes.toList());
                              setState(() {
                                _isEditMode = false;
                                _selectedCodes.clear();
                              });
                              _loadWatchlist();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.red.withValues(alpha: 0.3),
                          ),
                          child: Text('删除选中(${_selectedCodes.length})'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
  }

  void _addAlert(String code, String name) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController priceController = TextEditingController();
        String conditionType = 'price_above';
        return AlertDialog(
          title: Text('添加预警: $name'),
          backgroundColor: const Color(0xFF16213e),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: conditionType,
                items: const [
                  DropdownMenuItem(value: 'price_above', child: Text('价格高于')),
                  DropdownMenuItem(value: 'price_below', child: Text('价格低于')),
                  DropdownMenuItem(value: 'change_above', child: Text('涨幅超过')),
                  DropdownMenuItem(value: 'change_below', child: Text('跌幅超过')),
                ],
                onChanged: (value) => conditionType = value!,
                dropdownColor: const Color(0xFF16213e),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '预警值',
                  filled: true,
                  fillColor: Color(0xFF0f3460),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final threshold = double.tryParse(priceController.text);
                if (threshold != null) {
                  await _dbService.addAlert(AlertRule(
                    code: code,
                    name: name,
                    conditionType: conditionType,
                    thresholdValue: threshold,
                    enabled: true,
                  ));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('预警已添加')),
                  );
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  void _searchAndAddStock(String keyword) async {
    if (keyword.isEmpty) return;

    final results = await _apiClient.searchStocks(keyword);
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该股票')),
      );
      return;
    }

    if (results.length == 1) {
      final stock = results.first;
      await _dbService.addToWatchlist(stock.code, stock.name);
      _loadWatchlist();
      _searchController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${stock.name} 到自选股')),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择股票'),
          backgroundColor: const Color(0xFF16213e),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final stock = results[index];
                return ListTile(
                  title: Text(stock.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(stock.code, style: const TextStyle(color: Colors.grey)),
                  onTap: () async {
                    await _dbService.addToWatchlist(stock.code, stock.name);
                    Navigator.pop(context);
                    _loadWatchlist();
                    _searchController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已添加 ${stock.name} 到自选股')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
    }
  }
}
