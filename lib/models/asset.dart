import 'dart:convert';
import 'dart:typed_data';

class AssetItem {
  const AssetItem({
    required this.id,
    required this.path,
    required this.mediaType,
    required this.size,
    required this.bytes,
    required this.createdAt,
  });

  final String id;
  final String path;
  final String mediaType;
  final int size;
  final Uint8List bytes;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'mediaType': mediaType,
      'size': size,
      'bytesBase64': base64Encode(bytes),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AssetItem.fromMap(Map<String, dynamic> map) {
    final rawBytes = map['bytesBase64'] as String?;
    return AssetItem(
      id: map['id'] as String,
      path: map['path'] as String,
      mediaType: map['mediaType'] as String,
      size: map['size'] as int,
      bytes: rawBytes == null ? Uint8List(0) : base64Decode(rawBytes),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  AssetItem copyWith({
    String? id,
    String? path,
    String? mediaType,
    int? size,
    Uint8List? bytes,
    DateTime? createdAt,
  }) {
    return AssetItem(
      id: id ?? this.id,
      path: path ?? this.path,
      mediaType: mediaType ?? this.mediaType,
      size: size ?? this.size,
      bytes: bytes ?? this.bytes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
