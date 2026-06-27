import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/screens/home_screen.dart';
import 'package:stock_analyzer/widgets/sentiment_thermometer_card.dart';

void main() {
  // 工作台升级 (Task 12)：HomeScreen 集成情绪温度计大卡
  // 测试环境无 path_provider / 网络，DB / 择时 / 行情加载会失败 —
  // 这是允许的，工作台卡片本身仍应渲染（不抛出未捕获异常）。
  testWidgets('HomeScreen renders workbench with sentiment card slot', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeScreen())));
    // 让 initState 触发的异步任务执行一帧
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 关键：构建过程不应抛出未捕获异常
    expect(find.byType(HomeScreen), findsOneWidget);
    // 工作台卡片应渲染（标题至少出现一次）
    expect(find.textContaining('短线工作台'), findsWidgets);
    // 情绪温度计大卡槽位应存在（_sentiment == null 时显示 skeleton）
    expect(find.byType(SentimentThermometerCard), findsOneWidget);
  });

  testWidgets('SentimentThermometerCard shows temperature when sentiment provided', (tester) async {
    final s = SentimentResult(
      temperature: 62,
      phase: EmotionPhase.startup,
      zhabanRate: 0.2,
      continuationRate: 0.4,
      sealSuccessRate: 0.8,
      moneyMakingEffect: 2.0,
      limitUpCount: 35,
      limitDownCount: 3,
      continuationHeight: 5,
      signals: const [],
      timestamp: DateTime.now(),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
    ));
    expect(find.text('62°'), findsOneWidget);
  });
}
