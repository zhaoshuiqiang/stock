import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_version.dart';
import '../core/ai_config.dart';
import '../analysis/ai_layer.dart';
import 'update_log_screen.dart';
import 'indicator_reference_screen.dart';
import 'strategy_reference_screen.dart';
import '../analysis/scoring_config.dart';
import '../analysis/directional_weight_optimizer.dart';
import '../core/scoring_prefs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AIProvider? _selectedProvider;
  RiskProfile _riskProfile = RiskProfile.balanced;
  bool _recalDir = false;
  bool _dynWeights = false;
  bool _calibThresh = false;
  bool _showCalibProb = false;
  bool _isolateScan = false;
  bool _deemphTrend = false;
  bool _deemphBreakout = false;
  bool _reboundGuard = false;
  bool _shortTermReprofile = false;
  bool _shortTermTrendDiscount = false;
  bool _calibColdStart = false;

  @override
  void initState() {
    super.initState();
    _loadProviderSetting();
    _loadRiskProfile();
    _loadScoringFlags();
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

  Future<void> _loadScoringFlags() async {
    final prefs = await SharedPreferences.getInstance();
    applyScoringPrefs(prefs);
    if (!mounted) return;
    setState(() {
      _recalDir = ScoringConfig.useRecalibratedDirection;
      _dynWeights = ScoringConfig.useDynamicDirectionWeights;
      _calibThresh = ScoringConfig.useCalibratedThresholds;
      _showCalibProb = ScoringConfig.showCalibratedProbability;
      _isolateScan = ScoringConfig.useIsolateScan;
      _deemphTrend = ScoringConfig.deemphasizeTrendStrength;
      _deemphBreakout = ScoringConfig.deemphasizeBreakoutChase;
      _reboundGuard = ScoringConfig.useReboundGuard;
      _shortTermReprofile = ScoringConfig.useShortTermRealtimeReprofile;
      _shortTermTrendDiscount = ScoringConfig.useShortTermTrendDiscount;
      _calibColdStart = ScoringConfig.useCalibrationColdStart;
    });
  }

  Future<void> _setScoringFlag(
    String key,
    bool value,
    void Function(bool) apply, {
    bool reloadWeights = false,
    String hint = '下次扫描/进入详情后生效',
  }) async {
    apply(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (reloadWeights) {
      await DirectionalWeightOptimizer.loadAndApply();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? '已开启 · $hint' : '已关闭 · $hint')),
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

  Widget _buildScoringEngineCard(TextTheme textTheme) {
    Widget tile(bool value, String title, String subtitle, String key,
        void Function(bool) apply,
        {bool reloadWeights = false, String hint = '下次扫描/进入详情后生效'}) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: Colors.tealAccent,
        value: value,
        onChanged: (v) => _setScoringFlag(key, v, apply,
            reloadWeights: reloadWeights, hint: hint),
        title: Text(title),
        subtitle: Text(subtitle,
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      );
    }

    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.science_outlined, size: 20, color: Colors.tealAccent),
              const SizedBox(width: 8),
              Text('评分引擎（实验）',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            const Text('数据驱动的评分校准开关，默认关闭，可随时一键回退。',
                style: TextStyle(color: Colors.grey)),
            tile(_recalDir, '方向引擎循证校准',
                '降低追涨/放量奖励，加入低波/反转因子（提升评分准确性）',
                kPrefUseRecalibratedDirection,
                (x) { setState(() => _recalDir = x); ScoringConfig.useRecalibratedDirection = x; }),
            tile(_dynWeights, '动态方向权重',
                '依据历史决策结局自动校准各维度权重（需积累样本）',
                kPrefUseDynamicDirectionWeights,
                (x) { setState(() => _dynWeights = x); ScoringConfig.useDynamicDirectionWeights = x; },
                reloadWeights: true, hint: '已重载动态权重'),
            tile(_calibThresh, '校准推荐阈值',
                '用回测校准的分档/门控阈值替代默认值',
                kPrefUseCalibratedThresholds,
                (x) { setState(() => _calibThresh = x); ScoringConfig.useCalibratedThresholds = x; }),
            tile(_showCalibProb, '展示校准命中概率',
                '在 1-10 分旁显示校准后的真实命中概率',
                kPrefShowCalibratedProbability,
                (x) { setState(() => _showCalibProb = x); ScoringConfig.showCalibratedProbability = x; }),
            tile(_isolateScan, '后台 isolate 扫描',
                '批量扫描迁入后台线程（降低卡顿，需真机验证）',
                kPrefUseIsolateScan,
                (x) { setState(() => _isolateScan = x); ScoringConfig.useIsolateScan = x; }),
            tile(_deemphTrend, '趋势强度信号降权 (P1)',
                'ADX"趋势强度强劲"多空双向降权——反转市里该信号常做反（留档跨日验证后再开）',
                kPrefDeemphasizeTrendStrength,
                (x) { setState(() => _deemphTrend = x); ScoringConfig.deemphasizeTrendStrength = x; }),
            tile(_deemphBreakout, '追突破降权 (P2)',
                '"趋势突破上轨"买入信号降权（留档次日 0% 胜率）',
                kPrefDeemphasizeBreakoutChase,
                (x) { setState(() => _deemphBreakout = x); ScoringConfig.deemphasizeBreakoutChase = x; }),
            tile(_reboundGuard, '超跌反弹护栏 (P3)',
                '暴跌超卖股的偏空评分上拉向中性（追高惩罚的镜像）',
                kPrefUseReboundGuard,
                (x) { setState(() => _reboundGuard = x); ScoringConfig.useReboundGuard = x; }),
            tile(_shortTermReprofile, '实时评分倒U重定峰 (v4.10)',
                '温和回调/持平区最优，3-5%追高区改为惩罚（3281行留档实证，跨日验证后再开）',
                kPrefUseShortTermRealtimeReprofile,
                (x) { setState(() => _shortTermReprofile = x); ScoringConfig.useShortTermRealtimeReprofile = x; }),
            tile(_shortTermTrendDiscount, '趋势信号短周期降权 (B#1)',
                'MA多头排列/趋势类共振短周期降权（留档MA多头前向-2.0%），跨日验证后再开',
                kPrefUseShortTermTrendDiscount,
                (x) { setState(() => _shortTermTrendDiscount = x); ScoringConfig.useShortTermTrendDiscount = x; }),
            tile(_calibColdStart, '校准小样本参考 (v4.14)',
                '样本不足时显示放宽档(方向级)并标注“小样本参考”，而非“暂无数据”',
                kPrefUseCalibrationColdStart,
                (x) { setState(() => _calibColdStart = x); ScoringConfig.useCalibrationColdStart = x; }),
            const SizedBox(height: 4),
            Text('提示：多数开关在下次扫描/进入详情页后生效。',
                style: textTheme.bodySmall?.copyWith(color: Colors.grey[500])),
          ],
        ),
      ),
    );
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
        child: SingleChildScrollView(
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
            _buildScoringEngineCard(textTheme),
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
      ),
    );
  }
}