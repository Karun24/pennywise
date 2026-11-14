import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages bill and receipt photo attachments stored locally on the device.
class ReceiptService {
  const ReceiptService();

  /// Prompts the user to pick an image (receipt/bill/invoice) and saves a copy
  /// in the app's local receipts directory. Returns the absolute file path,
  /// or null if the user cancelled.
  Future<String?> pickAndSaveReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;

    final source = File(path);
    if (!await source.exists()) return null;

    final docDir = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory(p.join(docDir.path, 'receipts'));
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }

    final ext = p.extension(path);
    final filename =
        'receipt_${DateTime.now().millisecondsSinceEpoch}${ext.isNotEmpty ? ext : '.jpg'}';
    final targetPath = p.join(receiptsDir.path, filename);

    await source.copy(targetPath);
    return targetPath;
  }

  /// Safely deletes a stored receipt file from local storage.
  Future<void> deleteReceipt(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}
