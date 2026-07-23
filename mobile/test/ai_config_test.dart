import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/core/ai_config.dart';
import 'package:stock_analyzer/analysis/ai_layer.dart';

/// Verifies the runtime key-injection path introduced in v4.18: API keys are
/// no longer bundled in assets/secrets.json but persisted to (and read from)
/// SharedPreferences via AIConfig. These tests exercise the persistence path
/// directly so they stay deterministic regardless of any env-var override.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setApiKeyForProvider persists the key to SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    await AIConfig.setApiKeyForProvider(AIProvider.cliproxyapi, 'runtime_key');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AIConfig.prefKeyCliproxy), 'runtime_key');
  });

  test('setApiKeyForProvider trims whitespace before storing', () async {
    SharedPreferences.setMockInitialValues({});
    await AIConfig.setApiKeyForProvider(AIProvider.openrouter, '  padded  ');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AIConfig.prefKeyOpenrouter), 'padded');
  });

  test('setApiKeyForProvider with blank value clears the stored key', () async {
    SharedPreferences.setMockInitialValues({
      AIConfig.prefKeyCliproxy: 'to_be_removed',
    });
    await AIConfig.setApiKeyForProvider(AIProvider.cliproxyapi, '   ');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AIConfig.prefKeyCliproxy), isNull);
  });

  test('hasKeyForProvider reflects a runtime-configured key', () async {
    SharedPreferences.setMockInitialValues({});
    await AIConfig.setApiKeyForProvider(AIProvider.cliproxyapi, 'from_prefs');

    expect(AIConfig.hasKeyForProvider(AIProvider.cliproxyapi), isTrue);
  });

  test('pref key names are stable per provider', () {
    // Guards the SharedPreferences contract used by init() and the settings UI.
    expect(AIConfig.prefKeyZhipu, 'ai_key_zhipu');
    expect(AIConfig.prefKeyOpenrouter, 'ai_key_openrouter');
    expect(AIConfig.prefKeyCliproxy, 'ai_key_cliproxy');
  });
}
