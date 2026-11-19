import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IncomingTextScreen extends StatelessWidget {
  final String senderName;
  final String? deviceLabel;
  final String messageText;
  final bool isWhiteTheme;

  const IncomingTextScreen({
    super.key,
    required this.senderName,
    this.deviceLabel,
    required this.messageText,
    this.isWhiteTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isWhiteTheme ? const Color(0xFFF5F5F7) : const Color(0xFF0A0A0C);
    final cardBg = isWhiteTheme ? Colors.white : const Color(0xFF1A1A1E);
    final borderColor =
        isWhiteTheme ? Colors.black.withOpacity(0.08) : Colors.white.withOpacity(0.10);
    final fg = isWhiteTheme ? const Color(0xFF111113) : Colors.white;
    final subtle = isWhiteTheme ? const Color(0xFF6E6E73) : const Color(0xFF9E9EA6);
    final chipBg = isWhiteTheme ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.10);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 56,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: fg.withOpacity(0.85), width: 2.2),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: fg.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                senderName.isNotEmpty ? senderName : 'Устройство',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              if (deviceLabel != null && deviceLabel!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    deviceLabel!.trim(),
                    style: TextStyle(
                      color: fg.withOpacity(0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Text(
                'отправил вам сообщение:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: subtle,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 120, maxHeight: 260),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    messageText,
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ActionPill(
                    label: 'Проверка',
                    icon: Icons.check_circle_outline_rounded,
                    bg: cardBg,
                    borderColor: borderColor,
                    fg: fg,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Сообщение получено'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  _ActionPill(
                    label: 'Копировать',
                    icon: Icons.copy_rounded,
                    bg: cardBg,
                    borderColor: borderColor,
                    fg: fg,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: messageText));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Скопировано в буфер обмена'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const Spacer(flex: 3),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: fg.withOpacity(0.85), size: 20),
                label: Text(
                  'Закрыть',
                  style: TextStyle(
                    color: fg.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color borderColor;
  final Color fg;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.icon,
    required this.bg,
    required this.borderColor,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
