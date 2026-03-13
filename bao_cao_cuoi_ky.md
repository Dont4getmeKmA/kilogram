# BÁO CÁO ĐỒ ÁN CUỐI KỲ
# Ứng dụng Chat Kilogram — Bảo mật Đầu cuối (E2EE)

---

## MỤC LỤC

1. [Tổng quan hệ thống](#1-tổng-quan-hệ-thống)
2. [Kiến trúc ứng dụng](#2-kiến-trúc-ứng-dụng)
3. [Backend — Supabase](#3-backend--supabase)
4. [Cơ sở dữ liệu — Schema chi tiết](#4-cơ-sở-dữ-liệu--schema-chi-tiết)
5. [Mobile Frontend — Flutter/Dart](#5-mobile-frontend--flutterdart)
6. [Thư viện sử dụng](#6-thư-viện-sử-dụng)
7. [Quản lý trạng thái — BLoC Pattern](#7-quản-lý-trạng-thái--bloc-pattern)
8. [Bảo mật và Mã hóa Đầu cuối (E2EE)](#8-bảo-mật-và-mã-hóa-đầu-cuối-e2ee)
9. [Luồng hoạt động chính](#9-luồng-hoạt-động-chính)
10. [Kết luận](#10-kết-luận)

---

## 1. Tổng quan hệ thống

**Kilogram** là ứng dụng nhắn tin di động được phát triển trên nền tảng **Flutter** (Dart), sử dụng **Supabase** làm Backend-as-a-Service (BaaS). Ứng dụng hỗ trợ nhắn tin riêng tư 1-1, chat nhóm, gửi hình ảnh, và đặc biệt triển khai hệ thống **mã hóa đầu cuối (End-to-End Encryption — E2EE)** sử dụng kết hợp các thuật toán mật mã hiện đại.

### Các tính năng chính:
| Tính năng | Mô tả |
|---|---|
| Đăng ký / Đăng nhập | Xác thực qua email/password với Supabase Auth |
| Chat riêng tư 1-1 | Nhắn tin realtime giữa 2 người dùng |
| Chat nhóm | Tạo nhóm, thêm thành viên, nhắn tin nhóm |
| Gửi hình ảnh | Upload ảnh lên Supabase Storage, hiển thị trong chat |
| Hồ sơ cá nhân | Xem và chỉnh sửa thông tin, đổi avatar, chuyển theme |
| Mã hóa đầu cuối | Kết hợp ECDH, ElGamal, RSA-2048, AES-256-GCM |
| Bảo mật thiết bị | Lưu khóa riêng tư bằng FlutterSecureStorage |
| Realtime | Cập nhật tin nhắn tức thì qua Supabase Realtime |

---

## 2. Kiến trúc ứng dụng

```
┌───────────────────────────────────────────────────────────────┐
│                      KILOGRAM ARCHITECTURE                     │
├─────────────────────────┬─────────────────────────────────────┤
│   MOBILE (Flutter)      │         BACKEND (Supabase)          │
│                         │                                      │
│  ┌──────────────────┐   │   ┌──────────────────────────────┐  │
│  │   UI / Pages     │   │   │     Supabase Auth            │  │
│  │  - LoginPage     │◄──┼──►│  (JWT Authentication)        │  │
│  │  - RegisterPage  │   │   ├──────────────────────────────┤  │
│  │  - RoomsPage     │   │   │     PostgreSQL Database      │  │
│  │  - ChatPage      │◄──┼──►│  - profiles                  │  │
│  │  - ProfilePage   │   │   │  - rooms                     │  │
│  │  - CreateGroup   │   │   │  - room_participants          │  │
│  └────────┬─────────┘   │   │  - messages                  │  │
│           │             │   │  - group_keys                 │  │
│  ┌────────▼─────────┐   │   ├──────────────────────────────┤  │
│  │   BLoC Cubits    │   │   │     Supabase Storage         │  │
│  │  - RoomsCubit    │◄──┼──►│  - avatars (bucket)          │  │
│  │  - ChatCubit     │   │   │  - chat_images (bucket)      │  │
│  │  - ProfilesCubit │   │   ├──────────────────────────────┤  │
│  └────────┬─────────┘   │   │     Supabase Realtime        │  │
│           │             │   │  (WebSocket / pgBroadcast)   │  │
│  ┌────────▼─────────┐   │   └──────────────────────────────┘  │
│  │  CryptoService   │   │                                      │
│  │  (E2EE Layer)    │   │                                      │
│  │  - ECDH X25519   │   │                                      │
│  │  - ElGamal       │   │                                      │
│  │  - RSA-2048      │   │                                      │
│  │  - AES-256-GCM   │   │                                      │
│  └────────┬─────────┘   │                                      │
│           │             │                                      │
│  ┌────────▼─────────┐   │                                      │
│  │ FlutterSecure    │   │                                      │
│  │ Storage          │   │                                      │
│  │ (Private Keys)   │   │                                      │
│  └──────────────────┘   │                                      │
└─────────────────────────┴─────────────────────────────────────┘
```

---

## 3. Backend — Supabase

**Supabase** là nền tảng Backend-as-a-Service mã nguồn mở, cung cấp các dịch vụ:

### 3.1 Supabase Auth
- Xác thực người dùng bằng **email/password**
- Phát hành **JWT Token** (JSON Web Token) sau khi đăng nhập thành công
- Token được nhúng vào mọi request HTTP đến Supabase API
- Mọi truy vấn database thông qua RLS (Row Level Security) sử dụng `auth.uid()` để xác định user hiện tại

### 3.2 Supabase Database (PostgreSQL)
- Database quan hệ đầy đủ, chạy PostgreSQL
- Mỗi bảng có chính sách **RLS** riêng để phân quyền

### 3.3 Supabase Storage
- **Bucket `avatars`**: Lưu ảnh đại diện người dùng
- **Bucket `chat_images`**: Lưu ảnh gửi trong cuộc trò chuyện
- File được truy cập qua URL công khai sau khi upload

### 3.4 Supabase Realtime
- Sử dụng **WebSocket** để lắng nghe thay đổi database theo thời gian thực
- Kết nối qua `supabase.channel()` với `onPostgresChanges(event: INSERT)`
- Khi một tin nhắn mới được INSERT vào bảng `messages`, tất cả client đang lắng nghe cùng `room_id` sẽ nhận được dữ liệu ngay lập tức

### 3.5 Kết nối từ Flutter đến Supabase
```dart
// lib/main.dart
await Supabase.initialize(
  url:     'https://[project-id].supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
);

// Truy cập client toàn ứng dụng
final supabase = Supabase.instance.client;
```

Mọi thao tác (query, insert, upload, realtime) đều thực hiện qua object `supabase` này.

---

## 4. Cơ sở dữ liệu — Schema chi tiết

### 4.1 Bảng `profiles` — Thông tin người dùng

| Cột | Kiểu | Mô tả |
|---|---|---|
| `id` | UUID (PK) | Liên kết với `auth.users.id` |
| `username` | TEXT | Tên hiển thị của người dùng |
| `avatar_url` | TEXT (nullable) | URL ảnh đại diện trên Supabase Storage |
| `created_at` | TIMESTAMPTZ | Thời điểm tạo profile |
| `rsa_public_key` | TEXT (nullable) | Khóa công khai RSA-2048 (JSON BigInt) |
| `elgamal_public_key` | TEXT (nullable) | Khóa công khai ElGamal (JSON: p, g, y) |
| `ecdh_public_key` | TEXT (nullable) | Khóa công khai ECDH X25519 (Base64) |

**RLS Policies:**
```sql
-- Chỉ đọc profile của người dùng trong cùng phòng chat
CREATE POLICY "Users can read relevant profiles"
  ON profiles FOR SELECT
  USING (
    id = auth.uid() OR
    id IN (
      SELECT profile_id FROM room_participants
      WHERE room_id IN (
        SELECT room_id FROM room_participants
        WHERE profile_id = auth.uid()
      )
    )
  );

-- Chỉ tự cập nhật profile của mình
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid());
```

---

### 4.2 Bảng `rooms` — Phòng chat

| Cột | Kiểu | Mô tả |
|---|---|---|
| `id` | UUID (PK) | Định danh phòng chat |
| `created_at` | TIMESTAMPTZ | Thời điểm tạo phòng |
| `is_group` | BOOLEAN | `true` = chat nhóm, `false` = chat 1-1 |
| `name` | TEXT (nullable) | Tên nhóm (chỉ dùng khi `is_group = true`) |

---

### 4.3 Bảng `room_participants` — Thành viên phòng

| Cột | Kiểu | Mô tả |
|---|---|---|
| `room_id` | UUID (FK → rooms.id) | Phòng chat |
| `profile_id` | UUID (FK → profiles.id) | Thành viên |
| `created_at` | TIMESTAMPTZ | Thời điểm tham gia |

**Chức năng**: Mối quan hệ nhiều-nhiều giữa `rooms` và `profiles`. Mỗi row biểu diễn 1 người dùng trong 1 phòng.

---

### 4.4 Bảng `messages` — Tin nhắn

| Cột | Kiểu | Mô tả |
|---|---|---|
| `id` | UUID (PK) | Định danh tin nhắn |
| `room_id` | UUID (FK → rooms.id) | Phòng chứa tin nhắn |
| `profile_id` | UUID (FK → profiles.id) | Người gửi |
| `content` | TEXT | Nội dung văn bản (trống khi E2EE) |
| `image_url` | TEXT (nullable) | URL ảnh (khi gửi ảnh) |
| `created_at` | TIMESTAMPTZ | Thời điểm gửi |
| `ciphertext` | TEXT (nullable) | Bản mã AES-256-GCM (`ct.nonce.mac`) |
| `encrypted_key` | TEXT (nullable) | AES key đã ElGamal mã hóa (`{c1, c2}`) |
| `nonce` | TEXT (nullable) | Nonce AES-GCM (Base64) |
| `hmac` | TEXT (nullable) | HMAC-SHA256 (lưu trữ, không verify) |
| `signature` | TEXT (nullable) | Chữ ký số RSA-2048 (Base64) |

**RLS Policies:**
```sql
-- Chỉ đọc tin nhắn trong phòng của mình
CREATE POLICY "Users can only read messages in their rooms"
  ON messages FOR SELECT
  USING (
    room_id IN (
      SELECT room_id FROM room_participants
      WHERE profile_id = auth.uid()
    )
  );

-- Chỉ gửi vào phòng của mình
CREATE POLICY "Users can only insert messages in their rooms"
  ON messages FOR INSERT
  WITH CHECK (
    profile_id = auth.uid() AND
    room_id IN (
      SELECT room_id FROM room_participants WHERE profile_id = auth.uid()
    )
  );
```

---

### 4.5 Bảng `group_keys` — Khóa phiên nhóm

| Cột | Kiểu | Mô tả |
|---|---|---|
| `room_id` | UUID (FK → rooms.id) | Phòng nhóm |
| `profile_id` | UUID (FK → profiles.id) | Thành viên |
| `encrypted_key` | TEXT | Group Session Key đã ElGamal mã hóa |
| `created_at` | TIMESTAMPTZ | Thời điểm cấp khóa |

**Primary Key**: (`room_id`, `profile_id`)

---

## 5. Mobile Frontend — Flutter/Dart

### 5.1 Cấu trúc thư mục
```
lib/
├── main.dart                    # Khởi tạo ứng dụng, Supabase, theme
├── chat_page.dart               # Alias/module entry
│
├── components/
│   └── user_avatar.dart         # Widget hiển thị avatar người dùng
│
├── crypto/
│   └── crypto_service.dart      # Toàn bộ logic mã hóa E2EE
│
├── cubits/                      # BLoC state management
│   ├── chat/
│   │   ├── chat_cubit.dart      # Quản lý tin nhắn, mã hóa/giải mã
│   │   └── chat_state.dart      # Các trạng thái chat
│   ├── profiles/
│   │   ├── profiles_cubit.dart  # Quản lý cache profile người dùng
│   │   └── profiles_state.dart
│   └── rooms/
│       ├── rooms_cubit.dart     # Quản lý danh sách phòng chat
│       └── rooms_state.dart
│
├── models/
│   ├── message.dart             # Model tin nhắn (bao gồm E2EE fields)
│   ├── profile.dart             # Model hồ sơ người dùng
│   └── room.dart                # Model phòng chat
│
├── pages/
│   ├── chat_page.dart           # Màn hình chat, hiển thị bubble tin nhắn
│   ├── create_group_page.dart   # Tạo nhóm chat mới
│   ├── login_page.dart          # Đăng nhập
│   ├── profile_page.dart        # Hồ sơ cá nhân, đổi theme/avatar
│   ├── register_page.dart       # Đăng ký tài khoản mới
│   ├── rooms_page.dart          # Danh sách cuộc trò chuyện (tabs)
│   └── splash_page.dart         # Màn hình khởi động
│
└── utils/
    └── constants.dart           # Hằng số, Supabase client, extensions
```

### 5.2 Các màn hình chính

#### [SplashPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/splash_page.dart#8-14)
- Kiểm tra phiên đăng nhập còn hiệu lực không
- Tự động chuyển đến [RoomsPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/rooms_page.dart#15-30) nếu đã đăng nhập, hoặc [LoginPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/login_page.dart#10-20) nếu chưa

#### [LoginPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/login_page.dart#10-20)
- Form nhập email và password
- Sau đăng nhập: kiểm tra và tạo khóa E2EE nếu chưa có ([_ensureKeysExist](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/login_page.dart#45-75))

#### [RegisterPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/register_page.dart#10-24)
- Form đăng ký với email, password, username
- Sau đăng ký thành công: tự động generate RSA + ElGamal + ECDH key pairs
- Upload public keys lên `profiles` trên Supabase

#### [RoomsPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/rooms_page.dart#15-30)
- 3 tab: **Chat** (1-1), **Nhóm** (group), **Hồ sơ**
- Tab Chat & Nhóm: danh sách phòng với tin nhắn cuối cùng
- Tab Nhóm: nút tạo nhóm mới trên AppBar

#### [ChatPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/chat_page.dart#16-156)
- Hiển thị danh sách tin nhắn dạng bubble
- Tên người dùng hiển thị trên mỗi bubble
- Icon 🔒 màu xanh bên cạnh timestamp khi tin nhắn được E2EE
- Thanh nhập liệu với nút gửi văn bản và hình ảnh
- Realtime: nhận tin nhắn mới qua `supabase.channel()`

#### [CreateGroupPage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/create_group_page.dart#6-16)
- Tìm kiếm và chọn nhiều thành viên
- Nhập tên nhóm
- Gọi trực tiếp Supabase để tạo phòng và thêm participants

#### [ProfilePage](file:///Users/tiennh/AndroidStudioProjects/kilogram/lib/pages/profile_page.dart#11-21)
- Xem thông tin tài khoản
- Đổi ảnh đại diện
- Chuyển đổi Dark/Light theme
- Đăng xuất

---

## 6. Thư viện sử dụng

### 6.1 Dependencies chính

| Package | Version | Chức năng |
|---|---|---|
| `supabase_flutter` | ^2.12.0 | Kết nối Supabase: Auth, Database, Storage, Realtime |
| `flutter_bloc` | ^9.1.1 | Quản lý trạng thái theo kiến trúc BLoC |
| `bloc` | ^9.2.0 | Thư viện lõi BLoC |
| `pointycastle` | ^3.9.1 | Mật mã học: RSA-2048, ElGamal, Fortuna RNG |
| `cryptography` | ^2.7.0 | Mật mã học: ECDH X25519, AES-256-GCM, HMAC-SHA256 |
| `flutter_secure_storage` | ^9.2.2 | Lưu khóa riêng tư an toàn trên thiết bị |
| `convert` | ^3.1.1 | Chuyển đổi Hex/Base64 |
| `image_picker` | ^1.1.2 | Chọn ảnh từ thư viện hoặc camera |
| `timeago` | ^3.7.1 | Hiển thị thời gian tương đối ("2 phút trước") |
| `provider` | ^6.1.5+1 | Dependency injection hỗ trợ BLoC |
| `meta` | ^1.11.0 | Annotations Dart |
| `cupertino_icons` | ^1.0.6 | Icon style iOS |

### 6.2 Dev Dependencies

| Package | Chức năng |
|---|---|
| `flutter_lints` | Quy tắc lint code Dart |
| `flutter_launcher_icons` | Tạo icon ứng dụng cho Android/iOS |

---

## 7. Quản lý trạng thái — BLoC Pattern

Ứng dụng sử dụng **BLoC (Business Logic Component)** pattern thông qua `flutter_bloc`:

### 7.1 RoomsCubit
Quản lý danh sách các phòng chat hiển thị cho người dùng.

```
RoomsState:
├── RoomsInitial      – Trạng thái ban đầu
├── RoomsLoading      – Đang tải
├── RoomsLoaded       – Đã tải: rooms[], newUsers[]
├── RoomsEmpty        – Không có phòng nào
└── RoomsError        – Lỗi

Luồng:
1. Stream từ room_participants → group by room_id → 1 Room/room_id
2. Với nhóm: 1 Room object, không cần otherUserId
3. Với 1-1: lấy profile_id của người CÒN LẠI (không phải mình)
4. Tải tin nhắn mới nhất cho mỗi phòng
```

### 7.2 ChatCubit
Quản lý tin nhắn trong một phòng chat, tích hợp mã hóa/giải mã E2EE.

```
ChatState:
├── ChatInitial   – Chưa khởi tạo
├── ChatEmpty     – Chưa có tin nhắn
├── ChatLoaded    – Có tin nhắn: messages[]
└── ChatError     – Lỗi

Luồng làm việc:
1. setMessagesListener(roomId): tải tin nhắn cũ (REST) + đăng ký realtime channel
2. _loadMessages(): fetch từ Supabase → decrypt toàn bộ → emit(ChatLoaded)
3. Channel callback: nhận INSERT mới → decryptOne → thêm vào list → emit
4. setRecipientKeys(): được gọi khi keys fetch xong → re-decrypt
5. sendMessage(): encrypt → insert vào Supabase
```

### 7.3 ProfilesCubit
Cache thông tin profile người dùng theo `profile_id`.

```
ProfilesState:
├── ProfilesLoading – Đang tải
└── ProfilesLoaded  – Map<userId, Profile>

Dùng để:
- Hiển thị username trên chat bubble
- Hiển thị avatar qua UserAvatar widget
```

---

## 8. Bảo mật và Mã hóa Đầu cuối (E2EE)

### 8.1 Tổng quan kiến trúc mã hóa

Ứng dụng triển khai **5 lớp bảo mật** kết hợp:

```
┌──────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                            │
├──────────┬───────────────────────────────────────────────────┤
│  Layer 4 │  RSA-2048 Digital Signature (Xác thực danh tính) │
│  Layer 3 │  ElGamal Encryption (Mã hóa session key)         │
│  Layer 2 │  ECDH X25519 Key Exchange (Trao đổi khóa)        │
│  Layer 2 │  AES-256-GCM (Mã hóa nội dung tin nhắn)          │
│  Layer 1 │  TLS 1.3 (Bảo mật Transport qua Supabase)        │
└──────────┴───────────────────────────────────────────────────┘
```

---

### 8.2 Sinh khóa (Key Generation)

Khi người dùng đăng ký hoặc đăng nhập lần đầu, hệ thống tự động sinh 3 cặp khóa:

#### a) RSA-2048 Key Pair
```dart
// Sử dụng FortunaRandom (CSPRNG) cho entropy
final keyGen = RSAKeyGenerator();
final seed = Uint8List(32); // 256-bit random seed
secureRng.seed(KeyParameter(seed));
keyGen.init(ParametersWithRandom(
  RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
  secureRng,
));
// Public key: {n, e} → lưu Supabase (profiles.rsa_public_key)
// Private key: {n, d, p, q} → lưu FlutterSecureStorage
```

#### b) ElGamal Key Pair
```dart
// Sử dụng số nguyên tố an toàn 2048-bit theo chuẩn RFC 3526 Group 14
final p = BigInt.parse('FFFFFFFF...', radix: 16); // prime p
final g = BigInt.from(2);                          // generator
final x = random_bigint() % (p - 2) + 1;          // private key
final y = g.modPow(x, p);                          // public key = g^x mod p
// Public key: {p, g, y} → lưu Supabase (profiles.elgamal_public_key)
// Private key: {p, g, x} → lưu FlutterSecureStorage
```

#### c) ECDH X25519 Key Pair
```dart
// Elliptic Curve Diffie-Hellman trên Curve25519
final ecdhKeyPair = await X25519().newKeyPair();
// Public key: 32-byte Base64 → lưu Supabase (profiles.ecdh_public_key)
// Private key: 32-byte Base64 → lưu FlutterSecureStorage
```

**Lưu trữ khóa an toàn:**
```dart
// FlutterSecureStorage dùng Android Keystore / iOS Secure Enclave
const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
await storage.write(key: 'crypto_rsa_private', value: rsaPrivJson);
await storage.write(key: 'crypto_elgamal_private', value: elgPrivJson);
await storage.write(key: 'crypto_ecdh_private', value: ecdhPrivB64);
```

---

### 8.3 Thuật toán Diffie-Hellman (ECDH X25519)

**Mục đích**: Trao đổi khóa bí mật giữa 2 người dùng mà không cần truyền khóa qua mạng.

**Nguyên lý toán học:**
```
Alice có: private key a, public key A = g^a mod p
Bob   có: private key b, public key B = g^b mod p

SharedSecret = B^a mod p = A^b mod p = g^(ab) mod p
```

Trong Kilogram, sử dụng **Elliptic Curve variant (X25519)** — hiệu quả hơn DH cổ điển:
```
SharedSecret = scalar_multiply(alice_private, bob_public)
             = scalar_multiply(bob_private, alice_public)
```

**Ứng dụng trong mã hóa tin nhắn:**
```dart
// Người gửi
SharedSecret = ECDH(myPrivateKey, recipient.ecdhPublicKey)
AES_Key = SharedSecret.sublist(0, 32)  // 256-bit AES key

// Người nhận (tính được cùng AES_Key vì ECDH có tính đối xứng)
SharedSecret = ECDH(myPrivateKey, sender.ecdhPublicKey)
AES_Key = SharedSecret.sublist(0, 32)  // Kết quả giống hệt!
```

---

### 8.4 Thuật toán ElGamal

**Mục đích**: Mã hóa bất đối xứng — mã hóa AES session key bằng public key của người nhận.

**Nguyên lý toán học:**
```
Setup:    p (số nguyên tố 2048-bit, RFC 3526)
          g = 2 (generator)
          x (private key Bob) — bí mật
          y = g^x mod p (public key Bob) — công khai

Mã hóa (Alice mã hóa m cho Bob):
  Chọn ngẫu nhiên k
  c1 = g^k mod p
  c2 = m * y^k mod p
  → Gửi (c1, c2)

Giải mã (Bob giải mã):
  s = c1^x mod p  =  (g^k)^x  =  g^(kx)
  m = c2 * s^(-1) mod p
    = m * y^k * (g^(kx))^(-1)
    = m * g^(kx) * g^(-kx)
    = m ✓
```

**Ứng dụng trong Kilogram:**
```dart
// Mã hóa AES key (32 bytes) bằng ElGamal
final encryptedKey = _elgamalEncrypt(aesKeyBytes, recipientElGamalPublic);
// → Lưu vào messages.encrypted_key
// → Chỉ người nhận có private key x mới giải mã được
```

---

### 8.5 Thuật toán RSA-2048

**Mục đích**: Ký số (Digital Signature) — xác thực danh tính người gửi.

**Nguyên lý toán học:**
```
Sinh khóa: n = p * q (p, q là số nguyên tố lớn)
           e = 65537 (public exponent)
           d = e^(-1) mod φ(n) (private exponent)

Ký:        signature = hash(data)^d mod n
Xác minh:  hash_verify = signature^e mod n
           Hợp lệ nếu hash_verify == hash(data)
```

**Ứng dụng trong Kilogram:**
```dart
// Người gửi ký nội dung ciphertext
final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
signer.init(true, PrivateKeyParameter(rsaPrivateKey));
final signature = signer.generateSignature(utf8.encode(payload));
// → Lưu vào messages.signature

// Người nhận xác minh
signer.init(false, PublicKeyParameter(senderRsaPublicKey));
final isValid = signer.verifySignature(payload, signature);
// → Đảm bảo tin nhắn thực sự đến từ đúng người gửi
```

---

### 8.6 AES-256-GCM

**Mục đích**: Mã hóa nội dung tin nhắn bằng khóa đối xứng (nhanh, an toàn).

**Đặc điểm AES-256-GCM:**
- **AES** (Advanced Encryption Standard) với khóa 256-bit
- **GCM** (Galois/Counter Mode): tích hợp sẵn xác thực toàn vẹn (MAC)
- Không cần HMAC riêng — GCM tự phát hiện nếu ciphertext bị sửa đổi

```dart
// Mã hóa
final nonce     = AesGcm.with256bits().newNonce();      // 12 bytes random
final encrypted = await AesGcm.with256bits().encrypt(
  utf8.encode(plaintext),
  secretKey: SecretKey(aesKeyBytes),  // 32-byte key từ ECDH
  nonce: nonce,
);
// Lưu: ciphertext = "${encrypted.cipherText}.${nonce}.${encrypted.mac}"

// Giải mã
final decrypted = await AesGcm.with256bits().decrypt(
  SecretBox(ciphertextBytes, nonce: nonceBytes, mac: Mac(macBytes)),
  secretKey: SecretKey(aesKeyBytes),
);
```

---

### 8.7 Luồng mã hóa khi gửi tin nhắn

```
Alice gửi "Hello" cho Bob
│
├── BƯỚC 1: ECDH Key Exchange
│     SharedSecret = ECDH(Alice_privateKey, Bob_ecdhPublicKey)
│     AES_Key = SharedSecret.sublist(0, 32)
│
├── BƯỚC 2: AES-256-GCM Encrypt
│     nonce = random(12 bytes)
│     (ciphertext, mac) = AES_GCM_Encrypt("Hello", AES_Key, nonce)
│     combinedCipher = "${ciphertext}.${nonce}.${mac}"  [Base64]
│
├── BƯỚC 3: ElGamal Encrypt AES Key
│     k = random BigInt
│     c1 = g^k mod p
│     c2 = AES_Key * Bob_y^k mod p
│     encrypted_key = '{"c1":"...","c2":"..."}'
│
├── BƯỚC 4: RSA-2048 Sign
│     payload = "${combinedCipher}|${encrypted_key}|${hmac}"
│     signature = RSA_Sign(SHA256(payload), Alice_privateKey)
│
└── BƯỚC 5: Lưu vào Supabase
      messages.content       = ""           [trống]
      messages.ciphertext    = combinedCipher
      messages.encrypted_key = '{"c1":...}'
      messages.nonce         = nonce
      messages.signature     = signature
```

---

### 8.8 Luồng giải mã khi nhận tin nhắn

```
Bob nhận tin nhắn từ Alice
│
├── BƯỚC 1: ECDH Key Recovery
│     SharedSecret = ECDH(Bob_privateKey, Alice_ecdhPublicKey)
│     AES_Key = SharedSecret.sublist(0, 32)
│     [Tính được cùng AES_Key nhờ tính đối xứng của ECDH]
│
├── BƯỚC 2: RSA Signature Verify
│     payload = "${msg.ciphertext}|${msg.encrypted_key}|${msg.hmac}"
│     isValid = RSA_Verify(payload, msg.signature, Alice_rsaPublicKey)
│
├── BƯỚC 3: AES-256-GCM Decrypt
│     parts = msg.ciphertext.split('.')
│     plaintext = AES_GCM_Decrypt(parts[0], AES_Key, nonce=parts[1], mac=parts[2])
│     [GCM tự xác minh toàn vẹn — throw Exception nếu bị sửa đổi]
│
└── BƯỚC 4: Hiển thị
      message.content = "Hello" ✓
      [Hiển thị icon 🔒 xanh bên cạnh timestamp]
```

---

### 8.9 Chat nhóm — Group Session Key (GSK)

Do chat nhóm có nhiều người nhận, không thể dùng ECDH 1-1, hệ thống sử dụng **Group Session Key**:

```
Admin tạo nhóm:
  1. Tạo GSK = random(32 bytes)          [AES-256 key chung]
  2. Với mỗi thành viên:
     GSK_encrypted[member] = ElGamal_Encrypt(GSK, member.elgamal_public)
  3. Lưu vào bảng group_keys

Gửi tin nhắn nhóm:
  ciphertext = AES_256_GCM(message, GSK)
  → Chỉ những ai có và giải mã được GSK mới đọc được

Thành viên mới đọc tin:
  GSK = ElGamal_Decrypt(group_keys[me], my_private_key)
  message = AES_Decrypt(ciphertext, GSK)
```

---

### 8.10 Bảo vệ khóa riêng tư trên thiết bị

| Platform | Cơ chế lưu trữ |
|---|---|
| Android | **EncryptedSharedPreferences** + Android Keystore |
| iOS | **Keychain Services** (Secure Enclave nếu có) |

Khóa riêng tư **không bao giờ rời khỏi thiết bị**. Supabase chỉ nhận và lưu public keys.

---

### 8.11 Những gì server thấy vs không thấy

| Thông tin | Server (Supabase) thấy? | Giải thích |
|---|---|---|
| Nội dung tin nhắn | ❌ KHÔNG | Lưu dưới dạng ciphertext, không có key |
| Người gửi, người nhận | ✅ CÓ | profile_id, room_id vẫn rõ |
| Thời gian gửi | ✅ CÓ | created_at lưu rõ |
| Hình ảnh gửi | ✅ CÓ | URL công khai trên Storage |
| Khóa công khai | ✅ CÓ | Cần để người khác mã hóa |
| Khóa riêng tư | ❌ KHÔNG | Chỉ tồn tại trên thiết bị |

> **Kết luận**: Nội dung tin nhắn được bảo vệ hoàn toàn khỏi server (tương đương WhatsApp E2EE). Metadata (ai chat với ai) vẫn hiển thị với server — đây là giới hạn chung của mọi ứng dụng chat centralized.

---

## 9. Luồng hoạt động chính

### 9.1 Đăng ký tài khoản mới
```
[Người dùng] → Nhập email, password, username
    → signUp() → Supabase Auth tạo user
    → Trigger tự động tạo profile trong bảng profiles
    → GenerateKeyBundle():
        RSA-2048 keypair
        ElGamal keypair  
        ECDH X25519 keypair
    → Private keys → FlutterSecureStorage
    → Public keys → UPDATE profiles SET rsa_public_key=..., ...
    → Vào RoomsPage
```

### 9.2 Nhắn tin 1-1
```
[Alice mở chat với Bob]
    → Fetch Bob's public keys từ Supabase
    → setMessagesListener(roomId):
        → Load tin cũ (REST API)
        → Decrypt từng tin bằng ECDH + AES
        → Subscribe Realtime channel
    → Alice gửi "Hello":
        → ECDH(Alice_priv, Bob_pub) → AES key
        → AES_GCM_Encrypt("Hello") → ciphertext
        → ElGamal_Encrypt(AES_key, Bob's ElGamal pub) → encrypted_key
        → RSA_Sign(payload) → signature
        → INSERT vào messages
    → Bob nhận realtime event:
        → ECDH(Bob_priv, Alice_pub) → cùng AES key
        → AES_GCM_Decrypt(ciphertext) → "Hello"
        → RSA_Verify(signature, Alice's RSA pub) → ✓
        → Hiển thị "Hello" với icon 🔒
```

### 9.3 Tạo nhóm
```
[Người dùng] → Nhập tên nhóm, chọn thành viên
    → INSERT rooms (is_group=true, name=...)
    → INSERT room_participants (tất cả thành viên)
    → Tạo GSK (32-byte random)
    → Với mỗi thành viên: ElGamal_Encrypt(GSK, member_pub) → group_keys
    → Vào màn hình chat nhóm
```

---

## 10. Kết luận

### Tổng kết công nghệ sử dụng:

| Tầng | Công nghệ |
|---|---|
| Mobile framework | Flutter 3.x (Dart) |
| Backend | Supabase (PostgreSQL + Auth + Storage + Realtime) |
| State management | BLoC / Cubit pattern |
| Symmetric encryption | AES-256-GCM |
| Key exchange | ECDH X25519 (Diffie-Hellman trên Curve25519) |
| Asymmetric encryption | ElGamal (2048-bit safe prime RFC 3526) |
| Digital signature | RSA-2048 + SHA-256 |
| Key storage | FlutterSecureStorage (Android Keystore / iOS Keychain) |
| Realtime | Supabase Realtime (WebSocket + PostgreSQL Change) |
| Image storage | Supabase Storage |

### Điểm nổi bật của ứng dụng:
1. **E2EE thực sự** — Server không đọc được nội dung tin nhắn
2. **Kết hợp 3 hệ thống mật mã** (DH + ElGamal + RSA) — Độc đáo, nhiều lớp bảo vệ
3. **Backward compatible** — Tin nhắn cũ vẫn hiển thị bình thường
4. **Auto key generation** — User không cần làm gì thêm
5. **Realtime** — Tin nhắn cập nhật tức thì không cần reload
6. **RLS** — Phân quyền database chặt chẽ ở tầng server
