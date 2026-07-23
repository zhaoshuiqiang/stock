import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../analysis/ai_layer.dart';

class AIConfig {
  static const bool enableAIEnhancement = true;
  static const AIProvider defaultProvider = AIProvider.zhipu;
  static const String cloudFunctionProxy = '';
  static const int maxDebateRounds = 2;
  static const double aiConfidenceWeight = 0.3;

  // API 密钥不再随 APK 打包（assets/secrets.json 已从 pubspec 资产声明移除）。
  // 运行时由用户在“设置 - API 密钥”中填入，仅保存在本机 SharedPreferences；
  // 也可通过环境变量注入（桌面/测试）。以下为 SharedPreferences 的键名。
  static const String prefKeyZhipu = 'ai_key_zhipu';
  static const String prefKeyOpenrouter = 'ai_key_openrouter';
  static const String prefKeyCliproxy = 'ai_key_cliproxy';

  // 运行时缓存（应用启动时从 SharedPreferences 加载）
  static String _zhipuApiKey = '';
  static String _openrouterApiKey = '';
  static String _cliproxyApiKey = '';
  static bool _initialized = false;

  /// 应用启动时调用，从本地配置（SharedPreferences）加载用户填入的密钥。
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _zhipuApiKey = prefs.getString(prefKeyZhipu) ?? '';
      _openrouterApiKey = prefs.getString(prefKeyOpenrouter) ?? '';
      _cliproxyApiKey = prefs.getString(prefKeyCliproxy) ?? '';
      _initialized = true;
      debugPrint('[AIConfig] 密钥已从本地配置加载');
    } catch (e) {
      debugPrint('[AIConfig] 加载本地密钥配置失败: $e');
      _initialized = true;
    }
  }

  static String _prefKeyForProvider(AIProvider provider) {
    switch (provider) {
      case AIProvider.zhipu:
        return prefKeyZhipu;
      case AIProvider.openrouter:
        return prefKeyOpenrouter;
      case AIProvider.cliproxyapi:
        return prefKeyCliproxy;
    }
  }

  /// 保存用户填入的密钥（运行时注入）并同步内存缓存；传入空串则清除。
  static Future<void> setApiKeyForProvider(
      AIProvider provider, String key) async {
    final trimmed = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(_prefKeyForProvider(provider));
      } else {
        await prefs.setString(_prefKeyForProvider(provider), trimmed);
      }
    } catch (e) {
      debugPrint('[AIConfig] 保存密钥失败: $e');
    }
    switch (provider) {
      case AIProvider.zhipu:
        _zhipuApiKey = trimmed;
        break;
      case AIProvider.openrouter:
        _openrouterApiKey = trimmed;
        break;
      case AIProvider.cliproxyapi:
        _cliproxyApiKey = trimmed;
        break;
    }
  }

  /// 是否已配置某 provider 的密钥（仅用于 UI 状态展示，不回显明文）。
  static bool hasKeyForProvider(AIProvider provider) =>
      getApiKeyForProvider(provider).isNotEmpty;

  static String getApiKeyForProvider(AIProvider provider) {
    // 优先环境变量（桌面/测试注入），其次运行时本地配置。
    switch (provider) {
      case AIProvider.zhipu:
        final env = Platform.environment['GLM_API_KEY'];
        return (env != null && env.isNotEmpty) ? env : _zhipuApiKey;
      case AIProvider.openrouter:
        final env = Platform.environment['ANTHROPIC_AUTH_TOKEN'];
        return (env != null && env.isNotEmpty) ? env : _openrouterApiKey;
      case AIProvider.cliproxyapi:
        final env = Platform.environment['CLIPROXY_API_KEY'];
        return (env != null && env.isNotEmpty) ? env : _cliproxyApiKey;
    }
  }

  static bool get useCloudProxy => cloudFunctionProxy.isNotEmpty;

  static String get apiEndpoint => defaultProvider.endpoint;

  static String get defaultModel => defaultProvider.defaultModel;
}
