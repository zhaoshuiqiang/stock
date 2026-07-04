import 'dart:io';
import '../analysis/ai_layer.dart';

class AIConfig {
  static const bool enableAIEnhancement = true;
  static const AIProvider defaultProvider = AIProvider.zhipu;
  static const String cloudFunctionProxy = '';
  static const int maxDebateRounds = 2;
  static const double aiConfidenceWeight = 0.3;
  static const String _defaultApiKey = '';

  static String get apiKey {
    final envKey = Platform.environment['GLM_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      return envKey;
    }
    final anthropicKey = Platform.environment['ANTHROPIC_AUTH_TOKEN'];
    if (anthropicKey != null && anthropicKey.isNotEmpty) {
      return anthropicKey;
    }
    final cliproxyKey = Platform.environment['CLIPROXY_API_KEY'];
    if (cliproxyKey != null && cliproxyKey.isNotEmpty) {
      return cliproxyKey;
    }
    return _defaultApiKey;
  }

  static void setApiKey(String key) {
    _customApiKey = key;
  }

  static String? _customApiKey;

  static String get effectiveApiKey {
    if (_customApiKey != null && _customApiKey!.isNotEmpty) {
      return _customApiKey!;
    }
    return apiKey;
  }

  static bool get useCloudProxy => cloudFunctionProxy.isNotEmpty;

  static String get apiEndpoint => defaultProvider.endpoint;

  static String get defaultModel => defaultProvider.defaultModel;
}