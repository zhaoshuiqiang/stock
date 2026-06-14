import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../core/app_version.dart';
import '../widgets/alert_dialog.dart';
import 'update_log_screen.dart';

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

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('关于', style: TextStyle(color: _kTextPrimary)),
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('股票分析助手',
              style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('版本号: v${AppVersion.version}',
              style: const TextStyle(color: _kTextSecondary)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const UpdateLogScreen()),
              );
            },
            child: const Text('查看更新日志',
                style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定', style: TextStyle(color: _kAccent)),
        ),
      ],
    );
  }
}

class AlertsScreenState extends State<AlertsScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<AlertRule> _alerts = [];
  bool _isLoading = true;
  String _filterType = '全部'; // 全部 / 已启用 / 已禁用

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final alerts = await _dbService.getAlerts();
      setState(() {
        _alerts = alerts;
      });
    } catch (e) {
      // ignore
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<AlertRule> get _filteredAlerts {
    switch (_filterType) {
      case '已启用':
        return _alerts.where((a) => a.enabled).toList();
      case '已禁用':
        return _alerts.where((a) => !a.enabled).toList();
      default:
        return _alerts;
    }
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
            child:
                const Text('取消', style: TextStyle(color: _kTextSecondary)),
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

  void _batchToggleEnabled(bool enable) async {
    final targets =
        _alerts.where((a) => a.enabled != enable).toList();
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAlerts;
    final enabledCount = _alerts.where((a) => a.enabled).length;

    return Container(
      color: _kBg,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : Column(
              children: [
                // 顶部操作栏
                _buildHeader(enabledCount),
                // 筛选条
                _buildFilterBar(),
                // 列表
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              _buildAlertCard(filtered[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(int enabledCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '共${_alerts.length}条 · $enabledCount条启用',
            style: const TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
          const Spacer(),
          // 全部启用/禁用
          if (_alerts.isNotEmpty) ...[
            TextButton.icon(
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('全部启用', style: TextStyle(fontSize: 12)),
              onPressed: () => _batchToggleEnabled(true),
              style: TextButton.styleFrom(
                foregroundColor: _kAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.pause, size: 16),
              label: const Text('全部禁用', style: TextStyle(fontSize: 12)),
              onPressed: () => _batchToggleEnabled(false),
              style: TextButton.styleFrom(
                foregroundColor: _kTextSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
          const SizedBox(width: 4),
          // 添加按钮
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加预警'),
            onPressed: _createAlert,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = ['全部', '已启用', '已禁用'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = _filterType == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filterType = f),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? _kAccent.withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? _kAccent : _kBorder,
                  ),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    color: isSelected ? _kAccent : _kTextSecondary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

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
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _createAlert,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('添加预警'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(AlertRule alert) {
    final condColor = _conditionColor(alert.conditionType);
    final condText = _formatCondition(alert.conditionType);
    final threshText = _formatThreshold(alert.conditionType, alert.thresholdValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.enabled ? condColor.withOpacity(0.3) : _kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：股票名称 + 条件标签 + 开关
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      alert.name.isNotEmpty ? alert.name : alert.code,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      alert.code,
                      style: const TextStyle(
                          color: _kTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // 条件标签
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: condColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$condText $threshText',
                  style: TextStyle(
                    color: condColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 开关
              SizedBox(
                height: 28,
                child: Switch(
                  value: alert.enabled,
                  onChanged: (_) => _toggleAlert(alert),
                  activeColor: _kAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          // 指标类型（仅指标触发时显示）
          if (alert.conditionType == 'indicator' &&
              alert.indicatorType.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '指标: ${alert.indicatorType.toUpperCase()}',
              style:
                  const TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('编辑', style: TextStyle(fontSize: 12)),
                onPressed: () => _editAlert(alert),
                style: TextButton.styleFrom(
                  foregroundColor: _kAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除', style: TextStyle(fontSize: 12)),
                onPressed: () => _deleteAlert(alert.id),
                style: TextButton.styleFrom(
                  foregroundColor: _kUp,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => const _AboutDialog(),
    );
  }
}
