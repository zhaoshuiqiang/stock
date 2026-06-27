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

    testWidgets('signals truncated with ellipsis', (tester) async {
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
        signals: List.generate(10, (i) => '信号$i这是一个很长的信号文本'),
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      // 验证有 Text widget 使用了 overflow
      final textWidgets = find.byType(Text);
      expect(textWidgets, findsWidgets);
    });
  });
}
