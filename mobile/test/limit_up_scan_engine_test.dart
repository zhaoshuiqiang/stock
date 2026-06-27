import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/limit_up_scan_engine.dart';

void main() {
  group('LimitUpScanEngine', () {
    test('is singleton', () {
      expect(LimitUpScanEngine.instance, same(LimitUpScanEngine.instance));
    });

    test('initial state: not running, no latest progress', () {
      final engine = LimitUpScanEngine.instance;
      // dispose 后重新检查初始状态
      engine.dispose();
      expect(engine.isRunning, isFalse);
      expect(engine.latestProgress, isNull);
    });
  });
}
