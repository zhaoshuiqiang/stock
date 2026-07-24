import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/timeshare_parser.dart';

void main() {
  group('TimeshareParser.resolveTargetDate', () {
    test('trading day keeps today, ignoring older available dates', () {
      expect(
        TimeshareParser.resolveTargetDate(
          availableDates: const ['2026-07-23', '2026-07-24'],
          todayStr: '2026-07-24',
          isTradingDay: true,
        ),
        '2026-07-24',
      );
    });

    test('trading day pre-open (only yesterday present) still targets today',
        () {
      // The caller then filters to today => empty => "no data", preserving the
      // anti-stale intent (never render yesterday mapped as today's curve).
      expect(
        TimeshareParser.resolveTargetDate(
          availableDates: const ['2026-07-23'],
          todayStr: '2026-07-24',
          isTradingDay: true,
        ),
        '2026-07-24',
      );
    });

    test('non-trading day keeps the latest available session', () {
      // Saturday 2026-07-25: the API returns Friday 2026-07-24 (and older).
      expect(
        TimeshareParser.resolveTargetDate(
          availableDates: const ['2026-07-23', '2026-07-24'],
          todayStr: '2026-07-25',
          isTradingDay: false,
        ),
        '2026-07-24',
      );
    });

    test('non-trading day with no dates falls back to today', () {
      expect(
        TimeshareParser.resolveTargetDate(
          availableDates: const <String>[],
          todayStr: '2026-07-25',
          isTradingDay: false,
        ),
        '2026-07-25',
      );
    });

    test('ignores empty date strings when picking the latest session', () {
      expect(
        TimeshareParser.resolveTargetDate(
          availableDates: const ['', '2026-07-24', ''],
          todayStr: '2026-07-25',
          isTradingDay: false,
        ),
        '2026-07-24',
      );
    });
  });
}
