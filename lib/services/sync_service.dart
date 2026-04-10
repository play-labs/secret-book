import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_oss_aliyun/flutter_oss_aliyun.dart';
import 'package:path/path.dart' as path;

import '../models/app_config.dart';
import '../models/sync_status.dart';
import '../serialization/bundle_serializer.dart';
import 'app_config_store.dart';
import 'vault_file_store.dart';

abstract class SyncService {
  Future<SyncStatusSnapshot> syncAfterLocalSave({
    required int localRevision,
  });

  Future<SyncStatusSnapshot> checkRemoteStatus({
    required int localRevision,
  });

  Future<bool> pullRemoteToLocal();

  Future<SyncStatusSnapshot> overwriteRemoteWithLocal({
    required int localRevision,
  });

  Future<String> getRemoteBundlePath();

  Future<String> testStsConnection();
}

class AliyunOssSyncService implements SyncService {
  AliyunOssSyncService({
    required VaultFileStore fileStore,
    required BundleSerializer serializer,
    required AppConfigStore configStore,
    Dio? dio,
  })  : _fileStore = fileStore,
        _serializer = serializer,
        _configStore = configStore,
        _dio = dio ?? Dio();

  final VaultFileStore _fileStore;
  final BundleSerializer _serializer;
  final AppConfigStore _configStore;
  final Dio _dio;

  @override
  Future<String> getRemoteBundlePath() async {
    final config = await _configStore.read();
    final objectKey = _buildUserObjectKey(config);
    return 'oss://${config.ossBucketName}/$objectKey';
  }

  @override
  Future<String> testStsConnection() async {
    final config = await _configStore.read();
    final validationError = _validateConfig(config);
    if (validationError != null) {
      throw StateError(validationError);
    }
    final auth = await _fetchStsAuth(config);
    return 'STS OK: ${auth.accessKey} exp ${auth.expire}';
  }

  @override
  Future<SyncStatusSnapshot> syncAfterLocalSave({
    required int localRevision,
  }) async {
    final config = await _configStore.read();
    final validationError = _validateConfig(config);
    if (validationError != null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: validationError,
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final localBundle = await _fileStore.readBundle();
    if (localBundle == null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: 'Local vault.bundle is missing',
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final remoteRevision = await _readRemoteRevision();
    final knownRemoteRevision = config.lastSyncedRevision;
    final hasConflict = remoteRevision != null &&
        knownRemoteRevision != null &&
        remoteRevision > knownRemoteRevision;
    final hasUnknownRemote = remoteRevision != null && knownRemoteRevision == null;

    if (hasConflict || hasUnknownRemote) {
      final next = config.copyWith(
        syncProvider: SyncProvider.aliyunOss,
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
        syncState: SyncState.conflict,
        syncMessage: hasUnknownRemote
            ? 'Remote vault exists but local session has no sync baseline'
            : 'Remote revision is newer. Pull remote before uploading.',
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final client = await _buildClient(config);
    final objectKey = _buildUserObjectKey(config);
    await _backupRemoteBundleIfPresent(client, config, objectKey);
    await client.putObject(localBundle, objectKey);
    final next = config.copyWith(
      syncProvider: SyncProvider.aliyunOss,
      lastSyncedRevision: localRevision,
      lastRemoteRevision: localRevision,
      lastSyncAt: DateTime.now().toUtc(),
      syncState: SyncState.synced,
      syncMessage: 'Encrypted bundle uploaded to Aliyun OSS',
    );
    await _configStore.write(next);
    return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
  }

  @override
  Future<SyncStatusSnapshot> checkRemoteStatus({
    required int localRevision,
  }) async {
    final config = await _configStore.read();
    final validationError = _validateConfig(config);
    if (validationError != null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: validationError,
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final remoteRevision = await _readRemoteRevision();
    final lastSyncedRevision = config.lastSyncedRevision;

    AppConfig next;
    if (remoteRevision == null) {
      next = config.copyWith(
        syncProvider: SyncProvider.aliyunOss,
        syncState: SyncState.idle,
        syncMessage: 'Remote vault is empty',
        clearLastRemoteRevision: true,
        lastSyncAt: DateTime.now().toUtc(),
      );
    } else if (lastSyncedRevision != null && remoteRevision > lastSyncedRevision) {
      next = config.copyWith(
        syncProvider: SyncProvider.aliyunOss,
        syncState: SyncState.conflict,
        syncMessage: 'Remote revision is newer. Pull required.',
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
      );
    } else if (remoteRevision == localRevision) {
      next = config.copyWith(
        syncProvider: SyncProvider.aliyunOss,
        syncState: SyncState.synced,
        syncMessage: 'Remote revision matches local vault',
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
      );
    } else {
      next = config.copyWith(
        syncProvider: SyncProvider.aliyunOss,
        syncState: SyncState.idle,
        syncMessage: 'Local changes not uploaded yet',
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
      );
    }
    await _configStore.write(next);
    return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
  }

  @override
  Future<bool> pullRemoteToLocal() async {
    final config = await _configStore.read();
    if (_validateConfig(config) != null) {
      return false;
    }
    final remoteBytes = await _downloadRemoteBundle();
    if (remoteBytes == null) {
      return false;
    }
    await _fileStore.writeBundle(remoteBytes);
    final remoteRevision = _readRevision(remoteBytes);
    final next = config.copyWith(
      syncProvider: SyncProvider.aliyunOss,
      lastSyncedRevision: remoteRevision,
      lastRemoteRevision: remoteRevision,
      lastSyncAt: DateTime.now().toUtc(),
      syncState: SyncState.synced,
      syncMessage: 'Pulled remote encrypted bundle from Aliyun OSS',
    );
    await _configStore.write(next);
    return true;
  }

  @override
  Future<SyncStatusSnapshot> overwriteRemoteWithLocal({
    required int localRevision,
  }) async {
    final config = await _configStore.read();
    final validationError = _validateConfig(config);
    if (validationError != null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: validationError,
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final localBundle = await _fileStore.readBundle();
    if (localBundle == null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: 'Local vault.bundle is missing',
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final client = await _buildClient(config);
    final objectKey = _buildUserObjectKey(config);
    await _backupRemoteBundleIfPresent(client, config, objectKey);
    await client.putObject(localBundle, objectKey);

    final next = config.copyWith(
      syncProvider: SyncProvider.aliyunOss,
      lastSyncedRevision: localRevision,
      lastRemoteRevision: localRevision,
      lastSyncAt: DateTime.now().toUtc(),
      syncState: SyncState.synced,
      syncMessage: 'Local vault overwrote remote encrypted bundle',
    );
    await _configStore.write(next);
    return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
  }

  Future<int?> _readRemoteRevision() async {
    final bytes = await _downloadRemoteBundle();
    return _readRevision(bytes);
  }

  Future<Uint8List?> _downloadRemoteBundle() async {
    final config = await _configStore.read();
    final client = await _buildClient(config);
    final objectKey = _buildUserObjectKey(config);
    final exists = await _doesRemoteObjectExist(client, objectKey);
    if (!exists) {
      return null;
    }
    final response = await client.getObject(objectKey);
    final data = response.data;
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    if (data is String) {
      return Uint8List.fromList(utf8.encode(data));
    }
    throw StateError('Unexpected OSS response payload type: ${data.runtimeType}');
  }

  Future<bool> _doesRemoteObjectExist(Client client, String objectKey) async {
    try {
      return await client.doesObjectExist(objectKey);
    } on DioException catch (error) {
      if (_isNotFound(error)) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _backupRemoteBundleIfPresent(
    Client client,
    AppConfig config,
    String objectKey,
  ) async {
    final exists = await _doesRemoteObjectExist(client, objectKey);
    if (!exists) {
      return;
    }

    final backupKey = _buildBackupObjectKey(objectKey, DateTime.now().toUtc());
    await client.copyObject(
      CopyRequestOption(
        sourceBucketName: config.ossBucketName,
        sourceFileKey: objectKey,
        targetBucketName: config.ossBucketName,
        targetFileKey: backupKey,
      ),
    );
  }

  String _buildBackupObjectKey(String objectKey, DateTime timestamp) {
    final fileName = path.basename(objectKey);
    final username = _requireUsername();
    return '$username/backup/$fileName.${_formatBackupTimestamp(timestamp)}';
  }

  String _formatBackupTimestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final millisecond = value.millisecond.toString().padLeft(3, '0');
    return [year, month, day, 'T', hour, minute, second, millisecond, 'Z'].join();
  }

  String _buildUserObjectKey(AppConfig config) {
    final username = _requireUsername();
    return '$username/${config.ossObjectKey}';
  }

  String _requireUsername() {
    final username = _fileStore.activeUsername;
    if (username == null || username.isEmpty) {
      throw StateError('Active username is required.');
    }
    return username;
  }

  Future<Client> _buildClient(AppConfig config) async {
    return Client.init(
      ossEndpoint: config.ossEndpoint,
      bucketName: config.ossBucketName,
      authGetter: () => _fetchStsAuth(config),
      dio: _dio,
    );
  }

  Future<Auth> _fetchStsAuth(AppConfig config) async {
    final headers = _parseJsonMap(config.stsHeadersJson, fieldName: 'STS headers');
    final body = config.stsBodyJson.trim().isEmpty
        ? null
        : _parseJsonMap(config.stsBodyJson, fieldName: 'STS body');
    final response = await _dio.request<dynamic>(
      config.stsApiUrl,
      data: config.stsHttpMethod == StsHttpMethod.post ? body : null,
      options: Options(
        method: config.stsHttpMethod.name.toUpperCase(),
        headers: headers,
      ),
      queryParameters: config.stsHttpMethod == StsHttpMethod.get ? body : null,
    );
    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      throw StateError('STS API must return a JSON object.');
    }
    final credentialMap = _extractCredentialMap(raw);
    return Auth.fromJson(credentialMap);
  }

  Map<String, dynamic> _extractCredentialMap(Map<String, dynamic> raw) {
    if (_looksLikeAuthMap(raw)) {
      return raw;
    }
    final nested = raw['Credentials'];
    if (nested is Map<String, dynamic> && _looksLikeAuthMap(nested)) {
      return nested;
    }
    final lowerNested = raw['credentials'];
    if (lowerNested is Map<String, dynamic>) {
      final normalized = _normalizeCredentialMap(lowerNested);
      if (_looksLikeAuthMap(normalized)) {
        return normalized;
      }
    }
    final normalizedRoot = _normalizeCredentialMap(raw);
    if (_looksLikeAuthMap(normalizedRoot)) {
      return normalizedRoot;
    }
    throw StateError(
      'STS API response must contain AccessKeyId, AccessKeySecret, SecurityToken, and Expiration.',
    );
  }

  Map<String, dynamic> _normalizeCredentialMap(Map<String, dynamic> raw) {
    return {
      'AccessKeyId': raw['AccessKeyId'] ?? raw['access_key_id'],
      'AccessKeySecret': raw['AccessKeySecret'] ?? raw['access_key_secret'],
      'SecurityToken': raw['SecurityToken'] ?? raw['security_token'],
      'Expiration': raw['Expiration'] ?? raw['expiration'],
    };
  }

  Map<String, dynamic> _parseJsonMap(String raw, {required String fieldName}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw StateError('$fieldName must be a JSON object.');
    } catch (error) {
      throw StateError('$fieldName is invalid JSON: $error');
    }
  }

  bool _looksLikeAuthMap(Map<String, dynamic> map) {
    return map['AccessKeyId'] is String &&
        map['AccessKeySecret'] is String &&
        map['SecurityToken'] is String &&
        map['Expiration'] is String;
  }

  bool _isNotFound(DioException error) {
    return error.response?.statusCode == 404;
  }

  String? _validateConfig(AppConfig config) {
    if (config.ossEndpoint.trim().isEmpty) {
      return 'OSS endpoint is required';
    }
    if (config.ossBucketName.trim().isEmpty) {
      return 'OSS bucket is required';
    }
    if (config.ossObjectKey.trim().isEmpty) {
      return 'OSS object key is required';
    }
    if (config.stsApiUrl.trim().isEmpty) {
      return 'STS API URL is required';
    }
    if (config.stsHeadersJson.trim().isEmpty) {
      return 'STS headers JSON is required';
    }
    return null;
  }

  int? _readRevision(List<int>? bundleBytes) {
    if (bundleBytes == null) {
      return null;
    }
    final envelope = _serializer.deserializeEnvelope(Uint8List.fromList(bundleBytes));
    return envelope.revision;
  }
}

class MockOssSyncService implements SyncService {
  MockOssSyncService({
    required VaultFileStore fileStore,
    required BundleSerializer serializer,
    required AppConfigStore configStore,
  })  : _fileStore = fileStore,
        _serializer = serializer,
        _configStore = configStore;

  final VaultFileStore _fileStore;
  final BundleSerializer _serializer;
  final AppConfigStore _configStore;

  @override
  Future<String> getRemoteBundlePath() async {
    final file = await _fileStore.resolveRemoteBundleFile();
    return file.path;
  }

  @override
  Future<String> testStsConnection() async {
    return 'Mock OSS does not use STS';
  }

  @override
  Future<SyncStatusSnapshot> syncAfterLocalSave({
    required int localRevision,
  }) async {
    final config = await _configStore.read();
    final localBundle = await _fileStore.readBundle();
    if (localBundle == null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: 'Local vault.bundle is missing',
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    final remoteBundle = await _fileStore.readRemoteBundle();
    final remoteRevision = _readRevision(remoteBundle);
    final knownRemoteRevision = config.lastSyncedRevision;
    final hasConflict = remoteRevision != null &&
        knownRemoteRevision != null &&
        remoteRevision > knownRemoteRevision;
    final hasUnknownRemote = remoteRevision != null && knownRemoteRevision == null;

    if (hasConflict || hasUnknownRemote) {
      final next = config.copyWith(
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
        syncState: SyncState.conflict,
        syncMessage: hasUnknownRemote
            ? 'Remote vault exists but local session has no sync baseline'
            : 'Remote revision is newer. Pull remote before uploading.',
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    await _fileStore.writeRemoteBundle(localBundle);
    final next = config.copyWith(
      lastSyncedRevision: localRevision,
      lastRemoteRevision: localRevision,
      lastSyncAt: DateTime.now().toUtc(),
      syncState: SyncState.synced,
      syncMessage: 'Encrypted bundle uploaded to mock OSS',
    );
    await _configStore.write(next);
    return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
  }

  @override
  Future<SyncStatusSnapshot> checkRemoteStatus({
    required int localRevision,
  }) async {
    final config = await _configStore.read();
    final remoteRevision = _readRevision(await _fileStore.readRemoteBundle());
    final lastSyncedRevision = config.lastSyncedRevision;

    AppConfig next;
    if (remoteRevision == null) {
      next = config.copyWith(
        syncState: SyncState.idle,
        syncMessage: 'Remote vault is empty',
        lastRemoteRevision: null,
        clearLastRemoteRevision: true,
      );
    } else if (lastSyncedRevision != null && remoteRevision > lastSyncedRevision) {
      next = config.copyWith(
        syncState: SyncState.conflict,
        syncMessage: 'Remote revision is newer. Pull required.',
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
      );
    } else if (remoteRevision == localRevision) {
      next = config.copyWith(
        syncState: SyncState.synced,
        syncMessage: 'Remote revision matches local vault',
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
      );
    } else {
      next = config.copyWith(
        syncState: SyncState.idle,
        syncMessage: 'Local changes not uploaded yet',
        lastRemoteRevision: remoteRevision,
        lastSyncAt: DateTime.now().toUtc(),
      );
    }
    await _configStore.write(next);
    return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
  }

  @override
  Future<bool> pullRemoteToLocal() async {
    final remoteBundle = await _fileStore.readRemoteBundle();
    if (remoteBundle == null) {
      return false;
    }
    final remoteRevision = _readRevision(remoteBundle);
    await _fileStore.replaceLocalBundleWithRemote();
    final config = await _configStore.read();
    final next = config.copyWith(
      lastSyncedRevision: remoteRevision,
      lastRemoteRevision: remoteRevision,
      lastSyncAt: DateTime.now().toUtc(),
      syncState: SyncState.synced,
      syncMessage: 'Pulled remote encrypted bundle',
    );
    await _configStore.write(next);
    return true;
  }

  @override
  Future<SyncStatusSnapshot> overwriteRemoteWithLocal({
    required int localRevision,
  }) async {
    final localBundle = await _fileStore.readBundle();
    final config = await _configStore.read();
    if (localBundle == null) {
      final next = config.copyWith(
        syncState: SyncState.error,
        syncMessage: 'Local vault.bundle is missing',
      );
      await _configStore.write(next);
      return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
    }

    await _fileStore.writeRemoteBundle(localBundle);
    final next = config.copyWith(
      lastSyncedRevision: localRevision,
      lastRemoteRevision: localRevision,
      lastSyncAt: DateTime.now().toUtc(),
      syncState: SyncState.synced,
      syncMessage: 'Local vault overwrote mock remote bundle',
    );
    await _configStore.write(next);
    return SyncStatusSnapshot.fromConfig(next, localRevision: localRevision);
  }

  int? _readRevision(List<int>? bundleBytes) {
    if (bundleBytes == null) {
      return null;
    }
    final envelope = _serializer.deserializeEnvelope(Uint8List.fromList(bundleBytes));
    return envelope.revision;
  }
}