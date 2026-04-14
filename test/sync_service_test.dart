import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:secret_book/models/app_config.dart';
import 'package:secret_book/models/sync_status.dart';
import 'package:secret_book/models/document_vault.dart';
import 'package:secret_book/serialization/bundle_serializer.dart';
import 'package:secret_book/serialization/vault_packer.dart';
import 'package:secret_book/services/app_config_store.dart';
import 'package:secret_book/services/crypto_service.dart';
import 'package:secret_book/services/sync_service.dart';
import 'package:secret_book/services/vault_file_store.dart';

void main() {
  test('pulling remote bundle backs up existing local bundle in the same directory', () async {
    final root = await _createTempTestDirectory('sync-service-test');

    try {
      final fileStore = VaultFileStore(baseDirectoryPath: root.path);
      fileStore.setActiveUsername('alice');
      final configStore = AppConfigStore(fileStore: fileStore);
      await configStore.write(
        AppConfig.initial().copyWith(
          syncState: SyncState.idle,
          syncMessage: 'test',
        ),
      );

      final serializer = JsonBundleSerializer();
      final syncService = MockOssSyncService(
        fileStore: fileStore,
        serializer: serializer,
        configStore: configStore,
      );

      final localBytes = await _buildBundleBytes(revision: 1);
      final remoteBytes = await _buildBundleBytes(revision: 9);
      await fileStore.writeBundle(localBytes);
      await fileStore.writeRemoteBundle(remoteBytes);

      final pulled = await syncService.pullRemoteToLocal(backupLocalIfPresent: true);

      expect(pulled, isTrue);
      expect(await fileStore.readBundle(), remoteBytes);

      final userDir = await fileStore.resolveUserDirectory();
      final backupFiles = userDir
          .listSync()
          .whereType<File>()
          .where((file) => path.basename(file.path).startsWith('vault.bundle_'))
          .toList();

      expect(backupFiles, hasLength(1));
      expect(await backupFiles.single.readAsBytes(), localBytes);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('mock sync service reports remote bundle existence', () async {
    final root = await _createTempTestDirectory('sync-service-exists-test');

    try {
      final fileStore = VaultFileStore(baseDirectoryPath: root.path);
      fileStore.setActiveUsername('alice');
      final configStore = AppConfigStore(fileStore: fileStore);
      final syncService = MockOssSyncService(
        fileStore: fileStore,
        serializer: JsonBundleSerializer(),
        configStore: configStore,
      );

      expect(await syncService.remoteBundleExists(), isFalse);

      await fileStore.writeRemoteBundle(await _buildBundleBytes(revision: 3));

      expect(await syncService.remoteBundleExists(), isTrue);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('matching local and remote revisions do not conflict when sync baseline is missing', () async {
    final root = await _createTempTestDirectory('sync-service-matching-revision');

    try {
      final fileStore = VaultFileStore(baseDirectoryPath: root.path);
      fileStore.setActiveUsername('alice');
      final configStore = AppConfigStore(fileStore: fileStore);
      await configStore.write(
        AppConfig.initial().copyWith(
          clearLastSyncedRevision: true,
          clearLastRemoteRevision: true,
          syncState: SyncState.idle,
          syncMessage: 'test',
        ),
      );

      final syncService = MockOssSyncService(
        fileStore: fileStore,
        serializer: JsonBundleSerializer(),
        configStore: configStore,
      );

      final bundleBytes = await _buildBundleBytes(revision: 7);
      await fileStore.writeBundle(bundleBytes);
      await fileStore.writeRemoteBundle(bundleBytes);

      final status = await syncService.checkRemoteStatus(localRevision: 7);

      expect(status.state, SyncState.synced);
      expect(status.remoteRevision, 7);

      final config = await configStore.read();
      expect(config.lastSyncedRevision, 7);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('remote revision only conflicts when it is newer than local revision', () async {
    final root = await _createTempTestDirectory('sync-service-real-conflict');

    try {
      final fileStore = VaultFileStore(baseDirectoryPath: root.path);
      fileStore.setActiveUsername('alice');
      final configStore = AppConfigStore(fileStore: fileStore);
      await configStore.write(
        AppConfig.initial().copyWith(
          clearLastSyncedRevision: true,
          clearLastRemoteRevision: true,
          syncState: SyncState.idle,
          syncMessage: 'test',
        ),
      );

      final syncService = MockOssSyncService(
        fileStore: fileStore,
        serializer: JsonBundleSerializer(),
        configStore: configStore,
      );

      await fileStore.writeBundle(await _buildBundleBytes(revision: 7));
      await fileStore.writeRemoteBundle(await _buildBundleBytes(revision: 8));

      final status = await syncService.checkRemoteStatus(localRevision: 7);

      expect(status.state, SyncState.conflict);
      expect(status.remoteRevision, 8);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}

Future<Directory> _createTempTestDirectory(String name) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  return Directory(
    path.join(Directory.current.path, '.codex-temp', '$name-$suffix'),
  ).create(recursive: true);
}

Future<Uint8List> _buildBundleBytes({required int revision}) async {
  final serializer = JsonBundleSerializer();
  final packer = VaultPacker();
  final crypto = CryptoService();
  final vault = DocumentVault.seeded().copyWith(revision: revision);
  final envelope = await crypto.encrypt(
    password: 'test-password',
    plainBytes: packer.pack(vault),
    revision: revision,
  );
  return serializer.serializeEnvelope(envelope);
}
