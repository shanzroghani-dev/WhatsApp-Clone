import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Media attachment state notifier
class MediaStateNotifier extends ChangeNotifier {
  File? _selectedMediaFile;
  String? _selectedMediaType;
  Uint8List? _selectedVideoThumbnail;

  // Getters
  File? get selectedMediaFile => _selectedMediaFile;
  String? get selectedMediaType => _selectedMediaType;
  Uint8List? get selectedVideoThumbnail => _selectedVideoThumbnail;

  // Setters
  void setSelectedMediaFile(File? file) {
    _selectedMediaFile = file;
    notifyListeners();
  }

  void setSelectedMediaType(String? type) {
    _selectedMediaType = type;
    notifyListeners();
  }

  void setSelectedVideoThumbnail(Uint8List? thumbnail) {
    _selectedVideoThumbnail = thumbnail;
    notifyListeners();
  }

  void clear() {
    _selectedMediaFile = null;
    _selectedMediaType = null;
    _selectedVideoThumbnail = null;
    notifyListeners();
  }
}
