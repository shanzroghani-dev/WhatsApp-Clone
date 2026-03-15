import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';

void main() {
  group('RecordingStateNotifier', () {
    test('reset clears transient recording state', () {
      final notifier = RecordingStateNotifier();

      notifier.setIsRecording(true);
      notifier.setRecordingDuration(const Duration(seconds: 9));
      notifier.setRecordingSlideOffset(18);
      notifier.setRecordingCancelTriggered(true);
      notifier.setPlayingAudioMessageId('m-1');
      notifier.reset();

      expect(notifier.isRecording, isFalse);
      expect(notifier.recordingDuration, Duration.zero);
      expect(notifier.recordingSlideOffset, 0);
      expect(notifier.recordingCancelTriggered, isFalse);
      expect(notifier.playingAudioMessageId, 'm-1');
    });

    test('setRecordingTimer stores timer reference', () {
      final notifier = RecordingStateNotifier();
      final timer = Timer(const Duration(milliseconds: 1), () {});

      notifier.setRecordingTimer(timer);

      expect(identical(notifier.recordingTimer, timer), isTrue);
      timer.cancel();
    });
  });

  group('UploadStateNotifier', () {
    test('tracks uploading IDs and cached paths', () {
      final notifier = UploadStateNotifier();

      notifier.addUploadingMessageId('m1');
      notifier.updateCachedAttachmentPath('m1', '/tmp/file.jpg');
      notifier.updateVideoThumbnailPath('m1', '/tmp/thumb.jpg');

      expect(notifier.isUploading('m1'), isTrue);
      expect(notifier.cachedAttachmentPaths['m1'], '/tmp/file.jpg');
      expect(notifier.videoThumbnailPaths['m1'], '/tmp/thumb.jpg');

      notifier.removeUploadingMessageId('m1');
      notifier.removeCachedAttachmentPath('m1');
      notifier.removeVideoThumbnailPath('m1');

      expect(notifier.isUploading('m1'), isFalse);
      expect(notifier.cachedAttachmentPaths.containsKey('m1'), isFalse);
      expect(notifier.videoThumbnailPaths.containsKey('m1'), isFalse);
    });

    test('clear removes all tracked state', () {
      final notifier = UploadStateNotifier();

      notifier.addUploadingMessageId('m2');
      notifier.updateCachedAttachmentPath('m2', '/tmp/x');
      notifier.updateVideoThumbnailPath('m2', '/tmp/y');
      notifier.clear();

      expect(notifier.uploadingMessageIds, isEmpty);
      expect(notifier.cachedAttachmentPaths, isEmpty);
      expect(notifier.videoThumbnailPaths, isEmpty);
    });
  });
}
