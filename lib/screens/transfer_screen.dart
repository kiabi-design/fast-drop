import 'package:flutter/material.dart';

import '../widgets/liquid_glass.dart';

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
  final double? maxSpeedMBps;
  final double? avgSpeedMBps;
  final double? minSpeedMBps;

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
    this.maxSpeedMBps,
    this.avgSpeedMBps,
    this.minSpeedMBps,
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

  Widget _statCell(String label, double? value, GlassPalette p) {
    return GlassCard(
      isWhite: isWhiteTheme,
      radius: 18,
      blur: 0,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: p.subtle, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value == null ? '—' : value.toStringAsFixed(1),
            style: TextStyle(color: p.fg, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            'МБ/с',
            style: TextStyle(color: p.subtle, fontSize: 10),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhiteTheme);

    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final percentText = '${(clamped * 100).toStringAsFixed(1)}%';
    final isError = statusText.startsWith('Ошибка');
    final isDone = !isTransferring && isCompleted && !isError;
    final canOpenReceivedFile = !isSender &&
        isDone &&
        savedFilePath != null &&
        savedFilePath!.isNotEmpty &&
        onOpenFile != null;
    final statusColor = isError ? p.danger : (isDone ? p.success : p.subtle);
    final barColor = isError ? p.danger : (isDone ? p.success : p.accent);

    return PopScope(
      canPop: !isTransferring,
      child: LiquidBackground(
        isWhite: isWhiteTheme,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GlassChip(
                        label: isSender ? 'Отправка' : 'Приём',
                        icon: isSender ? Icons.upload_rounded : Icons.download_rounded,
                        isWhite: isWhiteTheme,
                        selected: true,
                        onTap: null,
                      ),
                      if (totalCount > 0)
                        GlassChip(
                          label: '$currentIndex / $totalCount',
                          isWhite: isWhiteTheme,
                          mono: true,
                          onTap: null,
                        ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: GlassCard(
                          isWhite: isWhiteTheme,
                          radius: 36,
                          padding: const EdgeInsets.all(24),
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
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text(
                                              speedMBps.toStringAsFixed(1),
                                              style: TextStyle(
                                                color: p.fg,
                                                fontSize: 52,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -1.5,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'МБ/с',
                                              style: TextStyle(
                                                color: p.subtle,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          etaText,
                                          style: TextStyle(
                                            color: p.subtle,
                                            fontSize: 15,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isTransferring)
                                    GlassIconButton(
                                      icon: Icons.close_rounded,
                                      isWhite: isWhiteTheme,
                                      danger: true,
                                      onTap: onCancel,
                                    )
                                  else ...[
                                    if (isDone)
                                      Icon(Icons.check_circle_rounded, color: p.success, size: 36),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 22),
                              GlassProgressBar(
                                value: clamped,
                                isWhite: isWhiteTheme,
                                color: barColor,
                                height: 12,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    percentText,
                                    style: TextStyle(
                                      color: p.fg,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  Text(
                                    '${_formatSize(transferredBytes)} / ${_formatSize(totalBytes)}',
                                    style: TextStyle(
                                      color: p.subtle,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: canOpenReceivedFile ? () => onOpenFile!(savedFilePath!) : null,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fileName.isNotEmpty ? fileName : 'Файл',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: p.fg,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          decoration: canOpenReceivedFile
                                              ? TextDecoration.underline
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    if (canOpenReceivedFile && onOpenFolder != null) ...[
                                      const SizedBox(width: 10),
                                      GlassIconButton(
                                        icon: Icons.folder_rounded,
                                        isWhite: isWhiteTheme,
                                        size: 42,
                                        onTap: onOpenFolder,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 14,
                                ),
                              ),
                              if (isDone && avgSpeedMBps != null) ...[
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(child: _statCell('Средняя', avgSpeedMBps, p)),
                                    const SizedBox(width: 10),
                                    Expanded(child: _statCell('Макс', maxSpeedMBps, p)),
                                    const SizedBox(width: 10),
                                    Expanded(child: _statCell('Мин', minSpeedMBps, p)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isSender && !isTransferring) ...[
                    Row(
                      children: [
                        Expanded(
                          child: GlassButton(
                            label: 'Готово',
                            isWhite: isWhiteTheme,
                            active: true,
                            expand: true,
                            onPressed: onDone,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassButton(
                            label: 'Отправить ещё',
                            isWhite: isWhiteTheme,
                            expand: true,
                            onPressed: onSendMore,
                          ),
                        ),
                      ],
                    ),
                  ] else if (!isSender && !isTransferring) ...[
                    GlassButton(
                      label: 'Готово',
                      isWhite: isWhiteTheme,
                      active: true,
                      expand: true,
                      onPressed: onDone,
                    ),
                  ] else ...[
                    GlassButton(
                      label: 'Отмена',
                      icon: Icons.close_rounded,
                      isWhite: isWhiteTheme,
                      danger: true,
                      expand: true,
                      onPressed: onCancel,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}