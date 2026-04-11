import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

import '../models/encryption_profile.dart';

class VaultEncryptionEnvelope {
  const VaultEncryptionEnvelope({
    required this.version,
    required this.revision,
    required this.savedAt,
    required this.salt,
    required this.nonce,
    required this.mac,
    required this.cipherText,
    required this.kdfMemory,
    required this.kdfIterations,
    required this.kdfParallelism,
  });

  final int version;
  final int revision;
  final DateTime savedAt;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List mac;
  final Uint8List cipherText;
  final int kdfMemory;
  final int kdfIterations;
  final int kdfParallelism;

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'revision': revision,
      'savedAt': savedAt.toIso8601String(),
      'kdf': {
        'name': 'argon2id',
        'memory': kdfMemory,
        'iterations': kdfIterations,
        'parallelism': kdfParallelism,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'name': 'xchacha20poly1305',
        'nonce': base64Encode(nonce),
        'mac': base64Encode(mac),
      },
      'payload': base64Encode(cipherText),
    };
  }

  factory VaultEncryptionEnvelope.fromMap(Map<String, dynamic> map) {
    final kdf = map['kdf'] as Map<String, dynamic>;
    final cipher = map['cipher'] as Map<String, dynamic>;
    return VaultEncryptionEnvelope(
      version: map['version'] as int,
      revision: map['revision'] as int,
      savedAt: DateTime.parse(map['savedAt'] as String),
      salt: Uint8List.fromList(base64Decode(kdf['salt'] as String)),
      nonce: Uint8List.fromList(base64Decode(cipher['nonce'] as String)),
      mac: Uint8List.fromList(base64Decode(cipher['mac'] as String)),
      cipherText: Uint8List.fromList(base64Decode(map['payload'] as String)),
      kdfMemory: kdf['memory'] as int,
      kdfIterations: kdf['iterations'] as int,
      kdfParallelism: kdf['parallelism'] as int,
    );
  }
}

class CryptoService {
  CryptoService({
    Argon2id? kdf,
    Cipher? cipher,
  })  : _kdf = kdf ??
            Argon2id(
              memory: 131072,
              iterations: 3,
              parallelism: 1,
              hashLength: 32,
            ),
        _cipher = cipher ?? Xchacha20.poly1305Aead();

  final Argon2id _kdf;
  final Cipher _cipher;

  VaultKdfSettings get kdfSettings => VaultKdfSettings(
        memoryKiB: _kdf.memory,
        iterations: _kdf.iterations,
        parallelism: _kdf.parallelism,
      );

  Future<VaultEncryptionEnvelope> encrypt({
    required String password,
    required Uint8List plainBytes,
    required int revision,
  }) async {
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => _randomByte()));
    final secretKey = await _deriveKey(
      password: password,
      salt: salt,
      memory: _kdf.memory,
      iterations: _kdf.iterations,
      parallelism: _kdf.parallelism,
    );
    final nonce = Uint8List.fromList(List<int>.generate(24, (_) => _randomByte()));
    final savedAt = DateTime.now().toUtc();
    final aad = utf8.encode(
      _buildAssociatedData(
        revision: revision,
        savedAt: savedAt,
        kdfMemory: _kdf.memory,
        kdfIterations: _kdf.iterations,
        kdfParallelism: _kdf.parallelism,
      ),
    );
    final secretBox = await _cipher.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    return VaultEncryptionEnvelope(
      version: 1,
      revision: revision,
      savedAt: savedAt,
      salt: salt,
      nonce: Uint8List.fromList(secretBox.nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      cipherText: Uint8List.fromList(secretBox.cipherText),
      kdfMemory: _kdf.memory,
      kdfIterations: _kdf.iterations,
      kdfParallelism: _kdf.parallelism,
    );
  }

  Future<Uint8List> decrypt({
    required String password,
    required VaultEncryptionEnvelope envelope,
  }) async {
    final secretKey = await _deriveKey(
      password: password,
      salt: envelope.salt,
      memory: envelope.kdfMemory,
      iterations: envelope.kdfIterations,
      parallelism: envelope.kdfParallelism,
    );
    final aad = utf8.encode(
      _buildAssociatedData(
        revision: envelope.revision,
        savedAt: envelope.savedAt,
        kdfMemory: envelope.kdfMemory,
        kdfIterations: envelope.kdfIterations,
        kdfParallelism: envelope.kdfParallelism,
      ),
    );
    final secretBox = SecretBox(
      envelope.cipherText,
      nonce: envelope.nonce,
      mac: Mac(envelope.mac),
    );
    final clearBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: aad,
    );
    return Uint8List.fromList(clearBytes);
  }

  Future<SecretKey> _deriveKey({
    required String password,
    required Uint8List salt,
    required int memory,
    required int iterations,
    required int parallelism,
  }) {
    return Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: 32,
    ).deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
  }

  String _buildAssociatedData({
    required int revision,
    required DateTime savedAt,
    required int kdfMemory,
    required int kdfIterations,
    required int kdfParallelism,
  }) {
    return jsonEncode({
      'version': 1,
      'revision': revision,
      'savedAt': savedAt.toIso8601String(),
      'kdf': {
        'name': 'argon2id',
        'memory': kdfMemory,
        'iterations': kdfIterations,
        'parallelism': kdfParallelism,
      },
      'cipher': 'xchacha20poly1305',
    });
  }
}

int _randomByte() {
  return SecureRandom.safe.nextInt(256);
}
