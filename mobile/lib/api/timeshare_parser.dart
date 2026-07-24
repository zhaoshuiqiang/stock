class TimesharePoint {
  final int offset;
  final double price;
  final double volume;
  final double amount;
  final double? vwap;

  const TimesharePoint({
    required this.offset,
    required this.price,
    required this.volume,
    required this.amount,
    this.vwap,
  });
}

class TimeshareParser {
  static TimesharePoint? parseEastMoneyTrendLine(String line) {
    final parts = line.split(',');
    if (parts.length < 7) return null;

    final offset = minuteOffsetFromTime(parts[0]);
    if (offset == null) return null;

    final close = _parseDouble(parts[2]);
    if (close <= 0) return null;

    return TimesharePoint(
      offset: offset,
      price: close,
      volume: _parseDouble(parts[5]),
      amount: _parseDouble(parts[6]),
      vwap: parts.length > 7 ? _parseDouble(parts[7]) : null,
    );
  }

  /// Extracts the "YYYY-MM-DD" date prefix from an EastMoney trend line
  /// ("2026-07-22 09:30,...") or a Sina `day` value ("2026-07-22 09:35:00").
  /// Returns null when no date prefix is present. Used to drop stale
  /// previous-day / multi-day rows that would otherwise be mapped by HH:MM
  /// only and rendered as today's intraday curve.
  static String? dateOf(String line) {
    final head = line.split(',').first.trim();
    final datePart = head.split(' ').first;
    return datePart.isEmpty ? null : datePart;
  }

  /// Chooses the single date whose intraday rows should be rendered from a
  /// trends payload that may span multiple days.
  ///
  /// On a trading day only [todayStr] is kept (pre-open yields an empty set so
  /// the UI shows "no data" instead of yesterday-mapped-as-today). On a
  /// non-trading day (weekend/holiday) the latest available session is kept so
  /// the last full trading day still renders instead of a blank chart.
  static String resolveTargetDate({
    required Iterable<String> availableDates,
    required String todayStr,
    required bool isTradingDay,
  }) {
    if (isTradingDay) return todayStr;
    final dates = availableDates.where((d) => d.isNotEmpty).toList()..sort();
    return dates.isEmpty ? todayStr : dates.last;
  }

  static int? minuteOffsetFromTime(String timeText) {
    final timePart = timeText.trim().split(' ').last;
    final timeParts = timePart.split(':');
    if (timeParts.length < 2) return null;
    final hour = int.tryParse(timeParts[0]) ?? -1;
    final minute = int.tryParse(timeParts[1]) ?? -1;
    if (hour < 0 || minute < 0) return null;

    final totalMinutes = hour * 60 + minute;
    const morningStart = 9 * 60 + 30;
    const morningEnd = 11 * 60 + 30;
    const afternoonStart = 13 * 60;
    const afternoonEnd = 15 * 60;

    if (totalMinutes >= morningStart && totalMinutes <= morningEnd) {
      return totalMinutes - morningStart;
    }
    if (totalMinutes >= afternoonStart && totalMinutes <= afternoonEnd) {
      return 120 + (totalMinutes - afternoonStart);
    }
    return null;
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
