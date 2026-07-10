import 'dart:math';
import 'package:flutter/material.dart';

/// 7维评分雷达图
///
/// 以技术/资金/实时/共振/情绪/基本面/结构 7个维度绘制雷达图，
/// 各维度分值 0-10。中心展示综合评分。
class ScoreRadarChart extends StatelessWidget {
  final Map<String, double> scores;
  final int? totalScore;
  final double size;

  const ScoreRadarChart({
    super.key,
    required this.scores,
    this.totalScore,
    this.size = 220,
  });

  /// 7维标准顺序（与综合评分权重顺序一致）
  static const kDimensions = [
    '技术面', '资金面', '实时行情', '共振', '情绪', '基本面', '结构',
  ];

  /// 每个维度对应的主题色
  static const kDimensionColors = [
    Color(0xFF26a69a), // 技术面 - 青绿
    Color(0xFF4caf50), // 资金面 - 绿
    Color(0xFFff9800), // 实时行情 - 橙
    Color(0xFF9c27b0), // 共振 - 紫
    Color(0xFF03a9f4), // 情绪 - 蓝
    Color(0xFFe91e63), // 基本面 - 粉红
    Color(0xFF607d8b), // 结构 - 蓝灰
  ];

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RadarPainter(
        scores: scores,
        totalScore: totalScore,
        dimensions: kDimensions,
        dimensionColors: kDimensionColors,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Map<String, double> scores;
  final int? totalScore;
  final List<String> dimensions;
  final List<Color> dimensionColors;

  _RadarPainter({
    required this.scores,
    required this.dimensions,
    required this.dimensionColors,
    this.totalScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 留出标签空间
    final radius = min(size.width, size.height) / 2 - 36;
    if (radius <= 0) return;

    final n = dimensions.length;
    // 第一个维度在正上方（-90°），顺时针分布
    double angleFor(int i) => -pi / 2 + 2 * pi * i / n;

    // ─── 1. 绘制背景网格（5层同心多边形） ──────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFF30363D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int level = 2; level <= 10; level += 2) {
      final r = radius * level / 10;
      final path = Path();
      for (int i = 0; i < n; i++) {
        final angle = angleFor(i);
        final point = Offset(
          center.dx + r * cos(angle),
          center.dy + r * sin(angle),
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // ─── 2. 绘制轴线 ──────────────────────────────────────────
    final axisPaint = Paint()
      ..color = const Color(0xFF30363D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 0; i < n; i++) {
      final angle = angleFor(i);
      final endPoint = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawLine(center, endPoint, axisPaint);
    }

    // ─── 3. 绘制数据多边形 ────────────────────────────────────
    final dataPath = Path();
    final dataPoints = <Offset>[];
    for (int i = 0; i < n; i++) {
      final dim = dimensions[i];
      final score = (scores[dim] ?? 5.0).clamp(0.0, 10.0);
      final r = radius * score / 10;
      final angle = angleFor(i);
      final point = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );
      dataPoints.add(point);
      if (i == 0) {
        dataPath.moveTo(point.dx, point.dy);
      } else {
        dataPath.lineTo(point.dx, point.dy);
      }
    }
    dataPath.close();

    // 填充
    final fillPaint = Paint()
      ..color = const Color(0xFF58A6FF).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(dataPath, fillPaint);

    // 边框
    final strokePaint = Paint()
      ..color = const Color(0xFF58A6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(dataPath, strokePaint);

    // ─── 4. 绘制数据点 ────────────────────────────────────────
    final pointPaint = Paint()
      ..color = const Color(0xFF58A6FF)
      ..style = PaintingStyle.fill;
    for (final point in dataPoints) {
      canvas.drawCircle(point, 3, pointPaint);
    }

    // ─── 5. 绘制维度标签 ──────────────────────────────────────
    for (int i = 0; i < n; i++) {
      final dim = dimensions[i];
      final angle = angleFor(i);
      final labelR = radius + 16;
      final labelPoint = Offset(
        center.dx + labelR * cos(angle),
        center.dy + labelR * sin(angle),
      );

      final score = (scores[dim] ?? 5.0).clamp(0.0, 10.0);
      final textSpan = TextSpan(
        text: '$dim\n${score.toStringAsFixed(1)}',
        style: TextStyle(
          color: dimensionColors[i],
          fontSize: 10,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      // 根据角度调整对齐方式
      final dx = labelPoint.dx - textPainter.width / 2;
      final dy = labelPoint.dy - textPainter.height / 2;
      textPainter.paint(canvas, Offset(dx, dy));
    }

    // ─── 6. 中心综合评分 ──────────────────────────────────────
    if (totalScore != null) {
      final scoreText = '$totalScore';
      final scoreSpan = TextSpan(
        text: scoreText,
        style: const TextStyle(
          color: Color(0xFFF0F6FC),
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      );
      final scorePainter = TextPainter(
        text: scoreSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      scorePainter.paint(
        canvas,
        Offset(
          center.dx - scorePainter.width / 2,
          center.dy - scorePainter.height / 2 - 6,
        ),
      );

      final labelSpan = TextSpan(
        text: '综合评分',
        style: TextStyle(
          color: const Color(0xFF8B949E),
          fontSize: 10,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          center.dx - labelPainter.width / 2,
          center.dy + 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    if (oldDelegate.totalScore != totalScore) return true;
    if (oldDelegate.scores.length != scores.length) return true;
    for (final key in scores.keys) {
      if (oldDelegate.scores[key] != scores[key]) return true;
    }
    return false;
  }
}
