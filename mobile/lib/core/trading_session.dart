class TradingSession {
  /// A股调休日（周末补班日）- 这些日期虽然是周末但为交易日
  /// 注意：节假日和调休日需要每年更新，请参考国务院发布的年度放假安排
  static final Set<String> _makeupDays = {
    // 2024年调休日
    '2024-02-04', // 春节调休，周日上班
    '2024-02-17', // 春节调休，周六上班
    '2024-04-07', // 清明调休，周日上班
    '2024-04-28', // 劳动节调休，周日上班
    '2024-05-11', // 劳动节调休，周六上班
    '2024-09-14', // 中秋/国庆调休，周六上班
    '2024-09-29', // 国庆调休，周日上班
    '2024-10-12', // 国庆调休，周六上班
    // 2025年调休日
    '2025-01-26', // 春节调休，周日上班
    '2025-02-08', // 春节调休，周六上班
    '2025-04-27', // 劳动节调休，周日上班
    '2025-09-28', // 国庆调休，周日上班
    '2025-10-11', // 国庆调休，周六上班
    // 2026年调休日（待国务院发布后更新）
    // '2026-02-14', // 春节调休示例
    // '2026-02-15', // 春节调休示例
  };

  /// 检查日期是否为调休日（周末补班，视为交易日）
  static bool _isMakeupDay(DateTime date) {
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _makeupDays.contains(key);
  }

  /// Check if current time is within A-share trading hours
  /// Trading hours: 9:30-11:30, 13:00-15:00 on weekdays
  static bool isInTradingSession() {
    final now = DateTime.now();

    // Not trading on weekends (unless it's a makeup day)
    if ((now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) &&
        !_isMakeupDay(now)) {
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
  /// 注意：节假日和调休日需要每年更新，请参考国务院发布的年度放假安排
  static bool isHoliday(DateTime date) {
    // 调休日（周末补班）不是假日，属于交易日
    if (_isMakeupDay(date)) return false;

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

    if ((now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) &&
        !_isMakeupDay(now)) {
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

    if ((now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) &&
        !_isMakeupDay(now)) {
      return true;
    }

    if (isHoliday(now)) return true;

    final totalMinutes = now.hour * 60 + now.minute;
    return totalMinutes > 15 * 60;
  }
}
