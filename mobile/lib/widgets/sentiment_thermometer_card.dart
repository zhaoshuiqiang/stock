import 'package:flutter/material.dart';
import 'package:stock_analyzer/models/stock_models.dart';

class SentimentThermometerCard extends StatelessWidget {
  final SentimentResult? sentiment;
  final VoidCallback? onRefresh;
  final bool isLoading;

  const SentimentThermometerCard({
    super.key,
    required this.sentiment,
    this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = sentiment;
    if (s == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('🌡️ 情绪温度计',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              const Spacer(),
              if (isLoading)
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
              else if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                  onPressed: onRefresh,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ]),
            const SizedBox(height: 10),
            const Text('暂无情绪数据，点击刷新扫描打板池',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _phaseGradient(s.phase),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🌡️ 情绪温度计',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            if (isLoading)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
            else if (onRefresh != null)
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                onPressed: onRefresh,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${s.temperature.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_phaseLabel(s.phase),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 2),
              Text('仓位 ${_phasePositionAdvice(s.phase)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ]),
          const SizedBox(height: 10),
          _buildThermometerBar(s.temperature),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _buildMiniMetric('炸板', '${(s.zhabanRate * 100).toStringAsFixed(0)}%'),
            _buildMiniMetric('晋级', '${(s.continuationRate * 100).toStringAsFixed(0)}%'),
            _buildMiniMetric('封板', '${(s.sealSuccessRate * 100).toStringAsFixed(0)}%'),
            _buildMiniMetric('赚钱', '${s.moneyMakingEffect.toStringAsFixed(1)}%'),
            _buildMiniMetric('高度', '${s.continuationHeight}板'),
          ]),
          if (s.signals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.signals.take(2).join(' · '),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          // v3.10: 显示数据更新时间戳
          const SizedBox(height: 6),
          Text(
            '更新于 ${_formatTime(s.timestamp)}',
            style: const TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  /// 格式化时间戳为短时间显示
  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<Color> _phaseGradient(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => const [Color(0xFF1A5276), Color(0xFF2E86C1)],
    EmotionPhase.climax    => const [Color(0xFF7B241C), Color(0xFFE74C3C)],
    EmotionPhase.retreat   => const [Color(0xFF7D6608), Color(0xFFF39C12)],
    EmotionPhase.freezing  => const [Color(0xFF1B2631), Color(0xFF566573)],
  };

  String _phaseLabel(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => '启动阶段',
    EmotionPhase.climax    => '高潮阶段',
    EmotionPhase.retreat   => '退潮阶段',
    EmotionPhase.freezing  => '冰点阶段',
  };

  String _phasePositionAdvice(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => '5-6 成',
    EmotionPhase.climax    => '7-8 成',
    EmotionPhase.retreat   => '3-4 成',
    EmotionPhase.freezing  => '1-2 成',
  };

  Widget _buildThermometerBar(double temp) {
    return LayoutBuilder(builder: (_, c) {
      final segWidth = c.maxWidth / 6;
      final pos = (temp / 100 * c.maxWidth).clamp(0.0, c.maxWidth - 8);
      return Stack(children: [
        Row(children: [
          for (final col in const [Color(0xFF566573), Color(0xFF566573),
                                   Color(0xFF2E86C1), Color(0xFF2E86C1),
                                   Color(0xFFE74C3C), Color(0xFFE74C3C)])
            Container(width: segWidth, height: 6, color: col),
        ]),
        Positioned(left: pos, top: -2,
            child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 14)),
      ]);
    });
  }

  Widget _buildMiniMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label $value',
          style: const TextStyle(fontSize: 10, color: Colors.white),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
