class NextSessionPrediction {
  final double nextOpenUpProbability;
  final double nextCloseUpProbability;
  final double expectedNextCloseReturn;
  final double downsideRiskProbability;
  final double confidence;
  final int sampleCount;
  final List<String> scenarioTags;
  final double neutralProbability;
  final List<String> riskWarnings;

  const NextSessionPrediction({
    required this.nextOpenUpProbability,
    required this.nextCloseUpProbability,
    required this.expectedNextCloseReturn,
    required this.downsideRiskProbability,
    required this.confidence,
    required this.sampleCount,
    required this.scenarioTags,
    this.neutralProbability = 0,
    required this.riskWarnings,
  });

  const NextSessionPrediction.neutral({
    this.nextOpenUpProbability = 0.5,
    this.nextCloseUpProbability = 0.5,
    this.expectedNextCloseReturn = 0,
    this.downsideRiskProbability = 0.5,
    this.neutralProbability = 0,
    this.confidence = 0,
    this.sampleCount = 0,
    this.scenarioTags = const [],
    this.riskWarnings = const [],
  });
}

class NextSessionFeatures {
  final double changePct;
  final double amplitudePct;
  final double closePosition;
  final double upperShadowRatio;
  final double lowerShadowRatio;
  final double return3;
  final double return5;
  final double return10;
  final int consecutiveUpDays;
  final int consecutiveDownDays;
  final double distanceMa5;
  final double distanceMa10;
  final double distanceMa20;
  final double volumeRatio5;
  final double volumeRatio10;
  final double turnover;
  final double rsi6;
  final double k;
  final double d;
  final double j;
  final double macdHist;
  final double volatility20;
  final Map<String, String> featureBins;
  final List<String> scenarioTags;
  final List<String> riskWarnings;

  const NextSessionFeatures({
    required this.changePct,
    required this.amplitudePct,
    required this.closePosition,
    required this.upperShadowRatio,
    required this.lowerShadowRatio,
    required this.return3,
    required this.return5,
    required this.return10,
    required this.consecutiveUpDays,
    required this.consecutiveDownDays,
    required this.distanceMa5,
    required this.distanceMa10,
    required this.distanceMa20,
    required this.volumeRatio5,
    required this.volumeRatio10,
    required this.turnover,
    required this.rsi6,
    required this.k,
    required this.d,
    required this.j,
    required this.macdHist,
    this.volatility20 = 0,
    this.featureBins = const {},
    required this.scenarioTags,
    required this.riskWarnings,
  });
}
