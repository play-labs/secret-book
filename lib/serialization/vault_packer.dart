import 'dart:convert';
import 'dart:typed_data';

import '../models/asset.dart';
import '../models/document.dart';
import '../models/document_vault.dart';

class VaultPacker {
  Uint8List pack(DocumentVault vault) {
    final payload = <String, dynamic>{
      'format': 'secret-book-vault',
      'version': 1,
      'manifest': _buildManifest(vault),
      'docs': {
        for (final doc in vault.documents) 'docs/${doc.id}.md': doc.content,
      },
      'assets': {
        for (final asset in vault.assets) asset.path: base64Encode(asset.bytes),
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  DocumentVault unpack(Uint8List bytes) {
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final format = payload['format'] as String? ?? '';
    final version = payload['version'] as int? ?? 0;
    if (format != 'secret-book-vault' || version != 1) {
      throw const FormatException('Unsupported vault payload format.');
    }

    final manifest = payload['manifest'] as Map<String, dynamic>;
    final docs = payload['docs'] as Map<String, dynamic>;
    final assetsPayload = payload['assets'] as Map<String, dynamic>? ?? const {};
    final entries = manifest['documents'] as List<dynamic>;
    final assetEntries = manifest['assets'] as List<dynamic>? ?? const [];

    return DocumentVault(
      revision: manifest['revision'] as int,
      documents: entries.map((entry) {
        final map = entry as Map<String, dynamic>;
        final docPath = map['path'] as String;
        return DocumentItem(
          id: map['id'] as String,
          title: map['title'] as String,
          content: docs[docPath] as String? ?? '',
          tags: List<String>.from(map['tags'] as List<dynamic>),
          assetRefs: List<String>.from(map['assetRefs'] as List<dynamic>? ?? const []),
          createdAt: DateTime.parse(map['createdAt'] as String),
          updatedAt: DateTime.parse(map['updatedAt'] as String),
        );
      }).toList(),
      assets: assetEntries.map((entry) {
        final map = Map<String, dynamic>.from(entry as Map<String, dynamic>);
        final path = map['path'] as String;
        map['bytesBase64'] = assetsPayload[path] as String? ?? map['bytesBase64'];
        return AssetItem.fromMap(map);
      }).toList(),
    );
  }

  Map<String, dynamic> _buildManifest(DocumentVault vault) {
    return {
      'revision': vault.revision,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'documents': vault.documents.map(_documentEntry).toList(),
      'assets': vault.assets.map((asset) => asset.copyWith(bytes: Uint8List(0)).toMap()).toList(),
    };
  }

  Map<String, dynamic> _documentEntry(DocumentItem doc) {
    return {
      'id': doc.id,
      'title': doc.title,
      'tags': doc.tags,
      'assetRefs': doc.assetRefs,
      'path': 'docs/${doc.id}.md',
      'createdAt': doc.createdAt.toIso8601String(),
      'updatedAt': doc.updatedAt.toIso8601String(),
    };
  }
}
