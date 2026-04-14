import 'encryption_profile.dart';

enum SyncProvider {
  aliyunOss,
  mockOss,
}

enum StsHttpMethod {
  get,
  post,
}

enum SyncState {
  idle,
  syncing,
  synced,
  checking,
  conflict,
  error,
  disabled,
}

class AppConfig {
  const AppConfig({
    required this.syncProvider,
    required this.encryptionProfile,
    required this.ossEndpoint,
    required this.ossBucketName,
    required this.ossObjectKey,
    required this.stsApiUrl,
    required this.stsHttpMethod,
    required this.stsHeadersJson,
    required this.stsBodyJson,
    required this.appUpdateJsonUrl,
    required this.autosaveDelaySeconds,
    required this.remoteSyncIntervalSeconds,
    required this.lastSyncedRevision,
    required this.lastRemoteRevision,
    required this.lastRemoteModifiedAt,
    required this.lastSyncAt,
    required this.syncState,
    required this.syncMessage,
  });

  final SyncProvider syncProvider;
  final EncryptionProfile encryptionProfile;
  final String ossEndpoint;
  final String ossBucketName;
  final String ossObjectKey;
  final String stsApiUrl;
  final StsHttpMethod stsHttpMethod;
  final String stsHeadersJson;
  final String stsBodyJson;
  final String appUpdateJsonUrl;
  final int autosaveDelaySeconds;
  final int remoteSyncIntervalSeconds;
  final int? lastSyncedRevision;
  final int? lastRemoteRevision;
  final DateTime? lastRemoteModifiedAt;
  final DateTime? lastSyncAt;
  final SyncState syncState;
  final String? syncMessage;

  factory AppConfig.initial() {
    return const AppConfig(
      syncProvider: SyncProvider.aliyunOss,
      encryptionProfile: EncryptionProfile.standard,
      ossEndpoint: 'oss-cn-example.aliyuncs.com',
      ossBucketName: 'example-secret-book',
      ossObjectKey: 'vault.bundle',
      stsApiUrl: 'https://example.com/api/v1/sts/assume-role',
      stsHttpMethod: StsHttpMethod.post,
      stsHeadersJson:
          '{"Content-Type":"application/json","X-Auth-Token":"replace-me"}',
      stsBodyJson:
          '{"role_session_name":"example-session","duration_seconds":1800}',
      appUpdateJsonUrl: 'https://example.com/secret-book/version.json',
      autosaveDelaySeconds: 15,
      remoteSyncIntervalSeconds: 60,
      lastSyncedRevision: null,
      lastRemoteRevision: null,
      lastRemoteModifiedAt: null,
      lastSyncAt: null,
      syncState: SyncState.idle,
      syncMessage: 'Ready',
    );
  }

  AppConfig copyWith({
    SyncProvider? syncProvider,
    EncryptionProfile? encryptionProfile,
    String? ossEndpoint,
    String? ossBucketName,
    String? ossObjectKey,
    String? stsApiUrl,
    StsHttpMethod? stsHttpMethod,
    String? stsHeadersJson,
    String? stsBodyJson,
    String? appUpdateJsonUrl,
    int? autosaveDelaySeconds,
    int? remoteSyncIntervalSeconds,
    int? lastSyncedRevision,
    bool clearLastSyncedRevision = false,
    int? lastRemoteRevision,
    bool clearLastRemoteRevision = false,
    DateTime? lastRemoteModifiedAt,
    bool clearLastRemoteModifiedAt = false,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    SyncState? syncState,
    String? syncMessage,
  }) {
    return AppConfig(
      syncProvider: syncProvider ?? this.syncProvider,
      encryptionProfile: encryptionProfile ?? this.encryptionProfile,
      ossEndpoint: ossEndpoint ?? this.ossEndpoint,
      ossBucketName: ossBucketName ?? this.ossBucketName,
      ossObjectKey: ossObjectKey ?? this.ossObjectKey,
      stsApiUrl: stsApiUrl ?? this.stsApiUrl,
      stsHttpMethod: stsHttpMethod ?? this.stsHttpMethod,
      stsHeadersJson: stsHeadersJson ?? this.stsHeadersJson,
      stsBodyJson: stsBodyJson ?? this.stsBodyJson,
      appUpdateJsonUrl: appUpdateJsonUrl ?? this.appUpdateJsonUrl,
      autosaveDelaySeconds: autosaveDelaySeconds ?? this.autosaveDelaySeconds,
      remoteSyncIntervalSeconds:
          remoteSyncIntervalSeconds ?? this.remoteSyncIntervalSeconds,
      lastSyncedRevision: clearLastSyncedRevision
          ? null
          : lastSyncedRevision ?? this.lastSyncedRevision,
      lastRemoteRevision: clearLastRemoteRevision
          ? null
          : lastRemoteRevision ?? this.lastRemoteRevision,
      lastRemoteModifiedAt: clearLastRemoteModifiedAt
          ? null
          : lastRemoteModifiedAt ?? this.lastRemoteModifiedAt,
      lastSyncAt: clearLastSyncAt ? null : lastSyncAt ?? this.lastSyncAt,
      syncState: syncState ?? this.syncState,
      syncMessage: syncMessage ?? this.syncMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'syncProvider': syncProvider.name,
      'encryptionProfile': encryptionProfile.name,
      'ossEndpoint': ossEndpoint,
      'ossBucketName': ossBucketName,
      'ossObjectKey': ossObjectKey,
      'stsApiUrl': stsApiUrl,
      'stsHttpMethod': stsHttpMethod.name,
      'stsHeadersJson': stsHeadersJson,
      'stsBodyJson': stsBodyJson,
      'appUpdateJsonUrl': appUpdateJsonUrl,
      'autosaveDelaySeconds': autosaveDelaySeconds,
      'remoteSyncIntervalSeconds': remoteSyncIntervalSeconds,
      'lastSyncedRevision': lastSyncedRevision,
      'lastRemoteRevision': lastRemoteRevision,
      'lastRemoteModifiedAt': lastRemoteModifiedAt?.toIso8601String(),
      'lastSyncAt': lastSyncAt?.toIso8601String(),
      'syncState': syncState.name,
      'syncMessage': syncMessage,
    };
  }

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    final rawDelay = map['autosaveDelaySeconds'];
    final parsedDelay = rawDelay is int
        ? rawDelay
        : rawDelay is String
            ? int.tryParse(rawDelay)
            : null;
    final rawSyncInterval = map['remoteSyncIntervalSeconds'];
    final parsedSyncInterval = rawSyncInterval is int
        ? rawSyncInterval
        : rawSyncInterval is String
            ? int.tryParse(rawSyncInterval)
            : null;
    final rawEncryptionProfile = map['encryptionProfile'] as String?;

    return AppConfig(
      syncProvider: SyncProvider.values.byName(
        map['syncProvider'] as String? ?? SyncProvider.aliyunOss.name,
      ),
      encryptionProfile: rawEncryptionProfile == null || rawEncryptionProfile.isEmpty
          ? EncryptionProfile.standard
          : EncryptionProfile.values.byName(rawEncryptionProfile),
      ossEndpoint:
          map['ossEndpoint'] as String? ?? 'oss-cn-example.aliyuncs.com',
      ossBucketName: map['ossBucketName'] as String? ?? 'example-secret-book',
      ossObjectKey: map['ossObjectKey'] as String? ?? 'vault.bundle',
      stsApiUrl: map['stsApiUrl'] as String? ??
          'https://example.com/api/v1/sts/assume-role',
      stsHttpMethod: StsHttpMethod.values.byName(
        map['stsHttpMethod'] as String? ?? StsHttpMethod.post.name,
      ),
      stsHeadersJson: map['stsHeadersJson'] as String? ??
          '{"Content-Type":"application/json","X-Auth-Token":"replace-me"}',
      stsBodyJson: map['stsBodyJson'] as String? ??
          '{"role_session_name":"example-session","duration_seconds":1800}',
      appUpdateJsonUrl: ((map['appUpdateJsonUrl'] as String?)?.trim().isNotEmpty ?? false)
          ? (map['appUpdateJsonUrl'] as String).trim()
          : 'https://example.com/secret-book/version.json',
      autosaveDelaySeconds:
          parsedDelay == null || parsedDelay < 1 ? 15 : parsedDelay,
      remoteSyncIntervalSeconds:
          parsedSyncInterval == null || parsedSyncInterval < 5
              ? 60
              : parsedSyncInterval,
      lastSyncedRevision: map['lastSyncedRevision'] as int?,
      lastRemoteRevision: map['lastRemoteRevision'] as int?,
      lastRemoteModifiedAt: map['lastRemoteModifiedAt'] == null
          ? null
          : DateTime.parse(map['lastRemoteModifiedAt'] as String),
      lastSyncAt: map['lastSyncAt'] == null
          ? null
          : DateTime.parse(map['lastSyncAt'] as String),
      syncState: SyncState.values.byName(
        map['syncState'] as String? ?? SyncState.idle.name,
      ),
      syncMessage: map['syncMessage'] as String? ?? 'Ready',
    );
  }
}
