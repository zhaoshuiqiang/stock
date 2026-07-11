import 'package:shared_preferences/shared_preferences.dart';

class PortfolioAssetSummary {
  static const String totalAssetsKey = 'portfolio_total_assets';
  static const String availableCashKey = 'portfolio_available_cash';

  final double totalAssets;
  final double availableCash;

  const PortfolioAssetSummary({
    this.totalAssets = 0,
    this.availableCash = 0,
  });

  bool get hasValue => totalAssets > 0 || availableCash > 0;

  PortfolioAssetSummary copyWith({
    double? totalAssets,
    double? availableCash,
  }) {
    return PortfolioAssetSummary(
      totalAssets: totalAssets ?? this.totalAssets,
      availableCash: availableCash ?? this.availableCash,
    );
  }

  static double parseAmount(String raw) {
    final normalized = raw
        .replaceAll(',', '')
        .replaceAll('%', '')
        .replaceAll('¥', '')
        .replaceAll('￥', '')
        .trim();
    if (normalized.isEmpty || normalized == '--') return 0;
    return double.tryParse(normalized) ?? 0;
  }
}

class PortfolioAssetStore {
  Future<PortfolioAssetSummary> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PortfolioAssetSummary(
      totalAssets: prefs.getDouble(PortfolioAssetSummary.totalAssetsKey) ?? 0,
      availableCash:
          prefs.getDouble(PortfolioAssetSummary.availableCashKey) ?? 0,
    );
  }

  Future<void> save(PortfolioAssetSummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      PortfolioAssetSummary.totalAssetsKey,
      summary.totalAssets,
    );
    await prefs.setDouble(
      PortfolioAssetSummary.availableCashKey,
      summary.availableCash,
    );
  }
}
