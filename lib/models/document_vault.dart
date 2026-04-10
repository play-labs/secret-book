import 'document.dart';
import 'asset.dart';

class DocumentVault {
  DocumentVault({
    required this.revision,
    required this.documents,
    required this.assets,
  });

  final int revision;
  final List<DocumentItem> documents;
  final List<AssetItem> assets;

  factory DocumentVault.seeded() {
    final now = DateTime.now();
    return DocumentVault(
      revision: 1,
      documents: [
        DocumentItem(
          id: 'doc-001',
          title: '欢迎使用 Secret Book',
          content: '''# 欢迎

这是一个个人加密文档管理应用的原型版本。

## 当前能力

- 解锁本地保险库
- 文档列表与搜索
- 标题、正文编辑
- Markdown 实时预览
- `vault.bundle` 序列化与加密存储

## 规划中的能力

1. 附件与图片导入
2. 更完整的虚拟文件系统布局
3. 远端同步冲突处理
4. 更完善的设置与诊断
''',
          tags: const [],
          assetRefs: const [],
          createdAt: now.subtract(const Duration(days: 3)),
          updatedAt: now.subtract(const Duration(minutes: 18)),
        ),
        DocumentItem(
          id: 'doc-002',
          title: '同步策略草案',
          content: '''# 同步策略

每次本地保存之后：

1. 重建内存中的保险库对象
2. 生成新的 revision
3. 上传前检查远端 revision
4. 如果远端已变化，则停止覆盖并提示拉取
''',
          tags: const [],
          assetRefs: const [],
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(hours: 2, minutes: 12)),
        ),
        DocumentItem(
          id: 'doc-003',
          title: '保险库结构',
          content: '''# 保险库结构

```text
/vault
  /docs
  /assets
  manifest.json
```

图片和其他二进制文件可以存放在 `assets/` 目录中。
''',
          tags: const [],
          assetRefs: const [],
          createdAt: now.subtract(const Duration(days: 1)),
          updatedAt: now.subtract(const Duration(hours: 6, minutes: 5)),
        ),
      ],
      assets: const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'revision': revision,
      'documents': documents.map((doc) => doc.toMap()).toList(),
      'assets': assets.map((asset) => asset.toMap()).toList(),
    };
  }

  factory DocumentVault.fromMap(Map<String, dynamic> map) {
    return DocumentVault(
      revision: map['revision'] as int,
      documents: (map['documents'] as List<dynamic>)
          .map((item) => DocumentItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      assets: (map['assets'] as List<dynamic>? ?? const [])
          .map((item) => AssetItem.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }

  DocumentVault copyWith({
    int? revision,
    List<DocumentItem>? documents,
    List<AssetItem>? assets,
  }) {
    return DocumentVault(
      revision: revision ?? this.revision,
      documents: documents ?? this.documents,
      assets: assets ?? this.assets,
    );
  }
}
