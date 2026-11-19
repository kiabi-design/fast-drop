import 'dart:io';

import 'package:flutter/material.dart';

class TransferScreen extends StatelessWidget {
  final bool isSender;
  final bool isTransferring;
  final bool isCompleted;
  final bool isCancelled;
  final String fileName;
  final int currentIndex;
  final int totalCount;
  final double progress; // 0.0 .. 1.0
  final double speedMBps;
  final int transferredBytes;
  final int totalBytes;
  final String etaText;
  final String statusText;
  final String? savedFilePath;
  final String? savedFolderPath;
  final bool isWhiteTheme;

  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onSendMore;
  final VoidCallback? onOpenFolder;
  final void Function(String filePath)? onOpenFile;

  const TransferScreen({
    super.key,
    required this.isSender,
    required this.isTransferring,
    required this.isCompleted,
    required this.isCancelled,
    required this.fileName,
    required this.currentIndex,
    required this.totalCount,
    required this.progress,
    required this.speedMBps,
    required this.transferredBytes,
    required this.totalBytes,
    required this.etaText,
    required this.statusText,
    this.savedFilePath,
    this.savedFolderPath,
    this.isWhiteTheme = false,
    required this.onCancel,
    required this.onDone,
    required this.onSendMore,
    this.onOpenFolder,
    this.onOpenFile,
  });

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 Б';
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    double size = bytes.toDouble();
    int idx = 0;
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    return '${size.toStringAsFixed(idx == 0 ? 0 : 2)} ${units[idx]}';
  }

  @override
  Widget build(BuildContext context) {
    final bg = isWhiteTheme ? const Color(0xFFF5F5F7) : const Color(0xFF0A0A0C);
    final cardBg = isWhiteTheme ? Colors.white : const Color(0xFF16161A);
    final borderColor =
        isWhiteTheme ? Colors.black.withOpacity(0.08) : Colors.white.withOpacity(0.10);
    final fg = isWhiteTheme ? const Color(0xFF111113) : Colors.white;
    final subtle = isWhiteTheme ? const Color(0xFF6E6E73) : const Color(0xFF9E9EA6);

    final clampedProgress = progress.clamp(0.0, 1.0);
    final percentText = '${(clampedProgress * 100).toStringAsFixed(1)}%';
    final canOpenReceivedFile = !isSender &&
        savedFilePath != null &&
        savedFilePath!.isNotEmpty &&
        onOpenFile != null;

    return PopScope(
      canPop: !isTransferring,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isSender ? 'Отправка' : 'Приём',
                      style: TextStyle(
                        color: subtle,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (totalCount > 0)
                      Text(
                        '$currentIndex / $totalCount',
                        style: TextStyle(
                          color: subtle,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${speedMBps.toStringAsFixed(1)} МБ/с',
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  etaText,
                                  style: TextStyle(
                                    color: subtle,
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isTransferring)
                            IconButton(
                              onPressed: onCancel,
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Отмена',
                              color: fg,
                              style: IconButton.styleFrom(
                                backgroundColor: isWhiteTheme
                                    ? Colors.black.withOpacity(0.06)
                                    : Colors.white.withOpacity(0.10),
                              ),
                            )
                          else if (!isSender && isCompleted && onOpenFolder != null)
                            IconButton(
                              onPressed: onOpenFolder,
                              icon: const Icon(Icons.folder_open_rounded),
                              color: fg,
                              style: IconButton.styleFrom(
                                backgroundColor: isWhiteTheme
                                    ? Colors.black.withOpacity(0.06)
                                    : Colors.white.withOpacity(0.10),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: clampedProgress,
                          minHeight: 7,
                          backgroundColor: isWhiteTheme
                              ? Colors.black.withOpacity(0.08)
                              : Colors.white.withOpacity(0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(fg),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            percentText,
                            style: TextStyle(
                              color: fg,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            '${_formatSize(transferredBytes)} / ${_formatSize(totalBytes)}',
                            style: TextStyle(
                              color: subtle,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: canOpenReceivedFile
                            ? () => onOpenFile!(savedFilePath!)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fileName.isNotEmpty ? fileName : 'Файл',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    decoration: canOpenReceivedFile
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                              if (canOpenReceivedFile) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  _iconForPath(savedFilePath!),
                                  size: 20,
                                  color: subtle,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: subtle,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isSender && !isTransferring) ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: onDone,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: const Text('Готово'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSendMore,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: Text(
                            'Отправить ещё',
                            style: TextStyle(color: fg),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (!isSender && !isTransferring) ...[
                  FilledButton(
                    onPressed: onDone,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('Готово'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.apk')) return Icons.android_rounded;
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    return Icons.open_in_new_rounded;
  }
}
