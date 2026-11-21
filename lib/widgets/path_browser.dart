import 'dart:io';

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

enum PathPickMode { files, folder }

/// Встроенный выбор файлов и папок (нужен на Linux, где системные окна
/// выбора зависят от zenity/kdialog и часто не открываются).
Future<List<String>?> showPathBrowser(
  BuildContext context, {
  required PathPickMode mode,
  required bool isWhite,
  String? initialDir,
}) {
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute<List<String>>(
      builder: (_) => PathBrowserPage(
        mode: mode,
        isWhite: isWhite,
        initialDir: initialDir,
      ),
    ),
  );
}

class PathBrowserPage extends StatefulWidget {
  final PathPickMode mode;
  final bool isWhite;
  final String? initialDir;

  const PathBrowserPage({
    super.key,
    required this.mode,
    required this.isWhite,
    this.initialDir,
  });

  @override
  State<PathBrowserPage> createState() => _PathBrowserPageState();
}

class _PathBrowserPageState extends State<PathBrowserPage> {
  late Directory _dir;
  List<FileSystemEntity> _entries = [];
  final Set<String> _selected = {};
  String? _error;
  bool _showHidden = false;
  bool _loading = false;

  String get _home => Platform.environment['HOME'] ?? '/';

  @override
  void initState() {
    super.initState();
    final start = widget.initialDir;
    if (start != null && start.isNotEmpty && Directory(start).existsSync()) {
      _dir = Directory(start);
    } else {
      _dir = Directory(_home);
    }
    _load(_dir);
  }

  String _name(FileSystemEntity e) {
    final parts = e.path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? e.path : parts.last;
  }

  bool _isDir(FileSystemEntity e) {
    if (e is Directory) return true;
    if (e is Link) return FileSystemEntity.isDirectorySync(e.path);
    return false;
  }

  Future<void> _load(Directory dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await dir.list(followLinks: false).toList();
      list.sort((a, b) {
        final ad = _isDir(a);
        final bd = _isDir(b);
        if (ad != bd) return ad ? -1 : 1;
        return _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _dir = dir;
        _entries = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Нет доступа к этой папке';
        _loading = false;
      });
    }
  }

  void _goUp() {
    final parent = _dir.parent;
    if (parent.path != _dir.path) {
      _load(parent);
    }
  }

  List<FileSystemEntity> get _visible {
    if (_showHidden) return _entries;
    return _entries.where((e) => !_name(e).startsWith('.')).toList();
  }

  List<MapEntry<String, String>> _shortcuts() {
    final home = _home;
    final candidates = <MapEntry<String, String>>[
      MapEntry('Домой', home),
      MapEntry('Загрузки', '$home/Downloads'),
      MapEntry('Загрузки', '$home/Загрузки'),
      MapEntry('Рабочий стол', '$home/Desktop'),
      MapEntry('Рабочий стол', '$home/Рабочий стол'),
      MapEntry('Документы', '$home/Documents'),
      MapEntry('Документы', '$home/Документы'),
      MapEntry('Картинки', '$home/Pictures'),
      MapEntry('Картинки', '$home/Изображения'),
      const MapEntry('Корень', '/'),
    ];
    final result = <MapEntry<String, String>>[];
    final seen = <String>{};
    for (final c in candidates) {
      if (seen.contains(c.key)) continue;
      if (Directory(c.value).existsSync()) {
        seen.add(c.key);
        result.add(c);
      }
    }
    return result;
  }

  Widget _row(FileSystemEntity e, GlassPalette p) {
    final isDir = _isDir(e);
    final name = _name(e);
    final selected = _selected.contains(e.path);
    final enabled = isDir || widget.mode == PathPickMode.files;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !enabled
          ? null
          : () {
              if (isDir) {
                _load(Directory(e.path));
              } else {
                setState(() {
                  if (selected) {
                    _selected.remove(e.path);
                  } else {
                    _selected.add(e.path);
                  }
                });
              }
            },
      child: Container(
        color: selected ? p.accent.withOpacity(0.16) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
              size: 22,
              color: isDir ? p.accent : p.fg.withOpacity(enabled ? 0.85 : 0.35),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? p.fg : p.subtle,
                  fontSize: 14,
                  fontWeight: isDir ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 20, color: p.accent)
            else if (isDir)
              Icon(Icons.chevron_right_rounded, size: 20, color: p.subtle),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWhite = widget.isWhite;
    final p = GlassPalette(isWhite);
    final files = widget.mode == PathPickMode.files;
    final visible = _visible;

    return LiquidBackground(
      isWhite: isWhite,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.close_rounded,
                      isWhite: isWhite,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        files ? 'Выберите файлы' : 'Выберите папку',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    GlassIconButton(
                      icon: Icons.arrow_upward_rounded,
                      isWhite: isWhite,
                      onTap: _goUp,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GlassCard(
                  isWhite: isWhite,
                  radius: 20,
                  blur: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    _dir.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.fg,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final s in _shortcuts()) ...[
                        GlassChip(
                          label: s.key,
                          isWhite: isWhite,
                          onTap: () => _load(Directory(s.value)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GlassChip(
                        label: 'Скрытые',
                        isWhite: isWhite,
                        selected: _showHidden,
                        onTap: () => setState(() => _showHidden = !_showHidden),
                      ),
                      if (files) ...[
                        const SizedBox(width: 8),
                        GlassChip(
                          label: 'Все файлы',
                          isWhite: isWhite,
                          onTap: () {
                            setState(() {
                              for (final e in visible) {
                                if (!_isDir(e)) _selected.add(e.path);
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GlassCard(
                    isWhite: isWhite,
                    radius: 24,
                    blur: 12,
                    padding: EdgeInsets.zero,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : (_error != null
                            ? Center(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: p.danger, fontSize: 14),
                                ),
                              )
                            : (visible.isEmpty
                                ? Center(
                                    child: Text(
                                      'Папка пуста',
                                      style: TextStyle(color: p.subtle, fontSize: 14),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: visible.length,
                                    itemBuilder: (context, i) => _row(visible[i], p),
                                  ))),
                  ),
                ),
                const SizedBox(height: 12),
                if (files)
                  GlassButton(
                    label: _selected.isEmpty ? 'Выберите файлы' : 'Выбрать (${_selected.length})',
                    icon: Icons.check_rounded,
                    isWhite: isWhite,
                    active: _selected.isNotEmpty,
                    expand: true,
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selected.toList()),
                  )
                else
                  GlassButton(
                    label: 'Выбрать эту папку',
                    icon: Icons.check_rounded,
                    isWhite: isWhite,
                    active: true,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(<String>[_dir.path]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}