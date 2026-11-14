import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../services/update_service.dart';

enum UpdateStatus { notConfigured, idle, checking, upToDate, available, error }

/// Tracks whether a newer version of the app has been published.
class UpdateController extends ChangeNotifier {
  UpdateController({
    Future<UpdateInfo?> Function()? fetchLatest,
    int? currentBuild,
    bool? configured,
  })  : _fetchLatest = fetchLatest ?? const UpdateService().fetchLatest,
        currentBuild = currentBuild ?? AppBuildInfo.buildNumber,
        _status = (configured ?? AppBuildInfo.updatesConfigured)
            ? UpdateStatus.idle
            : UpdateStatus.notConfigured;

  final Future<UpdateInfo?> Function() _fetchLatest;
  final int currentBuild;

  UpdateStatus _status;
  UpdateInfo? _available;
  String? _error;
  DateTime? _lastChecked;

  UpdateStatus get status => _status;
  UpdateInfo? get available => _available;
  String? get error => _error;
  DateTime? get lastChecked => _lastChecked;
  bool get isConfigured => _status != UpdateStatus.notConfigured;
  bool get hasUpdate => _status == UpdateStatus.available;

  /// Checks for a newer release. With [silent] true, failures are only
  /// logged (used for the automatic check on start-up).
  Future<void> check({bool silent = false}) async {
    if (!isConfigured || _status == UpdateStatus.checking) return;
    final previous = _status;
    _status = UpdateStatus.checking;
    _error = null;
    notifyListeners();
    try {
      final latest = await _fetchLatest();
      _lastChecked = DateTime.now();
      if (latest != null && latest.buildNumber > currentBuild) {
        _available = latest;
        _status = UpdateStatus.available;
      } else {
        _available = null;
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      debugPrint('PennyWise update check failed: $e');
      if (silent) {
        _status = previous == UpdateStatus.available
            ? UpdateStatus.available
            : UpdateStatus.idle;
      } else {
        _status = UpdateStatus.error;
        _error = e is UpdateCheckException
            ? e.message
            : 'Could not check for updates.';
      }
    }
    notifyListeners();
  }
}
