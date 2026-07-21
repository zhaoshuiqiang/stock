import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/services/notification_service.dart';

/// Better Loop F2: deterministic coverage for NotificationService's
/// SharedPreferences-backed configuration contracts. The push-dispatch paths
/// depend on the flutter_local_notifications plugin and timers, so these tests
/// only exercise the plugin-free accessors (enabled flags + polling interval),
/// which encode the user-facing defaults and must not silently drift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationService service;

  setUp(() {
    // Fresh in-memory store per test (no platform channel needed).
    SharedPreferences.setMockInitialValues({});
    service = NotificationService();
  });

  test('news notifications default to disabled', () async {
    expect(await service.isEnabled(), isFalse);
  });

  test('intraday signals default to enabled', () async {
    expect(await service.isIntradayEnabled(), isTrue);
  });

  test('polling interval defaults to 15 minutes', () async {
    expect(await service.getIntervalMinutes(), 15);
  });

  test('setIntervalMinutes persists the new interval', () async {
    await service.setIntervalMinutes(30);
    expect(await service.getIntervalMinutes(), 30);
  });

  test('disabling news notifications persists the flag', () async {
    await service.setEnabled(false);
    expect(await service.isEnabled(), isFalse);
  });
}
