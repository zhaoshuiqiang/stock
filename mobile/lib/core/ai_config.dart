import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import '../analysis/ai_layer.dart';

class AIConfig {
  static const bool enableAIEnhancement = true;
  static const AIProvider defaultProvider = AIProvider.zhipu;
  static const String cloudFunctionProxy = '';
  static const int maxDebateRounds = 2;
  static const double aiConfidenceWeight = 0.3;

  // 从 assets/secrets.json 加载的密钥（应用启动时调用 init()）
  static String _zhipuApiKey = '';
  static String _openrouterApiKey = '';
  static String _cliproxyApiKey = '';
  static bool _initialized = false;

  /// 应用启动时调用，从 assets/secrets.json 加载密钥
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final json = await rootBundle.loadString('assets/secrets.json');
      final map = jsonDecode(json) as Map<String, dynamic>;
      _zhipuApiKey = map['zhipu_api_key'] as String? ?? '';
      _openrouterApiKey = map['openrouter_api_key'] as String? ?? '';
      _cliproxyApiKey = map['cliproxy_api_key'] as String? ?? '';
      _initialized = true;
      debugPrint('[AIConfig] 密钥已从 secrets.json 加载');
    } catch (e) {
      debugPrint('[AIConfig] 加载 secrets.json 失败: $e');
      _initialized = true;
    }
  }

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
