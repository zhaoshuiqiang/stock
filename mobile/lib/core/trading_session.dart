class TradingSession {
  /// Check if current time is within A-share trading hours
  /// Trading hours: 9:30-11:30, 13:00-15:00 on weekdays
  static bool isInTradingSession() {
    final now = DateTime.now();

    // Not trading on weekends
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }

    final hour = now.hour;
    final minute = now.minute;
    final totalMinutes = hour * 60 + minute;

    // Morning session: 9:30 - 11:30
    const morningStart = 9 * 60 + 30;
    const morningEnd = 11 * 60 + 30;

    // Afternoon session: 13:00 - 15:00
    const afternoonStart = 13 * 60;
    const afternoonEnd = 15 * 60;

    return (totalMinutes >= morningStart && totalMinutes <= morningEnd) ||
        (totalMinutes >= afternoonStart && totalMinutes <= afternoonEnd);
  }

  /// Get trading session status description
  static String getSessionStatus() {
    final now = DateTime.now();

    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return '休市';
    }

    final hour = now.hour;
    final minute = now.minute;
    final totalMinutes = hour * 60 + minute;

    const morningStart = 9 * 60 + 30;
    const morningEnd = 11 * 60 + 30;
    const afternoonStart = 13 * 60;
    const afternoonEnd = 15 * 60;

    if (totalMinutes < morningStart) {
      return '盘前';
    } else if (totalMinutes <= morningEnd) {
      return '交易中';
    } else if (totalMinutes < afternoonStart) {
      return '午休';
    } else if (totalMinutes <= afternoonEnd) {
      return '交易中';
    } else {
      return '盘后';
    }
  }

  /// Check if market is closed for the day
  static bool isMarketClosed() {
    final now = DateTime.now();

    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return true;
    }

    final totalMinutes = now.hour * 60 + now.minute;
    return totalMinutes > 15 * 60;
  }
}
