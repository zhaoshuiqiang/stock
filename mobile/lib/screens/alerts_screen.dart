import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/alert_dialog.dart';
import 'update_log_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => AlertsScreenState();
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('关于'),
      backgroundColor: const Color(0xFF16213e),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('股票分析助手', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          Text('版本号: v2.1.0', style: textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UpdateLogScreen()),
              );
            },
            child: Text('查看更新日志', style: textTheme.bodyMedium?.copyWith(color: Colors.blue)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class AlertsScreenState extends State<AlertsScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<AlertRule> _alerts = [];
  bool _isLoading = true;

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
      print('Load alerts failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _createAlert() {
    showDialog(
      context: context,
      builder: (_) => AlertCreateDialog(
        rule: null,
      ),
    ).then((result) {
      if (result != null) {
        _dbService.addAlert(result as AlertRule).then((_) => _loadAlerts());
      }
    });
  }

  void _editAlert(AlertRule alert) {
    showDialog(
      context: context,
      builder: (_) => AlertCreateDialog(
        rule: alert,
      ),
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
    await _dbService.deleteAlert(id);
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
    if (conditionType == 'change_above' || conditionType == 'change_below' ||
        conditionType == 'rise' || conditionType == 'fall') {
      return '${value.toStringAsFixed(2)}%';
    }
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final dangerColor = isDark ? const Color(0xFFef5350) : const Color(0xFFc62828);

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  onPressed: _createAlert,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0f3460),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('+ 添加预警', style: TextStyle(fontSize: 16)),
                ),
              ),
              if (_alerts.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('暂无提醒规则', style: textTheme.titleMedium),
                  ),
                )
              else
                ..._alerts.map((alert) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFF16213e),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${alert.name} (${alert.code})',
                                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatCondition(alert.conditionType)} ${_formatThreshold(alert.conditionType, alert.thresholdValue)}',
                                      style: textTheme.bodyMedium?.copyWith(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: alert.enabled,
                                onChanged: (value) => _toggleAlert(alert),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _editAlert(alert),
                                child: Text('编辑', style: textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
                              ),
                              TextButton(
                                onPressed: () => _deleteAlert(alert.id),
                                child: Text('删除', style: textTheme.bodyMedium?.copyWith(color: dangerColor)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => const _AboutDialog(),
    );
  }
}
