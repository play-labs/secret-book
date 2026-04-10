import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/app_config.dart';
import '../models/asset.dart';
import '../models/document.dart';
import '../models/document_vault.dart';
import '../models/sync_status.dart';

class VaultController extends ChangeNotifier {
  VaultController({
    required DocumentVault initialVault,
    required Future<void> Function(DocumentVault vault) onPersist,
    required Future<SyncStatusSnapshot> Function(int localRevision) onSyncAfterSave,
    required Future<SyncStatusSnapshot> Function(int localRevision) onCheckRemoteStatus,
    this.saveDebounceDuration = const Duration(seconds: 15),
  })  : _documents = List<DocumentItem>.from(initialVault.documents),
        _assets = List<AssetItem>.from(initialVault.assets),
        _revision = initialVault.revision,
        _onPersist = onPersist,
        _onSyncAfterSave = onSyncAfterSave,
        _onCheckRemoteStatus = onCheckRemoteStatus {
    if (_documents.isNotEmpty) {
      _selectedId = _documents.first.id;
    }
    _syncStatus = SyncStatusSnapshot(
      state: SyncState.idle,
      message: 'Ready',
      localRevision: _revision,
    );
  }

  static const int maxAssetSizeBytes = 10 * 1024 * 1024;

  final List<DocumentItem> _documents;
  final List<AssetItem> _assets;
  final Future<void> Function(DocumentVault vault) _onPersist;
  final Future<SyncStatusSnapshot> Function(int localRevision) _onSyncAfterSave;
  final Future<SyncStatusSnapshot> Function(int localRevision) _onCheckRemoteStatus;
  final Duration saveDebounceDuration;

  int _revision;
  String? _selectedId;
  String _query = '';
  bool _regexMode = false;
  bool _wholeWord = true;
  Timer? _saveDebounce;
  DateTime? _lastSavedAt;
  bool _isSaving = false;
  bool _hasPendingChanges = false;
  bool _hasQueuedSave = false;
  int _changeVersion = 0;
  int _savedChangeVersion = 0;
  String? _saveError;
  late SyncStatusSnapshot _syncStatus;

  int get revision => _revision;
  String get query => _query;
  bool get regexMode => _regexMode;
  bool get wholeWord => _wholeWord;
  DateTime? get lastSavedAt => _lastSavedAt;
  bool get isSaving => _isSaving;
  bool get hasPendingChanges => _hasPendingChanges;
  String? get saveError => _saveError;
  SyncStatusSnapshot get syncStatus => _syncStatus;

  List<DocumentItem> get visibleDocuments {
    final docs = [..._documents]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_query.trim().isEmpty) {
      return docs;
    }

    final pattern = _query.trim();
    RegExp? regex;
    if (_regexMode) {
      try {
        regex = RegExp(pattern, caseSensitive: false);
      } on FormatException {
        return docs;
      }
    }

    return docs.where((doc) {
      final haystack = <String>[
        doc.title,
        doc.content,
      ];
      if (regex != null) {
        return haystack.any(regex.hasMatch);
      }
      return haystack.any((value) => _matchesText(value, pattern));
    }).toList();
  }

  DocumentItem? get selectedDocument {
    if (_selectedId == null) {
      return null;
    }
    try {
      return _documents.firstWhere((doc) => doc.id == _selectedId);
    } catch (_) {
      return _documents.isEmpty ? null : _documents.first;
    }
  }

  List<AssetItem> get allAssets => List<AssetItem>.unmodifiable(_assets);

  List<AssetItem> get unusedAssets {
    return _assets.where((asset) => !isAssetUsed(asset.path)).toList();
  }

  Uint8List? assetBytesForPath(String assetPath) {
    try {
      return _assets.firstWhere((asset) => asset.path == assetPath).bytes;
    } catch (_) {
      return null;
    }
  }

  DocumentVault snapshot({int? revision}) {
    return DocumentVault(
      revision: revision ?? _revision,
      documents: List<DocumentItem>.from(_documents),
      assets: List<AssetItem>.from(_assets),
    );
  }

  void selectDocument(String id) {
    if (_selectedId == id) {
      return;
    }
    _selectedId = id;
    notifyListeners();
  }

  void updateSearchQuery(String value) {
    _query = value;
    final docs = visibleDocuments;
    if (docs.isNotEmpty && docs.every((doc) => doc.id != _selectedId)) {
      _selectedId = docs.first.id;
    }
    notifyListeners();
  }

  void toggleRegexMode(bool value) {
    _regexMode = value;
    notifyListeners();
  }

  void toggleWholeWord(bool value) {
    _wholeWord = value;
    notifyListeners();
  }

  void updateSelectedDocument({
    required String title,
    required String content,
  }) {
    final current = selectedDocument;
    if (current == null) {
      return;
    }
    final index = _documents.indexWhere((doc) => doc.id == current.id);
    if (index == -1) {
      return;
    }

    final next = current.copyWith(
      title: title,
      content: content,
      updatedAt: DateTime.now(),
    );
    if (next.title == current.title && next.content == current.content) {
      return;
    }

    _documents[index] = next;
    _markPendingChanges();
    _scheduleSave();
    notifyListeners();
  }

  String? addAssetToSelectedDocument({
    required Uint8List bytes,
    required String sourceName,
    String? mediaType,
  }) {
    final current = selectedDocument;
    if (current == null || bytes.isEmpty || bytes.length > maxAssetSizeBytes) {
      return null;
    }
    final index = _documents.indexWhere((doc) => doc.id == current.id);
    if (index == -1) {
      return null;
    }

    final now = DateTime.now();
    final assetPath = _buildUniqueAssetPath(sourceName, now);
    final assetId = 'asset-${now.microsecondsSinceEpoch}';
    final resolvedMediaType = mediaType ?? _mediaTypeForFileName(sourceName);
    final asset = AssetItem(
      id: assetId,
      path: assetPath,
      mediaType: resolvedMediaType,
      size: bytes.length,
      bytes: bytes,
      createdAt: now,
    );
    _assets.add(asset);

    final nextAssetRefs = <String>{...current.assetRefs, assetPath}.toList();
    _documents[index] = current.copyWith(
      assetRefs: nextAssetRefs,
      updatedAt: now,
    );

    _markPendingChanges();
    _scheduleSave();
    notifyListeners();
    return assetPath;
  }

  void removeSelectedDocumentAssetReference(String assetPath) {
    final current = selectedDocument;
    if (current == null || !current.assetRefs.contains(assetPath)) {
      return;
    }
    final index = _documents.indexWhere((doc) => doc.id == current.id);
    if (index == -1) {
      return;
    }

    final nextAssetRefs = current.assetRefs.where((item) => item != assetPath).toList();
    _documents[index] = current.copyWith(
      assetRefs: nextAssetRefs,
      updatedAt: DateTime.now(),
    );

    _markPendingChanges();
    _scheduleSave();
    notifyListeners();
  }

  int assetReferenceCount(String assetPath) {
    return _documents.where((doc) => doc.assetRefs.contains(assetPath)).length;
  }

  bool deleteAsset(String assetPath) {
    final beforeCount = _assets.length;
    _assets.removeWhere((asset) => asset.path == assetPath);
    if (_assets.length == beforeCount) {
      return false;
    }

    final now = DateTime.now();
    for (var index = 0; index < _documents.length; index += 1) {
      final document = _documents[index];
      if (!document.assetRefs.contains(assetPath)) {
        continue;
      }
      _documents[index] = document.copyWith(
        assetRefs: document.assetRefs.where((item) => item != assetPath).toList(),
        updatedAt: now,
      );
    }

    _markPendingChanges();
    _scheduleSave();
    notifyListeners();
    return true;
  }

  void createDocument() {
    final now = DateTime.now();
    final doc = DocumentItem(
      id: 'doc-${now.microsecondsSinceEpoch}',
      title: 'Untitled Document',
      content: '# New Document\n\nStart writing here.',
      tags: const [],
      assetRefs: const [],
      createdAt: now,
      updatedAt: now,
    );
    _documents.add(doc);
    _selectedId = doc.id;
    _markPendingChanges();
    _scheduleSave();
    notifyListeners();
  }

  void deleteSelectedDocument() {
    final current = selectedDocument;
    if (current == null) {
      return;
    }

    final visibleBeforeDelete = visibleDocuments;
    final visibleIndex = visibleBeforeDelete.indexWhere((doc) => doc.id == current.id);
    _documents.removeWhere((doc) => doc.id == current.id);

    if (_documents.isEmpty) {
      _selectedId = null;
    } else {
      final visibleAfterDelete = visibleDocuments;
      final nextIndex = visibleIndex.clamp(0, visibleAfterDelete.length - 1);
      _selectedId = visibleAfterDelete[nextIndex].id;
    }

    _markPendingChanges();
    _scheduleSave();
    notifyListeners();
  }

  Future<void> saveNow() async {
    _saveDebounce?.cancel();
    if (_isSaving) {
      _enqueueSave();
      notifyListeners();
      return;
    }
    await _persistNow();
  }

  bool _matchesText(String text, String pattern) {
    if (_wholeWord) {
      final escaped = RegExp.escape(pattern);
      return RegExp('\\b$escaped\\b', caseSensitive: false).hasMatch(text);
    }
    return text.toLowerCase().contains(pattern.toLowerCase());
  }

  void _markPendingChanges() {
    _changeVersion += 1;
    _hasPendingChanges = true;
  }

  void _enqueueSave() {
    _hasQueuedSave = true;
  }

  void _scheduleSave() {
    if (_isSaving) {
      _enqueueSave();
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(saveDebounceDuration, _persistNow);
  }

  Future<void> _persistNow() async {
    if (_isSaving || !_hasPendingChanges) {
      return;
    }

    final nextRevision = _revision + 1;
    final nextVault = snapshot(revision: nextRevision);
    final saveTargetVersion = _changeVersion;
    _isSaving = true;
    _hasQueuedSave = false;
    _saveError = null;
    notifyListeners();

    try {
      await _onPersist(nextVault);
      _revision = nextRevision;
      _lastSavedAt = DateTime.now();
      _savedChangeVersion = saveTargetVersion;
      _hasPendingChanges = _changeVersion != _savedChangeVersion;
      _syncStatus = await _onSyncAfterSave(_revision);
    } catch (error) {
      _saveError = error.toString();
    } finally {
      final shouldRunQueuedSave = _hasQueuedSave && _hasPendingChanges;
      _isSaving = false;
      notifyListeners();
      if (shouldRunQueuedSave) {
        await _persistNow();
      }
    }
  }

  String _buildUniqueAssetPath(String sourceName, DateTime timestamp) {
    final sanitizedName = _sanitizeFileName(sourceName, timestamp);
    final extension = path.extension(sanitizedName);
    final baseName = extension.isEmpty
        ? sanitizedName
        : sanitizedName.substring(0, sanitizedName.length - extension.length);
    var suffix = 0;
    while (true) {
      final candidateName = suffix == 0 ? sanitizedName : '$baseName-${suffix + 1}$extension';
      final candidatePath = 'assets/$candidateName';
      if (_assets.every((asset) => asset.path != candidatePath)) {
        return candidatePath;
      }
      suffix += 1;
    }
  }

  String _sanitizeFileName(String sourceName, DateTime timestamp) {
    final trimmed = sourceName.trim();
    final fallbackName = 'asset-${_formatAssetTimestamp(timestamp)}';
    final normalized = trimmed.isEmpty ? fallbackName : trimmed;
    final segments = normalized.replaceAll('\\', '/').split('/');
    final lastSegment = segments.isEmpty ? fallbackName : segments.last;
    final sanitized = lastSegment.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return fallbackName;
    }
    return sanitized;
  }

  String _formatAssetTimestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final millisecond = value.millisecond.toString().padLeft(3, '0');
    return [year, month, day, '-', hour, minute, second, '-', millisecond].join();
  }

  String _mediaTypeForFileName(String sourceName) {
    switch (path.extension(sourceName).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.svg':
        return 'image/svg+xml';
      case '.pdf':
        return 'application/pdf';
      case '.zip':
        return 'application/zip';
      case '.md':
        return 'text/markdown';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<SyncStatusSnapshot> refreshRemoteStatus() async {
    try {
      _syncStatus = await _onCheckRemoteStatus(_revision);
    } catch (error) {
      _syncStatus = SyncStatusSnapshot(
        state: SyncState.error,
        message: error.toString(),
        localRevision: _revision,
      );
    }
    notifyListeners();
    return _syncStatus;
  }

  bool isAssetUsed(String assetPath) {
    return _documents.any((doc) => doc.assetRefs.contains(assetPath));
  }
}
