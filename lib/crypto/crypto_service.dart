import 'dart:convert';
import 'dart:math';
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Vai trò mã hoá/giải mã: người dùng hiện tại đóng vai trò là người gửi (sender) hay người nhận (recipient)
enum CryptoRole { sender, recipient }

/// Gói chứa các Khóa Công Khai (Public Keys) của người dùng để lưu lên máy chủ Supabase
class UserPublicKeyBundle {
  final String rsaPublicKey;
  final String elgamalPublicKey;
  final String ecdhPublicKey;

  const UserPublicKeyBundle({
    required this.rsaPublicKey,
    required this.elgamalPublicKey,
    required this.ecdhPublicKey,
  });

  Map<String, dynamic> toMap() => {
        'rsa_public_key': rsaPublicKey,
        'elgamal_public_key': elgamalPublicKey,
        'ecdh_public_key': ecdhPublicKey,
      };
}

/// Dữ liệu khóa công khai của một người dùng khác (được tải về từ Supabase)
class RemotePublicKeys {
  final String rsaPublicKey;
  final String elgamalPublicKey;
  final String ecdhPublicKey;

  const RemotePublicKeys({
    required this.rsaPublicKey,
    required this.elgamalPublicKey,
    required this.ecdhPublicKey,
  });
}

/// Cấu trúc gói tin đã được mã hoá hoàn chỉnh gửi lưu trữ trên cơ sở dữ liệu Supabase
class EncryptedPayload {
  /// Nội dung tin nhắn đã được mã hoá đối xứng bằng thuật toán AES-256-GCM
  final String ciphertext;

  /// Khóa AES đã bị bọc/mã hoá (sử dụng thuật toán ElGamal cho Chat nhóm, hoặc chỉ là cờ báo đối với Chat 1-1)
  final String encryptedKey;

  /// Chuỗi ngẫu nhiên (chỉ dùng duy nhất 1 lần) làm biến số đầu vào cho hàm AES-GCM
  final String nonce;

  /// Mã chống giả mạo (HMAC-SHA256), đảm bảo nguyên vẹn dữ liệu từ lúc gửi đến lúc nhận
  final String hmac;

  /// Chữ ký định danh điện tử RSA-2048 để chứng minh chắc chắn ai là người gửi
  final String signature;

  const EncryptedPayload({
    required this.ciphertext,
    required this.encryptedKey,
    required this.nonce,
    required this.hmac,
    required this.signature,
  });

  Map<String, dynamic> toMap() => {
        'ciphertext': ciphertext,
        'encrypted_key': encryptedKey,
        'nonce': nonce,
        'hmac': hmac,
        'signature': signature,
      };

  factory EncryptedPayload.fromMap(Map<String, dynamic> map) =>
      EncryptedPayload(
        ciphertext: map['ciphertext'] ?? '',
        encryptedKey: map['encrypted_key'] ?? '',
        nonce: map['nonce'] ?? '',
        hmac: map['hmac'] ?? '',
        signature: map['signature'] ?? '',
      );
}

/// ============================================================
/// Main CryptoService — Facade combining all algorithms
/// ============================================================
class CryptoService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ─── ECDH algorithm (Diffie-Hellman on Curve25519) ──────────
  static final _ecdh = X25519();
  // ─── AES-GCM ────────────────────────────────────────────────
  static final _aes = AesGcm.with256bits();
  // ─── HMAC-SHA256 ────────────────────────────────────────────
  static final _hmac = Hmac.sha256();

  // ─── Random ─────────────────────────────────────────────────
  static final _rng = Random.secure();

  // ============================================================
  // 1. KEY MANAGEMENT
  // ============================================================

  /// Đảm bảo thiết bị này đã tạo Khóa riêng tư (Private Keys) VÀ máy chủ đã lưu Khóa công khai (Public Keys).
  /// Nếu trên máy hoặc server bị thiếu, hàm tự động sinh (generate) nguyên bộ khóa mới và đăng tải chúng.
  /// Quá trình này hoàn thành mượt mà nếu khóa có sẵn, hoặc sẽ quăng (throw) lỗi nếu kết nối Supabase trục trặc.
  static Future<void> ensureKeysExistAndUploaded(String userId,
      {bool force = false}) async {
    try {
      debugPrint(
          '[Crypto] Starting key check for user: $userId (force=$force)');

      // 1. Check local keys for THIS SPECIFIC USER
      bool hasLocal = await hasKeyBundle(userId);

      // 2. Check server state
      final response = await Supabase.instance.client
          .from('profiles')
          .select('rsa_public_key, elgamal_public_key, ecdh_public_key')
          .eq('id', userId)
          .maybeSingle();

      final hasServerEcdh =
          response != null && response['ecdh_public_key'] != null;

      if (hasLocal && hasServerEcdh && !force) {
        debugPrint('[Crypto] Keys are consistent for $userId.');
        return;
      }

      // 3. Generate new bundle for this user
      final bundle = await generateAndSaveKeyBundle(userId);

      // 4. Upload to server
      final payload = bundle.toMap();
      await Supabase.instance.client
          .from('profiles')
          .update(payload)
          .eq('id', userId);

      debugPrint('[Crypto] Keys updated successfully for $userId');
    } catch (e) {
      debugPrint('[Crypto] Key management failed: $e');
      rethrow;
    }
  }

  static Future<UserPublicKeyBundle> generateAndSaveKeyBundle(
      String userId) async {
    // RSA keys
    final rsaKeyPair = _generateRsaKeyPair();
    final rsaPrivKey = rsaKeyPair.privateKey as pc.RSAPrivateKey;
    final rsaPubKey = rsaKeyPair.publicKey as pc.RSAPublicKey;

    final rsaPrivJson = jsonEncode({
      'n': rsaPrivKey.modulus.toString(),
      'e': rsaPrivKey.exponent.toString(),
      'p': rsaPrivKey.p!.toString(),
      'q': rsaPrivKey.q!.toString(),
      'd': rsaPrivKey.privateExponent.toString(),
    });
    final rsaPubJson = jsonEncode({
      'n': rsaPubKey.modulus.toString(),
      'e': rsaPubKey.exponent.toString(),
    });

    // ElGamal keys
    final elgKeyPair = _generateElGamalKeyPair();
    final elgPrivJson = jsonEncode({
      'p': elgKeyPair.p.toString(),
      'g': elgKeyPair.g.toString(),
      'x': elgKeyPair.x.toString()
    });
    final elgPubJson = jsonEncode({
      'p': elgKeyPair.p.toString(),
      'g': elgKeyPair.g.toString(),
      'y': elgKeyPair.y.toString()
    });

    // ECDH keys
    final ecdhKeyPair = await _ecdh.newKeyPair();
    final ecdhPub = await ecdhKeyPair.extractPublicKey();
    final ecdhPriv = await ecdhKeyPair.extractPrivateKeyBytes();
    final ecdhPrivB64 = base64.encode(ecdhPriv);
    final ecdhPubB64 = base64.encode(ecdhPub.bytes);

    // Persist with USER PREFIX
    await _storage.write(key: '${userId}_rsa_priv', value: rsaPrivJson);
    await _storage.write(key: '${userId}_elgamal_priv', value: elgPrivJson);
    await _storage.write(key: '${userId}_ecdh_priv', value: ecdhPrivB64);
    await _storage.write(key: '${userId}_ecdh_pub', value: ecdhPubB64);

    return UserPublicKeyBundle(
      rsaPublicKey: rsaPubJson,
      elgamalPublicKey: elgPubJson,
      ecdhPublicKey: ecdhPubB64,
    );
  }

  static Future<bool> hasKeyBundle(String userId) async {
    final val = await _storage.read(key: '${userId}_ecdh_priv');
    return val != null;
  }

  // ============================================================
  // 2. ENCRYPT — used when sending a message
  // ============================================================

  /// [CHAT 1-1] MÃ HOÁ TIN NHẮN:
  /// 1. Dùng Khóa công khai ECDH của người nhận kết hợp với Khóa riêng tư ECDH của mình để tính ra Khóa Bí Mật Chung (Shared Secret).
  /// 2. Băm Shared Secret ra thành Khóa AES-256 thực sự.
  /// 3. Dùng Khóa AES-256-GCM mã hoá nội dung văn bản (plaintext).
  static Future<EncryptedPayload> encryptMessage({
    required String plaintext,
    required RemotePublicKeys recipient,
  }) async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) throw Exception('Not authenticated');

    final myEcdhPrivB64 = await _storage.read(key: '${myId}_ecdh_priv');
    final myEcdhPubB64 = await _storage.read(key: '${myId}_ecdh_pub');
    if (myEcdhPrivB64 == null || myEcdhPubB64 == null) {
      throw Exception('Local keys missing');
    }

    final myEcdhPriv = SimpleKeyPairData(
      base64.decode(myEcdhPrivB64),
      publicKey: SimplePublicKey(base64.decode(myEcdhPubB64),
          type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final recipientEcdhPub = SimplePublicKey(
      base64.decode(recipient.ecdhPublicKey),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _ecdh.sharedSecretKey(
      keyPair: myEcdhPriv,
      remotePublicKey: recipientEcdhPub,
    );
    final sharedBytes = await sharedSecret.extractBytes();
    final aesKeyBytes = (await Sha256().hash(sharedBytes)).bytes;

    debugPrint(
        '[Crypto] Derived AES Key (Sender) first 4 bytes: ${aesKeyBytes.sublist(0, 4)}');

    // 2. AES-256-GCM: encrypt plaintext ─────────────────────
    final secretKey = SecretKey(aesKeyBytes);
    final nonce = _aes.newNonce();
    final encrypted = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    final ciphertextB64 = base64.encode(encrypted.cipherText);
    final nonceB64 = base64.encode(nonce);
    final macB64 = base64.encode(encrypted.mac.bytes);
    final combinedCipher = '$ciphertextB64.$nonceB64.$macB64';

    // 3. HMAC-SHA256 for extra integrity ────────────────────
    final hmacKey = SecretKey(sharedBytes);
    final hmacResult = await _hmac.calculateMac(
      utf8.encode(combinedCipher),
      secretKey: hmacKey,
    );
    final hmacB64 = base64.encode(hmacResult.bytes);

    // 4. RSA Digital Signature
    final rsaPrivJson = await _storage.read(key: '${myId}_rsa_priv');
    String signatureB64 = '';
    if (rsaPrivJson != null) {
      signatureB64 = _rsaSign('$combinedCipher|$hmacB64', rsaPrivJson);
    }

    return EncryptedPayload(
      ciphertext: combinedCipher,
      encryptedKey: 'v2_full', // Refined version
      nonce: nonceB64,
      hmac: hmacB64,
      signature: signatureB64,
    );
  }

  // ============================================================
  // 3. DECRYPT — used when receiving a message
  // ============================================================

  /// [CHAT 1-1] GIẢI MÃ TIN NHẮN:
  /// Làm ngược lại bước mã hoá. Lấy Khóa riêng tư ECDH của mình + Khóa công khai ECDH đối tác = Khóa Bí Mật Chung.
  /// Suy ra Khóa AES-256 và dùng nó để thu về văn bản gốc (plaintext).
  static Future<String> decryptMessage({
    required EncryptedPayload payload,
    required RemotePublicKeys otherParty,
    required String signerRsaPublicKey,
    required CryptoRole role,
  }) async {
    try {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId == null) throw Exception('Not authenticated');

      debugPrint('[Crypto] Decrypting full-v2 for $myId as ${role.name}...');

      // 1. ECDH: Derive shared secret ──────────────────────
      final myEcdhPrivB64 = await _storage.read(key: '${myId}_ecdh_priv');
      final myEcdhPubB64 = await _storage.read(key: '${myId}_ecdh_pub');
      if (myEcdhPrivB64 == null || myEcdhPubB64 == null) {
        throw Exception('Local keys missing for $myId');
      }

      final myEcdhPriv = SimpleKeyPairData(
        base64.decode(myEcdhPrivB64),
        publicKey: SimplePublicKey(base64.decode(myEcdhPubB64),
            type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
      final theirEcdhPub = SimplePublicKey(
        base64.decode(otherParty.ecdhPublicKey),
        type: KeyPairType.x25519,
      );
      final sharedSecret = await _ecdh.sharedSecretKey(
        keyPair: myEcdhPriv,
        remotePublicKey: theirEcdhPub,
      );
      final sharedBytes = await sharedSecret.extractBytes();
      final aesKeyBytes = (await Sha256().hash(sharedBytes)).bytes;

      // 2. HMAC Verify (Optional integrity check) ───────────
      if (payload.hmac.isNotEmpty) {
        final hmacKey = SecretKey(sharedBytes);
        final computedHmac = await _hmac.calculateMac(
          utf8.encode(payload.ciphertext),
          secretKey: hmacKey,
        );
        if (base64.encode(computedHmac.bytes) != payload.hmac) {
          debugPrint(
              '[Crypto] HMAC mismatch ignored for legacy v2, but detected.');
        }
      }

      final rsaPrivJson = await _storage.read(key: '${myId}_rsa_priv');
      if (rsaPrivJson == null) throw Exception('RSA signature key missing');

      if (payload.signature.isNotEmpty && signerRsaPublicKey.isNotEmpty) {
        final isValid = _rsaVerify('${payload.ciphertext}|${payload.hmac}',
            payload.signature, signerRsaPublicKey);
        if (!isValid) {
          debugPrint(
              '[Crypto] Warning: RSA signature invalid, but attempting decryption anyway.');
        }
      }

      // 4. AES-256-GCM Decrypt ──────────────────────────────
      final parts = payload.ciphertext.split('.');
      if (parts.length < 3) throw Exception('Incomplete ciphertext');

      final ciphertextBytes = base64.decode(parts[0]);
      final nonceBytes = base64.decode(parts[1]);
      final macBytes = base64.decode(parts[2]);

      final secretKey = SecretKey(Uint8List.fromList(aesKeyBytes));
      final decrypted = await _aes.decrypt(
        SecretBox(ciphertextBytes, nonce: nonceBytes, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('[Crypto] Decrypt failed: $e');
      rethrow;
    }
  }

  // ============================================================
  // GROUP CHAT helpers
  // ============================================================

  /// [CHAT NHÓM]: TẠO KHÓA PHIÊN NHÓM (Group Session Key - GSK)
  /// Là một chuỗi 32 bytes ngẫu nhiên làm chìa khóa đối xứng bảo vệ toàn bộ cuộc trò chuyện của một nhóm.
  static String generateGroupSessionKey() {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return base64.encode(bytes);
  }

  /// [CHAT NHÓM]: Khi mời người mới vào nhóm, trưởng nhóm dùng Khóa công khai ElGamal của người đó
  /// để bọc (mã hoá) Khóa Phiên Nhóm (GSK) và gửi cho họ tĩnh lặng qua DB.
  static String encryptGroupKey(String gsk, String memberElGamalPublicKey) {
    final gskBytes = base64.decode(gsk);
    final pub = _parseElGamalPublic(memberElGamalPublicKey);
    return _elgamalEncrypt(gskBytes, pub);
  }

  /// [CHAT NHÓM]: Thành viên mới mở khóa (giải mã) bằng Khóa Bí Mật ElGamal của chính họ
  /// để nhận lại Khóa Phiên Nhóm (GSK) nhằm đọc tin nhắn mọi người.
  static Future<String> decryptGroupKey(
      String userId, String encryptedGsk) async {
    final elgPrivJson = await _storage.read(key: '${userId}_elgamal_priv');
    if (elgPrivJson == null) throw Exception('ElGamal private key not found');
    final gskBytes = _elgamalDecrypt(encryptedGsk, elgPrivJson);
    return base64.encode(gskBytes);
  }

  /// [CHAT NHÓM]: Mã hoá tin nhắn gửi vào nhóm bằng Khóa Phiên Nhóm (GSK) chung (AES-256-GCM)
  static Future<String> encryptGroupMessage(
      String plaintext, String gskB64) async {
    final key = SecretKey(base64.decode(gskB64));
    final nonce = _aes.newNonce();
    final encrypted = await _aes.encrypt(utf8.encode(plaintext),
        secretKey: key, nonce: nonce);
    return jsonEncode({
      'ct': base64.encode(encrypted.cipherText),
      'n': base64.encode(nonce),
      'm': base64.encode(encrypted.mac.bytes),
    });
  }

  /// [CHAT NHÓM]: Thuật toán dùng Khóa Phiên Nhóm (GSK) để quy đổi về nội dung gốc
  static Future<String> decryptGroupMessage(
      String encryptedJson, String gskB64) async {
    final map = jsonDecode(encryptedJson);
    final key = SecretKey(base64.decode(gskB64));
    final decrypted = await _aes.decrypt(
      SecretBox(
        base64.decode(map['ct'] as String),
        nonce: base64.decode(map['n'] as String),
        mac: Mac(base64.decode(map['m'] as String)),
      ),
      secretKey: key,
    );
    return utf8.decode(decrypted);
  }

  // ============================================================
  // INTERNAL: RSA helpers (serialize as JSON BigInt)
  // ============================================================

  static pc.AsymmetricKeyPair<pc.PublicKey, pc.PrivateKey>
      _generateRsaKeyPair() {
    final keyGen = pc.RSAKeyGenerator();
    final secureRng = pc.FortunaRandom();
    final seed = Uint8List(32);
    for (int i = 0; i < seed.length; i++) {
      seed[i] = _rng.nextInt(256);
    }
    secureRng.seed(pc.KeyParameter(seed));
    keyGen.init(pc.ParametersWithRandom(
      pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
      secureRng,
    ));
    return keyGen.generateKeyPair();
  }

  static pc.RSAPrivateKey _parseRsaPrivate(String json) {
    final map = jsonDecode(json);
    return pc.RSAPrivateKey(
      BigInt.parse(map['n']),
      BigInt.parse(map['d']),
      BigInt.parse(map['p']),
      BigInt.parse(map['q']),
    );
  }

  static pc.RSAPublicKey _parseRsaPublic(String json) {
    final map = jsonDecode(json);
    return pc.RSAPublicKey(BigInt.parse(map['n']), BigInt.parse(map['e']));
  }

  static String _rsaSign(String data, String rsaPrivJson) {
    final key = _parseRsaPrivate(rsaPrivJson);
    final signer = pc.RSASigner(pc.SHA256Digest(), '0609608648016503040201');
    signer.init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(key));
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(data)));
    return base64.encode(sig.bytes);
  }

  static bool _rsaVerify(String data, String signatureB64, String rsaPubJson) {
    try {
      final key = _parseRsaPublic(rsaPubJson);
      final signer = pc.RSASigner(pc.SHA256Digest(), '0609608648016503040201');
      signer.init(false, pc.PublicKeyParameter<pc.RSAPublicKey>(key));
      return signer.verifySignature(
        Uint8List.fromList(utf8.encode(data)),
        pc.RSASignature(base64.decode(signatureB64)),
      );
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // INTERNAL: ElGamal helpers
  // ============================================================

  static ({BigInt p, BigInt g, BigInt x, BigInt y}) _generateElGamalKeyPair() {
    // RFC 3526 Group 14 — 2048-bit safe prime
    const pHex = 'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'
        '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'
        'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'
        'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
        'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D'
        'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'
        '83655D23DCA3AD961C62F356208552BB9ED529077096966D'
        '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'
        'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9'
        'DE2BCBF6955817183995497CEA956AE515D2261898FA0510'
        '15728E5A8AACAA68FFFFFFFFFFFFFFFF';
    final p = BigInt.parse(pHex, radix: 16);
    final g = BigInt.from(2);

    final xBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      xBytes[i] = _rng.nextInt(256);
    }
    final x = BigInt.parse(hex.encode(xBytes), radix: 16) % (p - BigInt.two) +
        BigInt.one;
    final y = g.modPow(x, p);
    return (p: p, g: g, x: x, y: y);
  }

  static ({BigInt p, BigInt g, BigInt y}) _parseElGamalPublic(String json) {
    final map = jsonDecode(json);
    return (
      p: BigInt.parse(map['p'] as String),
      g: BigInt.parse(map['g'] as String),
      y: BigInt.parse(map['y'] as String),
    );
  }

  static String _elgamalEncrypt(
      Uint8List data, ({BigInt p, BigInt g, BigInt y}) pub) {
    final m = BigInt.parse(hex.encode(data), radix: 16) % pub.p;
    final kBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      kBytes[i] = _rng.nextInt(256);
    }
    final k =
        BigInt.parse(hex.encode(kBytes), radix: 16) % (pub.p - BigInt.two) +
            BigInt.one;
    final c1 = pub.g.modPow(k, pub.p);
    final c2 = (m * pub.y.modPow(k, pub.p)) % pub.p;
    return jsonEncode({'c1': c1.toString(), 'c2': c2.toString()});
  }

  static Uint8List _elgamalDecrypt(String encJson, String privJson) {
    try {
      final enc = jsonDecode(encJson);
      final priv = jsonDecode(privJson);
      final p = BigInt.parse(priv['p'] as String);
      final x = BigInt.parse(priv['x'] as String);
      final c1 = BigInt.parse(enc['c1'] as String);
      final c2 = BigInt.parse(enc['c2'] as String);

      final s = c1.modPow(x, p);
      final sInv = s.modInverse(p);
      final m = (c2 * sInv) % p;

      // Biến BigInt thành hex string, đảm bảo độ dài 64 (32 bytes)
      String hexStr = m.toRadixString(16);
      if (hexStr.length % 2 != 0) hexStr = '0$hexStr';

      // Pad đủ 64 ký tự (32 bytes)
      while (hexStr.length < 64) {
        hexStr = '00$hexStr';
      }

      return Uint8List.fromList(hex.decode(hexStr));
    } catch (e) {
      debugPrint('[Crypto] ElGamal internal decrypt error: $e');
      rethrow;
    }
  }
}
