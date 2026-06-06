import 'package:flutter/material.dart';
import '../models/stock_models.dart';

class AlertCreateDialog extends StatefulWidget {
  final AlertRule? rule;

  const AlertCreateDialog({super.key, this.rule});

  @override
  State<AlertCreateDialog> createState() => _AlertCreateDialogState();
}

class _AlertCreateDialogState extends State<AlertCreateDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _thresholdController = TextEditingController();

  String _alertType = 'price_up';
  String _indicatorType = 'rsi';

  bool get isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    if (widget.rule != null) {
      _codeController.text = widget.rule!.code;
      _nameController.text = widget.rule!.name;
      _thresholdController.text = widget.rule!.threshold.toString();
      _alertType = widget.rule!.alertType;
      _indicatorType = widget.rule!.indicatorType.isNotEmpty
          ? widget.rule!.indicatorType
          : 'rsi';
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _save() {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入股票代码'), backgroundColor: Colors.red),
      );
      return;
    }

    final rule = AlertRule(
      id: widget.rule?.id ?? DateTime.now().millisecondsSinceEpoch,
      code: code,
      name: name,
      conditionType: _alertType,
      thresholdValue: threshold,
      alertType: _alertType,
      threshold: threshold,
      indicatorType: _alertType == 'indicator' ? _indicatorType : '',
      enabled: widget.rule?.enabled ?? true,
    );

    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16213e),
      title: Text(
        isEditing ? '编辑提醒' : '新建提醒',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 股票代码
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '股票代码',
                labelStyle: TextStyle(color: Colors.white38),
                hintText: '如: 000001',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 12),

            // 股票名称
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '股票名称 (可选)',
                labelStyle: TextStyle(color: Colors.white38),
                hintText: '如: 平安银行',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 16),

            // 提醒类型
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '提醒类型',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _alertType,
              dropdownColor: const Color(0xFF0f3460),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'price_up', child: Text('价格上涨至')),
                DropdownMenuItem(value: 'price_down', child: Text('价格下跌至')),
                DropdownMenuItem(value: 'pct_up', child: Text('涨幅超过')),
                DropdownMenuItem(value: 'pct_down', child: Text('跌幅超过')),
                DropdownMenuItem(value: 'indicator', child: Text('指标触发')),
              ],
              onChanged: (value) {
                setState(() {
                  _alertType = value ?? 'price_up';
                });
              },
            ),
            const SizedBox(height: 12),

            // 阈值
            TextField(
              controller: _thresholdController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _thresholdLabel(),
                labelStyle: const TextStyle(color: Colors.white38),
                hintText: _thresholdHint(),
                hintStyle: const TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 12),

            // 指标类型 (仅当类型为 indicator 时显示)
            if (_alertType == 'indicator') ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '指标类型',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _indicatorType,
                dropdownColor: const Color(0xFF0f3460),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'rsi', child: Text('RSI')),
                  DropdownMenuItem(value: 'macd', child: Text('MACD')),
                  DropdownMenuItem(value: 'kdj', child: Text('KDJ')),
                  DropdownMenuItem(value: 'ma', child: Text('均线')),
                  DropdownMenuItem(value: 'volume', child: Text('成交量')),
                ],
                onChanged: (value) {
                  setState(() {
                    _indicatorType = value ?? 'rsi';
                  });
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFef5350),
          ),
          child: Text(isEditing ? '保存' : '创建'),
        ),
      ],
    );
  }

  String _thresholdLabel() {
    switch (_alertType) {
      case 'price_up':
      case 'price_down':
        return '目标价格';
      case 'pct_up':
      case 'pct_down':
        return '涨跌幅(%)';
      case 'indicator':
        return '触发值';
      default:
        return '阈值';
    }
  }

  String _thresholdHint() {
    switch (_alertType) {
      case 'price_up':
      case 'price_down':
        return '如: 10.50';
      case 'pct_up':
      case 'pct_down':
        return '如: 5.0';
      case 'indicator':
        return '如: 70';
      default:
        return '输入阈值';
    }
  }
}