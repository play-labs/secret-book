import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:secret_book/models/app_config.dart';
import 'package:secret_book/models/sync_status.dart';
import 'package:secret_book/repositories/vault_repository.dart';
import 'package:secret_book/serialization/bundle_serializer.dart';
import 'package:secret_book/serialization/vault_packer.dart';
import 'package:secret_book/services/app_config_store.dart';
import 'package:secret_book/services/crypto_service.dart';
import 'package:secret_book/services/sync_service.dart';
import 'package:secret_book/services/vault_file_store.dart';

void main() {
  test('manual smoke: save local vault and upload encrypted bundle to Aliyun OSS', () async {
    final actualConfig = await _readInstalledConfig();
    final configsToTry = <AppConfig>[
      actualConfig,
      if (actualConfig.ossBucketName != 'ltp-book')
        actualConfig.copyWith(ossBucketName: 'ltp-book'),
    ];

    Object? lastError;
    StackTrace? lastStackTrace;

    for (final config in configsToTry) {
      try {
        final result = await _runSmoke(config);
        stdout.writeln('OSS smoke test bucket: ${result.bucketName}');
        stdout.writeln('OSS smoke test object key: ${result.objectKey}');
        stdout.writeln('OSS smoke test status: ${result.syncMessage}');
        stdout.writeln('OSS smoke test synced revision: ${result.syncedRevision}');
        return;
      } catch (error, stackTrace) {
        stdout.writeln('OSS smoke test failed with bucket ${config.ossBucketName}: $error');
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace!);
    }
    fail('未执行任何 OSS 联调配置。');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<_SmokeResult> _runSmoke(AppConfig baseConfig) async {
  final runId = DateTime.now().toUtc().millisecondsSinceEpoch;
  final tempDir = await Directory(
    path.join(Directory.current.path, '.codex-temp', 'aliyun-oss-smoke-$runId'),
  ).create(recursive: true);

  final fileStore = VaultFileStore(baseDirectoryPath: tempDir.path);
  final configStore = AppConfigStore(fileStore: fileStore);
  final smokeConfig = baseConfig.copyWith(
    ossObjectKey: 'codex-smoke/$runId/vault.bundle',
    clearLastRemoteRevision: true,
    clearLastSyncedRevision: true,
    clearLastSyncAt: true,
    syncState: SyncState.idle,
    syncMessage: '准备联调',
  );
  await configStore.write(smokeConfig);

  final repository = LocalVaultRepository(
    serializer: JsonBundleSerializer(),
    vaultPacker: VaultPacker(),
    fileStore: fileStore,
    cryptoServiceBuilder: () => CryptoService(),
  );
  final syncService = AliyunOssSyncService(
    fileStore: fileStore,
    serializer: JsonBundleSerializer(),
    configStore: configStore,
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      ),
    ),
  );

  try {
    await syncService.testStsConnection();
    stdout.writeln('STS 测试通过，bucket=${smokeConfig.ossBucketName}');
  } catch (error) {
    throw StateError(
      'STS 阶段失败（bucket=${smokeConfig.ossBucketName}）：${_describeError(error)}',
    );
  }

  const password = 'secret-book-smoke-pass';
  final vault = await repository.unlock(password);

  late final SyncStatusSnapshot syncStatus;
  try {
    syncStatus = await syncService.syncAfterLocalSave(
      localRevision: vault.revision,
    );
    stdout.writeln('上传阶段完成，状态=${syncStatus.state.name}');
  } catch (error) {
    throw StateError(
      '上传阶段失败（bucket=${smokeConfig.ossBucketName}）：${_describeError(error)}',
    );
  }

  late final SyncStatusSnapshot checkedStatus;
  try {
    checkedStatus = await syncService.checkRemoteStatus(
      localRevision: vault.revision,
    );
    stdout.writeln('回读检查完成，状态=${checkedStatus.state.name}');
  } catch (error) {
    throw StateError(
      '回读检查失败（bucket=${smokeConfig.ossBucketName}）：${_describeError(error)}',
    );
  }

  expect(syncStatus.state, SyncState.synced);
  expect(checkedStatus.state, SyncState.synced);

  final finalConfig = await configStore.read();
  return _SmokeResult(
    bucketName: smokeConfig.ossBucketName,
    objectKey: smokeConfig.ossObjectKey,
    syncMessage: finalConfig.syncMessage ?? '',
    syncedRevision: finalConfig.lastSyncedRevision,
  );
}

Future<AppConfig> _readInstalledConfig() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    throw StateError('未找到 APPDATA 环境变量。');
  }

  final file = File(
    path.join(
      appData,
      'com.example',
      'secret_book',
      'secret_book',
      'config.json',
    ),
  );
  if (!await file.exists()) {
    throw StateError('未找到已安装应用的 config.json：${file.path}');
  }

  final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  return AppConfig.fromMap(map);
}

class _SmokeResult {
  const _SmokeResult({
    required this.bucketName,
    required this.objectKey,
    required this.syncMessage,
    required this.syncedRevision,
  });

  final String bucketName;
  final String objectKey;
  final String syncMessage;
  final int? syncedRevision;
}

String _describeError(Object error) {
  if (error is DioException) {
    return [
      error.toString(),
      'uri=${error.requestOptions.uri}',
      'status=${error.response?.statusCode}',
      'data=${error.response?.data}',
    ].join(' | ');
  }
  return error.toString();
}
