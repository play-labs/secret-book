import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

import '../models/app_config.dart';
import 'vault_file_store.dart';

class AppConfigStore {
  static const String bundledConfigAssetPath = 'config.toml';

  AppConfigStore({
    required VaultFileStore fileStore,
  }) : _fileStore = fileStore;

  final VaultFileStore _fileStore;

  Future<AppConfig> read() async {
    final file = await _fileStore.resolveConfigFile();
    if (await file.exists()) {
      final toml = await file.readAsString();
      return AppConfig.fromMap(_decodeToml(toml));
    }

    final legacyFile = await _fileStore.resolveLegacyConfigJsonFile();
    if (await legacyFile.exists()) {
      final json = jsonDecode(await legacyFile.readAsString()) as Map<String, dynamic>;
      final config = AppConfig.fromMap(json);
      await write(config);
      return config;
    }

    final bundledConfig = await _readBundledConfig();
    final config = bundledConfig ?? AppConfig.initial();
    await write(config);
    return config;
  }

  Future<void> write(AppConfig config) async {
    final file = await _fileStore.resolveConfigFile();
    await file.writeAsString(
      _encodeToml(config),
      flush: true,
    );
  }

  Future<AppConfig?> _readBundledConfig() async {
    try {
      final toml = await rootBundle.loadString(bundledConfigAssetPath);
      return AppConfig.fromMap(_decodeToml(toml));
    } on FlutterError {
      return null;
    }
  }

  Map<String, dynamic> _decodeToml(String raw) {
    final result = <String, dynamic>{};
    String? section;

    for (final originalLine in const LineSplitter().convert(raw)) {
      final line = originalLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim();
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      final fullKey = section == null ? key : '$section.$key';
      result[fullKey] = _parseTomlValue(value);
    }

    return {
      'syncProvider': result['app.sync_provider'],
      'encryptionProfile': result['app.encryption_profile'],
      'appUpdateJsonUrl': result['app.app_update_json_url'],
      'autosaveDelaySeconds': result['app.autosave_delay_seconds'],
      'remoteSyncIntervalSeconds': result['app.remote_sync_interval_seconds'],
      'ossEndpoint': result['oss.endpoint'],
      'ossBucketName': result['oss.bucket_name'],
      'ossObjectKey': result['oss.object_key'],
      'stsApiUrl': result['sts.api_url'],
      'stsHttpMethod': result['sts.http_method'],
      'stsHeadersJson': result['sts.headers_json'],
      'stsBodyJson': result['sts.body_json'],
      'lastSyncedRevision': result['sync.last_synced_revision'],
      'lastRemoteRevision': result['sync.last_remote_revision'],
      'lastRemoteModifiedAt': result['sync.last_remote_modified_at'],
      'lastSyncAt': result['sync.last_sync_at'],
      'syncState': result['sync.state'],
      'syncMessage': result['sync.message'],
    };
  }

  dynamic _parseTomlValue(String raw) {
    if (raw == 'true') {
      return true;
    }
    if (raw == 'false') {
      return false;
    }
    if (raw == 'null') {
      return null;
    }
    final number = int.tryParse(raw);
    if (number != null) {
      return number;
    }
    if (raw.startsWith('"') && raw.endsWith('"')) {
      return jsonDecode(raw);
    }
    return raw;
  }

  String _encodeToml(AppConfig config) {
    final lines = <String>[
      '# Secret Book per-user configuration',
      '# Sensitive runtime values belong here, not in source control.',
      '',
      '[app]',
      'sync_provider = ${_tomlString(config.syncProvider.name)}',
      'encryption_profile = ${_tomlString(config.encryptionProfile.name)}',
      'app_update_json_url = ${_tomlString(config.appUpdateJsonUrl)}',
      'autosave_delay_seconds = ${config.autosaveDelaySeconds}',
      'remote_sync_interval_seconds = ${config.remoteSyncIntervalSeconds}',
      '',
      '[oss]',
      'endpoint = ${_tomlString(config.ossEndpoint)}',
      'bucket_name = ${_tomlString(config.ossBucketName)}',
      'object_key = ${_tomlString(config.ossObjectKey)}',
      '',
      '[sts]',
      'api_url = ${_tomlString(config.stsApiUrl)}',
      'http_method = ${_tomlString(config.stsHttpMethod.name)}',
      'headers_json = ${_tomlString(config.stsHeadersJson)}',
      'body_json = ${_tomlString(config.stsBodyJson)}',
      '',
      '[sync]',
      'last_synced_revision = ${_tomlNullableInt(config.lastSyncedRevision)}',
      'last_remote_revision = ${_tomlNullableInt(config.lastRemoteRevision)}',
      'last_remote_modified_at = ${_tomlNullableString(config.lastRemoteModifiedAt?.toIso8601String())}',
      'last_sync_at = ${_tomlNullableString(config.lastSyncAt?.toIso8601String())}',
      'state = ${_tomlString(config.syncState.name)}',
      'message = ${_tomlNullableString(config.syncMessage)}',
      '',
    ];
    return lines.join('\n');
  }

  String _tomlString(String value) => jsonEncode(value);

  String _tomlNullableString(String? value) {
    if (value == null) {
      return 'null';
    }
    return jsonEncode(value);
  }

  String _tomlNullableInt(int? value) {
    if (value == null) {
      return 'null';
    }
    return value.toString();
  }
}
