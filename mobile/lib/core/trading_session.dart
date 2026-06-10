class TradingSession {
  /// Check if current time is within A-share trading hours
  /// Trading hours: 9:30-11:30, 13:00-15:00 on weekdays
  static bool isInTradingSession() {
    final now = DateTime.now();

    // Not trading on weekends
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }

    // Not trading on holidays
    if (isHoliday(now)) return false;

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

  /// Check if a date is a Chinese A-share holiday
  static bool isHoliday(DateTime date) {
    final month = date.month;
    final day = date.day;
    final year = date.year;

    // Fixed holidays
    if (month == 1 && day == 1) return true; // 元旦
    if (month == 5 && day == 1) return true; // 劳动节
    if (month == 10 && day >= 1 && day <= 7) return true; // 国庆节

    // Spring Festival (approximate - varies yearly)
    if (year == 2025 && month == 1 && day >= 28 && day <= 31) return true;
    if (year == 2025 && month == 2 && day >= 1 && day <= 4) return true;
    if (year == 2026 && month == 2 && day >= 16 && day <= 23) return true;
    if (year == 2027 && month == 2 && day >= 5 && day <= 12) return true;

    // Qingming (approximate - early April)
    if (month == 4 && day >= 4 && day <= 6) return true;

    // Dragon Boat (approximate - varies)
    if (year == 2025 && month == 5 && day >= 31) return true;
    if (year == 2025 && month == 6 && day <= 2) return true;
    if (year == 2026 && month == 6 && day >= 19 && day <= 21) return true;

    // Mid-Autumn (approximate - varies)
    if (year == 2025 && month == 10 && day >= 6 && day <= 8) return true;
    if (year == 2026 && month == 9 && day >= 25 && day <= 27) return true;

    return false;
  }

  /// Get trading session status description
  static String getSessionStatus() {
    final now = DateTime.now();

    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return '休市';
    }

    if (isHoliday(now)) return '休市';

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

    if (isHoliday(now)) return true;

    final totalMinutes = now.hour * 60 + now.minute;
    return totalMinutes > 15 * 60;
  }
}
