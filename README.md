# WhatsApp Clone with Encrypted Local + Cloud Storage

A Flutter app with **username-based authentication**, **encrypted local storage**, and **optional Firebase Realtime DB sync**. Messages are encrypted locally, auto-delete after 24 hours, and can sync to cloud.

## Features

✅ **Hybrid Architecture**: Local encrypted DB + optional Firebase cloud sync
✅ **Username-based auth** via Firebase Auth (email/password) + Firestore profiles  
✅ **AES-256 encrypted messages** (sqflite with secure key storage)  
✅ **Permanent user data** (Firestore: usernames, emails, profiles)  
✅ **Temporary messages** (Realtime DB: 24h auto-delete via Cloud Function)  
✅ **Offline access** (messages cached locally, work without internet)  
✅ **E2E encryption ready**: Server stores only ciphertext + IV  

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed permanent vs temporary data breakdown.  

---

## Data Storage Layers (Permanent vs Temporary)

### **Permanent Data (Firestore)**
- User profiles: username, email, display name, avatar
- Account metadata: creation timestamp, last updated
- **Why?** Accounts require persistent identity for login, friend discovery, and profile lookup

### **Temporary Data (Realtime Database)**
- Messages: encrypted ciphertext + IV
- **TTL**: Auto-deleted after 24 hours by Cloud Function
- **Why?** Privacy, storage efficiency, E2E encryption (server cannot read plaintext)

### **Local Cache (SQLite on Device)**
- Encrypted message copies persist on-device
- Can stay >24h if user wants (offline access)
- **Why?** Offline-first design, user controls local data lifetime

**See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed data flow diagrams.**

---

The app works **fully offline** without Firebase setup:

```bash
flutter pub get
flutter run
```

**Test flow:**
1. Create account with username + password
2. Create second account
3. Send messages (encrypted locally, auto-delete after 24h)

---

## Firebase Setup (Optional Cloud Sync)

To enable cloud sync, follow these steps:

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click **Create Project** → name it `whatsapp-clone`
3. Enable **Realtime Database** and **Authentication**

### Step 2: Configure Android

1. In Firebase Console, under Project Settings → **Android**, register your app:
   - Package name: `com.example.whatsapp_clone` (verify in `android/app/build.gradle`)
   - SHA-1: Run `cd android && ./gradlew signingReport` → copy SHA-1 from **debugAndroidDebugKey**

2. Download `google-services.json` from Firebase Console

3. Place it here:
   ```
   whatsapp_clone/android/app/google-services.json
   ```

4. Update `android/build.gradle`:
   ```gradle
   dependencies {
     classpath 'com.google.gms:google-services:4.3.15'
   }
   ```

5. Update `android/app/build.gradle`:
   ```gradle
   plugins {
     id 'com.android.application'
     id 'com.google.gms.google-services'  // Add this line
   }
   ```

### Step 3: Configure iOS

1. In Firebase Console, register iOS app:
   - Bundle ID: `com.example.whatsappClone` (from `ios/Runner/Info.plist`)

2. Download `GoogleService-Info.plist` from Firebase Console

3. Open `ios/Runner.xcworkspace` in Xcode:
   ```bash
   cd ios
   open Runner.xcworkspace
   ```

4. Drag `GoogleService-Info.plist` into Xcode (under Runner folder)
   - Check "Copy items if needed"
   - Select "Runner" as target

5. Update `ios/Podfile` (uncomment Firebase sections):
   ```ruby
   post_install do |installer|
     installer.pods_project.targets.each do |target|
       flutter_additional_ios_build_settings(target)
       target.build_configurations.each do |config|
         config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
           '$(inherited)',
           'FIREBASE_ANALYTICS_COLLECTION_ENABLED=1',
         ]
       end
     end
   end
   ```

### Step 4: Configure Firestore Security Rules

In Firebase Console → **Firestore** → **Rules** tab, set (permanent user data):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection (permanent profiles)
    match /users/{uid} {
      allow read: if request.auth != null;
      allow create: if request.auth.uid == uid && 
                       request.resource.data.username is string &&
                       request.resource.data.email is string;
      allow update: if request.auth.uid == uid;
    }
  }
}
```

### Step 5: Configure Realtime Database Security Rules

In Firebase Console → **Realtime Database** → **Rules** tab, set (temporary messages):

```json
{
  "rules": {
    "usernames": {
      "$username": {
        ".read": true,
        ".write": "root.child('usernames').child($username).child('uid').val() === auth.uid"
      }
    },
    "messages": {
      "$receiverUID": {
        ".read": "$receiverUID === auth.uid",
        ".write": "auth != null",
        "$messageId": {
          ".validate": "newData.hasChildren(['senderUID', 'text', 'timestamp'])"
        }
      }
    }
  }
}
```

### Step 6: Test Firebase Integration

```bash
flutter clean
flutter pub get
flutter run
```

**Expected behavior:**
- App detects Firebase config automatically
- Login screen shows "Email + Password" instead of "Username"
- Messages sync to Firebase Realtime Database
- Messages decrypt locally and persist offline

---

## Architecture

```
┌─────────────────────────────────────────┐
│         Flutter App                     │
│  ┌──────────────┐  ┌────────────────┐  │
│  │ Local SQLite │  │ Firebase Auth  │  │
│  │  (Encrypted) │  │      + DB      │  │
│  └──────────────┘  └────────────────┘  │
│       AES-256         (Optional)        │
└─────────────────────────────────────────┘
         │                 │
         ├─ 24h TTL    ├─ Cloud Sync
         │  Cleanup    │  (if Firebase
         │  (Local)    │   enabled)
         │             │
    [Local DB]   [Realtime DB]
```

### Data Flow

1. **Register/Login**: Firebase Auth (if enabled) → Local user DB
2. **Send Message**: Encrypt locally → Save to SQLite → Sync to Realtime DB (if enabled)
3. **Receive Message**: Listen to Firebase → Decrypt locally → Show UI
4. **TTL Cleanup**: Auto-delete messages >24h old on app startup

---

## File Structure

```
lib/
  models/
    user.dart                      # User model
    message.dart                   # Message model
  services/
    storage_service.dart           # Local SQLite + AES encryption
    firebase_auth_service.dart     # Firebase Auth + Firestore user creation
    firebase_firestore_service.dart  # Firestore user profiles (permanent)
    firebase_db_service.dart       # Realtime DB message sync (temporary)
  screens/
    login.dart                     # Email login (Firebase) / username fallback
    register.dart                  # Email registration / username fallback
    chat_list.dart                 # List users for chat
    chat_screen.dart               # Chat UI + encrypted message sending
```

---

## Environment Variables (Optional)

For production, store Firebase config in `.env`:

```
FIREBASE_API_KEY=your_api_key
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_MESSAGING_SENDER_ID=your_sender_id
```

Then load in `main.dart` with `flutter_dotenv` package.

---

## Cloud Function: Auto-Delete Messages (Required for 24h TTL)

**See Firebase setup instructions above for detailed deployment steps.**

Summary:
- Deploy Cloud Function to run every 1 hour
- Deletes messages where `timestamp < (now - 24 hours)`
- Keeps server storage minimal while preserving local copies

---

## Testing

**Local Only:**
```bash
flutter test
```

**With Firebase Emulator:**
```bash
firebase emulators:start
# In another terminal:
flutter run
```

---

## Troubleshooting

### "Firebase not configured"
- App works offline with local storage only ✅
- To enable cloud: Complete Firebase Setup steps

### "Decryption error"
- Messages encrypted with device-specific AES key
- Messages don't sync between devices (security feature)
- To enable cross-device: Implement key exchange protocol

### "Username not found on login"
- Ensure user created account first
- Check Realtime Database `/usernames` if using Firebase

---

## Future Enhancements

- [ ] Push notifications (FCM)
- [ ] Asymmetric E2E encryption (per-user keypairs)
- [ ] Message read receipts
- [ ] Group chats
- [ ] Voice/video calls
- [ ] Profile pictures

---

## License

MIT
#   W h a t s A p p - C l o n e  
 