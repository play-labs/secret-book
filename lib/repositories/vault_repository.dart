import '../models/document_vault.dart';
import '../serialization/bundle_serializer.dart';
import '../serialization/vault_packer.dart';
import '../services/crypto_service.dart';
import '../services/vault_file_store.dart';

abstract class VaultRepository {
  Future<DocumentVault> unlock(String password);
  Future<void> save(DocumentVault vault, String password);
  Future<String> getBundlePath();
  int? get debugBundleBytesLength;
}

class LocalVaultRepository implements VaultRepository {
  LocalVaultRepository({
    required BundleSerializer serializer,
    required VaultPacker vaultPacker,
    required VaultFileStore fileStore,
    required CryptoService cryptoService,
  })  : _serializer = serializer,
        _vaultPacker = vaultPacker,
        _fileStore = fileStore,
        _cryptoService = cryptoService;

  final BundleSerializer _serializer;
  final VaultPacker _vaultPacker;
  final VaultFileStore _fileStore;
  final CryptoService _cryptoService;

  int? _debugBundleBytesLength;

  @override
  int? get debugBundleBytesLength => _debugBundleBytesLength;

  @override
  Future<String> getBundlePath() async {
    final file = await _fileStore.resolveBundleFile();
    return file.path;
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
    final clearBytes = await _cryptoService.decrypt(
      password: password,
      envelope: envelope,
    );
    return _vaultPacker.unpack(clearBytes);
  }

  @override
  Future<void> save(DocumentVault vault, String password) async {
    _validatePassword(password);
    final clearBytes = _vaultPacker.pack(vault);
    final envelope = await _cryptoService.encrypt(
      password: password,
      plainBytes: clearBytes,
      revision: vault.revision,
    );
    final bundleBytes = _serializer.serializeEnvelope(envelope);
    await _fileStore.writeBundle(bundleBytes);
    _debugBundleBytesLength = bundleBytes.length;
  }

  void _validatePassword(String password) {
    if (password.trim().isEmpty) {
      throw ArgumentError('Password cannot be empty.');
    }
  }
}
