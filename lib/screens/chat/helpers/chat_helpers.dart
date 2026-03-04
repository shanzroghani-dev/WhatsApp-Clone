import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:whatsapp_clone/utils/date_time_utils.dart';

class ChatHelpers {
  /// Sanitizes file names by removing special characters
  static String sanitizedFileName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  /// Generates a video thumbnail
  static Future<Uint8List?> generateVideoThumbnail(String videoPath) async {
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 256,
        maxWidth: 256,
        quality: 75,
      );
      return uint8list;
    } catch (_) {
      return null;
    }
  }

  /// Formats date separators for chat messages
  static String formatDateSeparator(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(messageDate).inDays < 7) {
      return DateTimeUtils.formatLastSeen(date).split(' ')[0]; // Day name
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Checks if a date separator should be shown between messages
  static bool shouldShowDateSeparator(int currentTimestamp, int nextTimestamp) {
    final currentDateTime = DateTime.fromMillisecondsSinceEpoch(currentTimestamp);
    final nextDateTime = DateTime.fromMillisecondsSinceEpoch(nextTimestamp);

    final currentDate = DateTime(
      currentDateTime.year,
      currentDateTime.month,
      currentDateTime.day,
    );
    final nextDate = DateTime(
      nextDateTime.year,
      nextDateTime.month,
      nextDateTime.day,
    );

    return currentDate != nextDate;
  }

  /// Formats duration for video player display
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
