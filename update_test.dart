import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/services/update_service.dart';
import 'package:pennywise/state/update_controller.dart';

Map<String, dynamic> _release(String tag, {bool withApk = true}) => {
      'tag_name': tag,
      'name': 'PennyWise 1.0.12',
      'body': 'Added update checks',
      'html_url': 'https://github.com/me/pennywise/releases/tag/$tag',
      'published_at': '2026-11-06T10:00:00Z',
      'assets': [
        if (withApk)
          {
            'name': 'PennyWise.apk',
            'browser_download_url':
                'https://github.com/me/pennywise/releases/download/$tag/PennyWise.apk',
          },
      ],
    };

UpdateInfo _info(int build) => UpdateInfo(
      buildNumber: build,
      title: 'b$build',
      notes: '',
      apkUrl: 'https://example.com/a.apk',
      pageUrl: 'https://example.com',
    );

void main() {
  group('UpdateService', () {
    test('reads the build number from the tag', () {
      expect(UpdateService.buildFromTag('build-42'), 42);
      expect(UpdateService.buildFromTag('v1.0.7'), 7);
      expect(UpdateService.buildFromTag('latest'), isNull);
    });

    test('parses a GitHub release', () {
      final info = UpdateService.parseRelease(_release('build-12'))!;
      expect(info.buildNumber, 12);
      expect(info.apkUrl, endsWith('/PennyWise.apk'));
      expect(info.notes, 'Added update checks');
      expect(info.publishedAt, DateTime.utc(2026, 11, 6, 10));
    });

    test('ignores releases without an APK', () {
      expect(UpdateService.parseRelease(_release('build-12', withApk: false)),
          isNull);
    });
  });

  group('UpdateController', () {
    test('reports an update only when the build is newer', () async {
      final c = UpdateController(
          fetchLatest: () async => _info(12), currentBuild: 10, configured: true);
      await c.check();
      expect(c.status, UpdateStatus.available);
      expect(c.available?.buildNumber, 12);

      final same = UpdateController(
          fetchLatest: () async => _info(10), currentBuild: 10, configured: true);
      await same.check();
      expect(same.status, UpdateStatus.upToDate);
      expect(same.hasUpdate, isFalse);
    });

    test('errors are shown for manual checks and hidden for silent ones',
        () async {
      Future<UpdateInfo?> fail() async =>
          throw const UpdateCheckException('offline');
      final manual =
          UpdateController(fetchLatest: fail, currentBuild: 1, configured: true);
      await manual.check();
      expect(manual.status, UpdateStatus.error);
      expect(manual.error, 'offline');

      final silent =
          UpdateController(fetchLatest: fail, currentBuild: 1, configured: true);
      await silent.check(silent: true);
      expect(silent.status, UpdateStatus.idle);
    });

    test('does nothing when the build is not from GitHub', () async {
      var called = false;
      final c = UpdateController(
        fetchLatest: () async {
          called = true;
          return null;
        },
        configured: false,
      );
      await c.check();
      expect(called, isFalse);
      expect(c.status, UpdateStatus.notConfigured);
    });
  });
}
