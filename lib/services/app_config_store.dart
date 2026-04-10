import 'dart:convert';

import '../models/app_config.dart';
import 'vault_file_store.dart';

class AppConfigStore {
  AppConfigStore({
    required VaultFileStore fileStore,
  }) : _fileStore = fileStore;

  final VaultFileStore _fileStore;

  Future<AppConfig> read() async {
    final file = await _fileStore.resolveConfigFile();
    if (!await file.exists()) {
      final config = AppConfig.initial();
      await write(config);
      return config;
    }
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AppConfig.fromMap(json);
  }

  Future<void> write(AppConfig config) async {
    final file = await _fileStore.resolveConfigFile();
    await file.writeAsString(
      jsonEncode(config.toMap()),
      flush: true,
    );
  }
}
