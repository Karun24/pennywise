import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Build information baked in by the GitHub build
/// (`--dart-define=BUILD_NUMBER=... --dart-define=UPDATE_REPO=owner/repo`).
/// Local builds have no build number, so update checks are disabled there.
class AppBuildInfo {
  AppBuildInfo._();

  static const int buildNumber =
      int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
  static const String repository = String.fromEnvironment('UPDATE_REPO');

  static bool get updatesConfigured =>
      buildNumber > 0 && repository.contains('/');

  static String get versionLabel =>
      buildNumber > 0 ? '1.0.$buildNumber (build $buildNumber)' : 'Dev build';
}

/// A newer published version of the app.
class UpdateInfo {
  const UpdateInfo({
    required this.buildNumber,
    required this.title,
    required this.notes,
    required this.apkUrl,
    required this.pageUrl,
    this.publishedAt,
  });

  final int buildNumber;
  final String title;
  final String notes;
  final String apkUrl;
  final String pageUrl;
  final DateTime? publishedAt;
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks GitHub for the latest release. The only data sent is a normal web
/// request for public release information; no financial data is involved.
class UpdateService {
  const UpdateService({this.repository = AppBuildInfo.repository});

  final String repository;

  /// Extracts the build number from a tag such as `build-42`.
  static int? buildFromTag(String tag) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(tag);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Turns a GitHub "latest release" JSON object into [UpdateInfo].
  /// Returns null if it has no APK asset or no build number.
  static UpdateInfo? parseRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final build = buildFromTag(tag);
    if (build == null) return null;
    final assets = json['assets'];
    String? apk;
    if (assets is List) {
      for (final a in assets) {
        if (a is Map &&
            a['name'] is String &&
            (a['name'] as String).toLowerCase().endsWith('.apk') &&
            a['browser_download_url'] is String) {
          apk = a['browser_download_url'] as String;
          break;
        }
      }
    }
    if (apk == null) return null;
    final body = json['body'];
    final name = json['name'];
    return UpdateInfo(
      buildNumber: build,
      title: name is String && name.isNotEmpty ? name : 'Build $build',
      notes: body is String ? body.trim() : '',
      apkUrl: apk,
      pageUrl: json['html_url'] is String ? json['html_url'] as String : apk,
      publishedAt: json['published_at'] is String
          ? DateTime.tryParse(json['published_at'] as String)
          : null,
    );
  }

  /// Returns the latest published release, or null if none was found.
  Future<UpdateInfo?> fetchLatest() async {
    if (!repository.contains('/')) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.https(
              'api.github.com', '/repos/$repository/releases/latest'))
          .timeout(const Duration(seconds: 10));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'PennyWise-App');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        throw const UpdateCheckException(
            'No public release found. The GitHub repository must be public '
            'for update checks to work.');
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateCheckException(
            'GitHub is busy right now. Please try again later.');
      }
      if (response.statusCode != 200) {
        throw UpdateCheckException(
            'Update check failed (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return parseRelease(decoded);
    } on UpdateCheckException {
      rethrow;
    } on SocketException {
      throw const UpdateCheckException(
          'No internet connection. Please try again later.');
    } on TimeoutException {
      throw const UpdateCheckException(
          'The update check timed out. Please try again later.');
    } on HandshakeException {
      throw const UpdateCheckException('Could not connect securely to GitHub.');
    } on FormatException {
      throw const UpdateCheckException('Unexpected response from GitHub.');
    } finally {
      client.close(force: true);
    }
  }
}
