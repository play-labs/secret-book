import 'dart:convert';
import 'dart:typed_data';

import '../services/crypto_service.dart';

abstract class BundleSerializer {
  Uint8List serializeEnvelope(VaultEncryptionEnvelope envelope);
  VaultEncryptionEnvelope deserializeEnvelope(Uint8List bytes);
}

class JsonBundleSerializer implements BundleSerializer {
  @override
  Uint8List serializeEnvelope(VaultEncryptionEnvelope envelope) {
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope.toMap())));
  }

  @override
  VaultEncryptionEnvelope deserializeEnvelope(Uint8List bytes) {
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final version = payload['version'] as int? ?? 0;
    if (version != 1) {
      throw const FormatException('Unsupported vault bundle version.');
    }
    return VaultEncryptionEnvelope.fromMap(payload);
  }
}
