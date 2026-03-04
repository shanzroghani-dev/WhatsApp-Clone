// Example: How to use RecordingStateNotifier in widgets after Phase 2 migration

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';

/// Example 1: Display recording duration using Consumer
class RecordingDurationDisplay extends StatelessWidget {
  const RecordingDurationDisplay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<RecordingStateNotifier>(
      builder: (context, recordingState, child) {
        if (!recordingState.isRecording) {
          return const SizedBox.shrink();
        }
        return Text(
          'Recording: ${_formatDuration(recordingState.recordingDuration)}',
          style: const TextStyle(color: Colors.red),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Example 2: Update recording state (from gesture handler)
void onVoiceLongPressStart(
  BuildContext context,
  LongPressStartDetails details,
) {
  final recordingState =
      Provider.of<RecordingStateNotifier>(context, listen: false);
  recordingState.setRecordingCancelTriggered(false);
  recordingState.setRecordingSlideOffset(0);
  // Start recording...
}

/// Example 3: Start recording with provider
Future<void> startRecording(BuildContext context) async {
  final recordingState =
      Provider.of<RecordingStateNotifier>(context, listen: false);

  // Start recording logic here...

  recordingState.setIsRecording(true);
  recordingState.setRecordingDuration(Duration.zero);
}

/// Example 4: Stop recording with provider
Future<void> stopRecording(BuildContext context) async {
  final recordingState =
      Provider.of<RecordingStateNotifier>(context, listen: false);

  // Stop recording logic here...

  recordingState.setIsRecording(false);
  recordingState.reset();
}

/// Example 5: Listen to recording state in initState
class RecordingListener extends StatefulWidget {
  const RecordingListener({Key? key}) : super(key: key);

  @override
  State<RecordingListener> createState() => _RecordingListenerState();
}

class _RecordingListenerState extends State<RecordingListener> {
  @override
  void initState() {
    super.initState();
    // Listen to recording state changes
    Future.microtask(() {
      final recordingState =
          Provider.of<RecordingStateNotifier>(context, listen: false);
      // You can add a custom listener here if needed
      recordingState.addListener(_onRecordingChanged);
    });
  }

  void _onRecordingChanged() {
    // React to recording state changes
    print('Recording state changed!');
  }

  @override
  void dispose() {
    final recordingState =
        Provider.of<RecordingStateNotifier>(context, listen: false);
    recordingState.removeListener(_onRecordingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
