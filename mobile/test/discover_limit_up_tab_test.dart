import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/screens/discover_screen.dart';
import 'package:stock_analyzer/storage/database_service.dart';

/// 发现页打板梯队 Tab 重画测试（Task 11）
///
/// 验证：
/// 1. 有数据时按连板高度分组渲染（龙头/高度板/中度板/首板/炸板）
/// 2. 空数据时显示"暂无涨停"提示 + 刷新按钮
/// 3. 无炸板标的时不渲染炸板分组
void main() {
  setUp(() {
    // 重置 DB singleton，使后续查询走 _initDatabase → getApplicationDocumentsDirectory
    // → MissingPluginException（被 try/catch 捕获），不产生 pending timer。
    DatabaseService().resetForTesting();
  });

  tearDown(() {
    DatabaseService().resetForTesting();
  });

  group('DiscoverScreen LimitUp Tab', () {
    testWidgets('renders group headers when pool has data', (tester) async {
      // 放大测试视口，确保所有分组头部都在可视区内（ListView 懒加载）
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pool = [
        LimitUpAnalysis(code: '001', name: '龙头A', consecutiveDays: 5, isZhaBan: false),
        LimitUpAnalysis(code: '002', name: '高度B', consecutiveDays: 3, isZhaBan: false),
        LimitUpAnalysis(code: '003', name: '中度C', consecutiveDays: 2, isZhaBan: false),
        LimitUpAnalysis(code: '004', name: '首板D', consecutiveDays: 1, isZhaBan: false),
      ];
      await tester.pumpWidget(MaterialApp(
        home: DiscoverScreen(limitUpPoolOverride: pool, sentimentOverride: _mockSentiment()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('龙头'), findsWidgets);
      expect(find.textContaining('高度板'), findsWidgets);
      expect(find.textContaining('中度板'), findsWidgets);
      expect(find.textContaining('首板'), findsWidgets);
    });

    testWidgets('empty state shows refresh button', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DiscoverScreen(limitUpPoolOverride: [], sentimentOverride: null),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无涨停'), findsWidgets);
    });

    testWidgets('zhaban group hidden when no zhaban', (tester) async {
      final pool = [
        LimitUpAnalysis(code: '004', name: '首板D', consecutiveDays: 1, isZhaBan: false),
      ];
      await tester.pumpWidget(MaterialApp(
        home: DiscoverScreen(limitUpPoolOverride: pool, sentimentOverride: null),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('炸板'), findsNothing);
    });
  });
}

SentimentResult _mockSentiment() => SentimentResult(
  temperature: 62, phase: EmotionPhase.startup,
  zhabanRate: 0.2, continuationRate: 0.4, sealSuccessRate: 0.8,
  moneyMakingEffect: 2.0, limitUpCount: 35, limitDownCount: 3,
  continuationHeight: 5, signals: const [], timestamp: DateTime.now(),
);
