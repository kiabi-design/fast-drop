import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// Версия области перетаскивания для Linux.
/// При сборке Linux этот файл копируется поверх lib/platform/drop_area.dart.
class FileDropArea extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => onHover?.call(true),
      onDragExited: (_) => onHover?.call(false),
      onDragDone: (detail) {
        onHover?.call(false);
        final paths = detail.files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
        if (paths.isNotEmpty) onFiles(paths);
      },
      child: child,
    );
  }
}