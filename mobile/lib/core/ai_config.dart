import 'dart:io';
import '../analysis/ai_layer.dart';

class AIConfig {
  static const bool enableAIEnhancement = true;
  static const AIProvider defaultProvider = AIProvider.zhipu;
  static const String cloudFunctionProxy = '';
  static const int maxDebateRounds = 2;
  static const double aiConfidenceWeight = 0.3;

  static const String _zhipuApiKey = 'REDACTED';
  static const String _openrouterApiKey = 'REDACTED';
  static const String _cliproxyApiKey = 'REDACTED';

  static String getApiKeyForProvider(AIProvider provider) {
    switch (provider) {
      case AIProvider.zhipu:
        return Platform.environment['GLM_API_KEY'] ?? _zhipuApiKey;
      case AIProvider.openrouter:
        return Platform.environment['ANTHROPIC_AUTH_TOKEN'] ?? _openrouterApiKey;
      case AIProvider.cliproxyapi:
        return Platform.environment['CLIPROXY_API_KEY'] ?? _cliproxyApiKey;
    }
  }

  static bool get useCloudProxy => cloudFunctionProxy.isNotEmpty;

  static String get apiEndpoint => defaultProvider.endpoint;

  static String get defaultModel => defaultProvider.defaultModel;
}