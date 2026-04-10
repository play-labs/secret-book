import 'dart:io';

import 'package:dio/dio.dart';

import '../models/app_release_info.dart';
import 'app_config_store.dart';

class AppUpdateService {
  AppUpdateService({
    required AppConfigStore configStore,
    Dio? dio,
  })  : _configStore = configStore,
        _dio = dio ?? Dio();

  final AppConfigStore _configStore;
  final Dio _dio;

  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
    required int currentBuild,
  }) async {
    final config = await _configStore.read();
    final url = config.appUpdateJsonUrl.trim();
    if (url.isEmpty) {
      throw StateError('appUpdateJsonUrl is not configured.');
    }

    final response = await _dio.get<dynamic>(url);
    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      throw StateError('version.json must return a JSON object.');
    }

    final release = AppReleaseInfo.fromMap(raw);
    if (release.downloadUrl.trim().isEmpty) {
      throw StateError('version.json must include downloadUrl.');
    }

    final versionCompare = _compareVersions(release.version, currentVersion);
    final buildCompare = release.build.compareTo(currentBuild);
    final hasUpdate = versionCompare > 0 || (versionCompare == 0 && buildCompare > 0);

    return UpdateCheckResult(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      release: release,
      isUpdateAvailable: hasUpdate,
      sourceUrl: url,
    );
  }

  Future<File> downloadInstaller(
    UpdateCheckResult result, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final release = result.release;
    final updatesDir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}secret_book_updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    final parsedUrl = Uri.tryParse(release.downloadUrl);
    final fileName = (parsedUrl == null || parsedUrl.pathSegments.isEmpty || parsedUrl.pathSegments.last.trim().isEmpty)
        ? 'secret_book_setup_${release.version}.exe'
        : parsedUrl.pathSegments.last;
    final installerFile = File('${updatesDir.path}${Platform.pathSeparator}$fileName');
    if (await installerFile.exists()) {
      return installerFile;
    }

    await _dio.download(
      release.downloadUrl,
      installerFile.path,
      deleteOnError: true,
      onReceiveProgress: onReceiveProgress,
    );
    return installerFile;
  }

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map((item) => int.tryParse(item) ?? 0).toList();
    final rightParts = right.split('.').map((item) => int.tryParse(item) ?? 0).toList();
    final length = leftParts.length > rightParts.length ? leftParts.length : rightParts.length;
    while (leftParts.length < length) {
      leftParts.add(0);
    }
    while (rightParts.length < length) {
      rightParts.add(0);
    }
    for (var index = 0; index < length; index += 1) {
      final compare = leftParts[index].compareTo(rightParts[index]);
      if (compare != 0) {
        return compare;
      }
    }
    return 0;
  }
}
