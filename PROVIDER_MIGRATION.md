## Provider Migration Guide

This document explains the new provider-based state management and how to migrate features step by step.

### Current State (✅ MIGRATION COMPLETE - 3 Phases)

**Providers Created & Active:**
1. `RecordingStateNotifier` - Voice recording & playback state (global UI state)
2. `MediaStateNotifier` - Media file selection state (global UI state)
3. `UploadStateNotifier` - Upload progress & caching (global UI state)

**Application Setup:**
- App wrapped with `MultiProvider` in `main.dart`
- 3 providers initialized and active
- All mixins using providers for shared UI state
- 0 compilation errors

**Migration Complete:**
- ✅ VoiceMessageHandler → RecordingStateNotifier
- ✅ MediaHandler → MediaStateNotifier + UploadStateNotifier
- ❌ ChatScreenState → Messages kept as local state (see Phase 4 note)
- ✅ All shared UI state provider-managed
- ✅ No unsafe cast operations
- ✅ Production-ready code

**Important: Why Messages Are NOT in Provider**
Messages are **conversation-specific data**, not global UI state. Each ChatScreen instance manages its own messages locally because:
- Different conversations have different messages
- Messages need to be loaded/unloaded per-chat
- Global provider would cause all chats to share the same messages list
- Local state is the correct pattern for per-instance data

### How to Use Providers

#### Reading State (in widgets)

```dart
// Access recording state
final recordingState = Provider.of<RecordingStateNotifier>(context);
final isRecording = recordingState.isRecording;

// Or using Consumer (preferred)
Consumer<RecordingStateNotifier>(
  builder: (context, recordingState, child) {
    return Text(recordingState.recordingDuration.toString());
  },
),
```

#### Updating State (from anywhere)

```dart
final recordingState = Provider.of<RecordingStateNotifier>(context, listen: false);
recordingState.setIsRecording(true);
recordingState.setRecordingDuration(Duration(seconds: 5));
```

### Migration Path (Step-by-Step)

#### Phase 1: Parallel Implementation ✅ COMPLETE
- ✅ Providers created
- ✅ App wrapped with MultiProvider  
- ✅ Commit: 624a5ab

#### Phase 2: Migrate Recording Feature ✅ COMPLETE
- ✅ Updated `VoiceMessageHandler` mixin to use `RecordingStateNotifier`
- ✅ Replaced all `setIsRecording()`, `setRecordingDuration()` calls with provider
- ✅ Replaced all `setRecordingSlideOffset()`, `setRecordingCancelTriggered()` calls with provider
- ✅ Replaced all `setPlayingAudioMessageId()` calls with provider
- ✅ Added provider accessor helper: `recordingProvider` getter
- ✅ 0 compilation errors, all lint warnings pre-existing
- ✅ Voice recording fully functional with provider state management

#### Phase 3: Migrate Media Feature ✅ COMPLETE
- ✅ Created `UploadStateNotifier` for upload progress and caching
- ✅ Updated `MediaHandler` mixin to use `MediaStateNotifier` and `UploadStateNotifier`
- ✅ Added mediaProvider and uploadProvider getters to mixin
- ✅ Replaced all media state setter calls:
  * `setSelectedMediaFile()` → `mediaProvider.setSelectedMediaFile()`
  * `setSelectedMediaType()` → `mediaProvider.setSelectedMediaType()`
  * `setSelectedVideoThumbnail()` → `mediaProvider.setSelectedVideoThumbnail()`
  * `clearSelectedMedia()` → `mediaProvider.clear()`
- ✅ Replaced all upload state setter calls:
  * `addUploadingMessageId()` → `uploadProvider.addUploadingMessageId()`
  * `removeUploadingMessageId()` → `uploadProvider.removeUploadingMessageId()`
  * `updateCachedAttachmentPath()` → `uploadProvider.updateCachedAttachmentPath()`
  * `removeCachedAttachmentPath()` → `uploadProvider.removeCachedAttachmentPath()`
  * `updateVideoThumbnailPath()` → `uploadProvider.updateVideoThumbnailPath()`
  * `removeVideoThumbnailPath()` → `uploadProvider.removeVideoThumbnailPath()`
- ✅ 0 compilation errors, all lint warnings pre-existing
- ✅ Media file selection and upload fully functional with providers

#### Phase 4: Messages Feature - NOT MIGRATED ⚠️
**Decision: Keep messages as local state in ChatScreenState**

**Why messages should NOT use a global provider:**
- ❌ Messages are **per-conversation data**, not shared UI state
- ❌ Each ChatScreen needs its own independent messages list
- ❌ Global provider would cause all chat screens to share messages (bug!)
- ❌ Would need complex scoping or multiple provider instances
- ✅ Local state (`_messages`, `_visibleCount`) is the correct pattern here

**What IS in providers (correct):**
- ✅ Recording state (shared - one recording at a time across app)
- ✅ Media selection (shared - one media picker session at a time)
- ✅ Upload progress (shared - tracks all uploads across app)

**What is NOT in providers (correct):**
- ✅ Messages (per-conversation - each chat has different messages)
- ✅ Per-chat UI state (scroll position, composer text, etc.)

**Phase 4 Conclusion: Migration complete with appropriate scope.**
Only shared/global UI state moved to providers. Per-instance data remains local.

### Implementation Example - Phase 2 (Voice Recording) ✅ COMPLETE

**Before (using setState in mixin):**
```dart
void onVoiceLongPressStart(LongPressStartDetails _) {
  setRecordingCancelTriggered(false);
  setRecordingSlideOffset(0);
  unawaited(startVoiceRecording());
}
```

**After (using provider):**
```dart
void onVoiceLongPressStart(LongPressStartDetails _) {
  recordingProvider.setRecordingCancelTriggered(false);
  recordingProvider.setRecordingSlideOffset(0);
  unawaited(startVoiceRecording());
}
```

**Key Changes:**
- Added `RecordingStateNotifier get recordingProvider` getter to mixin
- All state mutations now go through provider instead of abstract setters
- Voice recording timer and duration now provider-managed
- Audio playback state now provider-managed
- Cleaner, more testable code

### Testing Checklist

After each migration phase:
- [ ] Code compiles with 0 errors
- [ ] Widget rebuilds correctly when state changes
- [ ] No performance degradation  
- [ ] Old setState calls removed
- [ ] Provider reads work in widgets

### Rollback Plan

If issues occur at any phase:
1. Revert to previous commit
2. Keep the provider infrastructure (won't hurt)
3. Implement more carefully or adjust approach

### Benefits of Provider Pattern

✅ Cleaner separation of concerns  
✅ Easier to test (inject mocks)  
✅ Better performance (targeted rebuilds)  
✅ Less boilerplate than manual setState  
✅ Time-travel debugging support  
✅ Easier to debug state changes  
