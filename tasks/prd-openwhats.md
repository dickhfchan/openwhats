# PRD: OpenWhats — WhatsApp Clone (iOS + macOS)

## 1. Introduction / Overview

OpenWhats is a secure, end-to-end encrypted messaging application for Apple platforms (iPhone and Mac). It mirrors WhatsApp's core messaging experience — 1:1 text chat, image sharing, voice messages, and voice/video calling — built as a native SwiftUI multiplatform app backed by a cloud-hosted SaaS infrastructure.

Users authenticate exclusively via **Sign in with Apple**, and all messages are protected by a custom implementation of the **Signal Protocol** (Double Ratchet + X3DH), ensuring that no one — including the server — can read message content.

**Problem it solves:** Provide an open, Apple-native alternative to WhatsApp with full E2EE, a clean SwiftUI codebase, and no dependency on a third-party messaging vendor.

---

## 2. Goals

1. Deliver a fully functional 1:1 messaging app on iOS 17+ and macOS 14+ from a single SwiftUI codebase.
2. Implement the Signal Protocol for provable end-to-end encryption on all messages and media.
3. Authenticate users securely and privately via Sign in with Apple (no phone number or email required).
4. Support real-time text, image, voice message, and voice/video call features matching WhatsApp's core UX.
5. Deploy as a cloud-hosted SaaS so users simply download the app and create an account.
6. Achieve sub-200ms message delivery latency on a stable connection.

---

## 3. User Stories

### Onboarding
- **US-01:** As a new user, I can sign in with my Apple ID so I can create an account without sharing personal data.
- **US-02:** As a returning user, I can open the app and be automatically authenticated so I reach my chats immediately.
- **US-03:** As a user, I can set a display name and profile photo visible to my contacts.

### Contacts & Conversations
- **US-04:** As a user, I can search for other users by their display name or unique handle to start a conversation.
- **US-05:** As a user, I can see a chronological list of my conversations with unread badge counts.
- **US-06:** As a user, I can tap a conversation and see the full message history, newest at the bottom.

### Messaging
- **US-07:** As a user, I can send and receive text messages in real time.
- **US-08:** As a user, I can send and receive images from my photo library or camera.
- **US-09:** As a user, I can record and send voice messages (tap-hold to record, release to send).
- **US-10:** As a user, I can see delivery status indicators (sent ✓, delivered ✓✓, read ✓✓ in blue).
- **US-11:** As a user, I can long-press a message to reply, copy, or delete it.
- **US-12:** As a user, I receive push notifications for new messages when the app is backgrounded.

### Calling
- **US-13:** As a user, I can start a voice call with any contact directly from their conversation.
- **US-14:** As a user, I can start a video call with any contact directly from their conversation.
- **US-15:** As a user, I receive an incoming call UI (even when app is backgrounded) via CallKit on iOS.
- **US-16:** As a user on Mac, I can accept or initiate calls in a dedicated call window.

### Security
- **US-17:** As a user, I can view a "Security Code" (safety number) for any conversation to verify E2EE with my contact.
- **US-18:** As a user, my messages are encrypted on-device before being sent, and decrypted only on the recipient's device.

### Mac Experience
- **US-19:** As a Mac user, I see a three-column layout (conversation list | chat | details panel) matching macOS conventions.
- **US-20:** As a Mac user, I can use keyboard shortcuts to navigate conversations and compose messages.
- **US-21:** As a Mac user, notifications appear in macOS Notification Center.

---

## 4. Functional Requirements

### 4.1 Authentication
- **FR-01:** The app must support Sign in with Apple as the sole authentication method.
- **FR-02:** Upon first sign-in, the server must create a user account linked to the Apple user identifier.
- **FR-03:** Subsequent launches must auto-authenticate the user using a stored JWT/session token.
- **FR-04:** The user must be able to set a unique username (handle) during onboarding; handles must be globally unique and case-insensitive.
- **FR-05:** The user must be able to set a display name and upload a profile photo (stored in cloud, URL referenced in profile).

### 4.2 Contact Discovery
- **FR-06:** The app must provide a search endpoint to look up users by exact username handle.
- **FR-07:** The contact list must be stored server-side per user and synced on app launch.
- **FR-08:** Adding a contact must initiate the X3DH key exchange to pre-establish a Signal session.

### 4.3 Messaging (Signal Protocol — E2EE)
- **FR-09:** The app must generate an Identity Key Pair, Signed Pre-Key, and a batch of One-Time Pre-Keys per device on first launch and upload public keys to the key server.
- **FR-10:** Before sending the first message, the sender must perform X3DH key agreement using the recipient's published pre-keys.
- **FR-11:** All subsequent messages must use the Double Ratchet algorithm to derive per-message encryption keys.
- **FR-12:** The server must relay ciphertext only; the server must never have access to plaintext message content.
- **FR-13:** The app must support sealed-sender messaging so the server cannot determine the sender of a message.
- **FR-14:** Messages must be stored encrypted in the local SQLite database (SQLCipher) on-device.
- **FR-15:** Server must store undelivered messages (encrypted) for up to 30 days for offline recipients; messages must be deleted from the server once delivered.

### 4.4 Message Types
- **FR-16:** Text messages: UTF-8, up to 65,000 characters.
- **FR-17:** Image messages: JPEG/PNG/HEIC up to 16 MB; client must encrypt the attachment, upload to cloud storage (pre-signed URL), and send the decryption key + URL in the message payload.
- **FR-18:** Voice messages: recorded in AAC format, max 5 minutes; same encrypt-upload-send flow as images.
- **FR-19:** All message types must support delivery receipts: sent, delivered, read.

### 4.5 Real-Time Delivery
- **FR-20:** The client must maintain a persistent WebSocket connection to the relay server for real-time message delivery.
- **FR-21:** On reconnect, the client must request any missed messages (by last known message ID) from the server.
- **FR-22:** When the app is backgrounded, APNs (iOS) or standard macOS push must wake the app to fetch and display new messages.

### 4.6 Voice & Video Calling
- **FR-23:** Calls must use WebRTC for audio/video transport.
- **FR-24:** A STUN/TURN server must be provided to handle NAT traversal.
- **FR-25:** Call signaling (offer/answer/ICE candidates) must be relayed through the WebSocket connection and encrypted.
- **FR-26:** On iOS, incoming calls must integrate with CallKit to display the native call UI.
- **FR-27:** On macOS, incoming calls must display a native notification with Accept/Decline actions and open a dedicated call window on accept.
- **FR-28:** Call history (missed, incoming, outgoing) must be stored locally and viewable in a Calls tab.

### 4.7 Platform UI — iOS
- **FR-29:** Bottom tab bar with: Calls, Chats, Settings.
- **FR-30:** Chats list: avatar, display name, last message preview (truncated), timestamp, unread badge.
- **FR-31:** Chat view: message bubbles (right = sent, left = received), time stamps, delivery ticks, input bar with text field, attachment button, voice-record button.
- **FR-32:** Camera/photo picker integration for image sending.
- **FR-33:** Tap-hold voice record button; lift to send, swipe left to cancel.

### 4.8 Platform UI — macOS
- **FR-34:** Three-column NavigationSplitView: sidebar (conversation list) | content (chat) | detail (contact info).
- **FR-35:** Toolbar with search, new chat, and call buttons.
- **FR-36:** Keyboard shortcuts: ⌘N new chat, ⌘F search, arrow keys to navigate conversations, ↩ to send.
- **FR-37:** Drag-and-drop image files into the chat input area to attach.
- **FR-38:** Resizable columns; minimum window size 900×600 pt.

### 4.9 Security & Privacy
- **FR-39:** The app must display a "Security Code" (SHA-256 fingerprint of both parties' identity keys) that users can compare out-of-band.
- **FR-40:** All network traffic must use TLS 1.3.
- **FR-41:** The local database must be encrypted with SQLCipher using a key derived from the device's Secure Enclave.
- **FR-42:** The app must implement certificate pinning against the production server certificates.

### 4.10 Settings
- **FR-43:** Edit profile: display name, username, profile photo.
- **FR-44:** Notifications: toggle message and call notifications per conversation or globally.
- **FR-45:** Privacy: who can see my profile photo (Everyone / Nobody).
- **FR-46:** Account: sign out, delete account (with data wipe).

---

## 5. Non-Goals (Out of Scope for MVP)

- Group chats (more than 2 participants)
- Status / Stories feature
- WhatsApp Channels or broadcast lists
- In-app payments
- Desktop-web client (browser)
- Android client
- Message reactions or polls
- Disappearing messages timer
- Archived / starred messages
- Multi-device linking (one device per account for MVP)
- Stickers or GIF support

---

## 6. Design Considerations

### Visual Language
- Follow WhatsApp's established visual conventions (users already know them):
  - Sent messages: green/teal bubble, right-aligned.
  - Received messages: white/dark-mode-gray bubble, left-aligned.
  - Font: SF Pro (system default on Apple platforms).
  - Color accent: `#25D366` (WhatsApp green) for interactive elements and sent bubbles.

### Navigation Patterns
- **iOS:** Tab bar + NavigationStack per tab. Chat view pushes onto Chats stack.
- **macOS:** NavigationSplitView with persistent sidebar.

### Dark Mode
- Full system Dark Mode support required (automatic via SwiftUI `.colorScheme` environment).

### Accessibility
- VoiceOver labels on all interactive elements.
- Dynamic Type support for all text.

### Reference Screenshots
- Capture live WhatsApp screenshots on iPhone and Mac for pixel-level reference during implementation. Store in `/Design/screenshots/`.

---

## 7. Technical Considerations

### Codebase Structure
```
OpenWhats/
├── App/                    # App entry points (iOS + macOS targets)
├── Packages/
│   ├── OpenWhatsCore/      # Swift Package: business logic, Signal Protocol, networking
│   │   ├── Sources/
│   │   │   ├── Crypto/     # Signal Protocol (X3DH, Double Ratchet)
│   │   │   ├── Network/    # WebSocket client, REST API client
│   │   │   ├── Storage/    # SQLCipher models, Core Data stack
│   │   │   ├── Media/      # Image/audio encryption + upload
│   │   │   └── Models/     # Shared domain models
│   └── OpenWhatsUI/        # Shared SwiftUI views and components
├── iOS/                    # iOS-specific: AppDelegate, CallKit, APNS
├── macOS/                  # macOS-specific: AppDelegate, window management
├── Server/                 # Backend (Go recommended)
│   ├── api/                # REST endpoints
│   ├── ws/                 # WebSocket relay
│   ├── keyserver/          # Signal pre-key distribution
│   └── media/              # Pre-signed URL generation (S3-compatible)
└── Design/
    └── screenshots/        # WhatsApp UI reference images
```

### Signal Protocol Implementation
- Implement X3DH and Double Ratchet from spec in Swift (no external dependency) inside `OpenWhatsCore/Crypto/`.
- Use Apple's `CryptoKit` for Curve25519, AES-GCM, HKDF, and HMAC primitives — all hardware-accelerated.
- Key storage: Identity key in Secure Enclave (if supported), pre-keys in Keychain.

### Backend (Server)
- **Language:** Go — excellent WebSocket/concurrency support, small binary, easy to deploy.
- **Database:** PostgreSQL for user accounts, pre-keys, undelivered message envelopes.
- **Media Storage:** S3-compatible object storage (AWS S3 or self-hosted MinIO). Pre-signed URLs for upload/download.
- **WebSocket relay:** Each client holds one authenticated WebSocket; server routes envelopes by recipient user ID.
- **Push:** APNs HTTP/2 provider API for iOS/macOS push.
- **TURN:** coturn open-source TURN server for WebRTC NAT traversal.
- **Deployment:** Containerized (Docker + Kubernetes or Docker Compose for early stage), behind a TLS-terminating load balancer.

### Key Dependencies (iOS/macOS)
| Dependency | Purpose |
|---|---|
| `CryptoKit` (Apple) | Curve25519, AES-GCM, HKDF |
| `SQLCipher` (via SPM) | Encrypted local database |
| `Starscream` or `URLSessionWebSocketTask` | WebSocket client |
| `WebRTC.framework` | Voice/video calling |
| `CallKit` (iOS only) | Native incoming call UI |

### API Overview
- `POST /auth/apple` — exchange Apple identity token for server JWT
- `POST /users/register` — create user profile + upload initial pre-keys
- `GET /users/search?handle=` — look up user by handle
- `GET /keys/{userId}` — fetch pre-key bundle for X3DH
- `POST /keys/prekeys` — replenish one-time pre-keys
- `GET /messages/pending` — fetch queued envelopes on reconnect
- `POST /media/upload-url` — get pre-signed S3 upload URL
- `WebSocket /ws` — authenticated real-time message relay

---

## 8. Success Metrics

| Metric | Target |
|---|---|
| Message delivery latency (p95, good connection) | < 200 ms |
| App launch to chats visible | < 1.5 s |
| Voice call connection time | < 3 s |
| Crash-free session rate | ≥ 99.5% |
| E2EE test: server can read 0% of message content | 100% pass |
| iOS + macOS share >90% of business logic code | ≥ 90% |
| App Store review pass on first submission | Pass |

---

## 9. Open Questions

1. **Username recovery:** If a user loses their Apple ID access, can they recover their account or is it permanently lost? (Implications for key management.)
permanently lost
2. **Multi-device:** MVP scopes to one device. When multi-device is added, how are Signal sessions synchronized across devices (requires device linking protocol)?
multi-device, but only one in phone and one in desktop
3. **TURN server geography:** How many TURN regions are needed for MVP to ensure acceptable call quality globally?
US and Hong Kong
4. **Key server trust:** Should the app display a warning when a contact's identity key changes (possible MITM / new device) — like WhatsApp's "Security code changed" notice?
Yes
5. **Regulatory:** Are there any jurisdictions where E2EE apps face export-control or compliance requirements we need to address at launch?
US
6. **Rate limiting:** What are the initial rate limits for message sending and pre-key consumption to prevent abuse?
1 messages per second 
7. **Backend hosting:** Which cloud provider (AWS, GCP, Hetzner) and region for the initial SaaS deployment?
AWS only
