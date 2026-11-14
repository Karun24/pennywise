import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/backup_data.dart';
import 'backup_service.dart';
import 'csv_import_service.dart';

/// A file chosen for import: a full JSON backup or a CSV export.
class ImportFile {
  const ImportFile.backup(BackupData this.backup) : csv = null;
  const ImportFile.csv(List<CsvTransaction> this.csv) : backup = null;

  final BackupData? backup;
  final List<CsvTransaction>? csv;
}

/// Platform side of backups: writes files and hands them to the system
/// share sheet (Save to Files / Drive / email - the user chooses), and reads
/// a backup chosen with the system file picker. Neither needs storage
/// permissions on Android or iOS.
class BackupFileService {
  const BackupFileService();

  static String _stamp(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';

  Future<File> _writeTemp(String name, String contents) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(contents, flush: true);
    return file;
  }

  Rect? _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  Future<void> shareBackup(BuildContext context, BackupData data) async {
    final origin = _origin(context);
    final file = await _writeTemp(
        'pennywise-backup-${_stamp(DateTime.now())}.json',
        BackupService.encode(data));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'PennyWise backup',
      sharePositionOrigin: origin,
    ));
  }

  Future<void> shareCsv(BuildContext context, String csv) async {
    final origin = _origin(context);
    final file = await _writeTemp(
        'pennywise-transactions-${_stamp(DateTime.now())}.csv', csv);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'PennyWise transactions',
      sharePositionOrigin: origin,
    ));
  }

  /// Lets the user pick a JSON backup or a CSV export. Returns null if they
  /// cancel. Throws [BackupFormatException] if the file can't be used.
  Future<ImportFile?> pickImportFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return null;
    final size = picked.lengthSync() ?? await picked.length();
    if (size != null && size > 50 * 1024 * 1024) {
      throw const BackupFormatException('That file is too large.');
    }
    final List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      throw const BackupFormatException('Could not read that file.');
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const BackupFormatException('This is not a PennyWise backup file.');
    }
    if (text.trimLeft().startsWith('{')) {
      return ImportFile.backup(BackupService.decode(text));
    }
    if (CsvImportService.looksLikeCsv(text)) {
      return ImportFile.csv(CsvImportService.parse(text));
    }
    throw const BackupFormatException(
        'This is not a PennyWise backup (.json) or CSV export (.csv).');
  }
}
