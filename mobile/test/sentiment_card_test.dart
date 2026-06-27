import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/widgets/sentiment_thermometer_card.dart';

void main() {
  group('SentimentThermometerCard', () {
    testWidgets('null sentiment shows skeleton', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: null)),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('climax phase displays temperature and phase label', (tester) async {
      final s = SentimentResult(
        temperature: 75,
        phase: EmotionPhase.climax,
        zhabanRate: 0.1,
        continuationRate: 0.6,
        sealSuccessRate: 0.9,
        moneyMakingEffect: 4.0,
        limitUpCount: 60,
        limitDownCount: 2,
        continuationHeight: 5,
        signals: const ['🔥 封板极强', '🚀 接力强'],
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      expect(find.text('75°'), findsOneWidget);
      expect(find.textContaining('高潮'), findsWidgets);
    });

    testWidgets('displays all 5 mini metrics with values', (tester) async {
      final s = SentimentResult(
        temperature: 50,
        phase: EmotionPhase.startup,
        zhabanRate: 0.20,
        continuationRate: 0.30,
        sealSuccessRate: 0.80,
        moneyMakingEffect: 1.5,
        limitUpCount: 35,
        limitDownCount: 5,
        continuationHeight: 3,
        signals: const [],
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      // 验证 5 个 mini metric 标签都渲染
      expect(find.textContaining('炸板'), findsOneWidget);
      expect(find.textContaining('晋级'), findsOneWidget);
      expect(find.textContaining('封板'), findsOneWidget);
      expect(find.textContaining('赚钱'), findsOneWidget);
      expect(find.textContaining('高度'), findsOneWidget);
      // 验证数值格式化
      expect(find.textContaining('20%'), findsOneWidget);  // zhabanRate 0.20 → 20%
      expect(find.textContaining('3板'), findsOneWidget);  // continuationHeight 3
    });

    testWidgets('startup phase displays startup label and position advice', (tester) async {
      final s = SentimentResult(
        temperature: 45,
        phase: EmotionPhase.startup,
        zhabanRate: 0.2,
        continuationRate: 0.3,
        sealSuccessRate: 0.8,
        moneyMakingEffect: 1.0,
        limitUpCount: 35,
        limitDownCount: 5,
        continuationHeight: 3,
        signals: const [],
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      expect(find.textContaining('启动'), findsWidgets);
      expect(find.textContaining('5-6 成'), findsOneWidget);
    });

    testWidgets('signals display first 2 items joined', (tester) async {
      final s = SentimentResult(
        temperature: 50,
        phase: EmotionPhase.startup,
        zhabanRate: 0.2,
        continuationRate: 0.3,
        sealSuccessRate: 0.8,
        moneyMakingEffect: 1.0,
        limitUpCount: 35,
        limitDownCount: 5,
        continuationHeight: 3,
        signals: const ['🔥 信号A', '🚀 信号B', '❄️ 信号C'],
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      // 验证前 2 个信号被拼接显示
      expect(find.textContaining('信号A'), findsOneWidget);
      expect(find.textContaining('信号B'), findsOneWidget);
      // 第 3 个信号不应显示（take(2)）
      expect(find.textContaining('信号C'), findsNothing);
    });

    testWidgets('empty signals does not crash', (tester) async {
      final s = SentimentResult(
        temperature: 30,
        phase: EmotionPhase.freezing,
        zhabanRate: 0.8,
        continuationRate: 0.1,
        sealSuccessRate: 0.2,
        moneyMakingEffect: -2.0,
        limitUpCount: 10,
        limitDownCount: 8,
        continuationHeight: 1,
        signals: const [],
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      expect(find.text('30°'), findsOneWidget);
      expect(find.textContaining('冰点'), findsWidgets);
    });
  });
}
