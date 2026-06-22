import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../core/trading_session.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/alert_dialog.dart';

// ─── 配色常量 ────────────────────────────────────────────────────────
const _kBg = Color(0xFF0D1117);
const _kCard = Color(0xFF161B22);
const _kAccent = Color(0xFF58A6FF);
const _kUp = Color(0xFFE74C3C);
const _kDown = Color(0xFF2ECC71);
const _kTextPrimary = Color(0xFFF0F6FC);
const _kTextSecondary = Color(0xFF8B949E);
const _kBorder = Color(0xFF30363D);

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => AlertsScreenState();
}

class AlertsScreenState extends State<AlertsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ApiClient _apiClient = ApiClient();
  List<AlertRule> _alerts = [];
  bool _isLoading = true;
  String _filterType = '全部';
  String _sortBy = 'time';
  bool _sortAscending = false;
  Map<String, QuoteData> _currentQuotes = {};
  Timer? _refreshTimer;

  // 批量选择模式
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (TradingSession.isInTradingSession() && _alerts.isNotEmpty) {
        _refreshCurrentPrices();
      }
    });
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    try {
      final alerts = await _dbService.getAlerts();
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
      _refreshCurrentPrices();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCurrentPrices() async {
    if (_alerts.isEmpty) return;
    try {
      final codes = _alerts.map((a) => _apiClient.addMarketPrefix(a.code)).toList();
      final allQuotes = await _apiClient.getBatchRealtimeQuotes(codes);
      final quoteMap = <String, QuoteData>{};
      for (final q in allQuotes) {
        quoteMap[q.code] = q;
      }
      if (!mounted) return;
      setState(() {
        for (final alert in _alerts) {
          final prefixed = _apiClient.addMarketPrefix(alert.code);
          final quote = quoteMap[prefixed];
          if (quote != null) {
            _currentQuotes[alert.code] = quote;
          }
        }
      });
    } catch (_) {}
  }

  List<AlertRule> get _filteredAndSorted {
    var items = _alerts.toList();

    switch (_filterType) {
      case '已启用':
        items = items.where((a) => a.enabled).toList();
        break;
      case '已禁用':
        items = items.where((a) => !a.enabled).toList();
        break;
    }

    items.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'name':
          cmp = a.name.compareTo(b.name);
          break;
        case 'type':
          cmp = a.conditionType.compareTo(b.conditionType);
          break;
        default:
          cmp = a.createdAt.compareTo(b.createdAt);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return items;
  }

  void _createAlert() {
    showDialog(
      context: context,
      builder: (_) => const AlertCreateDialog(rule: null),
    ).then((result) {
      if (result != null) {
        _dbService.addAlert(result as AlertRule).then((_) => _loadAlerts());
      }
    });
  }

  void _editAlert(AlertRule alert) {
    showDialog(
      context: context,
      builder: (_) => AlertCreateDialog(rule: alert),
    ).then((result) {
      if (result != null) {
        _dbService.updateAlert(result as AlertRule).then((_) => _loadAlerts());
      }
    });
  }

  void _toggleAlert(AlertRule alert) async {
    await _dbService.updateAlert(alert.copyWith(enabled: !alert.enabled));
    _loadAlerts();
  }

  void _deleteAlert(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('确认删除', style: TextStyle(color: _kTextPrimary)),
        content: const Text('确定要删除该预警规则吗？',
            style: TextStyle(color: _kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: _kUp)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dbService.deleteAlert(id);
      _loadAlerts();
    }
  }

  void _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('批量删除', style: TextStyle(color: _kTextPrimary)),
        content: Text('确定要删除选中的 $count 条预警规则吗？',
            style: const TextStyle(color: _kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: _kUp)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final id in _selectedIds) {
        await _dbService.deleteAlert(id);
      }
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _selectMode = false;
      });
      _loadAlerts();
    }
  }

  void _batchToggleSelected(bool enable) async {
    for (final id in _selectedIds) {
      final alert = _alerts.firstWhere((a) => a.id == id);
      await _dbService.updateAlert(alert.copyWith(enabled: enable));
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
    _loadAlerts();
  }

  void _batchToggleAll(bool enable) async {
    final targets = _alerts.where((a) => a.enabled != enable).toList();
    if (targets.isEmpty) return;
    for (final alert in targets) {
      await _dbService.updateAlert(alert.copyWith(enabled: enable));
    }
    _loadAlerts();
  }

  String _formatCondition(String conditionType) {
    switch (conditionType) {
      case 'price_above':
      case 'above':
        return '价格高于';
      case 'price_below':
      case 'below':
        return '价格低于';
      case 'change_above':
      case 'rise':
        return '涨幅超过';
      case 'change_below':
      case 'fall':
        return '跌幅超过';
      case 'indicator':
        return '指标触发';
      default:
        return conditionType;
    }
  }

  String _formatThreshold(String conditionType, double value) {
    if (conditionType == 'change_above' ||
        conditionType == 'change_below' ||
        conditionType == 'rise' ||
        conditionType == 'fall') {
      return '${value.toStringAsFixed(2)}%';
    }
    return value.toStringAsFixed(2);
  }

  Color _conditionColor(String conditionType) {
    switch (conditionType) {
      case 'price_above':
      case 'change_above':
      case 'rise':
      case 'above':
        return _kUp;
      case 'price_below':
      case 'change_below':
      case 'fall':
      case 'below':
        return _kDown;
      case 'indicator':
        return _kAccent;
      default:
        return _kTextSecondary;
    }
  }

  String _formatIndicatorType(String type) {
    switch (type) {
      case 'rsi': return 'RSI';
      case 'macd': return 'MACD';
      case 'kdj': return 'KDJ';
      case 'volume': return '成交量';
      case 'volume_ratio': return '量比';
      case 'turnover': return '换手率';
      case 'amplitude': return '振幅';
      case 'cci': return 'CCI';
      case 'wr': return 'WR';
      case 'boll': return '布林带';
      case 'atr': return 'ATR';
      case 'ma_cross': return '均线交叉';
      default: return type.toUpperCase();
    }
  }

  /// 计算当前价格与触发阈值的距离描述
  String _distanceToThreshold(AlertRule alert, QuoteData? quote) {
    if (quote == null || quote.price <= 0) return '';
    final current = quote.price;
    final thresh = alert.thresholdValue;
    if (thresh <= 0) return '';

    final diff = thresh - current;

    switch (alert.conditionType) {
      case 'price_above':
      case 'above':
        return diff > 0
            ? '距触发还需涨 ${diff.toStringAsFixed(2)}'
            : '已触发（超出 ${diff.abs().toStringAsFixed(2)}）';
      case 'price_below':
      case 'below':
        return diff < 0
            ? '距触发还需跌 ${diff.abs().toStringAsFixed(2)}'
            : '已触发（低于 ${diff.abs().toStringAsFixed(2)}）';
      case 'change_above':
      case 'rise':
        // thresh是涨幅百分比，quote.changePct是当日实际涨跌幅
        final remaining = thresh - quote.changePct;
        return remaining > 0
            ? '距触发还需涨 ${remaining.toStringAsFixed(2)}%'
            : '已触发（超出 ${remaining.abs().toStringAsFixed(2)}%）';
      case 'change_below':
      case 'fall':
        // thresh是跌幅阈值（正数），触发条件是当日跌幅 <= -thresh
        final remaining = thresh + quote.changePct;
        return remaining > 0
            ? '距触发还需跌 ${remaining.toStringAsFixed(2)}%'
            : '已触发（超出 ${remaining.abs().toStringAsFixed(2)}%）';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAndSorted;
    final enabledCount = _alerts.where((a) => a.enabled).length;
    final triggeredCount = _alerts.where((a) => a.lastTriggeredAt != null).length;

    return SafeArea(
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: _selectMode ? _buildSelectAppBar(filtered) : null,
        body: RefreshIndicator(
          color: _kAccent,
          backgroundColor: _kCard,
          onRefresh: _loadAlerts,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _kAccent))
              : CustomScrollView(
                  slivers: [
                    // 统计头部卡片
                    SliverToBoxAdapter(
                      child: _buildStatsCard(enabledCount, triggeredCount),
                    ),
                    // 筛选排序栏
                    SliverToBoxAdapter(
                      child: _buildFilterSortBar(),
                    ),
                    // 预警列表或空状态
                    if (filtered.isEmpty)
                      SliverFillRemaining(child: _buildEmptyState())
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _buildAlertCard(filtered[i]),
                          childCount: filtered.length,
                        ),
                      ),
                    // 底部留白
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
        ),
      ),
    );
  }

  // ─── 选择模式 AppBar ──────────────────────────────────────────────
  PreferredSizeWidget _buildSelectAppBar(List<AlertRule> filtered) {
    final selectable = filtered.where((a) => !_selectedIds.contains(a.id)).length;
    return AppBar(
      backgroundColor: _kCard,
      leading: TextButton(
        onPressed: () => setState(() {
          _selectMode = false;
          _selectedIds.clear();
        }),
        child: const Text('取消', style: TextStyle(color: _kAccent, fontSize: 15)),
      ),
      title: Text('已选 ${_selectedIds.length} 项',
          style: const TextStyle(color: _kTextPrimary, fontSize: 16)),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            if (_selectedIds.length == filtered.length) {
              _selectedIds.clear();
            } else {
              _selectedIds.addAll(filtered.map((a) => a.id));
            }
          }),
          child: Text(
            _selectedIds.length == filtered.length ? '取消全选' : '全选$selectable项',
            style: const TextStyle(color: _kAccent, fontSize: 14),
          ),
        ),
        if (_selectedIds.isNotEmpty) ...[
          TextButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('启用', style: TextStyle(fontSize: 13)),
            onPressed: () => _batchToggleSelected(true),
            style: TextButton.styleFrom(foregroundColor: _kAccent),
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('删除', style: TextStyle(fontSize: 13)),
            onPressed: _deleteSelected,
            style: TextButton.styleFrom(foregroundColor: _kUp),
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  // ─── 统计头部卡片 ─────────────────────────────────────────────────
  Widget _buildStatsCard(int enabledCount, int triggeredCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAccent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('总计', _alerts.length.toString(), _kTextPrimary),
                _buildStatItem('启用', enabledCount.toString(), _kAccent),
                _buildStatItem('已触发', triggeredCount.toString(), _kUp),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 批量操作按钮组
          if (_alerts.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _batchToggleAll(true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _kAccent.withOpacity(0.4)),
                ),
                child: const Text('全部启用',
                    style: TextStyle(color: _kAccent, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _batchToggleAll(false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _kTextSecondary.withOpacity(0.4)),
                ),
                child: const Text('全部禁用',
                    style: TextStyle(color: _kTextSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          const SizedBox(width: 6),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加', style: TextStyle(fontSize: 12)),
            onPressed: _createAlert,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 11)),
      ],
    );
  }

  // ─── 筛选排序栏 ───────────────────────────────────────────────────
  Widget _buildFilterSortBar() {
    const filterItems = ['全部', '已启用', '已禁用'];
    const sortItems = ['时间', '名称', '类型'];
    const sortToValue = {'时间': 'time', '名称': 'name', '类型': 'type'};

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          // 筛选下拉框
          _buildCleanDropdown(
            value: _filterType,
            items: filterItems,
            label: '筛选',
            onChanged: (v) => setState(() => _filterType = v),
          ),
          const SizedBox(width: 6),
          // 排序下拉框
          _buildCleanDropdown(
            value: _sortBy == 'time' ? '时间' : _sortBy == 'name' ? '名称' : '类型',
            items: sortItems,
            label: '排序',
            onChanged: (display) {
              setState(() => _sortBy = sortToValue[display] ?? 'time');
            },
          ),
          // 升降序切换
          GestureDetector(
            onTap: () => setState(() => _sortAscending = !_sortAscending),
            child: Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 18,
              color: _kTextSecondary,
            ),
          ),
          const Spacer(),
          // 批量选择入口
          if (_alerts.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _selectMode = true;
                _selectedIds.clear();
              }),
              child: const Text('批量管理',
                  style: TextStyle(color: _kAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildCleanDropdown({
    required String value,
    required List<String> items,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          iconEnabledColor: _kTextSecondary,
          dropdownColor: const Color(0xFF21262D),
          style: const TextStyle(color: _kTextPrimary, fontSize: 12),
          selectedItemBuilder: (_) => items.map((item) => Text(
            item,
            style: const TextStyle(color: _kTextPrimary, fontSize: 12),
          )).toList(),
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 12)),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  // ─── 空状态 ───────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_outlined,
              size: 48, color: _kTextSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text('暂无预警规则',
              style: TextStyle(color: _kTextSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('添加价格/涨幅/指标预警，实时监控异动',
              style: TextStyle(color: _kTextSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加预警'),
            onPressed: _createAlert,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 预警卡片 ─────────────────────────────────────────────────────
  Widget _buildAlertCard(AlertRule alert) {
    final condColor = _conditionColor(alert.conditionType);
    final condText = _formatCondition(alert.conditionType);
    final threshText = _formatThreshold(alert.conditionType, alert.thresholdValue);
    final quote = _currentQuotes[alert.code];
    final distance = _distanceToThreshold(alert, quote);
    final isSelected = _selectedIds.contains(alert.id);

    return GestureDetector(
      onLongPress: () {
        if (!_selectMode) {
          setState(() {
            _selectMode = true;
            _selectedIds.add(alert.id);
          });
        }
      },
      onTap: _selectMode
          ? () => setState(() {
                if (isSelected) {
                  _selectedIds.remove(alert.id);
                  if (_selectedIds.isEmpty) _selectMode = false;
                } else {
                  _selectedIds.add(alert.id);
                }
              })
          : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: alert.enabled ? _kCard : _kCard.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: alert.enabled ? condColor : _kTextSecondary,
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：选择框 + 股票信息 + 条件标签 + 开关
              Row(
                children: [
                  if (_selectMode) ...[
                    Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? _kAccent : _kTextSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            alert.name.isNotEmpty ? alert.name : alert.code,
                            style: TextStyle(
                              color: alert.enabled ? _kTextPrimary : _kTextSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          alert.code,
                          style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // 条件标签
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: condColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$condText $threshText',
                      style: TextStyle(
                        color: condColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!_selectMode) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 28,
                      child: Switch(
                        value: alert.enabled,
                        onChanged: (_) => _toggleAlert(alert),
                        activeThumbColor: _kAccent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
              // 第二行：当前价格 + 距阈值距离
              if (quote != null && quote.price > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '现价: ',
                      style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                    ),
                    Text(
                      quote.price.toStringAsFixed(2),
                      style: TextStyle(
                        color: quote.changePct >= 0 ? _kUp : _kDown,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '  ${quote.changePct >= 0 ? "+" : ""}${quote.changePct.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: quote.changePct >= 0 ? _kUp : _kDown,
                        fontSize: 11,
                      ),
                    ),
                    if (distance.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          distance,
                          style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              // 指标类型（仅指标触发时显示）
              if (alert.conditionType == 'indicator' && alert.indicatorType.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '指标: ${_formatIndicatorType(alert.indicatorType)}',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                ),
              ],
              // 第三行：时间信息 + 操作按钮
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '创建: ${DateFormat('MM/dd HH:mm').format(alert.createdAt)}',
                      style: const TextStyle(color: _kTextSecondary, fontSize: 10),
                    ),
                  ),
                  if (alert.lastTriggeredAt != null) ...[
                    Text(
                      '上次触发: ${DateFormat('MM/dd HH:mm').format(alert.lastTriggeredAt!)}',
                      style: const TextStyle(color: _kTextSecondary, fontSize: 10),
                    ),
                  ],
                  const Spacer(),
                  if (!_selectMode) ...[
                    GestureDetector(
                      onTap: () => _editAlert(alert),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('编辑',
                            style: TextStyle(color: _kAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _deleteAlert(alert.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kUp.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('删除',
                            style: TextStyle(color: _kUp, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
