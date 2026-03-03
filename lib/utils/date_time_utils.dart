/// Date and time utility functions
class DateTimeUtils {
  /// Format milliseconds timestamp to readable time (HH:MM)
  static String formatTime(int milliseconds) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format milliseconds timestamp to readable date (MMM DD)
  static String formatDate(int milliseconds) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}';
  }

  /// Format milliseconds timestamp to readable date & time (MMM DD, HH:MM)
  static String formatDateTime(int milliseconds) {
    final date = formatDate(milliseconds);
    final time = formatTime(milliseconds);
    return '$date, $time';
  }

  /// Check if two timestamps are on the same day
  static bool isSameDay(int ms1, int ms2) {
    final date1 = DateTime.fromMillisecondsSinceEpoch(ms1);
    final date2 = DateTime.fromMillisecondsSinceEpoch(ms2);
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Get timestamp for start of today
  static int getTodayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch;
  }

  /// Get timestamp for end of today
  static int getTodayEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59)
        .millisecondsSinceEpoch;
  }

  /// Get timestamp for 24 hours ago
  static int get24hAgo() {
    return DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
  }

  /// Check if timestamp is older than 24 hours
  static bool isOlderThan24h(int milliseconds) {
    final hoursSince = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(milliseconds))
        .inHours;
    return hoursSince > 24;
  }

  /// Format milliseconds as relative time (e.g., "2 minutes ago", "3 hours ago")
  static String formatRelativeTime(int milliseconds) {
    final now = DateTime.now();
    final messageTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final difference = now.difference(messageTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else {
      return formatDate(milliseconds);
    }
  }

  /// Format last seen DateTime as relative time (e.g., "2 minutes ago", "today at 14:30")
  static String formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes minute${minutes > 1 ? 's' : ''} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days day${days > 1 ? 's' : ''} ago';
    } else {
      return formatDate(lastSeen.millisecondsSinceEpoch);
    }
  }
}
