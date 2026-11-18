import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Export Date Matching Logic', () {
    bool isDateMatching(
      String? dateStr, {
      required String mode,
      DateTime? singleDate,
      DateTimeRange? customRange,
    }) {
      if (dateStr == null || dateStr.trim().isEmpty) return false;
      final parsed = DateTime.tryParse(dateStr);
      if (parsed == null) return false;
      final date = parsed.toLocal();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      switch (mode) {
        case 'Today':
          return !date.isBefore(todayStart) && !date.isAfter(todayEnd);

        case 'Yesterday':
          final yStart = todayStart.subtract(const Duration(days: 1));
          final yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59, 999);
          return !date.isBefore(yStart) && !date.isAfter(yEnd);

        case 'Last 7 Days':
          final start7 = todayStart.subtract(const Duration(days: 6));
          return !date.isBefore(start7) && !date.isAfter(todayEnd);

        case 'Last 30 Days':
          final start30 = todayStart.subtract(const Duration(days: 29));
          return !date.isBefore(start30) && !date.isAfter(todayEnd);

        case 'This Month':
          final monthStart = DateTime(now.year, now.month, 1);
          final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
          final monthEnd = nextMonth.subtract(const Duration(milliseconds: 1));
          return !date.isBefore(monthStart) && !date.isAfter(monthEnd);

        case 'Year to Date':
          final startOfYear = DateTime(now.year, 1, 1);
          return !date.isBefore(startOfYear) && !date.isAfter(todayEnd);

        case 'Single Date':
          if (singleDate == null) return true;
          return date.year == singleDate.year && date.month == singleDate.month && date.day == singleDate.day;

        case 'Custom Range':
        case 'Date Range':
          if (customRange == null) return true;
          final rStart = DateTime(customRange.start.year, customRange.start.month, customRange.start.day);
          final rEnd = DateTime(customRange.end.year, customRange.end.month, customRange.end.day, 23, 59, 59, 999);
          return !date.isBefore(rStart) && !date.isAfter(rEnd);

        case 'All Time':
        default:
          return true;
      }
    }

    test('matches Single Date precisely', () {
      final now = DateTime.now();
      final targetDate = DateTime(2026, 11, 15);
      expect(isDateMatching('2026-11-15T14:30:00Z', mode: 'Single Date', singleDate: targetDate), isTrue);
      expect(isDateMatching('2026-11-16T08:00:00Z', mode: 'Single Date', singleDate: targetDate), isFalse);
    });

    test('matches Date Range inclusively', () {
      final range = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 10),
      );
      expect(isDateMatching('2026-11-01T12:00:00Z', mode: 'Date Range', customRange: range), isTrue);
      expect(isDateMatching('2026-11-05T12:00:00Z', mode: 'Date Range', customRange: range), isTrue);
      expect(isDateMatching('2026-11-10T12:00:00Z', mode: 'Date Range', customRange: range), isTrue);
      expect(isDateMatching('2026-11-15T00:00:01Z', mode: 'Date Range', customRange: range), isFalse);
      expect(isDateMatching('2026-10-25T23:59:59Z', mode: 'Date Range', customRange: range), isFalse);
    });

    test('matches Today and Yesterday', () {
      final now = DateTime.now();
      final todayStr = now.toIso8601String();
      final yesterdayStr = now.subtract(const Duration(days: 1)).toIso8601String();
      final lastWeekStr = now.subtract(const Duration(days: 7)).toIso8601String();

      expect(isDateMatching(todayStr, mode: 'Today'), isTrue);
      expect(isDateMatching(yesterdayStr, mode: 'Today'), isFalse);

      expect(isDateMatching(yesterdayStr, mode: 'Yesterday'), isTrue);
      expect(isDateMatching(todayStr, mode: 'Yesterday'), isFalse);

      expect(isDateMatching(todayStr, mode: 'Last 7 Days'), isTrue);
      expect(isDateMatching(yesterdayStr, mode: 'Last 7 Days'), isTrue);
      expect(isDateMatching(lastWeekStr, mode: 'Last 7 Days'), isFalse);
    });

    test('handles All Time and null/invalid dates gracefully', () {
      expect(isDateMatching('2022-01-01T00:00:00Z', mode: 'All Time'), isTrue);
      expect(isDateMatching(null, mode: 'All Time'), isFalse);
      expect(isDateMatching('invalid-date', mode: 'All Time'), isFalse);
    });
  });
}
