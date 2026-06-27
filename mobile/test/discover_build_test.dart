import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/screens/discover_screen.dart';

void main() {
  testWidgets('DiscoverScreen builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DiscoverScreen(),
    ));
    // Allow async initState callbacks to settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // If we reach here without exception, the build is OK
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });

  // 回归测试：sqflite db.query() 返回的 QueryResultSet 是只读 list，
  // _mainLinePicks 在无主线命中时回退到全部精选并 sort，必须创建可变副本，
  // 否则 sort 会触发 UnsupportedError('read-only')
  test('Sort on read-only db query result copy does not throw', () {
    // 模拟 sqflite QueryResultSet 的只读行为
    final readOnlyList = List<Map<String, dynamic>>.unmodifiable([
      {'code': '000001', 'name': '平安银行', 'score': 5, 'mainLine': 0},
      {'code': '000002', 'name': '万科A', 'score': 8, 'mainLine': 0},
    ]);

    // 复现 _mainLinePicks 的逻辑
    final all = readOnlyList;
    var picks = all.where((p) => p['mainLine'] == 1 || p['mainLine'] == true).toList();
    // 无主线命中时回退到全部精选 — 必须创建副本
    if (picks.isEmpty && all.isNotEmpty) {
      picks = List<Map<String, dynamic>>.from(all);
    }

    // sort 不应抛出 UnsupportedError('read-only')
    picks.sort((a, b) =>
        (b['score'] as num? ?? 0).toInt().compareTo((a['score'] as num? ?? 0).toInt()));

    expect(picks.first['code'], '000002'); // 评分高的排前面
    expect(picks.last['code'], '000001');
  });
}
