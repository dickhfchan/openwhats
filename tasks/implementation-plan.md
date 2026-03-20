# OpenWhats — Implementation Plan

**Decisions locked from open questions:**
- Lost Apple ID = permanently lost account (no recovery)
- Multi-device: 1 iPhone + 1 Mac per account (each is an independent Signal device)
- TURN regions: AWS us-east-1 (Virginia) + ap-east-1 (Hong Kong)
- Identity key change: show "Security code changed" warning
- Regulatory: US market only (Signal Protocol covered under EAR open-source exception)
- Rate limit: 1 message/second per user
- Cloud: AWS only

---

## Repository Layout

```
openwhats/
├── App/                        # Xcode multiplatform project
│   ├── iOS/                    # iOS-specific: AppDelegate, CallKit, APNS
│   └── macOS/                  # macOS-specific: AppDelegate, window management
├── Packages/
│   ├── OpenWhatsCore/          # Swift Package — all platform-shared logic
│   │   └── Sources/OpenWhatsCore/
│   │       ├── Crypto/         # Signal Protocol (X3DH, Double Ratchet, keys)
│   │       ├── Network/        # WebSocket client, REST API client
│   │       ├── Storage/        # SQLCipher DB, repositories
│   │       ├── Media/          # Attachment encrypt/decrypt/upload
│   │       ├── Call/           # WebRTC session management
│   │       └── Models/         # Domain models (Message, Conversation, User…)
│   └── OpenWhatsUI/            # Swift Package — shared SwiftUI views
│       └── Sources/OpenWhatsUI/
│           ├── Components/     # Bubbles, avatars, input bar, call UI
│           ├── iOS/            # iOS-only views (tab bar, sheets)
│           └── macOS/          # macOS-only views (split view, toolbar)
├── Server/                     # Go backend
│   ├── cmd/server/             # Main entry point
│   ├── internal/
│   │   ├── auth/               # Apple token verification, JWT
│   │   ├── user/               # User profiles, handles
│   │   ├── keyserver/          # Pre-key bundle store/distribution
│   │   ├── relay/              # WebSocket hub, message routing
│   │   ├── queue/              # Offline message envelope store
│   │   ├── media/              # S3 pre-signed URL generation
│   │   ├── call/               # WebRTC signaling relay
│   │   └── ratelimit/          # Token bucket per user (1 msg/s)
│   ├── migrations/             # PostgreSQL schema migrations
│   └── deploy/                 # Docker, docker-compose, K8s manifests
├── Infrastructure/             # Terraform for AWS resources
│   ├── network/                # VPC, subnets, security groups
│   ├── compute/                # ECS/EC2 for server + coturn
│   ├── database/               # RDS PostgreSQL
│   ├── storage/                # S3 buckets
│   └── dns/                    # Route53 + ACM certificates
├── Design/
│   └── screenshots/            # WhatsApp reference screenshots
└── tasks/
    ├── prd-openwhats.md
    └── implementation-plan.md
```

---

## Phase 0 — Project Infrastructure

**Goal:** Runnable skeleton; CI passes; AWS resources provisioned.

### 0.1 Xcode Project Setup
- [ ] Create multiplatform Xcode project `OpenWhats` targeting iOS 17.0 and macOS 14.0
- [ ] Add `OpenWhatsCore` local Swift Package (library target + test target)
- [ ] Add `OpenWhatsUI` local Swift Package (library target)
- [ ] Link both packages to iOS and macOS app targets
- [ ] Configure bundle IDs: `com.openwhats.app` (iOS), `com.openwhats.app.macos`
- [ ] Enable Sign in with Apple capability on both targets
- [ ] Enable Push Notifications capability on both targets
- [ ] Enable Keychain Sharing capability with group `com.openwhats.keychain`

### 0.2 Go Backend Scaffold
- [ ] Initialize Go module `github.com/openwhats/server`
- [ ] Set up directory structure (`cmd/`, `internal/`, `migrations/`)
- [ ] Add dependencies: `gorilla/websocket`, `golang-jwt/jwt/v5`, `lib/pq`, `aws/aws-sdk-go-v2`
- [ ] Implement health check endpoint `GET /health` returning `200 OK`
- [ ] Set up structured logging (`zap` or `slog`)
- [ ] Add graceful shutdown with context cancellation

### 0.3 Database
- [ ] Write initial migration: `users`, `devices`, `pre_keys`, `signed_pre_keys`, `message_envelopes`, `contacts` tables (schema in §Database Schema below)
- [ ] Set up `golang-migrate` for migration management
- [ ] Create `docker-compose.yml` with PostgreSQL 16 for local development

### 0.4 AWS Infrastructure (Terraform)
- [ ] VPC with public/private subnets in us-east-1 and ap-east-1
- [ ] RDS PostgreSQL 16 (Multi-AZ, private subnet)
- [ ] ECS Fargate cluster for the Go server
- [ ] S3 bucket `openwhats-media` with server-side encryption (SSE-S3)
- [ ] S3 bucket `openwhats-avatars` (public read via CloudFront)
- [ ] ACM certificates for `api.openwhats.app`, `turn-us.openwhats.app`, `turn-hk.openwhats.app`
- [ ] Route53 hosted zone + DNS records
- [ ] EC2 instances for coturn (t3.small) in us-east-1 and ap-east-1
- [ ] Security groups: server → RDS (5432), clients → server (443), clients → TURN (3478/5349 TCP+UDP)

### 0.5 CI/CD
- [ ] GitHub Actions workflow: Swift build + test (Xcode 16) on push to `main`
- [ ] GitHub Actions workflow: Go build + test + vet on push to `main`
- [ ] Dockerfile for Go server (multi-stage, distroless final image)
- [ ] ECS deploy action on merge to `main` (rolling update)

---

## Phase 1 — Authentication & User Identity

**Goal:** User can sign in with Apple, create a profile, and receive a session JWT.

### 1.1 Backend — Auth
- [ ] `POST /auth/apple`: Accept Apple identity token, verify with Apple's public keys (JWKS from `appleid.apple.com`), extract `sub` (Apple user ID)
- [ ] On first login: create `users` row with `apple_sub`, generate UUID `user_id`
- [ ] Issue signed JWT (HS256, 30-day expiry) containing `user_id` and `device_id`
- [ ] `POST /auth/refresh`: exchange valid JWT for a new one (sliding expiry)
- [ ] Middleware: validate JWT on all authenticated endpoints; attach `userID` and `deviceID` to request context

### 1.2 Backend — User Profile
- [ ] `POST /users/register`: set `username` (handle) + `display_name`; validate handle: lowercase alphanumeric + underscore, 3–20 chars, globally unique
- [ ] `GET /users/me`: return own profile
- [ ] `GET /users/search?handle=`: return `{user_id, display_name, avatar_url}` or 404
- [ ] `PATCH /users/me`: update `display_name`; avatar handled separately
- [ ] `POST /users/me/avatar`: accept multipart upload, store to S3 `openwhats-avatars`, return CloudFront URL; update user row

### 1.3 Backend — Device Registration
- [ ] Each user can have max 2 devices: one `phone` type, one `desktop` type
- [ ] `POST /devices/register`: register device with `device_type` (`phone`|`desktop`), `apns_token`; returns `device_id`
- [ ] Enforce 1-phone + 1-desktop constraint; re-registering same type replaces the old device (deregisters it)
- [ ] `DELETE /devices/{device_id}`: deregister (sign out)

### 1.4 iOS — Sign in with Apple
- [ ] `AuthenticationServices` sign-in button on onboarding screen
- [ ] Exchange Apple credential for server JWT via `POST /auth/apple`
- [ ] Store JWT in Keychain (shared group `com.openwhats.keychain`)
- [ ] On launch: check Keychain for valid JWT; if found, skip onboarding

### 1.5 iOS/macOS — Onboarding Flow
- [ ] Onboarding screen: Sign in with Apple button (shared SwiftUI view)
- [ ] After auth: username picker screen with real-time availability check (debounced 500ms)
- [ ] Display name + profile photo upload screen (camera / photo library picker)
- [ ] On completion: navigate to main app shell

---

## Phase 2 — Signal Protocol Core

**Goal:** Fully working E2EE: X3DH session establishment + Double Ratchet message encryption/decryption.

### 2.1 Key Generation & Storage
- [ ] **IdentityKey:** Generate Curve25519 key pair using `CryptoKit.Curve25519.Signing`; store private key in Keychain (accessibility `.whenUnlockedThisDeviceOnly`)
- [ ] **SignedPreKey:** Generate Curve25519 key pair; sign public key with identity key (Ed25519); rotate every 7 days
- [ ] **One-Time PreKeys (OTPKs):** Generate batch of 100 Curve25519 key pairs on first launch; maintain minimum 20 in Keychain; refill when server reports < 20 remaining
- [ ] All private keys stored in Keychain under deterministic service/account identifiers
- [ ] `KeyStore` class: CRUD for all key types, thread-safe

### 2.2 Backend — Key Server
- [ ] `POST /keys/prekeys`: upload signed pre-key + batch of OTPKs (public keys only, JSON array)
- [ ] `GET /keys/{userId}`: return pre-key bundle for any device of that user: `{identity_key, signed_pre_key, signed_pre_key_signature, one_time_pre_key}` — consume and delete the OTPK from DB
- [ ] If OTPKs exhausted: return bundle without OTPK (still secure, just no forward secrecy on that message)
- [ ] `GET /keys/{userId}/count`: return remaining OTPK count (client polls after each session establishment)
- [ ] `PUT /keys/signed-prekey`: replace signed pre-key (rotation)

### 2.3 X3DH Implementation (`Crypto/X3DH.swift`)
- [ ] Implement sender-side X3DH:
  ```
  DH1 = DH(IK_A, SPK_B)
  DH2 = DH(EK_A, IK_B)
  DH3 = DH(EK_A, SPK_B)
  DH4 = DH(EK_A, OPK_B)   // if OPK present
  SK  = HKDF(DH1 || DH2 || DH3 [|| DH4])
  ```
- [ ] Implement receiver-side X3DH key agreement from incoming PreKeyMessage
- [ ] Output: 32-byte shared secret `SK` used to initialize the Double Ratchet
- [ ] Initial message format: `{IK_A_pub, EK_A_pub, OPK_B_id, ciphertext}`

### 2.4 Double Ratchet Implementation (`Crypto/DoubleRatchet.swift`)
- [ ] Implement Diffie-Hellman Ratchet step (new DH key exchange every chain turn)
- [ ] Implement Symmetric-Key Ratchet for sending and receiving chains (HKDF-based KDF)
- [ ] Per-message encryption: AES-256-GCM with 32-byte message key + 32-byte IV derived from chain
- [ ] Message headers: `{ratchet_key, prev_chain_len, msg_index}` (unencrypted, included in AEAD associated data)
- [ ] Out-of-order message handling: cache skipped message keys (up to 2000 per session)
- [ ] Session serialization: encode full ratchet state to JSON → store encrypted in SQLCipher

### 2.5 Session Management (`Crypto/SessionStore.swift`)
- [ ] Maintain one Signal session per remote `(user_id, device_id)` pair
- [ ] On first message to a device: perform X3DH, initialize ratchet, persist session
- [ ] Load/save sessions from SQLCipher `sessions` table
- [ ] On receiving a message with unknown `ratchet_key`: handle session reset gracefully
- [ ] When recipient's identity key changes: surface "Security code changed" warning (see §Security)

### 2.6 Safety Numbers (`Crypto/SafetyNumbers.swift`)
- [ ] Compute safety number: `SHA-512(IK_A || phone_A || IK_B || phone_B)` → format as 60-digit string grouped in 5-digit blocks (12 groups), matching Signal's display format
- [ ] Since we use Apple IDs not phone numbers, substitute `user_id` UUID as the identity input
- [ ] Display as QR code + numeric string in Security Code screen

### 2.7 Multi-Device Encryption
- [ ] When sending a message to user X who has 2 devices: fetch pre-key bundles for both devices
- [ ] Encrypt message separately for each device (separate X3DH/ratchet session per device)
- [ ] Send one `MessageEnvelope` per device to the server
- [ ] Own devices: also encrypt and send to self's other device (keep both devices in sync)

---

## Phase 3 — Messaging Pipeline

**Goal:** Send and receive text messages end-to-end with delivery receipts and push notifications.

### 3.1 Local Database (`Storage/`)
- [ ] Integrate SQLCipher via Swift Package; derive encryption key from Keychain-stored 256-bit secret
- [ ] Schema (SQLCipher tables):
  - `conversations(id, peer_user_id, last_message_id, unread_count, updated_at)`
  - `messages(id, conversation_id, sender_id, type, body_encrypted, timestamp, status, local_path)`
  - `sessions(id, peer_user_id, peer_device_id, ratchet_state_json)`
  - `skipped_keys(session_id, ratchet_key, msg_index, message_key, created_at)`
  - `contacts(user_id, display_name, avatar_url, added_at)`
- [ ] Repository pattern: `ConversationRepository`, `MessageRepository`, `SessionRepository`
- [ ] All DB operations on a dedicated serial `DispatchQueue`

### 3.2 Backend — Message Relay
- [ ] `MessageEnvelope` struct: `{id, sender_user_id, sender_device_id, recipient_user_id, recipient_device_id, payload_base64, timestamp}`
- [ ] `POST /messages/send`: accept envelope array (one per recipient device); validate sender JWT; store to `message_envelopes` if recipient offline; route via WebSocket if online; enforce 1 msg/s rate limit (token bucket in Redis or in-memory)
- [ ] `GET /messages/pending`: return all queued envelopes for authenticated device; delete from DB after ack
- [ ] `POST /messages/ack`: client acknowledges receipt of envelope IDs; server deletes them
- [ ] Delivery receipt relay: special envelope type `DELIVERY_RECEIPT` and `READ_RECEIPT`; same relay path

### 3.3 WebSocket Connection (`Network/WebSocketClient.swift`)
- [ ] Connect to `wss://api.openwhats.app/ws` with JWT in `Authorization` header on upgrade
- [ ] Reconnect with exponential backoff (1s → 2s → 4s → … → 60s max)
- [ ] Heartbeat: send `PING` every 30s; server responds `PONG`; restart connection if no pong in 10s
- [ ] Message types over WebSocket: `ENVELOPE`, `DELIVERY_RECEIPT`, `READ_RECEIPT`, `CALL_SIGNAL`, `PING`, `PONG`
- [ ] On connect: immediately call `GET /messages/pending` to drain offline queue

### 3.4 Backend — WebSocket Hub
- [ ] `Hub` struct: `map[userID]map[deviceID]*Client`; mutex-protected
- [ ] On new WebSocket auth: register client in hub; send any pending envelopes immediately
- [ ] On disconnect: remove from hub
- [ ] Route incoming envelope: if recipient online → write to WebSocket; else → store in `message_envelopes` → send APNs push

### 3.5 Push Notifications
- [ ] Backend: APNs HTTP/2 provider API; `notification` push (not silent) with `mutable-content: 1`
- [ ] iOS Notification Service Extension: receive push → fetch pending messages from server → decrypt → show notification with plaintext
- [ ] macOS: same via `UNUserNotificationCenter`; request authorization on first launch
- [ ] Notification content: "New message from [display_name]" (decrypt on device in extension)
- [ ] APNS token refresh: client calls `PATCH /devices/me` when `didRegisterForRemoteNotificationsWithDeviceToken` fires

### 3.6 Delivery Receipts
- [ ] **Sent (✓):** set immediately when `POST /messages/send` returns 200
- [ ] **Delivered (✓✓):** recipient device sends `DELIVERY_RECEIPT` envelope on receiving; sender updates local DB and UI
- [ ] **Read (✓✓ blue):** send `READ_RECEIPT` when conversation is open and message is visible (use `ScrollViewReader` to detect)
- [ ] UI: render tick icons in message bubble bottom-right per WhatsApp design

### 3.7 Message Store & UI Model
- [ ] `MessageStore` (`@Observable`): loads paginated messages from SQLCipher; publishes updates
- [ ] Incoming message flow: WebSocket → decrypt → insert to SQLCipher → update `MessageStore` → UI refresh
- [ ] Outgoing message flow: encrypt → insert to SQLCipher as `.sent` → POST to server → update status
- [ ] `ConversationStore` (`@Observable`): list of conversations sorted by `updated_at` desc; unread counts

---

## Phase 4 — Media Messages

**Goal:** Send and receive images and voice messages.

### 4.1 Attachment Encryption (`Media/AttachmentCrypto.swift`)
- [ ] Generate random 256-bit AES key + 128-bit IV per attachment
- [ ] Encrypt file data with AES-256-CBC (streaming for large files); append HMAC-SHA256 over ciphertext
- [ ] Store encrypted blob locally in app's `Library/Caches/attachments/` with UUID filename
- [ ] Include `{key, iv, hmac, mime_type, size}` in the Signal message payload (encrypted by Double Ratchet)

### 4.2 Backend — Media Upload
- [ ] `POST /media/upload-url`: return pre-signed S3 PUT URL (15-min expiry) + object key
- [ ] Client: upload encrypted blob directly to S3 via pre-signed URL (no server proxy)
- [ ] `POST /media/confirm`: mark object key as committed; server checks object exists in S3
- [ ] `GET /media/download-url/{key}`: return pre-signed S3 GET URL (5-min expiry) for download
- [ ] S3 lifecycle: delete media objects after 30 days

### 4.3 Image Messages
- [ ] Photo Library picker: `PhotosUI.PhotosPicker` (SwiftUI); limit to images; max 16 MB HEIC/JPEG/PNG
- [ ] Camera capture: `UIImagePickerController` (iOS) / `NSOpenPanel` (macOS)
- [ ] On send: compress to JPEG quality 0.85 if > 2 MB → encrypt → upload → send message with attachment metadata
- [ ] On receive: download encrypted blob → verify HMAC → decrypt → cache locally → display with `AsyncImage`-like loader
- [ ] Show thumbnail placeholder with progress spinner during download

### 4.4 Voice Messages
- [ ] Record with `AVAudioRecorder` (iOS) / `AVCaptureSession` (macOS) in AAC format, 24kHz mono
- [ ] Max recording duration: 5 minutes; show waveform-style progress bar during recording
- [ ] Tap-hold to record button (iOS): `LongPressGesture` + `DragGesture` — drag left to cancel
- [ ] Mic button (macOS): click to start, click to stop
- [ ] On send: same encrypt → upload → send flow as images
- [ ] On receive/play: download → decrypt → play with `AVPlayer`; show duration and playhead scrubber

---

## Phase 5 — iOS UI

**Goal:** Full WhatsApp-equivalent iOS UI using SwiftUI.

### 5.1 App Shell
- [ ] `TabView` with 3 tabs: Calls (phone icon), Chats (message bubble icon), Settings (gear icon)
- [ ] Tab bar tint color: `#25D366`
- [ ] Each tab wraps a `NavigationStack`

### 5.2 Chats List Screen
- [ ] `List` of `ConversationRow` items, sorted by last activity
- [ ] `ConversationRow`: avatar (40pt circle, initials fallback), display name (semibold), last message preview (gray, truncated 1 line), timestamp (right), unread badge (green circle with count)
- [ ] Swipe left: "Delete" (red) action
- [ ] Pull-to-refresh: sync contacts + pending messages
- [ ] Navigation bar: "Chats" title, pencil icon button → new chat search screen
- [ ] Search bar (`.searchable`): filter conversations by contact name

### 5.3 Chat View
- [ ] `ScrollViewReader` + `LazyVStack` for message bubbles; auto-scroll to bottom on new message
- [ ] Load 50 messages initially; load older on scroll-to-top (pagination)
- [ ] **Sent bubble:** rounded rect (18pt radius, flat bottom-right), teal `#DCF8C6` (light) / `#005C4B` (dark), right-aligned, 12pt timestamp + delivery ticks bottom-right
- [ ] **Received bubble:** white (light) / `#262D31` (dark), left-aligned, 12pt timestamp bottom-right
- [ ] **Image bubble:** image fills bubble (max 280pt wide), tap → full-screen viewer with pinch-zoom
- [ ] **Voice bubble:** waveform bars + play/pause button + duration label
- [ ] Date separators between messages from different days (centered gray pill)
- [ ] Long-press bubble → context menu: Reply, Copy, Delete (for own messages)
- [ ] Input bar (pinned to bottom, above keyboard):
  - Multiline `TextField`, max 5 lines visible before scrolling
  - Left: attachment `+` button → sheet with Camera / Photo Library options
  - Right: send button (arrow up, teal) when text present; mic button when empty
  - Voice record: long-press mic → recording indicator with waveform + duration counter + slide-to-cancel hint

### 5.4 Contact Search / New Chat
- [ ] Search screen: `TextField` with handle search
- [ ] Results list: avatar, display name, handle — tap → open or create conversation
- [ ] "Add contact" confirmation sheet before opening conversation with a new user

### 5.5 Contact / Conversation Info Screen
- [ ] Push from chat navigation bar person icon
- [ ] Large avatar, display name, handle
- [ ] "Security Code" row → Security Code screen (QR + 60-digit number)
- [ ] "Mute Notifications" toggle
- [ ] "Delete Conversation" button (destructive)
- [ ] Calls section: recent call log with the contact

---

## Phase 6 — macOS UI

**Goal:** Native macOS experience using NavigationSplitView, keyboard shortcuts, and macOS conventions.

### 6.1 App Shell
- [ ] `NavigationSplitView` (three-column): sidebar | content | detail
- [ ] Sidebar: conversation list (same data as iOS, different layout)
- [ ] Content: chat view
- [ ] Detail: contact info panel (collapsible)
- [ ] Min window size: 900×600 pt; default: 1200×750 pt
- [ ] Toolbar: search field (left), new chat button, video call button, voice call button (right)

### 6.2 Sidebar (Conversation List)
- [ ] `List(selection:)` with `ConversationRow` (compact macOS variant: smaller avatar 32pt, no chevron)
- [ ] Selection drives the content column
- [ ] Right-click context menu: Mute, Delete Conversation
- [ ] Unread count badge on tab icon in Dock

### 6.3 Chat View (macOS)
- [ ] Same bubble rendering as iOS (shared `OpenWhatsUI` components)
- [ ] Input area: `TextEditor` with ⌘↩ to send (single ↩ sends, Shift-↩ adds newline — preference in Settings)
- [ ] Drag image files from Finder → drop zone in input area → attach
- [ ] Toolbar inline: voice/video call buttons, contact info toggle

### 6.4 Keyboard Shortcuts
- [ ] `⌘N`: open new chat search
- [ ] `⌘F`: focus search bar in sidebar
- [ ] `⌘↑` / `⌘↓`: navigate to previous/next conversation
- [ ] `⌘W`: close detail panel
- [ ] `Escape`: dismiss search / close modal

### 6.5 Incoming Call Window (macOS)
- [ ] `NSPanel` (always-on-top, non-activating) with caller avatar, name, Accept (green) / Decline (red) buttons
- [ ] On Accept: open call window (see Phase 7)
- [ ] Notification Center fallback if app not frontmost: "Incoming call from [name]" with Reply actions

---

## Phase 7 — Voice & Video Calls

**Goal:** WebRTC-based voice and video calls with CallKit on iOS and native call window on macOS.

### 7.1 WebRTC Setup
- [ ] Integrate `WebRTC.framework` (Google's prebuilt binary via SPM or manual xcframework)
- [ ] `RTCPeerConnectionFactory` singleton initialized on app start
- [ ] `CallSession` class: manages one `RTCPeerConnection` per active call; publishes call state

### 7.2 STUN/TURN Configuration
- [ ] coturn deployed on EC2 in us-east-1 and ap-east-1
- [ ] coturn config: `use-auth-secret`, time-limited HMAC credentials (valid 24h)
- [ ] Backend `GET /calls/ice-servers`: return time-limited TURN credentials + STUN URLs; client fetches on call initiation
- [ ] `RTCIceServer` array: `stun:stun.openwhats.app:3478`, `turn:turn-us.openwhats.app:3478`, `turn:turn-hk.openwhats.app:3478`

### 7.3 Call Signaling
- [ ] Signaling messages sent over existing WebSocket as `CALL_SIGNAL` envelopes (encrypted via Signal ratchet like regular messages)
- [ ] Signal types: `CALL_OFFER`, `CALL_ANSWER`, `ICE_CANDIDATE`, `CALL_HANGUP`, `CALL_BUSY`, `CALL_RINGING`
- [ ] `CallManager` singleton: handles signaling state machine

### 7.4 iOS — CallKit Integration
- [ ] Implement `CXProvider` and `CXCallController`
- [ ] Incoming call push (APNs with `voip` push type via PushKit): wake app, report call to CallKit
- [ ] CallKit UI: caller display name, avatar, audio/video toggle, mute, speaker, end
- [ ] On answer via CallKit: initialize WebRTC, send `CALL_ANSWER`
- [ ] On end: send `CALL_HANGUP`, clean up `RTCPeerConnection`
- [ ] Audio session: `AVAudioSession` category `.playAndRecord`, mode `.voiceChat`

### 7.5 macOS — Call Window
- [ ] Dedicated `CallWindow` (`NSWindow` or SwiftUI `.windowStyle(.hiddenTitleBar)`)
- [ ] Local video preview (small PiP corner), remote video full-frame
- [ ] Controls: mute (⌘M), camera toggle (⌘E), end call (⌘.) — matching macOS FaceTime conventions
- [ ] Audio: `RTCAudioSession` passthrough; no special session needed on macOS

### 7.6 Call UI (Shared SwiftUI Components)
- [ ] `CallView`: full-screen during active call; works on both platforms with conditional layout
- [ ] Connecting → Ringing → Connected states with animated indicators
- [ ] Call duration timer

### 7.7 Call History
- [ ] Local table `call_logs(id, peer_user_id, direction, type, duration_sec, timestamp, missed)`
- [ ] Calls tab on iOS: `List` of call log rows with callback button
- [ ] macOS: call history in sidebar or detail panel

---

## Phase 8 — Multi-Device Support (1 Phone + 1 Mac)

**Goal:** Messages sent to a user are delivered to both their phone and Mac simultaneously.

### 8.1 Device Pairing Flow
- [ ] After signing into Mac app with same Apple ID: server recognizes `apple_sub` matches existing user
- [ ] Server issues new JWT with `device_type: desktop`, new `device_id`
- [ ] Desktop device uploads its own pre-key bundle to key server

### 8.2 Multi-Device Message Delivery
- [ ] When sending to user X: fetch pre-key bundles for ALL of X's registered devices
- [ ] Encrypt a separate `MessageEnvelope` for each device; submit all in one `POST /messages/send` call
- [ ] Also encrypt for own other device (self-send to keep both devices in sync)
- [ ] Backend stores/routes each envelope independently per target `device_id`

### 8.3 Message Sync Between Own Devices
- [ ] Sent messages: include own other device as recipient in every send (self-send envelope)
- [ ] Receiving own sent-message envelope: decrypt → mark conversation read on this device
- [ ] Delivery/read receipts from peer: relay to all sender's devices so both show updated ticks

### 8.4 Device Management UI
- [ ] Settings → Linked Devices: shows up to 2 entries (phone, desktop) with device type icon and last-active timestamp
- [ ] "Unlink Desktop" button: calls `DELETE /devices/{device_id}`; server destroys that device's sessions and enqueued messages

---

## Phase 9 — Security & Hardening

### 9.1 Certificate Pinning
- [ ] Pin SHA-256 fingerprints of leaf certificates for `api.openwhats.app` in app bundle
- [ ] Implement `URLSession` delegate `urlSession(_:didReceive:completionHandler:)` to validate pin
- [ ] Include 2 backup pins (for cert rotation); document rotation process

### 9.2 Identity Key Change Warning
- [ ] On receiving a message, compare sender's `identity_key` in the pre-key bundle with stored value
- [ ] If changed: block message display; show banner "Security code with [name] has changed. Tap to verify."
- [ ] User must explicitly tap "I understand" to re-establish session (re-fetch pre-key bundle, re-run X3DH)

### 9.3 Rate Limiting
- [ ] Server: per-user token bucket, refill 1 token/second, max burst 5
- [ ] `POST /messages/send` consumes tokens equal to number of envelopes submitted
- [ ] Return `429 Too Many Requests` with `Retry-After` header
- [ ] Client: respect `Retry-After`; queue and retry automatically

### 9.4 TLS & Transport
- [ ] Enforce TLS 1.3 on server (nginx/ALB); disable TLS 1.2 and below
- [ ] App Transport Security: `NSAllowsArbitraryLoads = false`; pin to production domain only
- [ ] WebSocket over WSS only; reject `ws://` connections

### 9.5 Jailbreak / Integrity Checks (iOS)
- [ ] Basic jailbreak detection: check for Cydia, suspicious dylibs; warn user (not block — avoid false positives)
- [ ] Enable Hardened Runtime (macOS)

---

## Phase 10 — Settings, Polish & App Store

### 10.1 Settings Screens
- [ ] **Profile:** edit display name; change avatar; view own handle (read-only)
- [ ] **Notifications:** master toggle; per-conversation mute (1h / 8h / 1 week / always)
- [ ] **Privacy:** profile photo visibility (Everyone / Nobody)
- [ ] **Linked Devices:** list + unlink (Phase 8 UI)
- [ ] **Account:** Sign Out; Delete Account (confirmation alert → `DELETE /users/me` → wipe local DB + Keychain)
- [ ] **About:** app version, privacy policy link, open-source licenses

### 10.2 Accessibility
- [ ] VoiceOver: `accessibilityLabel` on all bubbles ("Message from [name]: [content], sent [time], [status]")
- [ ] Dynamic Type: all fonts use `.body`, `.caption` text styles (scale automatically)
- [ ] Reduce Motion: disable bubble appear animations when enabled

### 10.3 Performance
- [ ] Message list: `LazyVStack` with `id` stability; no unnecessary re-renders
- [ ] Image caching: `NSCache`-backed in-memory cache + disk cache under `Library/Caches/`
- [ ] DB queries: index on `messages(conversation_id, timestamp)`; index on `conversations(updated_at)`

### 10.4 App Store Submission
- [ ] Privacy Nutrition Labels: data types collected (User ID, Name, Profile Photo, Messages — on-device only for messages)
- [ ] Export Compliance: answer "Yes" to encryption question; reference EAR open-source exception (Signal Protocol)
- [ ] App Review notes: explain E2EE, Sign in with Apple flow, and feature set

---

## Database Schema

```sql
-- Users
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_sub   TEXT UNIQUE NOT NULL,
    handle      TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    avatar_url  TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- Devices (max 2 per user: phone + desktop)
CREATE TABLE devices (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID REFERENCES users(id) ON DELETE CASCADE,
    device_type  TEXT NOT NULL CHECK (device_type IN ('phone','desktop')),
    apns_token   TEXT,
    last_seen_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ DEFAULT now(),
    UNIQUE (user_id, device_type)
);

-- Signal pre-keys
CREATE TABLE identity_keys (
    device_id   UUID PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    public_key  BYTEA NOT NULL,  -- 32-byte Curve25519 public key
    updated_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE signed_pre_keys (
    id          SERIAL PRIMARY KEY,
    device_id   UUID REFERENCES devices(id) ON DELETE CASCADE,
    key_id      INT NOT NULL,
    public_key  BYTEA NOT NULL,
    signature   BYTEA NOT NULL,  -- Ed25519 signature over public_key
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE one_time_pre_keys (
    id          SERIAL PRIMARY KEY,
    device_id   UUID REFERENCES devices(id) ON DELETE CASCADE,
    key_id      INT NOT NULL,
    public_key  BYTEA NOT NULL,
    used        BOOLEAN DEFAULT false,
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- Offline message envelopes
CREATE TABLE message_envelopes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id      UUID NOT NULL,
    sender_device_id    UUID NOT NULL,
    recipient_device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    payload             BYTEA NOT NULL,  -- encrypted, opaque to server
    created_at          TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON message_envelopes(recipient_device_id, created_at);

-- Contacts (server-side for discovery)
CREATE TABLE contacts (
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    added_at        TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, contact_user_id)
);

-- Call logs (server-side for missed call push only; detailed log is local)
CREATE TABLE call_events (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id    UUID REFERENCES users(id),
    callee_id    UUID REFERENCES users(id),
    call_type    TEXT CHECK (call_type IN ('voice','video')),
    status       TEXT CHECK (status IN ('answered','missed','declined')),
    started_at   TIMESTAMPTZ,
    ended_at     TIMESTAMPTZ
);
```

---

## Implementation Order (Dependency Graph)

```
Phase 0 (Infrastructure)
    → Phase 1 (Auth)
        → Phase 2 (Signal Protocol)           [can parallel with Phase 5/6 UI skeletons]
            → Phase 3 (Messaging Pipeline)
                → Phase 4 (Media Messages)
                → Phase 7 (Calling)           [needs Phase 3 WebSocket]
                → Phase 8 (Multi-Device)      [needs Phase 3 delivery]
        → Phase 5 (iOS UI)                    [builds on Phase 3 data models]
        → Phase 6 (macOS UI)                  [builds on Phase 3 data models]
    → Phase 9 (Security)                      [runs in parallel with Phase 4–8]
→ Phase 10 (Polish & App Store)               [final gate]
```

**Suggested sprint order:**
1. Phase 0 → Phase 1
2. Phase 2 (Signal Protocol) in parallel with Phase 5/6 shell UI
3. Phase 3 (text messaging E2E working)
4. Phase 4 (media) in parallel with Phase 7 (calls)
5. Phase 8 (multi-device)
6. Phase 9 → Phase 10
