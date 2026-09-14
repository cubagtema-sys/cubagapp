import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// On mobile: save CSV to temp directory then share via native share sheet.
Future<void> downloadFile(String csvData, String fileName) async {
  try {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(file.path)], subject: fileName);
  } catch (e) {
    // Silently fail — not critical
  }
}
