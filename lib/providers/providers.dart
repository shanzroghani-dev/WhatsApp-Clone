import 'package:provider/provider.dart';
import 'package:whatsapp_clone/providers/media_provider.dart';
import 'package:whatsapp_clone/providers/messages_provider.dart';
import 'package:whatsapp_clone/providers/recording_provider.dart';
import 'package:whatsapp_clone/providers/upload_provider.dart';

/// Central registry for all app providers
/// Use this to wrap the MaterialApp in main.dart
List<ChangeNotifierProvider> getAppProviders() {
  return [
    ChangeNotifierProvider(create: (_) => RecordingStateNotifier()),
    ChangeNotifierProvider(create: (_) => MediaStateNotifier()),
    ChangeNotifierProvider(create: (_) => UploadStateNotifier()),
    ChangeNotifierProvider(create: (_) => MessagesStateNotifier()),
  ];
}
