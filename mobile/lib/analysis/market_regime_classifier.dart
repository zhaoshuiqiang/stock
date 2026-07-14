import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

const String marketContextMissingFlag = 'market_context_missing';
const String marketContextInvalidFlag = 'market_context_invalid';
const String marketBreadthMissingFlag = 'market_breadth_missing';

class MarketRegimeClassification {
  final MarketRegime marketRegime;
  final int marketBias;
  final double breadth;
  final List<String> dataQualityFlags;

  MarketRegimeClassification({
    required this.marketRegime,
    required this.marketBias,
    required this.breadth,
    List<String> dataQualityFlags = const [],
  }) : dataQualityFlags = List<String>.unmodifiable(dataQualityFlags);
}

class MarketRegimeClassifier {
  static const Map<MarketRegime, int> marketBiasByRegime = <MarketRegime, int>{
    MarketRegime.bullishTrend: 50,
    MarketRegime.rebound: 25,
    MarketRegime.range: 0,
    MarketRegime.highVolatility: 0,
    MarketRegime.unknown: 0,
    MarketRegime.pullback: -20,
    MarketRegime.bearishTrend: -50,
  };

  static MarketRegimeClassification classify(MarketContext? context) {
    if (context == null) {
      return _result(
        MarketRegime.unknown,
        dataQualityFlags: const <String>[marketContextMissingFlag],
      );
    }

    if (!_isValid(context)) {
      return _result(
        MarketRegime.unknown,
        dataQualityFlags: const <String>[marketContextInvalidFlag],
      );
    }

    final flags = <String>[];
    final totalBreadthCount = context.upCount + context.downCount;
    final breadth = totalBreadthCount > 0
        ? context.upCount / totalBreadthCount
        : _neutralBreadth;
    if (totalBreadthCount == 0) {
      flags.add(marketBreadthMissingFlag);
    }

    final marketTrend = context.marketTrend.trim().toLowerCase();
    final indexAverage = (context.shIndexPct + context.szIndexPct) / 2;
    final indexSpread = (context.shIndexPct - context.szIndexPct).abs();

    final indexDisagreement = context.shIndexPct * context.szIndexPct < 0 &&
        indexSpread >= _majorIndexDisagreementSpread;
    final majorIndexSpread = indexSpread >= _majorIndexSpread &&
        (context.shIndexPct.abs() >= _meaningfulIndexMove ||
            context.szIndexPct.abs() >= _meaningfulIndexMove);
    final breadthPriceDivergence =
        _hasBreadthPriceDivergence(indexAverage, context.avgChangePct, breadth);
    if (indexDisagreement || majorIndexSpread || breadthPriceDivergence) {
      return _result(
        MarketRegime.highVolatility,
        breadth: breadth,
        dataQualityFlags: flags,
      );
    }

    final positiveTrend = marketTrend == 'strong_up' || marketTrend == 'up';
    final negativeTrend = marketTrend == 'strong_down' || marketTrend == 'down';

    final confirmedBullish = positiveTrend &&
        context.shIndexPct >= _confirmedIndexMove &&
        context.szIndexPct >= _confirmedIndexMove &&
        context.avgChangePct >= _confirmedAverageMove &&
        breadth >= _confirmedBullishBreadth;
    if (confirmedBullish) {
      return _result(
        MarketRegime.bullishTrend,
        breadth: breadth,
        dataQualityFlags: flags,
      );
    }

    final confirmedBearish = negativeTrend &&
        context.shIndexPct <= -_confirmedIndexMove &&
        context.szIndexPct <= -_confirmedIndexMove &&
        context.avgChangePct <= -_confirmedAverageMove &&
        breadth <= _confirmedBearishBreadth;
    if (confirmedBearish) {
      return _result(
        MarketRegime.bearishTrend,
        breadth: breadth,
        dataQualityFlags: flags,
      );
    }

    final recovering = (context.avgChangePct >= _mildAverageMove ||
            indexAverage >= _mildIndexMove ||
            (context.shIndexPct >= _mildIndexMove &&
                context.szIndexPct >= _mildIndexMove)) &&
        breadth >= _constructiveBreadth;
    if (recovering) {
      return _result(
        MarketRegime.rebound,
        breadth: breadth,
        dataQualityFlags: flags,
      );
    }

    final pullingBack = (context.avgChangePct <= -_mildAverageMove ||
            indexAverage <= -_mildIndexMove ||
            negativeTrend) &&
        (breadth <= _weakBreadth || negativeTrend);
    if (pullingBack) {
      return _result(
        MarketRegime.pullback,
        breadth: breadth,
        dataQualityFlags: flags,
      );
    }

    return _result(
      MarketRegime.range,
      breadth: breadth,
      dataQualityFlags: flags,
    );
  }

  static int marketBiasFor(MarketRegime regime) {
    return marketBiasByRegime[regime] ?? 0;
  }

  static bool _isValid(MarketContext context) {
    return context.shIndexPct.isFinite &&
        context.szIndexPct.isFinite &&
        context.indexChange.isFinite &&
        context.avgChangePct.isFinite &&
        context.upCount >= 0 &&
        context.downCount >= 0;
  }

  static bool _hasBreadthPriceDivergence(
    double indexAverage,
    double avgChangePct,
    double breadth,
  ) {
    final broadPriceStrength =
        indexAverage >= _divergenceMove || avgChangePct >= _divergenceMove;
    final broadPriceWeakness =
        indexAverage <= -_divergenceMove || avgChangePct <= -_divergenceMove;

    return (broadPriceStrength && breadth <= _weakBreadth) ||
        (broadPriceWeakness && breadth >= _constructiveBreadth);
  }

  static MarketRegimeClassification _result(
    MarketRegime regime, {
    double breadth = _neutralBreadth,
    List<String> dataQualityFlags = const [],
  }) {
    return MarketRegimeClassification(
      marketRegime: regime,
      marketBias: marketBiasFor(regime),
      breadth: breadth,
      dataQualityFlags: dataQualityFlags,
    );
  }

  static const double _neutralBreadth = 0.5;
  static const double _majorIndexDisagreementSpread = 0.8;
  static const double _majorIndexSpread = 1.5;
  static const double _meaningfulIndexMove = 0.4;
  static const double _confirmedIndexMove = 0.6;
  static const double _confirmedAverageMove = 0.8;
  static const double _confirmedBullishBreadth = 0.6;
  static const double _confirmedBearishBreadth = 0.4;
  static const double _mildAverageMove = 0.3;
  static const double _mildIndexMove = 0.3;
  static const double _constructiveBreadth = 0.52;
  static const double _weakBreadth = 0.48;
  static const double _divergenceMove = 1.0;
}
