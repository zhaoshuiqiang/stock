import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/storage/portfolio_asset_store.dart';

void main() {
  group('PortfolioAssetStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists imported total assets and available cash', () async {
      final store = PortfolioAssetStore();

      await store.save(
        const PortfolioAssetSummary(
          totalAssets: 123456.78,
          availableCash: 2345.67,
        ),
      );

      final restored = await PortfolioAssetStore().load();

      expect(restored.totalAssets, closeTo(123456.78, 0.001));
      expect(restored.availableCash, closeTo(2345.67, 0.001));
      expect(restored.hasValue, isTrue);
    });

    test('parses broker amount strings with comma and percent noise', () {
      expect(PortfolioAssetSummary.parseAmount('123,456.78'), 123456.78);
      expect(PortfolioAssetSummary.parseAmount('¥2,345.60'), 2345.6);
      expect(PortfolioAssetSummary.parseAmount('--'), 0);
      expect(PortfolioAssetSummary.parseAmount(''), 0);
    });
  });
}
