import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where Attenlume keeps its database and media (ADR-028).
///
/// Android and iOS: the app documents folder, which is private to the app.
/// Windows: `%LOCALAPPDATA%\Samlytics\Attenlume`. The Windows documents
/// folder is shared with the user and often synced to OneDrive, so
/// recordings there would leave the device without the user asking.
Future<Directory> appDataDirectory() async {
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      return Directory(p.join(local, 'Samlytics', 'Attenlume'))
          .create(recursive: true);
    }
  }
  return getApplicationDocumentsDirectory();
}
