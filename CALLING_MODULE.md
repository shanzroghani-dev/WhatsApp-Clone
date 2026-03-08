# Voice & Video Calling Module

Complete implementation of 1-on-1 voice and video calling using **Agora SDK**.

## Features

✅ **1-on-1 Voice Calls** - High-quality audio calling  
✅ **1-on-1 Video Calls** - HD video calling  
✅ **Call History** - Track all incoming/outgoing calls  
✅ **Call Controls** - Mute/unmute, video on/off, speaker phone  
✅ **Incoming Call Notifications** - Real-time ringing with accept/reject  
✅ **Call Duration Tracking** - Live timer during calls  
✅ **Firebase Integration** - Signaling via Firestore & Real-time Database  

## Architecture

### Core Services

**`lib/core/agora_service.dart`** - Agora SDK wrapper
- Initialize RTC engine
- Join/leave channels
- Audio/video toggle controls
- Camera switching
- Speaker management

**`lib/chat/call_service.dart`** - Call signaling & history
- Initiate calls (signals via Firebase)
- Accept/reject calls
- End calls (tracks duration)
- Retrieve call history
- Real-time call status updates

### State Management

**`lib/providers/call_provider.dart`** - Call state notifier
- `CallStateNotifier` - Active call state
- `IncomingCallNotifier` - Incoming call handling
- Integrated with Provider pattern

### Models

**`lib/models/call_model.dart`** - Call data structure
- Call ID, initiator, receiver
- Timestamps (initiated, answered, ended)
- Call type (voice/video), status, duration
- End reason tracking

### UI Screens

**`lib/screens/call/incoming_call_screen.dart`** - Incoming call UI
- Caller profile & info
- Pulsing accept/reject buttons
- Call type badge (Voice/Video)

**`lib/screens/call/in_call_screen.dart`** - Active call UI
- Video preview (video calls)
- Profile image (audio calls)
- Real-time call duration
- Controls: Mute, Video, Speaker, End Call
- Full-screen option for video

**`lib/screens/call/call_history_screen.dart`** - Call history
- List of all calls (missed, incoming, outgoing)
- Call duration & timestamp
- Status indicators with colors
- Tap to call user again

## Setup

### 1. Install Dependencies

```bash
flutter pub get
```

Dependencies added:
- `agora_rtc_engine: ^6.2.4` (Core Agora SDK)
- `permission_handler: ^12.0.1` (Runtime permissions)

### 2. Get Agora App ID

1. Create account at [agora.io](https://agora.io)
2. Get your **App ID** from Agora Console
3. Generate **App Certificate** (recommended for production)

### 3. Configure Agora

Update `lib/core/agora_service.dart`:

```dart
static const String agoraAppId = 'YOUR_AGORA_APP_ID';
```

### 4. Android Permissions

Add to `android/app/build.gradle`:

```gradle
android {
  compileSdkVersion 33
  minSdkVersion 21
}
```

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```

### 5. iOS Permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for calls</string>
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
```

## Integration with Chat

### 1. Add Call Buttons to Chat Screen

In your chat screen, add voice/video call buttons:

```dart
// Example in chat_screen.dart header
IconButton(
  icon: const Icon(Icons.call),
  onPressed: () => _initiateCall('voice'),
),
IconButton(
  icon: const Icon(Icons.videocam),
  onPressed: () => _initiateCall('video'),
),
```

### 2. Implement Call Initiation

```dart
Future<void> _initiateCall(String callType) async {
  try {
    final callModel = await CallService.initiateCall(
      initiatorId: currentUser.uid,
      initiatorName: currentUser.displayName,
      initiatorProfilePic: currentUser.profilePic,
      receiverId: peerUser.uid,
      receiverName: peerUser.displayName,
      receiverProfilePic: peerUser.profilePic,
      callType: callType, // 'voice' or 'video'
      agoraToken: token, // Get from your backend
    );
    
    // Navigate to in-call screen
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => InCallScreen(
          callModel: callModel,
          agoraService: agoraService,
          onEndCall: _endCall,
          remoteUid: callModel.initiatorId.hashCode % 100000,
        ),
      ));
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to initiate call: $e')),
    );
  }
}
```

### 3. Handle Incoming Calls

Listen for incoming calls in your home/root screen:

```dart
StreamBuilder<CallModel>(
  stream: CallService.listenForIncomingCalls(currentUser.uid),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final incomingCall = snapshot.data!;
      return IncomingCallScreen(
        incomingCall: incomingCall,
        onAccept: () {
          // Handle accept
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => InCallScreen(
              callModel: incomingCall,
              agoraService: agoraService,
              onEndCall: _endCall,
              remoteUid: incomingCall.initiatorId.hashCode % 100000,
            ),
          ));
        },
        onReject: () {
          CallService.rejectCall(
            callId: incomingCall.callId,
            initiatorId: incomingCall.initiatorId,
          );
        },
      );
    }
    return SizedBox.shrink();
  },
)
```

## Firebase Rules

Add to `database.rules.json`:

```json
{
  "rules": {
    "active_calls": {
      "$callId": {
        ".read": "true",
        ".write": "auth != null"
      }
    }
  }
}
```

Add to Firestore:

```
Collection: calls
- callId (string)
- initiatorId (string)
- receiverId (string)
- status (ringing|active|ended)
- callType (voice|video)
```

## Agora Token Generation

For production, generate tokens on your backend:

```javascript
// Cloud Function example
const AgoraTokenGenerator = require('agora-token').RtcTokenBuilder;

exports.generateAgoraToken = functions.https.onCall(async (data, context) => {
  const appId = process.env.AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE;
  
  const tokenBuilder = new AgoraTokenGenerator();
  const token = tokenBuilder
    .buildTokenWithUid(appId, appCertificate, data.channel, data.uid, AgoraTokenGenerator.RolePublisher, 3600)
    .build();
    
  return { token };
});
```

## Testing

### Voice Call Flow
1. User A initiates call → `CallService.initiateCall()`
2. Call saved to Firestore with status "ringing"
3. User B receives notification → `listenForIncomingCalls()`
4. User B sees incoming call screen
5. User B taps accept → `CallService.acceptCall()`
6. Both users join Agora channel
7. Either taps end → `CallService.endCall()`
8. Call saved to history with duration

### Video Call Flow
- Same as voice but: `callType='video'` and video UI shown

## Troubleshooting

**No incoming call notification:**
- Check Firestore rules allow reads
- Verify stream listener is active

**Can't hear/see video:**
- Check permissions granted
- Verify Agora channel name matches
- Confirm token is valid

**App crashes on join:**
- Check Agora App ID is set
- Verify minSdkVersion >= 21 (Android)
- Check permissions in AndroidManifest.xml

## TODO / Production Checklist

- [ ] Add Agora token generation on backend
- [ ] Implement call notifications via FCM
- [ ] Add call ringtone audio
- [ ] Handle app backgrounding (keep call active)
- [ ] Add call recording capability
- [ ] Implement do-not-disturb mode integration
- [ ] Add video quality settings
- [ ] Implement retry logic on connection loss
- [ ] Add call quality stats display
- [ ] Implement group calling (future)

## Files Created

```
lib/
  models/call_model.dart
  core/agora_service.dart
  chat/call_service.dart
  providers/call_provider.dart
  screens/call/
    incoming_call_screen.dart
    in_call_screen.dart
    call_history_screen.dart
```

## Dependencies Added

```yaml
pubspec.yaml:
  agora_uikit: ^1.3.2
  agora_rtc_engine: ^6.2.4
  permission_handler: ^11.4.4
```
