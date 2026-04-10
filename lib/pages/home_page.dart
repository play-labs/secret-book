import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/asset.dart';
import '../models/document.dart';
import '../state/vault_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.bundleSizeBuilder,
    required this.bundlePath,
    required this.remoteBundlePath,
    required this.masterPasswordLabel,
    required this.onLock,
    required this.onChangePassword,
    required this.onInstallDownloadedUpdate,
    required this.titleUpdateLabel,
    required this.showTitleUpdateAction,
  });

  final VaultController controller;
  final int Function() bundleSizeBuilder;
  final String bundlePath;
  final String remoteBundlePath;
  final String masterPasswordLabel;
  final VoidCallback onLock;
  final Future<void> Function() onInstallDownloadedUpdate;
  final String? titleUpdateLabel;
  final bool showTitleUpdateAction;
  final Future<void> Function({
    required String currentPassword,
    required String newPassword,
  }) onChangePassword;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _WorkspaceView { document, files, tools }

class _HomePageState extends State<HomePage> {
  late final TextEditingController _searchController;
  final TextEditingController _titleController = TextEditingController();
  final _MarkdownEditingController _contentController =
      _MarkdownEditingController();

  bool _detailsExpanded = false;
  bool _previewMode = true;
  bool _isImportingAsset = false;
  _WorkspaceView _workspaceView = _WorkspaceView.document;
  String? _boundDocumentId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.query);
    widget.controller.addListener(_syncEditingState);
    _bindSelectedDocument(force: true);
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncEditingState);
      widget.controller.addListener(_syncEditingState);
      _boundDocumentId = null;
      _bindSelectedDocument(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncEditingState);
    _searchController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _syncEditingState() {
    _bindSelectedDocument();
    if (_searchController.text != widget.controller.query) {
      _searchController.text = widget.controller.query;
    }
  }

  void _bindSelectedDocument({bool force = false}) {
    final doc = widget.controller.selectedDocument;
    if (doc == null) {
      _boundDocumentId = null;
      _titleController.clear();
      _contentController.clear();
      return;
    }
    if (force || _boundDocumentId != doc.id) {
      _boundDocumentId = doc.id;
      _titleController.text = doc.title;
      _contentController.text = doc.content;
    }
  }

  void _onDocumentChanged() {
    final selected = widget.controller.selectedDocument;
    if (selected == null) {
      return;
    }
    widget.controller.updateSelectedDocument(
      title: _titleController.text,
      content: _contentController.text,
    );
  }

  Future<void> _saveNow() async {
    await widget.controller.saveNow();
  }

  Future<void> _deleteSelectedDocument() async {
    final selected = widget.controller.selectedDocument;
    if (selected == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete document?'),
          content: Text('This will permanently remove "${selected.title}".'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8F2D2D)),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      widget.controller.deleteSelectedDocument();
    }
  }

  Future<void> _pickLocalFile() async {
    if (_isImportingAsset) {
      return;
    }
    setState(() => _isImportingAsset = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      final file =
          result == null || result.files.isEmpty ? null : result.files.first;
      if (file == null) {
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showMessage('Unable to read the selected file.');
        return;
      }
      if (bytes.length > VaultController.maxAssetSizeBytes) {
        _showMessage('File is too large. Files over 10MB are not allowed.');
        return;
      }
      _insertImportedAsset(bytes: bytes, sourceName: file.name);
    } catch (error) {
      _showMessage('File upload failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isImportingAsset = false);
      }
    }
  }

  Future<void> _pasteImageFromClipboard({bool silentIfEmpty = false}) async {
    if (_isImportingAsset) {
      return;
    }
    setState(() => _isImportingAsset = true);
    try {
      final bytes = await _readClipboardImageBytes();
      if (bytes == null || bytes.isEmpty) {
        if (!silentIfEmpty) {
          _showMessage('No image found in clipboard.');
        }
        return;
      }
      if (bytes.length > VaultController.maxAssetSizeBytes) {
        _showMessage(
            'Clipboard image is too large. Files over 10MB are not allowed.');
        return;
      }
      _insertImportedAsset(
          bytes: bytes, sourceName: 'clipboard.png', mediaType: 'image/png');
    } catch (error) {
      _showMessage('Clipboard image import failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isImportingAsset = false);
      }
    }
  }

  Future<List<int>?> _readClipboardImageBytes() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return null;
    }
    final reader = await clipboard.read();
    if (!reader.canProvide(Formats.png)) {
      return null;
    }
    final completer = Completer<List<int>?>();
    final progress = reader.getFile(
      Formats.png,
      (file) async {
        final bytes = await file.readAll();
        if (!completer.isCompleted) {
          completer.complete(bytes);
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );
    if (progress == null) {
      return null;
    }
    return completer.future.timeout(const Duration(seconds: 10));
  }

  void _insertImportedAsset({
    required List<int> bytes,
    required String sourceName,
    String? mediaType,
  }) {
    final assetPath = widget.controller.addAssetToSelectedDocument(
      bytes: Uint8List.fromList(bytes),
      sourceName: sourceName,
      mediaType: mediaType,
    );
    if (assetPath == null) {
      _showMessage(
          'Please select a document first, and keep files under 10MB.');
      return;
    }
    final markdown = _buildAssetMarkdown(assetPath, sourceName, mediaType);
    final selection = _contentController.selection;
    final sourceText = _contentController.text;
    final safeOffset = selection.isValid
        ? selection.baseOffset.clamp(0, sourceText.length)
        : sourceText.length;
    final nextText = sourceText.replaceRange(safeOffset, safeOffset, markdown);
    _contentController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: safeOffset + markdown.length),
    );
    _onDocumentChanged();
    _showMessage('File uploaded into the vault.');
  }

  Future<void> _previewAsset(AssetItem asset) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final isImage = _isImageAsset(asset);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_assetDisplayName(asset),
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 4),
                            SelectableText(asset.path,
                                style:
                                    const TextStyle(color: Color(0xFF5B6A63))),
                          ],
                        ),
                      ),
                      IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3EEE2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: isImage
                          ? InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 6,
                              child: Center(
                                  child: Image.memory(asset.bytes,
                                      fit: BoxFit.contain)),
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.insert_drive_file_outlined,
                                      size: 56),
                                  const SizedBox(height: 12),
                                  Text(asset.mediaType),
                                  const SizedBox(height: 4),
                                  Text('${asset.size} bytes'),
                                  const SizedBox(height: 12),
                                  const Text(
                                      'This file type does not support inline preview.'),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyMarkdownReference(AssetItem asset) async {
    await Clipboard.setData(
      ClipboardData(
          text: _buildAssetMarkdown(
                  asset.path, _assetDisplayName(asset), asset.mediaType)
              .trim()),
    );
    if (mounted) {
      _showMessage('Markdown reference copied.');
    }
  }

  Future<void> _downloadAsset(AssetItem asset) async {
    try {
      final targetPath = await FilePicker.saveFile(
        dialogTitle: 'Save file to local disk',
        fileName: _assetDisplayName(asset),
      );
      if (targetPath == null || targetPath.isEmpty) {
        return;
      }
      await File(targetPath).writeAsBytes(asset.bytes, flush: true);
      if (mounted) {
        _showMessage('File downloaded to local disk.');
      }
    } catch (error) {
      _showMessage('File download failed: $error');
    }
  }

  Future<void> _removeCurrentAssetReference(AssetItem asset) async {
    final selected = widget.controller.selectedDocument;
    if (selected == null || !selected.assetRefs.contains(asset.path)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove current reference?'),
          content: Text(
              'This removes the current document reference to ${_assetDisplayName(asset)}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove')),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final updatedContent =
        _removeAssetMarkdown(_contentController.text, asset.path);
    _contentController.text = updatedContent;
    widget.controller.removeSelectedDocumentAssetReference(asset.path);
    _onDocumentChanged();
    _showMessage('Current document reference removed.');
  }

  Future<void> _deleteAsset(AssetItem asset) async {
    final referenceCount = widget.controller.assetReferenceCount(asset.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete uploaded file?'),
          content: Text(
            referenceCount > 0
                ? 'This will remove ${_assetDisplayName(asset)} and clear $referenceCount document reference(s).'
                : 'This will permanently remove ${_assetDisplayName(asset)} from the vault.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8F2D2D)),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final deleted = widget.controller.deleteAsset(asset.path);
    _showMessage(
      deleted
          ? (referenceCount > 0
              ? 'File deleted and references removed.'
              : 'File deleted.')
          : 'File delete failed.',
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isPaste = (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (isPaste) {
      unawaited(_pasteImageFromClipboard(silentIfEmpty: true));
    }
    return KeyEventResult.ignored;
  }

  String _buildAssetMarkdown(
      String assetPath, String sourceName, String? mediaType) {
    final baseName = sourceName.split('.').first.trim();
    final label = baseName.isEmpty ? 'asset' : baseName;
    final prefix = _contentController.text.isEmpty ? '' : '\n';
    final isImage = (mediaType ?? '').startsWith('image/');
    return isImage
        ? '$prefix![$label]($assetPath)\n'
        : '$prefix[$label]($assetPath)\n';
  }

  String _assetDisplayName(AssetItem asset) {
    final segments = asset.path.split('/');
    return segments.isEmpty ? asset.path : segments.last;
  }

  bool _isImageAsset(AssetItem asset) {
    return asset.mediaType.startsWith('image/');
  }

  String _removeAssetMarkdown(String content, String assetPath) {
    final escaped = RegExp.escape(assetPath);
    var updated = content.replaceAll(
        RegExp('^\\s*!?\\[[^\\]]*\\]\\($escaped\\)\\s*\\n?', multiLine: true),
        '');
    updated =
        updated.replaceAll(RegExp('!?\\[[^\\]]*\\]\\($escaped\\)\\n?'), '');
    updated = updated.replaceAll(RegExp('\n{3,}'), '\n\n');
    return updated.trimRight();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final nextController = TextEditingController();
    final confirmController = TextEditingController();
    var obscureCurrent = true;
    var obscureNext = true;
    var obscureConfirm = true;
    var isSubmitting = false;
    String? errorText;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final navigator = Navigator.of(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                final currentPassword = currentController.text;
                final newPassword = nextController.text;
                final confirmPassword = confirmController.text;
                if (currentPassword.isEmpty) {
                  setDialogState(
                      () => errorText = 'Enter your current password.');
                  return;
                }
                if (newPassword.trim().isEmpty) {
                  setDialogState(() => errorText = 'Enter a new password.');
                  return;
                }
                if (newPassword.length < 8) {
                  setDialogState(() => errorText =
                      'New password must be at least 8 characters.');
                  return;
                }
                if (newPassword != confirmPassword) {
                  setDialogState(
                      () => errorText = 'The new passwords do not match.');
                  return;
                }
                if (newPassword == currentPassword) {
                  setDialogState(() => errorText =
                      'Use a different password from the current one.');
                  return;
                }
                setDialogState(() {
                  isSubmitting = true;
                  errorText = null;
                });
                try {
                  await widget.onChangePassword(
                      currentPassword: currentPassword,
                      newPassword: newPassword);
                  if (!mounted) {
                    return;
                  }
                  navigator.pop();
                  _showMessage('Password updated.');
                } catch (error) {
                  setDialogState(() {
                    errorText = error.toString();
                    isSubmitting = false;
                  });
                }
              }

              return AlertDialog(
                title: const Text('Change password'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: currentController,
                        obscureText: obscureCurrent,
                        enabled: !isSubmitting,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          errorText: errorText,
                          suffixIcon: IconButton(
                            onPressed: () => setDialogState(
                                () => obscureCurrent = !obscureCurrent),
                            icon: Icon(obscureCurrent
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nextController,
                        obscureText: obscureNext,
                        enabled: !isSubmitting,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          suffixIcon: IconButton(
                            onPressed: () => setDialogState(
                                () => obscureNext = !obscureNext),
                            icon: Icon(obscureNext
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: confirmController,
                        obscureText: obscureConfirm,
                        enabled: !isSubmitting,
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Confirm new password',
                          suffixIcon: IconButton(
                            onPressed: () => setDialogState(
                                () => obscureConfirm = !obscureConfirm),
                            icon: Icon(obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: isSubmitting ? null : () => navigator.pop(),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: isSubmitting ? null : submit,
                      child: Text(isSubmitting ? 'Updating...' : 'Update')),
                ],
              );
            },
          );
        },
      );
    } finally {
      currentController.dispose();
      nextController.dispose();
      confirmController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final selected = widget.controller.selectedDocument;
        final documents = widget.controller.visibleDocuments;
        final assets = widget.controller.allAssets;
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyS, control: true):
                SaveIntent(),
          },
          child: Actions(
            actions: {
              SaveIntent: CallbackAction<SaveIntent>(
                onInvoke: (_) {
                  _saveNow();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: Scaffold(
                body: SafeArea(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 340,
                        child: DecoratedBox(
                          decoration:
                              const BoxDecoration(color: Color(0xFF17352C)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _VaultHeader(),
                                const SizedBox(height: 20),
                                _VaultDetailsCard(
                                  isExpanded: _detailsExpanded,
                                  revision: widget.controller.revision,
                                  bundleSizeBytes: widget.bundleSizeBuilder(),
                                  bundlePath: widget.bundlePath,
                                  remoteBundlePath: widget.remoteBundlePath,
                                  sessionLabel: widget.masterPasswordLabel,
                                  saveLabel: _saveLabel(widget.controller),
                                  onToggle: () => setState(() =>
                                      _detailsExpanded = !_detailsExpanded),
                                ),
                                const SizedBox(height: 20),
                                _SidebarSearch(
                                  controller: _searchController,
                                  wholeWord: widget.controller.wholeWord,
                                  regexMode: widget.controller.regexMode,
                                  onChanged:
                                      widget.controller.updateSearchQuery,
                                  onToggleWholeWord:
                                      widget.controller.toggleWholeWord,
                                  onToggleRegex:
                                      widget.controller.toggleRegexMode,
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: widget.controller.createDocument,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF14745C),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(22)),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('New Document'),
                                ),
                                const SizedBox(height: 18),
                                Expanded(
                                  child: documents.isEmpty
                                      ? const _EmptySidebarState()
                                      : ScrollConfiguration(
                                          behavior:
                                              const _MouseDragScrollBehavior(),
                                          child: ListView.separated(
                                            itemCount: documents.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 14),
                                            itemBuilder: (context, index) {
                                              final document = documents[index];
                                              return _DocumentListTile(
                                                document: document,
                                                selected:
                                                    selected?.id == document.id,
                                                onTap: () => widget.controller
                                                    .selectDocument(
                                                        document.id),
                                              );
                                            },
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(36, 24, 36, 24),
                          child: selected == null
                              ? _EmptyDocumentState(
                                  onCreate: widget.controller.createDocument,
                                  showTools: () => setState(() =>
                                      _workspaceView = _WorkspaceView.tools),
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _WorkspaceSegment(
                                          value: _workspaceView,
                                          onChanged: (next) => setState(
                                              () => _workspaceView = next),
                                        ),
                                        const Spacer(),
                                        if (_workspaceView !=
                                            _WorkspaceView.tools) ...[
                                          FilledButton.icon(
                                            onPressed: _isImportingAsset
                                                ? null
                                                : _pickLocalFile,
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFD3ECE1),
                                              foregroundColor:
                                                  const Color(0xFF0F6F59),
                                            ),
                                            icon: _isImportingAsset
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2),
                                                  )
                                                : const Icon(
                                                    Icons.upload_file_outlined),
                                            label: const Text('Upload File'),
                                          ),
                                          const SizedBox(width: 12),
                                          FilledButton.icon(
                                            onPressed:
                                                widget.controller.isSaving
                                                    ? null
                                                    : _saveNow,
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFD3ECE1),
                                              foregroundColor:
                                                  const Color(0xFF29443D),
                                            ),
                                            icon:
                                                const Icon(Icons.save_outlined),
                                            label: const Text('Save Now'),
                                          ),
                                          const SizedBox(width: 12),
                                          FilledButton.icon(
                                            onPressed:
                                                _showChangePasswordDialog,
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFD3ECE1),
                                              foregroundColor:
                                                  const Color(0xFF29443D),
                                            ),
                                            icon:
                                                const Icon(Icons.key_outlined),
                                            label:
                                                const Text('Change Password'),
                                          ),
                                          const SizedBox(width: 12),
                                          FilledButton.icon(
                                            onPressed: widget.onLock,
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFD3ECE1),
                                              foregroundColor:
                                                  const Color(0xFF29443D),
                                            ),
                                            icon:
                                                const Icon(Icons.lock_outline),
                                            label: const Text('Lock'),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    if (_workspaceView ==
                                        _WorkspaceView.document) ...[
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        _titleController,
                                                    onChanged: (_) =>
                                                        _onDocumentChanged(),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .displaySmall,
                                                    decoration:
                                                        const InputDecoration(
                                                      border: InputBorder.none,
                                                      isCollapsed: true,
                                                      hintText:
                                                          'Untitled Document',
                                                    ),
                                                  ),
                                                ),
                                                if (widget.titleUpdateLabel !=
                                                    null) ...[
                                                  const SizedBox(width: 10),
                                                  InkWell(
                                                    onTap: widget
                                                            .showTitleUpdateAction
                                                        ? widget
                                                            .onInstallDownloadedUpdate
                                                        : null,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 6),
                                                      child: Text(
                                                        widget
                                                            .titleUpdateLabel!,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                              color: widget
                                                                      .showTitleUpdateAction
                                                                  ? const Color(
                                                                      0xFF0F6F59)
                                                                  : const Color(
                                                                      0xFF5E6E68),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      Row(
                                        children: [
                                          if (_workspaceView ==
                                              _WorkspaceView.document)
                                            _ModeSegment(
                                              previewMode: _previewMode,
                                              onChanged: (value) => setState(
                                                  () => _previewMode = value),
                                            ),
                                          const Spacer(),
                                          IconButton.filledTonal(
                                            onPressed: _deleteSelectedDocument,
                                            style: IconButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFF7D8D6),
                                              foregroundColor:
                                                  const Color(0xFFB3261E),
                                            ),
                                            icon: const Icon(
                                                Icons.delete_outline),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 22),
                                      Expanded(
                                        child: _previewMode
                                            ? _MarkdownPreview(
                                                document: selected,
                                                assetBytesForPath: widget
                                                    .controller
                                                    .assetBytesForPath,
                                              )
                                            : _EditorSurface(
                                                controller: _contentController,
                                                onChanged: (_) =>
                                                    _onDocumentChanged()),
                                      ),
                                    ] else if (_workspaceView ==
                                        _WorkspaceView.files) ...[
                                      Expanded(
                                        child: _AssetLibraryView(
                                          assets: assets,
                                          selectedDocument: selected,
                                          referenceCountForPath: widget
                                              .controller.assetReferenceCount,
                                          isImageAsset: _isImageAsset,
                                          assetDisplayName: _assetDisplayName,
                                          onPreviewAsset: _previewAsset,
                                          onCopyMarkdownReference:
                                              _copyMarkdownReference,
                                          onDownloadAsset: _downloadAsset,
                                          onRemoveCurrentReference:
                                              _removeCurrentAssetReference,
                                          onDeleteAsset: _deleteAsset,
                                        ),
                                      ),
                                    ] else ...[
                                      const Expanded(
                                        child: Align(
                                            alignment: Alignment.topLeft,
                                            child: _PasswordGeneratorCard()),
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _saveLabel(VaultController controller) {
    if (controller.isSaving) return 'Saving...';
    if (controller.saveError != null) return 'Save failed';
    if (controller.hasPendingChanges) return 'Pending changes';
    if (controller.lastSavedAt == null) return 'Not saved yet';
    return 'Saved ${_formatDateTime(controller.lastSavedAt!)}';
  }

  String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class _VaultHeader extends StatelessWidget {
  const _VaultHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Secret Book',
          style: Theme.of(context)
              .textTheme
              .displaySmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'Encrypted document manager prototype',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: const Color(0xFFF0F7F3), height: 1.45),
        ),
      ],
    );
  }
}

class _VaultDetailsCard extends StatelessWidget {
  const _VaultDetailsCard({
    required this.isExpanded,
    required this.revision,
    required this.bundleSizeBytes,
    required this.bundlePath,
    required this.remoteBundlePath,
    required this.sessionLabel,
    required this.saveLabel,
    required this.onToggle,
  });

  final bool isExpanded;
  final int revision;
  final int bundleSizeBytes;
  final String bundlePath;
  final String remoteBundlePath;
  final String sessionLabel;
  final String saveLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF214B3F),
          borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Color(0xFFDDECE5)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Vault Details',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFFDDECE5)),
              ],
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 16),
            _SidebarDetailRow(label: 'Revision', value: '$revision'),
            _SidebarDetailRow(label: 'Bundle', value: '$bundleSizeBytes bytes'),
            _SidebarDetailRow(
                label: 'Local', value: bundlePath, compactValue: true),
            _SidebarDetailRow(
                label: 'Remote', value: remoteBundlePath, compactValue: true),
            _SidebarDetailRow(label: 'Session', value: sessionLabel),
            _SidebarDetailRow(label: 'Save', value: saveLabel),
            const _SidebarDetailRow(
                label: 'Shortcut', value: 'Ctrl+S / Ctrl+V'),
          ],
        ],
      ),
    );
  }
}

class _SidebarDetailRow extends StatelessWidget {
  const _SidebarDetailRow(
      {required this.label, required this.value, this.compactValue = false});

  final String label;
  final String value;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFFC5DDD4),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: compactValue ? 13 : 14,
                  height: 1.3,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch({
    required this.controller,
    required this.wholeWord,
    required this.regexMode,
    required this.onChanged,
    required this.onToggleWholeWord,
    required this.onToggleRegex,
  });

  final TextEditingController controller;
  final bool wholeWord;
  final bool regexMode;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onToggleWholeWord;
  final ValueChanged<bool> onToggleRegex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: Color(0xFFF9FCFA)),
          decoration: InputDecoration(
            hintText: 'Search title, content',
            hintStyle: const TextStyle(color: Color(0xFFD2E3DB)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFFD1E6DB)),
            filled: true,
            fillColor: const Color(0xFF214B3F),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SidebarToggleChip(
                label: 'Whole Word',
                active: wholeWord,
                onTap: () => onToggleWholeWord(!wholeWord)),
            _SidebarToggleChip(
                label: 'Regex',
                active: regexMode,
                onTap: () => onToggleRegex(!regexMode)),
          ],
        ),
      ],
    );
  }
}

class _SidebarToggleChip extends StatelessWidget {
  const _SidebarToggleChip(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE9F4EE) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? const Color(0xFF9BC6B2) : const Color(0xFFC9DACE),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                const Icon(Icons.check, size: 18, color: Color(0xFF1E4B3D)),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF17352C),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentListTile extends StatelessWidget {
  const _DocumentListTile(
      {required this.document, required this.selected, required this.onTap});

  final DocumentItem document;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2E6E5B) : const Color(0xFF255144),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color:
                  selected ? const Color(0xFFA9D6C3) : const Color(0xFF3B6F5D),
              width: 1.4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2)),
              const SizedBox(height: 10),
              Text(_formatTimestamp(document.updatedAt),
                  style:
                      const TextStyle(color: Color(0xFFD8ECE2), fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}

class _EmptySidebarState extends StatelessWidget {
  const _EmptySidebarState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF214B3F),
          borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.all(20),
      child: const Text('No documents yet. Create one to get started.',
          style: TextStyle(color: Colors.white70)),
    );
  }
}

class _EmptyDocumentState extends StatelessWidget {
  const _EmptyDocumentState({required this.onCreate, required this.showTools});

  final VoidCallback onCreate;
  final VoidCallback showTools;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 22,
                  offset: Offset(0, 12))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No document selected',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              const Text(
                  'Create a new note or open the tools view to use utility features.'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('New Document')),
                  OutlinedButton.icon(
                      onPressed: showTools,
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('Open Tools')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  const _MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class _WorkspaceSegment extends StatelessWidget {
  const _WorkspaceSegment({required this.value, required this.onChanged});

  final _WorkspaceView value;
  final ValueChanged<_WorkspaceView> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_WorkspaceView>(
      showSelectedIcon: true,
      segments: const [
        ButtonSegment<_WorkspaceView>(
            value: _WorkspaceView.document,
            icon: Icon(Icons.check),
            label: Text('Document')),
        ButtonSegment<_WorkspaceView>(
            value: _WorkspaceView.files,
            icon: Icon(Icons.folder_outlined),
            label: Text('Files')),
        ButtonSegment<_WorkspaceView>(
            value: _WorkspaceView.tools,
            icon: Icon(Icons.handyman_outlined),
            label: Text('Tools')),
      ],
      selected: {value},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onChanged(selection.first);
        }
      },
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({required this.previewMode, required this.onChanged});

  final bool previewMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: true,
      segments: const [
        ButtonSegment<bool>(
            value: false, icon: Icon(Icons.edit_outlined), label: Text('Edit')),
        ButtonSegment<bool>(
            value: true,
            icon: Icon(Icons.visibility_outlined),
            label: Text('Preview')),
      ],
      selected: {previewMode},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onChanged(selection.first);
        }
      },
    );
  }
}

class _MarkdownEditingController extends TextEditingController {
  static const TextStyle _baseStyle = TextStyle(
    color: Color(0xFF1E2A24),
    fontSize: 16,
    height: 1.55,
  );
  static const TextStyle _headingStyle = TextStyle(
    color: Color(0xFF0D5C4A),
    fontWeight: FontWeight.w800,
  );
  static const TextStyle _syntaxStyle = TextStyle(
    color: Color(0xFF7C4D1F),
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _quoteStyle = TextStyle(
    color: Color(0xFF6A7D74),
    fontStyle: FontStyle.italic,
  );
  static const TextStyle _codeStyle = TextStyle(
    color: Color(0xFF8F2D2D),
    fontFamily: 'Consolas',
    backgroundColor: Color(0xFFF5ECE7),
  );
  static const TextStyle _linkStyle = TextStyle(
    color: Color(0xFF0B63A5),
    decoration: TextDecoration.underline,
  );
  static const TextStyle _emphasisStyle = TextStyle(
    color: Color(0xFF5C2E91),
    fontWeight: FontWeight.w700,
  );

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final effectiveStyle = _baseStyle.merge(style);
    final children = <InlineSpan>[];
    final lines = text.split('\n');
    var inCodeBlock = false;

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final lineChildren = <InlineSpan>[];
      final trimmedLeft = line.trimLeft();

      if (trimmedLeft.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        lineChildren
            .add(TextSpan(text: line, style: effectiveStyle.merge(_codeStyle)));
      } else if (inCodeBlock) {
        lineChildren
            .add(TextSpan(text: line, style: effectiveStyle.merge(_codeStyle)));
      } else {
        final headingMatch = RegExp(r'^(#{1,6})(\s+)(.*)$').firstMatch(line);
        final quoteMatch = RegExp(r'^(\s*>\s?)(.*)$').firstMatch(line);
        final listMatch =
            RegExp(r'^(\s*(?:[-*+] |\d+\. ))(.*)$').firstMatch(line);

        if (headingMatch != null) {
          lineChildren.add(TextSpan(
              text: headingMatch.group(1),
              style: effectiveStyle.merge(_syntaxStyle)));
          lineChildren.add(
              TextSpan(text: headingMatch.group(2), style: effectiveStyle));
          lineChildren.add(TextSpan(
              text: headingMatch.group(3),
              style: effectiveStyle.merge(_headingStyle)));
        } else if (quoteMatch != null) {
          lineChildren.add(TextSpan(
              text: quoteMatch.group(1),
              style: effectiveStyle.merge(_syntaxStyle)));
          _appendInlineMarkdown(lineChildren, quoteMatch.group(2) ?? '',
              effectiveStyle.merge(_quoteStyle));
        } else if (listMatch != null) {
          lineChildren.add(TextSpan(
              text: listMatch.group(1),
              style: effectiveStyle.merge(_syntaxStyle)));
          _appendInlineMarkdown(
              lineChildren, listMatch.group(2) ?? '', effectiveStyle);
        } else {
          _appendInlineMarkdown(lineChildren, line, effectiveStyle);
        }
      }

      children.add(TextSpan(children: lineChildren, style: effectiveStyle));
      if (lineIndex < lines.length - 1) {
        children.add(TextSpan(text: '\n', style: effectiveStyle));
      }
    }

    return TextSpan(style: effectiveStyle, children: children);
  }

  void _appendInlineMarkdown(
      List<InlineSpan> spans, String source, TextStyle baseStyle) {
    final pattern = RegExp(
      r'(\!\[[^\]]*\]\([^\)]+\)|\[[^\]]+\]\([^\)]+\)|`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_)',
    );
    var current = 0;

    for (final match in pattern.allMatches(source)) {
      if (match.start > current) {
        spans.add(TextSpan(
            text: source.substring(current, match.start), style: baseStyle));
      }
      final token = match.group(0)!;
      if (token.startsWith('![') || token.startsWith('[')) {
        spans.add(TextSpan(text: token, style: baseStyle.merge(_linkStyle)));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(text: token, style: baseStyle.merge(_codeStyle)));
      } else {
        spans
            .add(TextSpan(text: token, style: baseStyle.merge(_emphasisStyle)));
      }
      current = match.end;
    }

    if (current < source.length) {
      spans.add(TextSpan(text: source.substring(current), style: baseStyle));
    }
  }
}

class _EditorSurface extends StatelessWidget {
  const _EditorSurface({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 24, offset: Offset(0, 14))
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        expands: true,
        maxLines: null,
        minLines: null,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(28),
            hintText: 'Start writing here...'),
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview(
      {required this.document, required this.assetBytesForPath});

  final DocumentItem document;
  final Uint8List? Function(String path) assetBytesForPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 24, offset: Offset(0, 14))
        ],
      ),
      child: SelectionArea(
        child: Markdown(
          data: document.content,
          padding: const EdgeInsets.all(28),
          sizedImageBuilder: (config) {
            final bytes = assetBytesForPath(config.uri.toString());
            if (bytes == null) {
              return _MissingAssetBox(
                  label: config.alt ?? config.uri.toString());
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MissingAssetBox extends StatelessWidget {
  const _MissingAssetBox({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFE5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD5CBB9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined),
          const SizedBox(width: 10),
          Flexible(child: Text('Missing asset: $label')),
        ],
      ),
    );
  }
}

class _AssetLibraryView extends StatelessWidget {
  const _AssetLibraryView({
    required this.assets,
    required this.selectedDocument,
    required this.referenceCountForPath,
    required this.isImageAsset,
    required this.assetDisplayName,
    required this.onPreviewAsset,
    required this.onCopyMarkdownReference,
    required this.onDownloadAsset,
    required this.onRemoveCurrentReference,
    required this.onDeleteAsset,
  });

  final List<AssetItem> assets;
  final DocumentItem? selectedDocument;
  final int Function(String path) referenceCountForPath;
  final bool Function(AssetItem asset) isImageAsset;
  final String Function(AssetItem asset) assetDisplayName;
  final Future<void> Function(AssetItem asset) onPreviewAsset;
  final Future<void> Function(AssetItem asset) onCopyMarkdownReference;
  final Future<void> Function(AssetItem asset) onDownloadAsset;
  final Future<void> Function(AssetItem asset) onRemoveCurrentReference;
  final Future<void> Function(AssetItem asset) onDeleteAsset;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
                color: Color(0x11000000), blurRadius: 24, offset: Offset(0, 14))
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: const Align(
          alignment: Alignment.topLeft,
          child: Text(
              'No uploaded files yet. You can upload images or any binary file under 10MB.'),
        ),
      );
    }

    final sortedAssets = [...assets]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 24, offset: Offset(0, 14))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('All Uploaded Files',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Any file under 10MB can be stored as binary data. Duplicate file names are auto-renamed with -2, -3 and so on.',
            style: TextStyle(color: Color(0xFF5F665D)),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: sortedAssets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final asset = sortedAssets[index];
                final referenceCount = referenceCountForPath(asset.path);
                final usedHere =
                    selectedDocument?.assetRefs.contains(asset.path) ?? false;
                final status = usedHere
                    ? 'Used Here'
                    : (referenceCount == 0
                        ? 'Unused'
                        : 'Used in Other Documents');
                return _AssetTile(
                  asset: asset,
                  displayName: assetDisplayName(asset),
                  status: status,
                  referenceCount: referenceCount,
                  isImage: isImageAsset(asset),
                  onPreview: () => onPreviewAsset(asset),
                  onCopyMarkdown: () => onCopyMarkdownReference(asset),
                  onDownload: () => onDownloadAsset(asset),
                  onRemoveCurrentReference:
                      usedHere ? () => onRemoveCurrentReference(asset) : null,
                  onDelete: () => onDeleteAsset(asset),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.displayName,
    required this.status,
    required this.referenceCount,
    required this.isImage,
    required this.onPreview,
    required this.onCopyMarkdown,
    required this.onDownload,
    required this.onRemoveCurrentReference,
    required this.onDelete,
  });

  final AssetItem asset;
  final String displayName;
  final String status;
  final int referenceCount;
  final bool isImage;
  final VoidCallback onPreview;
  final VoidCallback onCopyMarkdown;
  final VoidCallback onDownload;
  final VoidCallback? onRemoveCurrentReference;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3EA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3DBCA)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 72,
              height: 72,
              child: isImage
                  ? Image.memory(asset.bytes, fit: BoxFit.cover)
                  : const _AssetThumbnailFallback(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(asset.path,
                    style: const TextStyle(color: Color(0xFF5F665D))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _MetaChip(label: status),
                    _MetaChip(label: '${asset.size} bytes'),
                    _MetaChip(label: '$referenceCount refs'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.outlined(
                  onPressed: onPreview, icon: const Icon(Icons.open_in_full)),
              IconButton.outlined(
                  onPressed: onCopyMarkdown,
                  icon: const Icon(Icons.content_copy_outlined)),
              IconButton.outlined(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_outlined)),
              IconButton.outlined(
                  onPressed: onRemoveCurrentReference,
                  icon: const Icon(Icons.link_off_outlined)),
              IconButton.outlined(
                onPressed: onDelete,
                style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFA52D2D)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssetThumbnailFallback extends StatelessWidget {
  const _AssetThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE6E0D3),
      child: const Icon(Icons.insert_drive_file_outlined,
          color: Color(0xFF6A6A66)),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFE2ECDF),
          borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _PasswordGeneratorCard extends StatefulWidget {
  const _PasswordGeneratorCard();

  @override
  State<_PasswordGeneratorCard> createState() => _PasswordGeneratorCardState();
}

class _PasswordGeneratorCardState extends State<_PasswordGeneratorCard> {
  static const String _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%^&*()-_=+[]{}';
  final Random _random = Random.secure();
  late int _length;
  late String _password;

  @override
  void initState() {
    super.initState();
    _length = 12;
    _password = _generate(_length);
  }

  String _generate(int length) {
    return List.generate(
        length, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join();
  }

  void _regenerate() {
    setState(() => _password = _generate(_length));
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: _password));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Password copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      height: 340,
      child: Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFDDD4C2)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 12))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('随机密码生成器', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            const Text(
                'Generate a strong random password and copy it for later use.',
                style: TextStyle(color: Color(0xFF5F665D))),
            const SizedBox(height: 22),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.circular(22)),
                child: SelectableText(
                  _password,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      height: 1.45),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Length: $_length',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Expanded(
                  child: Slider(
                    value: _length.toDouble(),
                    min: 8,
                    max: 18,
                    divisions: 10,
                    label: '$_length',
                    onChanged: (value) {
                      setState(() {
                        _length = value.round();
                        _password = _generate(_length);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.icon(
                    onPressed: _regenerate,
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Regenerate')),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                    onPressed: _copyPassword,
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('Copy')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
