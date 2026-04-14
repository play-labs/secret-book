import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class VaultFileStore {
  VaultFileStore({
    String? baseDirectoryPath,
  }) : _baseDirectoryPath = baseDirectoryPath;

  final String? _baseDirectoryPath;
  String? _activeUsername;

  String? get activeUsername => _activeUsername;

  void setActiveUsername(String username) {
    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty) {
      throw ArgumentError('Username cannot be empty.');
    }
    _activeUsername = normalized;
  }

  void clearActiveUsername() {
    _activeUsername = null;
  }

  Future<Directory> resolveAppDirectory() async {
    final appDir = _baseDirectoryPath == null
        ? Directory(path.join((await getApplicationSupportDirectory()).path, 'secret_book'))
        : Directory(_baseDirectoryPath);
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  Future<Directory> resolveUserDirectory() async {
    final appDir = await resolveAppDirectory();
    final username = _requireActiveUsername();
    final userDir = Directory(path.join(appDir.path, username));
    if (!await userDir.exists()) {
      await userDir.create(recursive: true);
    }
    return userDir;
  }

  Future<File> resolveBundleFile() async {
    final userDir = await resolveUserDirectory();
    return File(path.join(userDir.path, 'vault.bundle'));
  }

  Future<File?> backupLocalBundleIfPresent({DateTime? timestamp}) async {
    final bundleFile = await resolveBundleFile();
    if (!await bundleFile.exists()) {
      return null;
    }

    final backupTimestamp = timestamp ?? DateTime.now().toUtc();
    final backupFile = File(
      path.join(
        bundleFile.parent.path,
        'vault.bundle_${_formatBackupTimestamp(backupTimestamp)}',
      ),
    );
    await bundleFile.copy(backupFile.path);
    return backupFile;
  }

  Future<File> resolveConfigFile() async {
    final userDir = await resolveUserDirectory();
    return File(path.join(userDir.path, 'config.toml'));
  }

  Future<File> resolveLegacyConfigJsonFile() async {
    final userDir = await resolveUserDirectory();
    return File(path.join(userDir.path, 'config.json'));
  }

  Future<File> resolveRemoteBundleFile() async {
    final userDir = await resolveUserDirectory();
    final remoteDir = Directory(path.join(userDir.path, 'mock_remote'));
    if (!await remoteDir.exists()) {
      await remoteDir.create(recursive: true);
    }
    return File(path.join(remoteDir.path, 'vault.bundle'));
  }

  Future<bool> bundleExists() async {
    final file = await resolveBundleFile();
    return file.exists();
  }

  Future<Uint8List?> readBundle() async {
    final file = await resolveBundleFile();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<void> writeBundle(Uint8List bytes) async {
    final file = await resolveBundleFile();
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> readRemoteBundle() async {
    final file = await resolveRemoteBundleFile();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<void> writeRemoteBundle(Uint8List bytes) async {
    final file = await resolveRemoteBundleFile();
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> replaceLocalBundleWithRemote() async {
    final remoteBytes = await readRemoteBundle();
    if (remoteBytes == null) {
      return;
    }
    await writeBundle(remoteBytes);
  }

  String _formatBackupTimestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final millisecond = value.millisecond.toString().padLeft(3, '0');
    return '${year}${month}${day}T${hour}${minute}${second}${millisecond}Z';
  }

  String _requireActiveUsername() {
    final username = _activeUsername;
    if (username == null || username.isEmpty) {
      throw StateError('Active username is required.');
    }
    return username;
  }

  String _normalizeUsername(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (RegExp(r'[<>:"/\|?*]').hasMatch(trimmed)) {
      throw ArgumentError('Username contains unsupported characters.');
    }
    if (trimmed == '.' || trimmed == '..') {
      throw ArgumentError('Username is invalid.');
    }
    return trimmed;
  }
}
