import '../models/short_term_decision.dart';

class LegacyDecisionAdapter {
  static int scoreOf(RecommendationDecision decision) => decision.legacyScore;

  static String recommendationOf(RecommendationDecision decision) =>
      decision.label;
}
