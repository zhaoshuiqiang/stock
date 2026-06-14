import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/stock_card.dart';
import 'quote_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen>
    with WidgetsBindingObserver {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  List<WatchlistItem> _watchlist = [];
  List<QuoteData> _quotes = [];
  bool _isLoading = true;

  // 排序相关状态
  String _sortBy = 'default'; // 'default', 'change_pct'
  bool _sortAscending = false;

  // 批量删除相关状态
  bool _isEditMode = false;
  Set<String> _selectedCodes = {};

  // 筛选：全部/看多/看空/观望
  String _filterType = '全部';

  // 30秒自动刷新
  Timer? _refreshTimer;

  // 颜色常量
  static const Color _bgColor = Color(0xFF0D1117);
  static const Color _cardColor = Color(0xFF161B22);
  static const Color _accentColor = Color(0xFF58A6FF);
  static const Color _upColor = Color(0xFFE74C3C);
  static const Color _downColor = Color(0xFF2ECC71);
  static const Color _textPrimary = Color(0xFFF0F6FC);
  static const Color _textSecondary = Color(0xFF8B949E);
  static const Color _borderColor = Color(0xFF30363D);
  static const Color _darkSurface = Color(0xFF21262D);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWatchlist();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      _loadWatchlist();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshQuotes();
    });
  }

  Future<void> _refreshQuotes() async {
    if (_watchlist.isEmpty) return;
    try {
      final codes =
          _watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
      final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
      final results = await Future.wait(futures);
      final quotes = results.where((q) => q != null).cast<QuoteData>().toList();
      if (mounted) {
        setState(() {
          _quotes = quotes;
        });
      }
    } catch (_) {}
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
        final codes = watchlist
            .map((item) => _apiClient.addMarketPrefix(item.code))
            .toList();
        final futures = codes.map((code) => _apiClient.getRealtimeQuote(code));
        final results = await Future.wait(futures);
        final quotes =
            results.where((q) => q != null).cast<QuoteData>().toList();

        setState(() {
          _watchlist = watchlist;
          _quotes = quotes;
        });
      }
    } catch (_) {
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

  void _toggleSort() {
    setState(() {
      if (_sortBy == 'change_pct') {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = 'change_pct';
        _sortAscending = false;
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredAndSortedWatchlist() {
    final items = <Map<String, dynamic>>[];

    for (var i = 0; i < _watchlist.length; i++) {
      final item = _watchlist[i];
      final codeWithPrefix = _apiClient.addMarketPrefix(item.code);
      final quote = _quotes.firstWhere(
        (q) => q.code == codeWithPrefix,
        orElse: () => QuoteData.empty(),
      );

      // 筛选
      if (_filterType == '看多' && quote.changePct <= 0) continue;
      if (_filterType == '看空' && quote.changePct >= 0) continue;
      if (_filterType == '观望' && quote.changePct != 0) continue;

      items.add({
        'item': item,
        'quote': quote,
        'codeWithPrefix': codeWithPrefix,
      });
    }

    // 排序
    if (_sortBy == 'change_pct') {
      items.sort((a, b) {
        final changeA = a['quote'].changePct;
        final changeB = b['quote'].changePct;
        return _sortAscending
            ? changeA.compareTo(changeB)
            : changeB.compareTo(changeA);
      });
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bgColor,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _accentColor))
          : Column(
              children: [
                _buildSearchBar(),
                _buildFilterAndSortBar(),
                Expanded(child: _buildList()),
                if (_isEditMode) _buildEditBottomBar(),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: _darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: _textPrimary, fontSize: 15),
        decoration: const InputDecoration(
          hintText: '搜索股票名称或代码',
          hintStyle: TextStyle(color: _textSecondary, fontSize: 15),
          prefixIcon: Icon(Icons.search, color: _textSecondary, size: 22),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onSubmitted: _searchAndAddStock,
      ),
    );
  }

  Widget _buildFilterAndSortBar() {
    final filters = ['全部', '看多', '看空', '观望'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          // 筛选 Chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((f) {
                  final isSelected = _filterType == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterType = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _accentColor.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? _accentColor
                                : _borderColor,
                          ),
                        ),
                        child: Text(
                          f,
                          style: TextStyle(
                            color: isSelected
                                ? _accentColor
                                : _textSecondary,
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 排序按钮
          GestureDetector(
            onTap: _toggleSort,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _sortBy == 'change_pct'
                    ? _accentColor.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _sortBy == 'change_pct'
                      ? _accentColor
                      : _borderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort,
                    size: 16,
                    color: _sortBy == 'change_pct'
                        ? _accentColor
                        : _textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _sortBy == 'change_pct' ? '涨跌幅' : '默认排序',
                    style: TextStyle(
                      fontSize: 13,
                      color: _sortBy == 'change_pct'
                          ? _accentColor
                          : _textSecondary,
                      fontWeight: _sortBy == 'change_pct'
                          ? FontWeight.w600
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
                      color: _accentColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final items = _getFilteredAndSortedWatchlist();

    if (_watchlist.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.watch_later_outlined,
                  size: 64, color: _textSecondary.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text(
                '暂无自选股',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '在上方搜索框输入股票名称或代码添加',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '当前筛选无结果',
            style: TextStyle(color: _textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _accentColor,
      backgroundColor: _cardColor,
      onRefresh: _loadWatchlist,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final data = items[index];
          final item = data['item'] as WatchlistItem;
          final quote = data['quote'] as QuoteData;
          final codeWithPrefix = data['codeWithPrefix'] as String;

          if (_isEditMode) {
            return _buildEditItem(item, quote, codeWithPrefix);
          }

          return Dismissible(
            key: Key(item.code),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 8),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete, color: Colors.red, size: 28),
            ),
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: _cardColor,
                  title: const Text('确认删除',
                      style: TextStyle(color: _textPrimary)),
                  content: Text('确定要从自选股移除 ${item.name} 吗？',
                      style: const TextStyle(color: _textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消',
                          style: TextStyle(color: _textSecondary)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) => _removeFromWatchlist(item.code),
            child: GestureDetector(
              onLongPress: () {
                setState(() {
                  _isEditMode = true;
                  _selectedCodes.add(item.code);
                });
              },
              child: StockCard(
                name: item.name,
                code: codeWithPrefix,
                price: quote.price,
                changePct: quote.changePct,
                pe: quote.pe > 0 ? quote.pe : null,
                pb: quote.pb > 0 ? quote.pb : null,
                onTap: () => _onStockTap(codeWithPrefix, item.name),
                trailing: IconButton(
                  icon: const Icon(Icons.add_alert,
                      color: _accentColor, size: 22),
                  onPressed: () => _addAlert(codeWithPrefix, item.name),
                  tooltip: '添加预警',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditItem(
      WatchlistItem item, QuoteData quote, String codeWithPrefix) {
    final isSelected = _selectedCodes.contains(item.code);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCodes.remove(item.code);
          } else {
            _selectedCodes.add(item.code);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _accentColor : _borderColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _accentColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? _accentColor : _textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: _textPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(codeWithPrefix,
                      style: const TextStyle(
                          color: _textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  quote.price > 0
                      ? '¥${quote.price.toStringAsFixed(2)}'
                      : '--',
                  style: TextStyle(
                    color: quote.changePct > 0
                        ? _upColor
                        : quote.changePct < 0
                            ? _downColor
                            : _textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${quote.changePct >= 0 ? '+' : ''}${quote.changePct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: quote.changePct > 0
                        ? _upColor
                        : quote.changePct < 0
                            ? _downColor
                            : _textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _darkSurface,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text(
              '已选${_selectedCodes.length}只',
              style: const TextStyle(color: _textSecondary, fontSize: 14),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() {
                  final allCodes = _watchlist.map((w) => w.code).toSet();
                  if (_selectedCodes.length == allCodes.length) {
                    _selectedCodes.clear();
                  } else {
                    _selectedCodes = allCodes;
                  }
                });
              },
              child: Text(
                _selectedCodes.length == _watchlist.length ? '取消全选' : '全选',
                style: TextStyle(
                  color: _selectedCodes.isEmpty
                      ? _textSecondary.withOpacity(0.5)
                      : _accentColor,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _selectedCodes.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: _cardColor,
                          title: const Text('确认删除',
                              style: TextStyle(color: _textPrimary)),
                          content: Text(
                              '确定要删除选中的${_selectedCodes.length}只股票吗？',
                              style:
                                  const TextStyle(color: _textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('取消',
                                  style:
                                      TextStyle(color: _textSecondary)),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await DatabaseService()
                            .batchRemoveFromWatchlist(_selectedCodes.toList());
                        setState(() {
                          _isEditMode = false;
                          _selectedCodes.clear();
                        });
                        _loadWatchlist();
                      }
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedCodes.isEmpty
                      ? Colors.red.withOpacity(0.2)
                      : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '删除选中(${_selectedCodes.length})',
                  style: TextStyle(
                    color: _selectedCodes.isEmpty
                        ? _textSecondary
                        : _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addAlert(String code, String name) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController priceController = TextEditingController();
        String conditionType = 'price_above';
        return AlertDialog(
          backgroundColor: _cardColor,
          title: Text('添加预警: $name',
              style: const TextStyle(color: _textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: conditionType,
                items: const [
                  DropdownMenuItem(
                      value: 'price_above', child: Text('价格高于')),
                  DropdownMenuItem(
                      value: 'price_below', child: Text('价格低于')),
                  DropdownMenuItem(
                      value: 'change_above', child: Text('涨幅超过')),
                  DropdownMenuItem(
                      value: 'change_below', child: Text('跌幅超过')),
                ],
                onChanged: (value) => conditionType = value!,
                dropdownColor: _darkSurface,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '预警值',
                  labelStyle: const TextStyle(color: _textSecondary),
                  filled: true,
                  fillColor: _darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                ),
                style: const TextStyle(color: _textPrimary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消',
                  style: TextStyle(color: _textSecondary)),
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
              child:
                  const Text('确认', style: TextStyle(color: _accentColor)),
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
          backgroundColor: _cardColor,
          title: const Text('选择股票',
              style: TextStyle(color: _textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final stock = results[index];
                return ListTile(
                  title: Text(stock.name,
                      style: const TextStyle(color: _textPrimary)),
                  subtitle: Text(stock.code,
                      style: const TextStyle(color: _textSecondary)),
                  onTap: () async {
                    await _dbService.addToWatchlist(stock.code, stock.name);
                    Navigator.pop(context);
                    _loadWatchlist();
                    _searchController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('已添加 ${stock.name} 到自选股')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消',
                  style: TextStyle(color: _textSecondary)),
            ),
          ],
        ),
      );
    }
  }
}
