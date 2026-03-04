import 'package:flutter/foundation.dart';

/// Upload state notifier for media upload progress and caching
class UploadStateNotifier extends ChangeNotifier {
  final Set<String> _uploadingMessageIds = <String>{};
  final Map<String, String> _cachedAttachmentPaths = <String, String>{};
  final Map<String, String> _videoThumbnailPaths = <String, String>{};

  // Getters
  Set<String> get uploadingMessageIds => _uploadingMessageIds;
  Map<String, String> get cachedAttachmentPaths => _cachedAttachmentPaths;
  Map<String, String> get videoThumbnailPaths => _videoThumbnailPaths;

  bool isUploading(String messageId) => _uploadingMessageIds.contains(messageId);

  // Setters
  void addUploadingMessageId(String id) {
    _uploadingMessageIds.add(id);
    notifyListeners();
  }

  void removeUploadingMessageId(String id) {
    _uploadingMessageIds.remove(id);
    notifyListeners();
  }

  void updateCachedAttachmentPath(String key, String path) {
    _cachedAttachmentPaths[key] = path;
    notifyListeners();
  }

  void removeCachedAttachmentPath(String key) {
    _cachedAttachmentPaths.remove(key);
    notifyListeners();
  }

  void updateVideoThumbnailPath(String key, String path) {
    _videoThumbnailPaths[key] = path;
    notifyListeners();
  }

  void removeVideoThumbnailPath(String key) {
    _videoThumbnailPaths.remove(key);
    notifyListeners();
  }

  void clear() {
    _uploadingMessageIds.clear();
    _cachedAttachmentPaths.clear();
    _videoThumbnailPaths.clear();
    notifyListeners();
  }
}
