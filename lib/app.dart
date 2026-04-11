import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_metadata.dart';
import 'models/app_config.dart';
import 'models/app_release_info.dart';
import 'models/document_vault.dart';
import 'models/encryption_profile.dart';
import 'models/sync_status.dart';
import 'pages/create_password_page.dart';
import 'pages/home_page.dart';
import 'pages/unlock_page.dart';
import 'pages/username_entry_page.dart';
import 'repositories/vault_repository.dart';
import 'serialization/bundle_serializer.dart';
import 'serialization/vault_packer.dart';
import 'services/app_config_store.dart';
import 'services/app_update_service.dart';
import 'services/crypto_service.dart';
import 'services/sync_service.dart';
import 'services/vault_file_store.dart';
import 'state/vault_controller.dart';

class SecretBookApp extends StatefulWidget {
  const SecretBookApp({super.key});

  @override
  State<SecretBookApp> createState() => _SecretBookAppState();
}

enum _ConflictChoice { local, remote, later }

const MethodChannel _windowChannel = MethodChannel('secret_book/window');

class _SecretBookAppState extends State<SecretBookApp> with WidgetsBindingObserver {
  late VaultRepository repository;
  late final VaultFileStore fileStore;
  late final AppConfigStore configStore;
  late final SyncService syncService;
  late final AppUpdateService updateService;
  late final JsonBundleSerializer _bundleSerializer;
  late final VaultPacker _vaultPacker;

  VaultController? _controller;
  String? _activeUsername;
  String? _masterPassword;
  String? _bundlePath;
  String? _remoteBundlePath;
  bool? _hasExistingBundle;
  AppConfig? _appConfig;
  VaultKdfSettings? _bundleKdfSettings;
  bool _isPreparingUser = false;
  Timer? _remoteSyncTimer;
  Timer? _updateCheckTimer;
  bool _isRunningRemoteSync = false;
  bool _suspendAutoSyncForConflict = false;
  bool _isConflictDialogActive = false;
  bool _isCheckingUpdates = false;
  bool _isDownloadingUpdate = false;
  UpdateCheckResult? _availableUpdate;
  AppReleaseInfo? _latestRelease;
  String? _downloadedInstallerPath;
  String? _lastPushedWindowTitle;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  String get _windowTitle {
    final username = _activeUsername;
    if (username != null && username.trim().isNotEmpty) {
      return "$username's $kAppName - $kAppVersion";
    }
    return '$kAppName - $kAppVersion';
  }

  @override
  void initState() {
    super.initState();
    fileStore = VaultFileStore();
    configStore = AppConfigStore(fileStore: fileStore);
    _bundleSerializer = JsonBundleSerializer();
    _vaultPacker = VaultPacker();
    repository = _createRepository();
    syncService = AliyunOssSyncService(
      fileStore: fileStore,
      serializer: JsonBundleSerializer(),
      configStore: configStore,
    );
    updateService = AppUpdateService(configStore: configStore);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRemoteSyncTimer();
    _stopUpdateCheckTimer();
    _controller?.removeListener(_handleControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  bool _isHandlingAppExit = false;

  VaultRepository _createRepository() {
    return LocalVaultRepository(
      serializer: _bundleSerializer,
      vaultPacker: _vaultPacker,
      fileStore: fileStore,
      cryptoServiceBuilder: _buildCryptoService,
    );
  }

  CryptoService _buildCryptoService() {
    final profile = _appConfig?.encryptionProfile ?? EncryptionProfile.standard;
    return CryptoService(
      kdf: Argon2id(
        memory: profile.memoryKiB,
        iterations: profile.iterations,
        parallelism: profile.parallelism,
        hashLength: 32,
      ),
    );
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    if (_isHandlingAppExit) {
      return ui.AppExitResponse.cancel;
    }
    _isHandlingAppExit = true;
    try {
      final flushed = await _flushPendingWorkBeforeExit();
      return flushed ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
    } finally {
      _isHandlingAppExit = false;
    }
  }

  Future<bool> _flushPendingWorkBeforeExit() async {
    final controller = _controller;
    if (controller == null) {
      return true;
    }

    if (controller.hasPendingChanges || controller.isSaving) {
      await controller.saveNow();
      for (var attempt = 0; attempt < 60; attempt += 1) {
        if (!controller.isSaving && !controller.hasPendingChanges) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (controller.hasPendingChanges && !controller.isSaving) {
        await controller.saveNow();
      }
      for (var attempt = 0; attempt < 60; attempt += 1) {
        if (!controller.isSaving && !controller.hasPendingChanges) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    if (controller.isSaving || controller.hasPendingChanges || controller.saveError != null) {
      if (mounted) {
        await _showMessageDialog(
          title: 'Close blocked',
          message: controller.saveError ?? 'Local save or OSS upload is still in progress. Please wait a moment and try again.',
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _selectUsername(String username) async {
    setState(() {
      _isPreparingUser = true;
    });

    try {
      fileStore.setActiveUsername(username);
      var config = await configStore.read();
      var bundleKdfSettings = await repository.inspectBundleKdfSettings();
      final matchedProfile = bundleKdfSettings == null
          ? null
          : EncryptionProfile.fromSettings(bundleKdfSettings);
      if (matchedProfile != null && matchedProfile != config.encryptionProfile) {
        config = config.copyWith(encryptionProfile: matchedProfile);
        await configStore.write(config);
      }
      _appConfig = config;
      repository = _createRepository();
      bundleKdfSettings ??= await repository.inspectBundleKdfSettings();
      final bundlePath = await repository.getBundlePath();
      final hasBundle = await fileStore.bundleExists();
      final remotePath = await syncService.getRemoteBundlePath();

      if (!mounted) {
        return;
      }
      _stopRemoteSyncTimer();
      _stopUpdateCheckTimer();
      _replaceController(null);
      setState(() {
        _activeUsername = fileStore.activeUsername;
        _bundlePath = bundlePath;
        _remoteBundlePath = remotePath;
        _hasExistingBundle = hasBundle;
        _masterPassword = null;
        _isPreparingUser = false;
        _suspendAutoSyncForConflict = false;
        _isConflictDialogActive = false;
        _appConfig = config;
        _bundleKdfSettings = bundleKdfSettings;
      });
    } catch (_) {
      fileStore.clearActiveUsername();
      rethrow;
    }
  }

  Future<void> _unlock(String password) async {
    final vault = await repository.unlock(password);
    final controller = _buildController(vault: vault, password: password);

    _replaceController(controller);
    setState(() {
      _masterPassword = password;
      _hasExistingBundle = true;
      _suspendAutoSyncForConflict = false;
      _isConflictDialogActive = false;
      _bundleKdfSettings = repository.currentKdfSettings;
    });
    await _restartRemoteSyncTimer();
    _restartUpdateCheckTimer();
    unawaited(_checkForUpdates(silent: true));
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

    _replaceController(nextController);
    setState(() {
      _masterPassword = newPassword;
      _bundleKdfSettings = repository.currentKdfSettings;
    });
    await _restartRemoteSyncTimer();
  }

  void _lock() {
    _stopRemoteSyncTimer();
    _stopUpdateCheckTimer();
    _replaceController(null);
    setState(() {
      _masterPassword = null;
      _suspendAutoSyncForConflict = false;
      _isConflictDialogActive = false;
      _availableUpdate = null;
      _latestRelease = null;
      _downloadedInstallerPath = null;
      _bundleKdfSettings = null;
      _isCheckingUpdates = false;
      _isDownloadingUpdate = false;
    });
  }

  void _changeUser() {
    _stopRemoteSyncTimer();
    _stopUpdateCheckTimer();
    fileStore.clearActiveUsername();
    _replaceController(null);
    setState(() {
      _activeUsername = null;
      _masterPassword = null;
      _bundlePath = null;
      _remoteBundlePath = null;
      _hasExistingBundle = null;
      _isPreparingUser = false;
      _suspendAutoSyncForConflict = false;
      _appConfig = null;
      _bundleKdfSettings = null;
      _isConflictDialogActive = false;
      _availableUpdate = null;
      _latestRelease = null;
      _downloadedInstallerPath = null;
      _isCheckingUpdates = false;
      _isDownloadingUpdate = false;
    });
  }

  void _replaceController(VaultController? nextController) {
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_handleControllerChanged);
      previous.dispose();
    }
    _controller = nextController;
    _controller?.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) {
      return;
    }
    final status = controller.syncStatus;
    if (status.state == SyncState.conflict && !_isConflictDialogActive) {
      _suspendAutoSyncForConflict = true;
      _isConflictDialogActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _showConflictResolutionDialog(status);
        } finally {
          if (mounted) {
            setState(() {
              _isConflictDialogActive = false;
            });
          } else {
            _isConflictDialogActive = false;
          }
        }
      });
    }
  }

  Future<void> _restartRemoteSyncTimer() async {
    _stopRemoteSyncTimer();
    if (_controller == null || _masterPassword == null) {
      return;
    }
    final config = await configStore.read();
    final seconds = config.remoteSyncIntervalSeconds;
    if (seconds < 5) {
      return;
    }
    _remoteSyncTimer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => _syncVaultFromRemoteSilently(),
    );
    unawaited(_syncVaultFromRemoteSilently());
  }

  void _stopRemoteSyncTimer() {
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = null;
  }

  void _restartUpdateCheckTimer() {
    _stopUpdateCheckTimer();
    if (_controller == null) {
      return;
    }
    _updateCheckTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_checkForUpdates(silent: true)),
    );
    unawaited(_checkForUpdates(silent: true));
  }

  void _stopUpdateCheckTimer() {
    _updateCheckTimer?.cancel();
    _updateCheckTimer = null;
  }

  String? get _titleUpdateLabel {
    final available = _availableUpdate;
    if (available != null && _downloadedInstallerPath != null) {
      return '\uFF08\u5B89\u88C5\u6700\u65B0\u7248\u672C ${available.release.version}\uFF09';
    }
    final latest = _latestRelease;
    if (latest != null) {
      return '\uFF08\u6700\u65B0\u7248\u672C ${latest.version}\uFF09';
    }
    return null;
  }

  Future<void> _syncVaultFromRemoteSilently() async {
    if (_isRunningRemoteSync || _controller == null || _masterPassword == null) {
      return;
    }
    if (_suspendAutoSyncForConflict) {
      return;
    }
    if (_controller!.isSaving || _controller!.hasPendingChanges) {
      return;
    }

    _isRunningRemoteSync = true;
    try {
      await _controller!.refreshRemoteStatus();
    } catch (_) {
      // Keep the current UI usable when background sync fails.
    } finally {
      _isRunningRemoteSync = false;
    }
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    if (_isCheckingUpdates || _isDownloadingUpdate) {
      return;
    }

    if (mounted) {
      setState(() {
        _isCheckingUpdates = true;
      });
    } else {
      _isCheckingUpdates = true;
    }

    try {
      final result = await updateService.checkForUpdate(
        currentVersion: kAppVersion,
        currentBuild: kAppBuild,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _latestRelease = result.release;
      });

      if (!result.isUpdateAvailable) {
        setState(() {
          _availableUpdate = null;
          _downloadedInstallerPath = null;
        });
        return;
      }

      setState(() {
        _isDownloadingUpdate = true;
      });
      final installer = await updateService.downloadInstaller(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _availableUpdate = result;
        _latestRelease = result.release;
        _downloadedInstallerPath = installer.path;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (!silent) {
        await _showMessageDialog(
          title: 'Check update failed',
          message: '$error\n\nConfigure appUpdateJsonUrl in config.toml before using this feature.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdates = false;
          _isDownloadingUpdate = false;
        });
      } else {
        _isCheckingUpdates = false;
        _isDownloadingUpdate = false;
      }
    }
  }

  Future<void> _showMessageDialog({
    required String title,
    required String message,
  }) async {
    final dialogRootContext = _navigatorKey.currentContext;
    if (dialogRootContext == null) {
      return;
    }
    await showDialog<void>(
      context: dialogRootContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _installDownloadedUpdate() async {
    final installerPath = _downloadedInstallerPath;
    if (installerPath == null || installerPath.trim().isEmpty) {
      await _showMessageDialog(
        title: 'Update not ready',
        message: 'No downloaded installer was found yet.',
      );
      return;
    }

    final installer = File(installerPath);
    if (!await installer.exists()) {
      if (mounted) {
        setState(() {
          _availableUpdate = null;
          _downloadedInstallerPath = null;
        });
      }
      await _showMessageDialog(
        title: 'Installer missing',
        message: 'The downloaded installer file is missing. Please check for updates again.',
      );
      return;
    }

    await Process.start(
      installer.path,
      const <String>[],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    exit(0);
  }

  Future<void> _showConflictResolutionDialog(SyncStatusSnapshot status) async {
    if (!mounted || _controller == null) {
      return;
    }

    while (mounted) {
      final liveStatus = _controller?.syncStatus ?? status;
      final dialogRootContext = _navigatorKey.currentContext;
      if (dialogRootContext == null) {
        return;
      }
      // ignore: use_build_context_synchronously
      final choice = await showDialog<_ConflictChoice>(
        // ignore: use_build_context_synchronously
        context: dialogRootContext,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Sync conflict detected'),
            content: Text(
              '${liveStatus.message}\n\nChoose whether to keep local data or replace it with remote data. Automatic pulling stays paused until this conflict is resolved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(_ConflictChoice.later),
                child: const Text('Later'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(_ConflictChoice.remote),
                child: const Text('Use remote data'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(_ConflictChoice.local),
                child: const Text('Use local data'),
              ),
            ],
          );
        },
      );

      if (!mounted || choice == null) {
        return;
      }
      if (choice == _ConflictChoice.later) {
        return;
      }

      final confirmed = await _showConflictConfirmation(choice);
      if (!mounted) {
        return;
      }
      if (!confirmed) {
        continue;
      }

      await _applyConflictChoice(choice);
      return;
    }
  }

  Future<bool> _showConflictConfirmation(_ConflictChoice choice) async {
    final useLocal = choice == _ConflictChoice.local;
    final title = useLocal ? 'Confirm local overwrite' : 'Confirm remote overwrite';
    final message = useLocal
        ? 'This uploads the current local vault and overwrites remote data. The previous remote bundle will be moved into backup. Continue?'
        : 'This replaces the current local vault with remote data. Unsynced local content will be discarded. Continue?';
    final dialogRootContext = _navigatorKey.currentContext;
    if (dialogRootContext == null) {
      return false;
    }
    // ignore: use_build_context_synchronously
    final result = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: dialogRootContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _applyConflictChoice(_ConflictChoice choice) async {
    if (_controller == null || _masterPassword == null) {
      return;
    }

    _stopRemoteSyncTimer();
    try {
      if (choice == _ConflictChoice.local) {
        await syncService.overwriteRemoteWithLocal(localRevision: _controller!.revision);
        await _controller!.refreshRemoteStatus();
      } else if (choice == _ConflictChoice.remote) {
        final pulled = await syncService.pullRemoteToLocal();
        if (!pulled || !mounted || _masterPassword == null) {
          return;
        }
        final vault = await repository.unlock(_masterPassword!);
        final nextController = _buildController(vault: vault, password: _masterPassword!);
        _replaceController(nextController);
        await _controller!.refreshRemoteStatus();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _suspendAutoSyncForConflict = false;
      });
    } finally {
      if (mounted && !_suspendAutoSyncForConflict) {
        await _restartRemoteSyncTimer();
      }
    }
  }

  Future<void> _changeEncryptionProfile(EncryptionProfile profile) async {
    final current = _appConfig ?? await configStore.read();
    final next = current.copyWith(encryptionProfile: profile);
    await configStore.write(next);
    repository = _createRepository();
    if (!mounted) {
      _appConfig = next;
      return;
    }
    setState(() {
      _appConfig = next;
    });
  }

  VaultController _buildController({
    required DocumentVault vault,
    required String password,
  }) {
    return VaultController(
      initialVault: vault,
      onPersist: (nextVault) async {
        await repository.save(nextVault, password);
        _bundleKdfSettings = repository.currentKdfSettings;
        if (mounted) {
          setState(() {});
        }
      },
      onSyncAfterSave: (localRevision) => syncService.syncAfterLocalSave(
        localRevision: localRevision,
      ),
      onCheckRemoteStatus: (localRevision) => syncService.checkRemoteStatus(
        localRevision: localRevision,
      ),
    );
  }


  Future<void> _pushWindowTitle() async {
    final nextTitle = _windowTitle;
    if (_lastPushedWindowTitle == nextTitle) {
      return;
    }
    _lastPushedWindowTitle = nextTitle;
    try {
      await _windowChannel.invokeMethod<void>('setTitle', nextTitle);
    } catch (_) {
      // Keep UI usable even if the native window title channel is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_pushWindowTitle());
      }
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Secret Book',
      onGenerateTitle: (context) => _windowTitle,
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
                      autosaveDelaySeconds:
                          _appConfig?.autosaveDelaySeconds ?? 15,
                      selectedEncryptionProfile:
                          _appConfig?.encryptionProfile ?? EncryptionProfile.standard,
                      currentVaultKdfLabel:
                          (_bundleKdfSettings ?? (_appConfig?.encryptionProfile ?? EncryptionProfile.standard).settings)
                              .technicalLabel,
                      onChangeEncryptionProfile: _changeEncryptionProfile,
                      onLock: _lock,
                      onChangePassword: _changePassword,
                      onInstallDownloadedUpdate: _installDownloadedUpdate,
                      titleUpdateLabel: _titleUpdateLabel,
                      showTitleUpdateAction: _availableUpdate != null && _downloadedInstallerPath != null,
                    ),
    );
  }
}
