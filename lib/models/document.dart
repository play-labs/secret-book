class DocumentItem {
  DocumentItem({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    required this.assetRefs,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final List<String> assetRefs;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'tags': tags,
      'assetRefs': assetRefs,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DocumentItem.fromMap(Map<String, dynamic> map) {
    return DocumentItem(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      tags: List<String>.from(map['tags'] as List<dynamic>),
      assetRefs: List<String>.from((map['assetRefs'] as List<dynamic>? ?? const [])),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  DocumentItem copyWith({
    String? title,
    String? content,
    List<String>? tags,
    List<String>? assetRefs,
    DateTime? updatedAt,
  }) {
    return DocumentItem(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      assetRefs: assetRefs ?? this.assetRefs,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
