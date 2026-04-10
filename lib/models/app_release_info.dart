class AppReleaseInfo {
  const AppReleaseInfo({
    required this.schemaVersion,
    required this.app,
    required this.platform,
    required this.version,
    required this.build,
    required this.publishedAt,
    required this.mandatory,
    required this.downloadUrl,
    required this.notes,
  });

  final int schemaVersion;
  final String app;
  final String platform;
  final String version;
  final int build;
  final DateTime? publishedAt;
  final bool mandatory;
  final String downloadUrl;
  final List<String> notes;

  factory AppReleaseInfo.fromMap(Map<String, dynamic> map) {
    final rawNotes = map['notes'];
    final notes = rawNotes is List
        ? rawNotes.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList()
        : rawNotes is String && rawNotes.trim().isNotEmpty
            ? <String>[rawNotes]
            : const <String>[];

    return AppReleaseInfo(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      app: map['app'] as String? ?? 'secret_book',
      platform: map['platform'] as String? ?? 'windows',
      version: map['version'] as String? ?? '0.0.0',
      build: (map['build'] as num?)?.toInt() ?? 0,
      publishedAt: map['publishedAt'] == null ? null : DateTime.tryParse(map['publishedAt'] as String),
      mandatory: map['mandatory'] as bool? ?? false,
      downloadUrl: map['downloadUrl'] as String? ?? '',
      notes: notes,
    );
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    required this.release,
    required this.isUpdateAvailable,
    required this.sourceUrl,
  });

  final String currentVersion;
  final int currentBuild;
  final AppReleaseInfo release;
  final bool isUpdateAvailable;
  final String sourceUrl;
}
