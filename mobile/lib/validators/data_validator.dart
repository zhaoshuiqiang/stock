import '../models/stock_models.dart';
import '../core/trading_session.dart';

enum DataAnomalyType {
  zeroPrice,
  extremeChange,
  zeroVolume,
  negativeValue,
  staleData,
  suspiciousUnit,
  invalidRange,
}

class DataAnomaly {
  final DataAnomalyType type;
  final String field;
  final String description;
  final double severity; // 0.0-1.0

  DataAnomaly({
    required this.type,
    required this.field,
    required this.description,
    required this.severity,
  });
}

class DataValidationResult {
  final bool isValid;
  final List<DataAnomaly> anomalies;

  DataValidationResult({required this.isValid, required this.anomalies});

  bool get hasWarnings => anomalies.any((a) => a.severity < 0.8);
  bool get hasErrors => anomalies.any((a) => a.severity >= 0.8);
}

class DataValidator {
  /// Validate quote data
  static DataValidationResult validateQuote(QuoteData quote) {
    final anomalies = <DataAnomaly>[];

    // Zero price check
    if (quote.price <= 0) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.zeroPrice,
        field: 'price',
        description: '价格为0或负值，数据可能异常',
        severity: 1.0,
      ));
    }

    // 主板(60x/00x)涨跌停10%，创业板(300x)/科创板(688x)涨跌停20%
    final isST = quote.name.contains('ST');
    final codeNum = quote.code.replaceAll(RegExp(r'^[a-zA-Z]+'), '');
    final isMainBoard = codeNum.startsWith('60') || codeNum.startsWith('00');
    final changeLimit = isST ? 6.0 : (isMainBoard ? 11.0 : 21.0); // 留1%容差
    if (quote.changePct.abs() > changeLimit) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.extremeChange,
        field: 'changePct',
        description: '涨跌幅${quote.changePct.toStringAsFixed(2)}%超出正常范围',
        severity: 0.7,
      ));
    }

    // Zero volume during trading hours
    if (quote.volume <= 0) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.zeroVolume,
        field: 'volume',
        description: '成交量为0',
        severity: 0.5,
      ));
    }

    // Negative values check
    if (quote.high < 0 || quote.low < 0 || quote.open < 0) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.negativeValue,
        field: 'high/low/open',
        description: '价格数据存在负值',
        severity: 1.0,
      ));
    }

    // High > Low sanity check
    if (quote.high > 0 && quote.low > 0 && quote.high < quote.low) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.negativeValue,
        field: 'high/low',
        description: '最高价低于最低价，数据异常',
        severity: 1.0,
      ));
    }

    // 成交额单位/数量级校验：QuoteData约定 volume=手、amount=元。
    if (quote.price > 0 && quote.volume > 0 && quote.amount > 0) {
      final expectedAmount = quote.price * quote.volume * 100;
      final ratio = quote.amount / expectedAmount;
      if (ratio < 0.2 || ratio > 5.0) {
        anomalies.add(DataAnomaly(
          type: DataAnomalyType.suspiciousUnit,
          field: 'amount',
          description:
              '成交额与价格×成交量不匹配，可能存在单位错误(amount/expected=${ratio.toStringAsFixed(2)})',
          severity: 0.6,
        ));
      }
    }

    if (quote.turnover < 0 || quote.turnover > 100) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.invalidRange,
        field: 'turnover',
        description: '换手率${quote.turnover.toStringAsFixed(2)}%超出合理范围',
        severity: 0.6,
      ));
    }

    if (quote.pe.abs() > 1000) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.invalidRange,
        field: 'pe',
        description: '市盈率${quote.pe.toStringAsFixed(1)}超出合理范围',
        severity: 0.5,
      ));
    }

    if (quote.pb < 0 || quote.pb > 100) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.invalidRange,
        field: 'pb',
        description: '市净率${quote.pb.toStringAsFixed(2)}超出合理范围',
        severity: 0.5,
      ));
    }

    if (quote.mainNetFlowRate.abs() > 100) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.invalidRange,
        field: 'mainNetFlowRate',
        description: '主力净流入率${quote.mainNetFlowRate.toStringAsFixed(2)}%超出合理范围',
        severity: 0.6,
      ));
    }

    if (quote.totalMarketCap > 0 &&
        quote.circulatingMarketCap > 0 &&
        quote.circulatingMarketCap > quote.totalMarketCap * 1.05) {
      anomalies.add(DataAnomaly(
        type: DataAnomalyType.invalidRange,
        field: 'marketCap',
        description: '流通市值大于总市值，市值字段可能存在单位或字段映射错误',
        severity: 0.7,
      ));
    }

    return DataValidationResult(
      isValid: !anomalies.any((a) => a.severity >= 1.0),
      anomalies: anomalies,
    );
  }

  /// Validate K-line data
  static DataValidationResult validateKlines(List<HistoryKline> klines) {
    final anomalies = <DataAnomaly>[];

    for (int i = 0; i < klines.length; i++) {
      final k = klines[i];

      // Negative price check
      if (k.open < 0 || k.high < 0 || k.low < 0 || k.close < 0) {
        anomalies.add(DataAnomaly(
          type: DataAnomalyType.negativeValue,
          field: 'kline[$i]',
          description: 'K线数据存在负值: ${k.date}',
          severity: 1.0,
        ));
      }

      // High < Low check
      if (k.high < k.low) {
        anomalies.add(DataAnomaly(
          type: DataAnomalyType.negativeValue,
          field: 'kline[$i]',
          description: '最高价低于最低价: ${k.date}',
          severity: 1.0,
        ));
      }
    }

    return DataValidationResult(
      isValid: !anomalies.any((a) => a.severity >= 1.0),
      anomalies: anomalies,
    );
  }

  /// Check K-line data continuity (detect missing trading days)
  static List<DateTime> findMissingTradingDays(List<HistoryKline> klines) {
    if (klines.length < 2) return [];

    final missingDays = <DateTime>[];
    final dates = klines
        .map((k) => DateTime(k.date.year, k.date.month, k.date.day))
        .toSet();

    // Check from first to last date
    final first = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);

    var current = first;
    while (current.isBefore(last)) {
      current = current.add(const Duration(days: 1));
      // Skip weekends
      if (current.weekday == DateTime.saturday ||
          current.weekday == DateTime.sunday) {
        continue;
      }
      // Skip known Chinese holidays (simplified - just check major ones)
      if (_isChineseHoliday(current)) {
        continue;
      }

      if (!dates.contains(current)) {
        missingDays.add(current);
      }
    }

    return missingDays;
  }

  static bool _isChineseHoliday(DateTime date) {
    // Simplified Chinese holiday check - major holidays only
    // Spring Festival, National Day, etc. would need a proper calendar
    // For now, just check month/day patterns
    final md =
        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    // New Year's Day
    if (md == '01-01') return true;
    // Labor Day
    if (md == '05-01') return true;
    // National Day
    if (md.startsWith('10-') && int.parse(md.split('-')[1]) <= 7) return true;
    return false;
  }

  /// Check price reasonability
  static DataValidationResult validateKlinePrices(List<HistoryKline> klines) {
    final anomalies = <DataAnomaly>[];

    for (int i = 0; i < klines.length; i++) {
      final k = klines[i];

      // Extreme price movement (>30% in a single day for non-ST)
      if (k.changePct.abs() > 30) {
        anomalies.add(DataAnomaly(
          type: DataAnomalyType.extremeChange,
          field: 'kline[$i].changePct',
          description: '日涨跌幅${k.changePct.toStringAsFixed(2)}%异常: ${k.date}',
          severity: 0.8,
        ));
      }

      // Zero volume with price change
      if (k.volume <= 0 && k.close != k.open) {
        anomalies.add(DataAnomaly(
          type: DataAnomalyType.zeroVolume,
          field: 'kline[$i].volume',
          description: '成交量为0但价格有变化: ${k.date}',
          severity: 0.9,
        ));
      }
    }

    return DataValidationResult(
      isValid: !anomalies.any((a) => a.severity >= 1.0),
      anomalies: anomalies,
    );
  }

  static bool isStaleQuote(QuoteData quote) {
    if (quote.updateTime == null) return false;
    final now = DateTime.now();
    final diff = now.difference(quote.updateTime!).inSeconds;
    // During trading hours, data older than 60 seconds is stale
    if (TradingSession.isInTradingSession()) {
      return diff > 60;
    }
    // After hours, data older than 30 minutes is stale
    return diff > 1800;
  }
}
