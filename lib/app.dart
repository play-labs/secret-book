import 'package:flutter/material.dart';

import 'models/document_vault.dart';
import 'pages/create_password_page.dart';
import 'pages/home_page.dart';
import 'pages/unlock_page.dart';
import 'pages/username_entry_page.dart';
import 'repositories/vault_repository.dart';
import 'serialization/bundle_serializer.dart';
import 'serialization/vault_packer.dart';
import 'services/app_config_store.dart';
import 'services/crypto_service.dart';
import 'services/sync_service.dart';
import 'services/vault_file_store.dart';
import 'state/vault_controller.dart';

class SecretBookApp extends StatefulWidget {
  const SecretBookApp({super.key});

  @override
  State<SecretBookApp> createState() => _SecretBookAppState();
}

class _SecretBookAppState extends State<SecretBookApp> {
  late final VaultRepository repository;
  late final VaultFileStore fileStore;
  late final AppConfigStore configStore;
  late final SyncService syncService;

  VaultController? _controller;
  String? _activeUsername;
  String? _masterPassword;
  String? _bundlePath;
  String? _remoteBundlePath;
  bool? _hasExistingBundle;
  bool _isPreparingUser = false;

  @override
  void initState() {
    super.initState();
    fileStore = VaultFileStore();
    configStore = AppConfigStore(fileStore: fileStore);
    repository = LocalVaultRepository(
      serializer: JsonBundleSerializer(),
      vaultPacker: VaultPacker(),
      fileStore: fileStore,
      cryptoService: CryptoService(),
    );
    syncService = AliyunOssSyncService(
      fileStore: fileStore,
      serializer: JsonBundleSerializer(),
      configStore: configStore,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _selectUsername(String username) async {
    setState(() {
      _isPreparingUser = true;
    });

    try {
      fileStore.setActiveUsername(username);
      await configStore.read();
      final bundlePath = await repository.getBundlePath();
      final hasBundle = await fileStore.bundleExists();
      final remotePath = await syncService.getRemoteBundlePath();

      if (!mounted) {
        return;
      }
      setState(() {
        _activeUsername = fileStore.activeUsername;
        _bundlePath = bundlePath;
        _remoteBundlePath = remotePath;
        _hasExistingBundle = hasBundle;
        _masterPassword = null;
        _controller?.dispose();
        _controller = null;
        _isPreparingUser = false;
      });
    } catch (_) {
      fileStore.clearActiveUsername();
      rethrow;
    }
  }

  Future<void> _unlock(String password) async {
    final vault = await repository.unlock(password);
    final controller = _buildController(vault: vault, password: password);

    setState(() {
      _controller?.dispose();
      _controller = controller;
      _masterPassword = password;
      _hasExistingBundle = true;
    });
  }

  Future<void> _createVault(String password) async {
    await _unlock(password);
  }

  Future<void> _changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_controller == null || _masterPassword == null) {
      throw StateError('Vault is locked.');
    }
    if (currentPassword != _masterPassword) {
      throw ArgumentError('Current password is incorrect.');
    }
    if (newPassword.trim().isEmpty) {
      throw ArgumentError('New password cannot be empty.');
    }
    if (newPassword.length < 8) {
      throw ArgumentError('New password must be at least 8 characters.');
    }

    await _controller!.saveNow();
    if (_controller!.saveError != null) {
      throw StateError(_controller!.saveError!);
    }

    final vault = _controller!.snapshot();
    await repository.save(vault, newPassword);
    final nextController = _buildController(vault: vault, password: newPassword);

    setState(() {
      _controller?.dispose();
      _controller = nextController;
      _masterPassword = newPassword;
    });
  }

  void _lock() {
    setState(() {
      _controller?.dispose();
      _controller = null;
      _masterPassword = null;
    });
  }

  void _changeUser() {
    fileStore.clearActiveUsername();
    setState(() {
      _controller?.dispose();
      _controller = null;
      _activeUsername = null;
      _masterPassword = null;
      _bundlePath = null;
      _remoteBundlePath = null;
      _hasExistingBundle = null;
      _isPreparingUser = false;
    });
  }

  VaultController _buildController({
    required DocumentVault vault,
    required String password,
  }) {
    return VaultController(
      initialVault: vault,
      onPersist: (nextVault) => repository.save(nextVault, password),
      onSyncAfterSave: (localRevision) => syncService.syncAfterLocalSave(
        localRevision: localRevision,
      ),
      onCheckRemoteStatus: (localRevision) => syncService.checkRemoteStatus(
        localRevision: localRevision,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secret Book',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF245B4B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F1E8),
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
      ),
      home: _isPreparingUser
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _activeUsername == null
              ? UsernameEntryPage(onContinue: _selectUsername)
              : _controller == null
                  ? ((_hasExistingBundle ?? false)
                      ? UnlockPage(
                          username: _activeUsername!,
                          onUnlock: _unlock,
                          onChangeUser: _changeUser,
                        )
                      : CreatePasswordPage(
                          username: _activeUsername!,
                          onCreatePassword: _createVault,
                          onChangeUser: _changeUser,
                        ))
                  : HomePage(
                      controller: _controller!,
                      bundleSizeBuilder: () => repository.debugBundleBytesLength ?? 0,
                      bundlePath: _bundlePath ?? 'Resolving...',
                      remoteBundlePath: _remoteBundlePath ?? 'Resolving...',
                      masterPasswordLabel: _masterPassword == null
                          ? 'Locked'
                          : 'Unlocked (${_masterPassword!.length} chars)',
                      onLock: _lock,
                      onChangePassword: _changePassword,
                    ),
    );
  }
}