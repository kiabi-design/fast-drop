import 'dart:io';

import 'package:flutter/services.dart';

class FileActions {
  static const MethodChannel _channel = MethodChannel('fastdrop/file_actions');

  /// Открывает файл в системе: для .apk на Android запускает установщик,
  /// для фото/документов — подходящее приложение.
  static Future<bool> openFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;

    try {
      final result = await _channel.invokeMethod<bool>('openFile', {
        'path': file.path,
      });
      if (result == true) return true;
    } catch (_) {}

    // Запасной вариант для desktop/платформ без нативного канала
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', file.path]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Открывает папку, в которой сохранён файл.
  static Future<bool> openFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return false;

    try {
      final result = await _channel.invokeMethod<bool>('openFolder', {
        'path': dir.path,
      });
      if (result == true) return true;
    } catch (_) {}

    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [dir.path]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
        return true;
      }
    } catch (_) {}

    return false;
  }
}
