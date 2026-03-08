import 'package:provider/provider.dart';
import 'package:whatsapp_clone/providers/media_provider.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/theme_mode_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';

/// Central registry for all app providers
/// Use this to wrap the MaterialApp in main.dart
List<ChangeNotifierProvider> getAppProviders() {
  return [
    ChangeNotifierProvider<RecordingStateNotifier>(
      create: (_) => RecordingStateNotifier(),
    ),
    ChangeNotifierProvider<MediaStateNotifier>(
      create: (_) => MediaStateNotifier(),
    ),
    ChangeNotifierProvider<UploadStateNotifier>(
      create: (_) => UploadStateNotifier(),
    ),
    ChangeNotifierProvider<ThemeModeNotifier>(
      create: (_) => ThemeModeNotifier(),
    ),
  ];
}
