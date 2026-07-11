import 'package:flutter/material.dart';
import '../models/stock_models.dart';

/// 快速预设
class _AlertPreset {
  final String label;
  final String conditionType;
  final double threshold;
  final String indicatorType;
  final IconData icon;

  const _AlertPreset({
    required this.label,
    required this.conditionType,
    required this.threshold,
    this.indicatorType = '',
    this.icon = Icons.flash_on,
  });
}

const _kPresets = [
  _AlertPreset(label: '接近涨停', conditionType: 'change_above', threshold: 9.5, icon: Icons.trending_up),
  _AlertPreset(label: '接近跌停', conditionType: 'change_below', threshold: 9.5, icon: Icons.trending_down),
  _AlertPreset(label: '涨超5%', conditionType: 'change_above', threshold: 5.0, icon: Icons.arrow_upward),
  _AlertPreset(label: '跌超5%', conditionType: 'change_below', threshold: 5.0, icon: Icons.arrow_downward),
  _AlertPreset(label: '放量2倍', conditionType: 'indicator', threshold: 2.0, indicatorType: 'volume_ratio', icon: Icons.bar_chart),
  _AlertPreset(label: 'RSI超买', conditionType: 'indicator', threshold: 70.0, indicatorType: 'rsi', icon: Icons.show_chart),
  _AlertPreset(label: 'RSI超卖', conditionType: 'indicator', threshold: 30.0, indicatorType: 'rsi', icon: Icons.show_chart),
  _AlertPreset(label: '换手率>5%', conditionType: 'indicator', threshold: 5.0, indicatorType: 'turnover', icon: Icons.swap_horiz),
  _AlertPreset(label: '换手率>10%', conditionType: 'indicator', threshold: 10.0, indicatorType: 'turnover', icon: Icons.swap_horiz),
  _AlertPreset(label: '振幅>5%', conditionType: 'indicator', threshold: 5.0, indicatorType: 'amplitude', icon: Icons.waves),
  _AlertPreset(label: '振幅>10%', conditionType: 'indicator', threshold: 10.0, indicatorType: 'amplitude', icon: Icons.waves),
];

class AlertCreateDialog extends StatefulWidget {
  final AlertRule? rule;
  final String? initialCode;
  final String? initialName;

  const AlertCreateDialog({super.key, this.rule, this.initialCode, this.initialName});

  @override
  State<AlertCreateDialog> createState() => _AlertCreateDialogState();
}

class _AlertCreateDialogState extends State<AlertCreateDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _thresholdController = TextEditingController();

  String _alertType = 'price_above';
  String _indicatorType = 'rsi';

  bool get isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    if (widget.rule != null) {
      _codeController.text = widget.rule!.code;
      _nameController.text = widget.rule!.name;
      _thresholdController.text =
          (widget.rule!.threshold ?? widget.rule!.thresholdValue).toString();
      _alertType = widget.rule!.alertType;
      _indicatorType = widget.rule!.indicatorType.isNotEmpty
          ? widget.rule!.indicatorType
          : 'rsi';
    } else {
      if (widget.initialCode != null) _codeController.text = widget.initialCode!;
      if (widget.initialName != null) _nameController.text = widget.initialName!;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _applyPreset(_AlertPreset preset) {
    setState(() {
      _alertType = preset.conditionType;
      _thresholdController.text = preset.threshold.toString();
      if (preset.indicatorType.isNotEmpty) {
        _indicatorType = preset.indicatorType;
      }
    });
  }

  bool _isPresetActive(_AlertPreset preset) {
    if (_alertType != preset.conditionType) return false;
    final currentText = _thresholdController.text.trim();
    if (currentText != preset.threshold.toString()) return false;
    if (preset.indicatorType.isNotEmpty && _indicatorType != preset.indicatorType) {
      return false;
    }
    return true;
  }

  void _save() {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请输入股票代码'), backgroundColor: Colors.red),
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
      backgroundColor: const Color(0xFF161B22),
      title: Row(
        children: [
          Text(
            isEditing ? '编辑预警' : '新建预警',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const Spacer(),
          if (!isEditing)
            Text(
              '快速预设',
              style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 12,
                  fontWeight: FontWeight.normal),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 快速预设 Chips（仅新建时显示）
            if (!isEditing) ...[
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kPresets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final p = _kPresets[i];
                    return GestureDetector(
                      onTap: () => _applyPreset(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF30363D).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isPresetActive(p)
                                ? const Color(0xFF58A6FF)
                                : const Color(0xFF30363D),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(p.icon,
                                size: 14, color: const Color(0xFF58A6FF)),
                            const SizedBox(width: 4),
                            Text(
                              p.label,
                              style: const TextStyle(
                                color: Color(0xFFF0F6FC),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF30363D)),
              const SizedBox(height: 12),
            ],

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
              dropdownColor: const Color(0xFF161B22),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'price_above', child: Text('价格高于')),
                DropdownMenuItem(
                    value: 'price_below', child: Text('价格低于')),
                DropdownMenuItem(
                    value: 'change_above', child: Text('涨幅超过')),
                DropdownMenuItem(
                    value: 'change_below', child: Text('跌幅超过')),
                DropdownMenuItem(value: 'indicator', child: Text('指标触发')),
              ],
              onChanged: (value) {
                setState(() {
                  _alertType = value ?? 'price_above';
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
                dropdownColor: const Color(0xFF161B22),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'rsi', child: Text('RSI (>N / <N)')),
                  DropdownMenuItem(
                      value: 'macd', child: Text('MACD (DIF > N)')),
                  DropdownMenuItem(value: 'kdj', child: Text('KDJ (K > N)')),
                  DropdownMenuItem(
                      value: 'ma_cross', child: Text('均线金叉/死叉')),
                  DropdownMenuItem(value: 'volume', child: Text('成交量 (万手)')),
                  DropdownMenuItem(
                      value: 'volume_ratio', child: Text('量比 (>N倍)')),
                  DropdownMenuItem(
                      value: 'turnover', child: Text('换手率 (>N%)')),
                  DropdownMenuItem(
                      value: 'amplitude', child: Text('振幅 (>N%)')),
                  DropdownMenuItem(value: 'cci', child: Text('CCI (>N / <N)')),
                  DropdownMenuItem(value: 'wr', child: Text('WR (>N / <N)')),
                  DropdownMenuItem(
                      value: 'boll', child: Text('布林带 (突破)')),
                  DropdownMenuItem(value: 'atr', child: Text('ATR (>N%)')),
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
      case 'price_above':
      case 'price_below':
        return '目标价格';
      case 'change_above':
      case 'change_below':
        return '涨跌幅(%)';
      case 'indicator':
        return _indicatorThresholdLabel();
      default:
        return '阈值';
    }
  }

  String _indicatorThresholdLabel() {
    switch (_indicatorType) {
      case 'rsi':
      case 'kdj':
      case 'wr':
      case 'cci':
        return '阈值 (0-100)';
      case 'macd':
        return 'DIF 值';
      case 'volume':
        return '成交量 (万手)';
      case 'volume_ratio':
        return '量比倍数';
      case 'turnover':
      case 'amplitude':
      case 'atr':
        return '百分比 (%)';
      case 'ma_cross':
        return '周期 (5=MA5↔10, 10=MA10↔20, 20=MA20↔60, 60=收盘价↔MA60)';
      case 'boll':
        return '方向 (上轨1/下轨0)';
      default:
        return '触发值';
    }
  }

  String _thresholdHint() {
    switch (_alertType) {
      case 'price_above':
      case 'price_below':
        return '如: 10.50';
      case 'change_above':
      case 'change_below':
        return '如: 5.0';
      case 'indicator':
        return _indicatorThresholdHint();
      default:
        return '输入阈值';
    }
  }

  String _indicatorThresholdHint() {
    switch (_indicatorType) {
      case 'rsi':
        return '超买70, 超卖30';
      case 'macd':
        return 'DIF值, 如: 0.5';
      case 'kdj':
        return 'K值, 超买80, 超卖20';
      case 'volume':
        return '成交量万手, 如: 100';
      case 'volume_ratio':
        return '量比, 如: 2.0';
      case 'turnover':
        return '换手率%, 如: 5';
      case 'amplitude':
        return '振幅%, 如: 5';
      case 'cci':
        return '超买100, 超卖-100';
      case 'wr':
        return '超买20, 超卖80';
      case 'atr':
        return 'ATR%, 如: 5';
      case 'ma_cross':
        return '均线周期: 5/10/20/60';
      case 'boll':
        return '上轨=1, 下轨=0';
      default:
        return '输入阈值';
    }
  }
}
