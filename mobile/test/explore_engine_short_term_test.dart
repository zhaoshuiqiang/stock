import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/explore_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('ExploreEngine valuation policy', () {
    test('default mode keeps valuation hard filter', () {
      expect(
        ExploreEngine.passesValuationFilter(_quote(pe: -1, pb: 2)),
        isFalse,
      );
      expect(
        ExploreEngine.passesValuationFilter(_quote(pe: 90, pb: 2)),
        isFalse,
      );
    });

    test('short-term mode treats valuation as risk, not hard exclusion', () {
      expect(
        ExploreEngine.passesValuationFilter(
          _quote(pe: -1, pb: 2),
          shortTermMode: true,
        ),
        isTrue,
      );
      expect(
        ExploreEngine.passesValuationFilter(
          _quote(pe: 90, pb: 2),
          shortTermMode: true,
        ),
        isTrue,
      );
    });
  });
}

QuoteData _quote({required double pe, required double pb}) {
  return QuoteData(
    code: 'sh600001',
    name: '测试股票',
    price: 10,
    pe: pe,
    pb: pb,
  );
}
