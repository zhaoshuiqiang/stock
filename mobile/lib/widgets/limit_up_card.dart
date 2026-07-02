import 'package:flutter/material.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';

class LimitUpCard extends StatelessWidget {
  final LimitUpAnalysis analysis;
  final bool isWatched;
  final VoidCallback? onTap;
  final VoidCallback? onWatchlistToggle;

  const LimitUpCard({
    super.key,
    required this.analysis,
    required this.isWatched,
    this.onTap,
    this.onWatchlistToggle,
  });

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: const Color(0xFF161B22),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：连板徽章 + 名称 + 板型/时段徽章 + 星标
              Row(children: [
                _buildConsecutiveBadge(a.consecutiveDays),
                const SizedBox(width: 8),
                Expanded(child: Text(a.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (a.boardType.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildTypeBadge(a.boardType, _boardTypeColor(a.boardType)),
                ],
                if (a.timeGrade.isNotEmpty && a.timeGrade != '未知') ...[
                  const SizedBox(width: 4),
                  _buildTypeBadge(a.timeGrade, _timeGradeColor(a.timeGrade)),
                ],
                IconButton(
                  icon: Icon(isWatched ? Icons.star : Icons.star_border,
                      size: 18, color: isWatched ? const Color(0xFFFFB000) : Colors.grey),
                  onPressed: onWatchlistToggle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ]),
              const SizedBox(height: 6),
              // 第二行：价格 + 涨幅 + 封单 + 封成比
              Text(
                '¥${a.price.toStringAsFixed(2)}  '
                '${a.changePct >= 0 ? '+' : ''}${a.changePct.toStringAsFixed(2)}%   '
                '封单 ${_formatAmount(a.sealAmount)}   '
                '封成比 ${a.sealRate.toStringAsFixed(1)}x',
                style: TextStyle(fontSize: 12, color: a.changePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a)),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // 第三行：次日溢价 + 质量 + 板块
              Text(
                '次日溢价 ${(a.premiumProb * 100).toStringAsFixed(0)}%  ·  '
                '质量 ${a.qualityScore.toStringAsFixed(1)}分'
                '${a.sector != null && a.sector!.isNotEmpty ? '  ·  ${a.sector}' : ''}',
                style: TextStyle(fontSize: 11,
                    color: a.premiumProb > 0.7 ? const Color(0xFFFFB000) : const Color(0xFF8B949E)),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsecutiveBadge(int days) {
    final color = days >= 4 ? const Color(0xFF9D2933) :
                  days == 3 ? const Color(0xFFE74C3C) :
                  days == 2 ? const Color(0xFFE67E22) :
                  const Color(0xFF58A6FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text('$days连板',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          maxLines: 1),
    );
  }

  Widget _buildTypeBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 9, color: color),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Color _boardTypeColor(String type) {
    if (type.contains('一字')) return const Color(0xFFef5350);
    if (type.contains('T字')) return const Color(0xFFE74C3C);
    if (type.contains('换手')) return const Color(0xFFE67E22);
    return const Color(0xFF8B5A5A);
  }

  Color _timeGradeColor(String grade) {
    if (grade.contains('竞价')) return const Color(0xFFFFB000);
    if (grade.contains('早盘') || grade.contains('秒板')) return const Color(0xFFef5350);
    if (grade.contains('上午')) return const Color(0xFFE67E22);
    return const Color(0xFF8B949E);
  }

  String _formatAmount(double wan) {
    if (wan >= 10000) return '${(wan / 10000).toStringAsFixed(1)}亿';
    return '${wan.toStringAsFixed(0)}万';
  }
}
