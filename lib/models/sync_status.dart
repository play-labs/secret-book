import 'app_config.dart';

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.state,
    required this.message,
    this.localRevision,
    this.remoteRevision,
    this.updatedAt,
  });

  final SyncState state;
  final String message;
  final int? localRevision;
  final int? remoteRevision;
  final DateTime? updatedAt;

  factory SyncStatusSnapshot.fromConfig(AppConfig config, {int? localRevision}) {
    return SyncStatusSnapshot(
      state: config.syncState,
      message: config.syncMessage ?? '就绪',
      localRevision: localRevision,
      remoteRevision: config.lastRemoteRevision,
      updatedAt: config.lastSyncAt,
    );
  }
}
