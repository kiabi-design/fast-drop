import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Область, в которую можно перетащить файлы.
/// Эта версия используется на iPhone и Android: на iPhone файлы приходят
/// из нативного кода (ios_patch/AppDelegate.swift), на Android ничего не делает.
/// Для Linux при сборке подставляется версия из linux_patch/drop_area_linux.dart.
class FileDropArea extends StatefulWidget {
  final Widget child;
  final ValueChanged<List<String>> onFiles;
  final ValueChanged<bool>? onHover;

  const FileDropArea({
    super.key,
    required this.child,
    required this.onFiles,
    this.onHover,
  });

  @override
  State<FileDropArea> createState() => _FileDropAreaState();
}

class _FileDropAreaState extends State<FileDropArea> {
  static const MethodChannel _channel = MethodChannel('fastdrop/drop');

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  @override
  void dispose() {
    if (Platform.isIOS) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'dropped') {
      final raw = call.arguments;
      if (raw is List) {
        final list = raw.map((e) => e.toString()).toList();
        if (list.isNotEmpty) widget.onFiles(list);
      }
    } else if (call.method == 'hover') {
      widget.onHover?.call(call.arguments == true);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}