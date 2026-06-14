import 'package:flutter/material.dart';

/// 统一的股票卡片组件，用于自选列表和发现页面
class StockCard extends StatelessWidget {
  final String name;
  final String code;
  final double price;
  final double changePct;
  final double? pe;
  final double? pb;
  final int? score;
  final String? recommendation;
  final String? riskLevel;
  final List<Widget>? tags;
  final List<Widget>? actions;
  final int? rank;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const StockCard({
    super.key,
    required this.name,
    required this.code,
    required this.price,
    required this.changePct,
    this.pe,
    this.pb,
    this.score,
    this.recommendation,
    this.riskLevel,
    this.tags,
    this.actions,
    this.rank,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  Color get _changeColor =>
      changePct > 0 ? const Color(0xFFE74C3C) :
      changePct < 0 ? const Color(0xFF2ECC71) :
      const Color(0xFF8B949E);

  Color get _recColor {
    if (recommendation == null) return const Color(0xFF8B949E);
    if (recommendation!.contains('强烈买入') || recommendation!.contains('买入')) {
      return const Color(0xFFE74C3C);
    }
    if (recommendation!.contains('卖出')) {
      return const Color(0xFF2ECC71);
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: recommendation != null
                ? _recColor.withOpacity(0.3)
                : const Color(0xFF30363D),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：排名 + 名称 + 推荐标签 + 尾部组件
            Row(
              children: [
                if (rank != null) ...[
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rank! <= 3
                          ? const Color(0xFF58A6FF).withOpacity(0.2)
                          : const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: rank! <= 3
                            ? const Color(0xFF58A6FF)
                            : const Color(0xFF8B949E),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFFF0F6FC),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (recommendation != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _recColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      recommendation!,
                      style: TextStyle(
                        color: _recColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            // 第二行：代码
            Text(
              code,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
            const SizedBox(height: 8),
            // 第三行：价格 + 涨跌幅 + PE/PB + 评分
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price > 0 ? '¥${price.toStringAsFixed(2)}' : '--',
                  style: TextStyle(
                    color: _changeColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _changeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: _changeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (pe != null && pe! > 0)
                  Text(
                    'PE:${pe!.toStringAsFixed(1)}',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                if (pe != null && pe! > 0 && pb != null && pb! > 0)
                  const SizedBox(width: 8),
                if (pb != null && pb! > 0)
                  Text(
                    'PB:${pb!.toStringAsFixed(1)}',
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                if (score != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF58A6FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$score分',
                      style: const TextStyle(
                        color: Color(0xFF58A6FF),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // 第四行：信号标签（可选）
            if (tags != null && tags!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: tags!),
            ],
            // 第五行：操作按钮（可选）
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: actions!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 信号标签组件
class SignalTag extends StatelessWidget {
  final String text;
  final Color color;

  const SignalTag({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
