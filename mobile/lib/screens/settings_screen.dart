import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_version.dart';
import '../core/ai_config.dart';
import '../analysis/ai_layer.dart';
import 'update_log_screen.dart';
import 'indicator_reference_screen.dart';
import 'strategy_reference_screen.dart';
import '../analysis/scoring_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AIProvider? _selectedProvider;
  RiskProfile _riskProfile = RiskProfile.balanced;

  @override
  void initState() {
    super.initState();
    _loadProviderSetting();
    _loadRiskProfile();
  }

  Future<void> _loadProviderSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString('ai_provider');
    if (providerName != null) {
      setState(() {
        _selectedProvider = AIProvider.fromString(providerName);
      });
    } else {
      setState(() {
        _selectedProvider = AIProvider.zhipu;
      });
    }
  }

  Future<void> _saveProviderSetting(AIProvider provider) async {
    setState(() {
      _selectedProvider = provider;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', provider.name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换至${provider.label}，重启应用生效')),
      );
    }
  }

  Future<void> _loadRiskProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('risk_profile');
    setState(() {
      _riskProfile = v == 'conservative'
          ? RiskProfile.conservative
          : v == 'aggressive'
              ? RiskProfile.aggressive
              : RiskProfile.balanced;
    });
    ScoringConfig.riskProfile = _riskProfile;
  }

  Future<void> _saveRiskProfile(RiskProfile p) async {
    setState(() => _riskProfile = p);
    ScoringConfig.riskProfile = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('risk_profile', p.name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已更新风险偏好')),
      );
    }
  }

  String _riskLabel(RiskProfile p) {
    switch (p) {
      case RiskProfile.conservative:
        return '保守';
      case RiskProfile.balanced:
        return '均衡';
      case RiskProfile.aggressive:
        return '激进';
    }
  }

  String _riskDesc(RiskProfile p) {
    switch (p) {
      case RiskProfile.conservative:
        return '门控更严：更少但更高置信的买入';
      case RiskProfile.balanced:
        return '默认：不调整门控';
      case RiskProfile.aggressive:
        return '门控更松：更多买入信号';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('设置', style: textTheme.titleLarge),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF161B22),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          '关于',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '本应用独立运行，无需连接服务器。所有行情数据通过公开接口获取，技术分析在本地计算完成。',
                      style: textTheme.bodyMedium?.copyWith(color: Colors.grey[300]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF161B22),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.psychology, size: 20, color: Colors.purple),
                        const SizedBox(width: 8),
                        Text(
                          'AI分析引擎',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '选择AI分析使用的API服务：',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: AIProvider.values.map((provider) {
                        return RadioListTile<AIProvider>(
                          title: Text(provider.label),
                          subtitle: Text(provider.defaultModel),
                          value: provider,
                          groupValue: _selectedProvider,
                          onChanged: (value) {
                            if (value != null) {
                              _saveProviderSetting(value);
                            }
                          },
                          activeColor: Colors.blue,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '提示：切换后需要重启应用才能生效。API Key请通过环境变量配置。',
                      style: textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF161B22),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, size: 20, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text('风险偏好',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('调整推荐门控松紧（个性化，立即生效）：',
                        style: TextStyle(color: Colors.grey)),
                    Column(
                      children: RiskProfile.values.map((p) {
                        return RadioListTile<RiskProfile>(
                          title: Text(_riskLabel(p)),
                          subtitle: Text(_riskDesc(p)),
                          value: p,
                          groupValue: _riskProfile,
                          onChanged: (v) {
                            if (v != null) _saveRiskProfile(v);
                          },
                          activeColor: Colors.orange,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF161B22),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UpdateLogScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 24, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '更新日志',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF161B22),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const IndicatorReferenceScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.bar_chart_outlined, size: 24, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '指标说明',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF161B22),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const StrategyReferenceScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.smart_toy_outlined, size: 24, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '战法说明',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '版本: v${AppVersion.version}',
              style: textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}