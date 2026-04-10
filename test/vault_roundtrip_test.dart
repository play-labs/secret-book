import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_book/models/asset.dart';
import 'package:secret_book/models/document.dart';
import 'package:secret_book/models/document_vault.dart';
import 'package:secret_book/serialization/vault_packer.dart';
import 'package:secret_book/services/crypto_service.dart';

void main() {
  test('vault packer preserves document metadata and content', () {
    final vault = DocumentVault.seeded();
    final packer = VaultPacker();

    final bytes = packer.pack(vault);
    final unpacked = packer.unpack(bytes);

    expect(unpacked.revision, vault.revision);
    expect(unpacked.documents.length, vault.documents.length);
    expect(unpacked.documents.first.id, vault.documents.first.id);
    expect(unpacked.documents.first.title, vault.documents.first.title);
    expect(unpacked.documents.first.content, vault.documents.first.content);
    expect(unpacked.documents.first.tags, vault.documents.first.tags);
  });

  test('vault packer preserves embedded asset bytes', () {
    final now = DateTime.now();
    final vault = DocumentVault(
      revision: 2,
      documents: [
        DocumentItem(
          id: 'doc-image',
          title: 'Image Doc',
          content: '![demo](assets/20260409-120000-001.png)',
          tags: const ['image'],
          assetRefs: const ['assets/20260409-120000-001.png'],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      assets: [
        AssetItem(
          id: 'asset-001',
          path: 'assets/20260409-120000-001.png',
          mediaType: 'image/png',
          size: 4,
          bytes: Uint8List.fromList(const [1, 2, 3, 4]),
          createdAt: now,
        ),
      ],
    );
    final packer = VaultPacker();

    final bytes = packer.pack(vault);
    final unpacked = packer.unpack(bytes);

    expect(unpacked.assets, hasLength(1));
    expect(unpacked.assets.first.path, vault.assets.first.path);
    expect(unpacked.assets.first.bytes, vault.assets.first.bytes);
    expect(unpacked.documents.first.assetRefs, vault.documents.first.assetRefs);
  });

  test('crypto service decrypts previously encrypted vault payload', () async {
    final packer = VaultPacker();
    final crypto = CryptoService();
    final plainBytes = packer.pack(DocumentVault.seeded());

    final envelope = await crypto.encrypt(
      password: 'secret-passphrase',
      plainBytes: plainBytes,
      revision: 7,
    );
    final decryptedBytes = await crypto.decrypt(
      password: 'secret-passphrase',
      envelope: envelope,
    );

    expect(decryptedBytes, plainBytes);
  });
}
