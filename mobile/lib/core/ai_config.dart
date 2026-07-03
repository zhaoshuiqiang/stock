import 'dart:io';

class AIConfig {
  static const bool enableAIEnhancement = true;
  static const String defaultProvider = 'glm';
  static const String apiEndpoint = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const String cloudFunctionProxy = '';
  static const int maxDebateRounds = 2;
  static const double aiConfidenceWeight = 0.3;
  static const String defaultModel = 'glm-4.7-flash';
  static const String _defaultApiKey = '';

  static String get apiKey {
    final envKey = Platform.environment['GLM_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      return envKey;
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

  static const List<String> supportedProviders = [
    'deepseek',
    'openai',
    'qwen',
    'glm',
    'ollama',
  ];

  static String getProviderEndpoint(String provider) {
    switch (provider) {
      case 'deepseek':
        return 'https://api.deepseek.com/v1/chat/completions';
      case 'openai':
        return 'https://api.openai.com/v1/chat/completions';
      case 'qwen':
        return 'https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/text-generation/generation';
      case 'glm':
        return 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
      case 'ollama':
        return 'http://localhost:11434/v1/chat/completions';
      default:
        return apiEndpoint;
    }
  }

  static String getProviderModel(String provider) {
    switch (provider) {
      case 'glm':
        return 'glm-4.7-flash';
      case 'deepseek':
        return 'deepseek-chat';
      case 'openai':
        return 'gpt-5.4-mini';
      case 'qwen':
        return 'qwen-max';
      case 'ollama':
        return 'llama3.1';
      default:
        return defaultModel;
    }
  }
}