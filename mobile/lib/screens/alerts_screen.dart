import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../widgets/alert_dialog.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => AlertsScreenState();
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
        return '价格高于';
      case 'price_below':
        return '价格低于';
      case 'change_above':
        return '涨幅高于';
      case 'change_below':
        return '跌幅高于';
      default:
        return conditionType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final dangerColor = isDark ? const Color(0xFFef5350) : const Color(0xFFc62828);

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _alerts.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Text('暂无提醒规则', style: textTheme.titleMedium),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _createAlert,
                        child: const Text('添加提醒'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _alerts.length,
                itemBuilder: (context, index) {
                  final alert = _alerts[index];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
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
                                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatCondition(alert.conditionType)} ${alert.thresholdValue}',
                                      style: textTheme.bodyMedium?.copyWith(color: isDark ? Colors.grey[500] : Colors.grey[600]),
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
                },
              );
  }
}
