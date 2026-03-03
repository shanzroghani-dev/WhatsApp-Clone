# Architecture: Permanent vs Temporary Data

## Data Storage Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App                              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Local SQLite (Device - Encrypted)                   │  │
│  │ ├─ Messages (cached, can persist >24h)             │  │
│  │ └─ Optional: User profiles (offline fallback)      │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↕                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Authentication & Sync                              │  │
│  │ ├─ Firebase Auth (email/password)                 │  │
│  │ ├─ Firestore (permanent user profiles)            │  │
│  │ ├─ Realtime DB (temporary messages, 24h TTL)      │  │
│  │ └─ Cloud Functions (message cleanup)              │  │
│  └──────────────────────────────────────────────────────┘  │
│                          ↕                                   │
└─────────────────────────────────────────────────────────────┘
         Firebase Cloud (Permanent & Temporary)
```

---

## What is Permanent?

### **Firestore: User Profiles** (Permanent storage)

Data that must persist for the app to function:
- Username (unique identifier for login)
- Email (account recovery, communication)
- Display name (what friends see)
- Profile picture URL (avatar)
- Account creation timestamp
- Last updated timestamp

**Firestore Structure:**
```
users/
  ├─ UID_123/
  │   ├─ uid: "UID_123"
  │   ├─ username: "alice"
  │   ├─ email: "alice@mail.com"
  │   ├─ displayName: "Alice"
  │   ├─ profilePic: "https://..."
  │   ├─ createdAt: Timestamp(2026-03-01...)
  │   └─ lastUpdated: Timestamp(2026-03-03...)
  │
  └─ UID_456/
      ├─ uid: "UID_456"
      ├─ username: "bob"
      ├─ email: "bob@mail.com"
      ├─ displayName: "Bob"
      └─ ...
```

**Why permanent?**
- Users need to create an account once and keep it
- Usernames must be unique and stay reserved
- Friends find you by username
- Profile data persists across sessions

**Access Pattern:**
```dart
// Get user by UID (after login)
final profile = await FirebaseFirestoreService.getUserProfile(uid);

// Get user by username (friend lookup)
final user = await FirebaseFirestoreService.getUserByUsername("alice");

// List all users (for chat contacts)
final allUsers = await FirebaseFirestoreService.getAllUsers(currentUID);
```

---

## What is Temporary?

### **Realtime Database: Messages** (Temporary, 24h TTL)

Messages auto-delete after 24 hours via Cloud Function.

**Realtime DB Structure:**
```
messages/
  ├─ UID_123/  (receiver's UID)
  │   ├─ messageId_1/
  │   │   ├─ senderUID: "UID_456"
  │   │   ├─ text: "encrypted_base64_string"
  │   │   ├─ iv: "encrypted_iv_base64"
  │   │   ├─ timestamp: 1740970800000  (milliseconds)
  │   │   └─ delivered: false
  │   │
  │   └─ messageId_2/
  │       ├─ senderUID: "UID_456"
  │       ├─ text: "..."
  │       └─ ...
  │
  └─ UID_456/  (another receiver)
      └─ ...
```

**Cloud Function deletes messages where:**
```
current_timestamp - message.timestamp > 24 hours (86400000 ms)
```

**Why temporary?**
- Privacy: Messages don't linger indefinitely on server
- Storage cost: Prevents database bloat
- E2E encryption: Server can't read messages anyway
- User expectation: "Messages disappear after 24h"

**Access Pattern:**
```dart
// Send message (encrypted, to Realtime DB)
await FirebaseDBService.sendMessageToCloud(
  senderUID: currentUID,
  receiverUID: peerUID,
  encryptedText: ciphertext,
  iv: iv.base64,
  timestamp: now,
);

// Listen for incoming messages (realtime stream)
FirebaseDBService.listenForMessages(currentUID).listen((messages) {
  // Decrypt locally & show in UI
});
```

---

## What is Local?

### **SQLite: Message Cache** (Device-only, indefinite but encrypted)

Messages stored **locally** on the device as an offline cache.

**Local DB Structure:**
```
messages (SQLite table)
├─ id: "messageId_1"
├─ fromId: "UID_456"
├─ toId: "UID_123"
├─ cipher: "encrypted_text_base64"
├─ iv: "encrypted_iv_base64"
└─ timestamp: 1740970800000
```

**Why local?**
- **Offline access**: User can read old messages without internet
- **Privacy**: Messages persist on device beyond 24h if user wants
- **Encryption**: AES-256 with device-specific key in secure storage
- **Optional TTL**: Can run cleanup locally (separate from cloud)

**Access Pattern:**
```dart
// Save message locally (encrypted)
await StorageService.sendMessage(message);

// Read local cache (instant, no network)
final localMessages = await StorageService.messagesBetween(fromId, toId);

// Optional: cleanup local messages >24h old
await StorageService.deleteOldLocalMessages();
```

---

## Data Flow: Send a Message

```
┌─ User types "Hello" ─────────────────────┐
│                                          │
├─ 1. Encrypt locally with AES-256       │
│    └─ Generate random IV per message    │
│                                          │
├─ 2. Save to local SQLite (encrypted)    │
│    └─ Instant, offline-capable          │
│                                          │
├─ 3. Sync to Firebase Realtime DB        │
│    └─ If online, upload encrypted msg   │
│                                          │
└─ 4.Cloud Function watches Realtime DB ──┘
   └─ After 24h: Delete message from server
   └─ Local copy remains encrypted on device
```

---

## Data Flow: Receive a Message

```
┌─ Cloud: Message arrives in Realtime DB ─┐
│                                          │
├─ 1. App listens to Realtime DB          │
│    └─ Triggers realtime listener        │
│                                          │
├─ 2. Download encrypted message          │
│                                          │
├─ 3. Decrypt locally                     │
│    └─ Use AES key from secure storage   │
│                                          │
├─ 4. Save plaintext to local SQL DB      │
│    └─ Now accessible offline            │
│                                          │
└─ 5. Show in UI ────────────────────────┘
   └─ Message visible without network
```

---

## Key Points

### **Firestore (Permanent)**
```
✅ User profiles (username, email, display name, avatar)
✅ Account metadata (created at, last login, etc.)
✅ Persists forever (or until account deletion)
✅ Indexed for quick lookups (username search)
```

### **Realtime Database (Temporary)**
```
✅ Messages stored encrypted
✅ Cloud Function auto-deletes after 24h
✅ Keeps server storage minimal
✅ Server cannot read plaintext (E2E)
```

### **Local SQLite (Offline Cache)**
```
✅ Messages cached encrypted on device
✅ Persists longer than 24h (if desired)
✅ Accessible offline (no internet needed)
✅ Optional local TTL cleanup
```

---

## Security Model

```
┌──────────────────────────────┐
│   Plaintext Message (Device) │
│     "Hello, Alice!"          │
└──────────────┬───────────────┘
               │ AES-256 Encrypt
               ↓
┌──────────────────────────────┐
│ Ciphertext (Device & Cloud)  │
│ "x8j2k@9vL2mQ#pR+sT..."     │
│ IV: "randomIVbase64"         │
└──────────────┬───────────────┘
               │
         ┌─────┴──────┐
         │            │
    Local DB      Realtime DB
  (Encrypted)   (Encrypted)
    Device       Server
   Offline      Temporary
    >24h        24h TTL
```

**Server cannot read messages** (only ciphertext + IV exists)  
**Client decrypts locally** (AES key never sent to server)  
**Messages auto-delete from cloud** (Cloud Function cleanup)  
**Local copy persists** (user can keep for reference)

---

## Implementation Checklist

- [x] Firestore: User profiles (permanent, `firebase_firestore_service.dart`)
- [x] Realtime DB: Messages (temporary, 24h TTL, `firebase_db_service.dart`)
- [x] Local SQLite: Encrypted message cache (`storage_service.dart`)
- [ ] Cloud Function: Auto-delete messages >24h old (see README Cloud Function section)
- [ ] Security Rules: Firestore & Realtime DB rules configured
- [ ] Testing: Local auth, Firebase auth, offline scenarios

---

## Configuration Reference

**Firestore Index:** (auto-created if needed)
```
Collection: users
Field: username (Ascending)
```

**Realtime DB Rules:** (see README.md)
- `/usernames/{username}`: Read public, write by user
- `/messages/{uid}`: Read by recipient, write by authenticated sender

**Cloud Function:** (see README.md)
- Runs every 1 hour
- Deletes messages where `timestamp < (now - 24h)`
