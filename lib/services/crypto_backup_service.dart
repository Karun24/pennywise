import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class CryptoBackupException implements Exception {
  const CryptoBackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Provides AES-256 encryption and decryption for password-protected backups.
class CryptoBackupService {
  const CryptoBackupService();

  static const formatId = 'pennywise-encrypted-backup';
  static const formatVersion = 1;

  static Uint8List _randomBytes(int length) {
    final rand = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = rand.nextInt(256);
    }
    return bytes;
  }

  /// Derives a 32-byte (256-bit) AES key from [password] and [saltBytes].
  static List<int> _deriveKey(String password, List<int> saltBytes) {
    // Two rounds of SHA-256 with salt for key hardening
    final first = sha256.convert([...saltBytes, ...utf8.encode(password)]).bytes;
    return sha256.convert([...first, ...saltBytes]).bytes;
  }

  /// Encrypts [plainTextJson] with AES-256-CBC using a key derived from [password].
  String encrypt(String plainTextJson, String password) {
    if (password.trim().isEmpty) {
      throw const CryptoBackupException('Password cannot be empty.');
    }

    final saltBytes = _randomBytes(16);
    final ivBytes = _randomBytes(16);
    final keyBytes = _deriveKey(password, saltBytes);

    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encrypt(plainTextJson, iv: iv);

    final container = {
      'format': formatId,
      'version': formatVersion,
      'salt': base64Encode(saltBytes),
      'iv': base64Encode(ivBytes),
      'ciphertext': encrypted.base64,
      'createdAt': DateTime.now().toIso8601String(),
    };

    return const JsonEncoder.withIndent('  ').convert(container);
  }

  /// Checks whether [source] is an encrypted PennyWise backup.
  static bool isEncrypted(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return decoded['format'] == formatId;
      }
    } catch (_) {}
    return false;
  }

  /// Decrypts [encryptedJson] using [password]. Returns the original JSON string.
  /// Throws [CryptoBackupException] if the password is wrong or format is invalid.
  String decrypt(String encryptedJson, String password) {
    final Object? root;
    try {
      root = jsonDecode(encryptedJson);
    } catch (_) {
      throw const CryptoBackupException('Invalid encrypted backup file format.');
    }

    if (root is! Map) {
      throw const CryptoBackupException('Invalid encrypted backup container.');
    }

    if (root['format'] != formatId) {
      throw const CryptoBackupException('Not an encrypted PennyWise backup.');
    }

    try {
      final saltBytes = base64Decode(root['salt'] as String);
      final ivBytes = base64Decode(root['iv'] as String);
      final ciphertextBase64 = root['ciphertext'] as String;

      final keyBytes = _deriveKey(password, saltBytes);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final decrypted =
          encrypter.decrypt(enc.Encrypted.fromBase64(ciphertextBase64), iv: iv);
      return decrypted;
    } catch (_) {
      throw const CryptoBackupException(
          'Incorrect password or corrupted backup file.');
    }
  }
}
