import '../models/document_vault.dart';
import '../models/encryption_profile.dart';
import '../serialization/bundle_serializer.dart';
import '../serialization/vault_packer.dart';
import '../services/crypto_service.dart';
import '../services/vault_file_store.dart';

abstract class VaultRepository {
  Future<DocumentVault> unlock(String password);
  Future<void> save(DocumentVault vault, String password);
  Future<String> getBundlePath();
  Future<VaultKdfSettings?> inspectBundleKdfSettings();
  int? get debugBundleBytesLength;
  VaultKdfSettings? get currentKdfSettings;
}

class LocalVaultRepository implements VaultRepository {
  LocalVaultRepository({
    required BundleSerializer serializer,
    required VaultPacker vaultPacker,
    required VaultFileStore fileStore,
    required CryptoService Function() cryptoServiceBuilder,
  })  : _serializer = serializer,
        _vaultPacker = vaultPacker,
        _fileStore = fileStore,
        _cryptoServiceBuilder = cryptoServiceBuilder;

  final BundleSerializer _serializer;
  final VaultPacker _vaultPacker;
  final VaultFileStore _fileStore;
  final CryptoService Function() _cryptoServiceBuilder;

  int? _debugBundleBytesLength;
  VaultKdfSettings? _currentKdfSettings;

  @override
  int? get debugBundleBytesLength => _debugBundleBytesLength;

  @override
  VaultKdfSettings? get currentKdfSettings => _currentKdfSettings;

  @override
  Future<String> getBundlePath() async {
    final file = await _fileStore.resolveBundleFile();
    return file.path;
  }

  @override
  Future<VaultKdfSettings?> inspectBundleKdfSettings() async {
    final bundleBytes = await _fileStore.readBundle();
    if (bundleBytes == null) {
      return null;
    }
    final envelope = _serializer.deserializeEnvelope(bundleBytes);
    final settings = VaultKdfSettings(
      memoryKiB: envelope.kdfMemory,
      iterations: envelope.kdfIterations,
      parallelism: envelope.kdfParallelism,
    );
    _currentKdfSettings = settings;
    return settings;
  }

  @override
  Future<DocumentVault> unlock(String password) async {
    _validatePassword(password);
    final bundleBytes = await _fileStore.readBundle();
    if (bundleBytes == null) {
      final seeded = DocumentVault.seeded();
      await save(seeded, password);
      return seeded;
    }

    _debugBundleBytesLength = bundleBytes.length;
    final envelope = _serializer.deserializeEnvelope(bundleBytes);
    _currentKdfSettings = VaultKdfSettings(
      memoryKiB: envelope.kdfMemory,
      iterations: envelope.kdfIterations,
      parallelism: envelope.kdfParallelism,
    );
    final clearBytes = await _cryptoServiceBuilder().decrypt(
      password: password,
      envelope: envelope,
    );
    return _vaultPacker.unpack(clearBytes);
  }

  @override
  Future<void> save(DocumentVault vault, String password) async {
    _validatePassword(password);
    final clearBytes = _vaultPacker.pack(vault);
    final cryptoService = _cryptoServiceBuilder();
    final envelope = await cryptoService.encrypt(
      password: password,
      plainBytes: clearBytes,
      revision: vault.revision,
    );
    final bundleBytes = _serializer.serializeEnvelope(envelope);
    await _fileStore.writeBundle(bundleBytes);
    _debugBundleBytesLength = bundleBytes.length;
    _currentKdfSettings = cryptoService.kdfSettings;
  }

  void _validatePassword(String password) {
    if (password.trim().isEmpty) {
      throw ArgumentError('Password cannot be empty.');
    }
  }
}
