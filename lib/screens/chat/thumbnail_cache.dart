import 'dart:io';
import 'dart:typed_data';

/// Manages video thumbnail caching for chat messages
class ThumbnailCacheManager {
  static const String _cacheDir = 'app_flutter/chat_media_cache';
  static const String _thumbnailSuffix = '_thumbnail.jpg';

  /// Initialize cache directory
  static Future<void> initialize() async {
    try {
      final cacheDir = Directory(_cacheDir);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
    } catch (_) {
      // Cache initialization is non-critical
    }
  }

  /// Save thumbnail to disk
  static Future<bool> saveThumbnail({
    required String messageId,
    required Uint8List thumbnailBytes,
  }) async {
    try {
      final cacheDir = Directory(_cacheDir);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final filePath = '$_cacheDir/$messageId$_thumbnailSuffix';
      final file = File(filePath);
      await file.writeAsBytes(thumbnailBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get thumbnail from disk
  static Future<Uint8List?> getThumbnail(String messageId) async {
    try {
      final filePath = '$_cacheDir/$messageId$_thumbnailSuffix';
      final file = File(filePath);

      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Check if thumbnail exists
  static Future<bool> thumbnailExists(String messageId) async {
    try {
      final filePath = '$_cacheDir/$messageId$_thumbnailSuffix';
      final file = File(filePath);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Delete thumbnail
  static Future<bool> deleteThumbnail(String messageId) async {
    try {
      final filePath = '$_cacheDir/$messageId$_thumbnailSuffix';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Delete all thumbnails (clear cache)
  static Future<bool> clearAllThumbnails() async {
    try {
      final cacheDir = Directory(_cacheDir);
      if (await cacheDir.exists()) {
        final files = cacheDir.listSync();
        for (var file in files) {
          if (file is File && file.path.endsWith(_thumbnailSuffix)) {
            await file.delete();
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rename thumbnail from temp ID to real message ID
  static Future<bool> renameThumbnail({
    required String tempMessageId,
    required String realMessageId,
  }) async {
    try {
      final tempFilePath = '$_cacheDir/$tempMessageId$_thumbnailSuffix';
      final realFilePath = '$_cacheDir/$realMessageId$_thumbnailSuffix';

      final tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        await tempFile.rename(realFilePath);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get cache directory size in bytes
  static Future<int> getCacheSizeBytes() async {
    try {
      final cacheDir = Directory(_cacheDir);
      if (!await cacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      final files = cacheDir.listSync();
      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
      return totalSize;
    } catch (_) {
      return 0;
    }
  }

  /// Get list of cached message IDs
  static Future<List<String>> getCachedMessageIds() async {
    try {
      final cacheDir = Directory(_cacheDir);
      if (!await cacheDir.exists()) {
        return [];
      }

      final messageIds = <String>[];
      final files = cacheDir.listSync();
      for (var file in files) {
        if (file is File && file.path.endsWith(_thumbnailSuffix)) {
          final fileName = file.path.split('/').last;
          final messageId = fileName.replaceAll(_thumbnailSuffix, '');
          messageIds.add(messageId);
        }
      }
      return messageIds;
    } catch (_) {
      return [];
    }
  }

  /// Cleanup old thumbnails (older than specified days)
  static Future<bool> cleanupOldThumbnails({int days = 30}) async {
    try {
      final cacheDir = Directory(_cacheDir);
      if (!await cacheDir.exists()) {
        return true;
      }

      final now = DateTime.now();
      final cutoffTime = now.subtract(Duration(days: days));

      final files = cacheDir.listSync();
      for (var file in files) {
        if (file is File && file.path.endsWith(_thumbnailSuffix)) {
          final lastModified = file.lastModifiedSync();
          if (lastModified.isBefore(cutoffTime)) {
            await file.delete();
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
