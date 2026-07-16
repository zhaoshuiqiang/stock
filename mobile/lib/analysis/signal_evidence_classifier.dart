import '../models/stock_models.dart';

class SignalEvidenceClassification {
  final String component;
  final String family;

  const SignalEvidenceClassification(this.component, this.family);
}

/// Maps one production signal to one decision component and one independent
/// indicator family. Relative-strength and next-session are model inputs and
/// are deliberately not inferred from free-form signal text.
class SignalEvidenceClassifier {
  static SignalEvidenceClassification classify(SignalItem signal) {
    final indicator = signal.indicator.trim().toLowerCase();
    final text =
        '$indicator ${signal.signal} ${signal.description} ${signal.desc}'
            .toLowerCase();

    if (indicator.contains('macd')) {
      if (_containsAny(text, const <String>['背离', 'divergence'])) {
        return const SignalEvidenceClassification(
          'reversal_momentum',
          'macd_divergence',
        );
      }
      return const SignalEvidenceClassification('trend', 'macd_trend');
    }
    if (indicator.contains('rsi')) {
      return const SignalEvidenceClassification('reversal_momentum', 'rsi');
    }
    if (indicator.contains('kdj')) {
      return const SignalEvidenceClassification('reversal_momentum', 'kdj');
    }
    if (_matchesIndicator(indicator, 'wr')) {
      return const SignalEvidenceClassification('reversal_momentum', 'wr');
    }
    if (indicator.contains('cci')) {
      return const SignalEvidenceClassification('reversal_momentum', 'cci');
    }
    if (indicator.contains('bias') || indicator.contains('乖离')) {
      return const SignalEvidenceClassification('reversal_momentum', 'bias');
    }
    if (_containsAny(indicator, const <String>['k线形态', '蜡烛', 'candlestick']) ||
        indicator == '形态') {
      return const SignalEvidenceClassification(
        'reversal_momentum',
        'candlestick_reversal',
      );
    }
    if (_containsAny(indicator, const <String>['缺口', 'gap'])) {
      return const SignalEvidenceClassification(
        'reversal_momentum',
        'gap_reversal',
      );
    }
    if (text.contains('obv')) {
      return const SignalEvidenceClassification('volume_flow', 'obv');
    }
    if (_containsAny(text, const <String>[
      '资金',
      '主力',
      'fund flow',
      'capital flow',
      '吸筹',
      '派发',
    ])) {
      return const SignalEvidenceClassification('volume_flow', 'capital_flow');
    }
    if (_containsAny(text, const <String>['turnover', '换手'])) {
      return const SignalEvidenceClassification('volume_flow', 'turnover');
    }
    if (_containsAny(
        text, const <String>['量价', '成交量', '量能', 'volume', '放量', '缩量', '地量'])) {
      return const SignalEvidenceClassification('volume_flow', 'volume_price');
    }
    if (_containsAny(text, const <String>['k线形态', '蜡烛', 'candlestick'])) {
      return const SignalEvidenceClassification(
        'reversal_momentum',
        'candlestick_reversal',
      );
    }
    if (_containsAny(text, const <String>['缺口', '跳空', 'gap'])) {
      return const SignalEvidenceClassification(
        'reversal_momentum',
        'gap_reversal',
      );
    }
    if (text.contains('macd')) {
      if (_containsAny(text, const <String>['背离', 'divergence'])) {
        return const SignalEvidenceClassification(
          'reversal_momentum',
          'macd_divergence',
        );
      }
      return const SignalEvidenceClassification('trend', 'macd_trend');
    }
    if (text.contains('rsi')) {
      return const SignalEvidenceClassification('reversal_momentum', 'rsi');
    }
    if (text.contains('kdj')) {
      return const SignalEvidenceClassification('reversal_momentum', 'kdj');
    }
    if (_matchesIndicator(indicator, 'wr') || text.contains('williams')) {
      return const SignalEvidenceClassification('reversal_momentum', 'wr');
    }
    if (text.contains('cci')) {
      return const SignalEvidenceClassification('reversal_momentum', 'cci');
    }
    if (text.contains('bias') || text.contains('乖离')) {
      return const SignalEvidenceClassification('reversal_momentum', 'bias');
    }
    if (text.contains('boll') || text.contains('布林')) {
      return const SignalEvidenceClassification('trend', 'boll_trend');
    }
    if (_matchesIndicator(indicator, 'ma') || text.contains('均线')) {
      return const SignalEvidenceClassification('trend', 'ma');
    }
    if (text.contains('adx') || _matchesIndicator(indicator, 'di')) {
      return const SignalEvidenceClassification('trend', 'adx');
    }
    if (_containsAny(text, const <String>['背离', '反转', '超卖', '超买'])) {
      return const SignalEvidenceClassification(
        'reversal_momentum',
        'generic_reversal',
      );
    }
    return const SignalEvidenceClassification('trend', 'generic_trend');
  }

  static bool _matchesIndicator(String indicator, String token) =>
      indicator == token || indicator.startsWith('$token ');

  static bool _containsAny(String text, List<String> tokens) =>
      tokens.any(text.contains);
}

/// Records independent same-direction component coverage without modifying a
/// signal's evidence confidence. Repeated signals from one indicator/component
/// therefore cannot manufacture confluence.
class SignalConfluenceAnnotator {
  static List<SignalItem> annotate(List<SignalItem> signals) {
    final componentsByDirection = <String, Set<String>>{};
    for (final signal in signals) {
      componentsByDirection
          .putIfAbsent(signal.type, () => <String>{})
          .add(SignalEvidenceClassifier.classify(signal).component);
    }

    return signals
        .map((signal) => signal.copyWith(
              signalCount: componentsByDirection[signal.type]
                      ?.length
                      .clamp(1, 5)
                      .toInt() ??
                  1,
            ))
        .toList();
  }
}
