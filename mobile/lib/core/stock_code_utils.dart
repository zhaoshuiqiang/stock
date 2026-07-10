class StockCodeUtils {
  static String normalizeForArchive(String code) {
    final value = code.trim().toLowerCase();
    if (value.isEmpty) return value;
    if (value.startsWith('sh') ||
        value.startsWith('sz') ||
        value.startsWith('bj') ||
        value.startsWith('hk')) {
      return value;
    }
    if (value.startsWith('8') || value.startsWith('43')) return 'bj$value';
    if (value.startsWith('6')) return 'sh$value';
    if (value.startsWith('0') || value.startsWith('3')) return 'sz$value';
    return value;
  }

  static String toEastMoneySecId(String code) {
    final normalized = normalizeForArchive(code);
    if (normalized.startsWith('hk')) return normalized;
    final rawCode = stripMarketPrefix(normalized);
    if (rawCode.isEmpty) return rawCode;
    if (normalized.startsWith('sh')) return '1.$rawCode';
    if (normalized.startsWith('sz') || normalized.startsWith('bj')) {
      return '0.$rawCode';
    }
    if (rawCode.startsWith('6')) return '1.$rawCode';
    if (rawCode.startsWith('0') ||
        rawCode.startsWith('3') ||
        rawCode.startsWith('8') ||
        rawCode.startsWith('43')) {
      return '0.$rawCode';
    }
    return normalized;
  }

  static String stripMarketPrefix(String code) {
    final value = code.trim().toLowerCase();
    if (value.startsWith('sh') ||
        value.startsWith('sz') ||
        value.startsWith('bj') ||
        value.startsWith('hk')) {
      return value.substring(2);
    }
    return value;
  }
}
