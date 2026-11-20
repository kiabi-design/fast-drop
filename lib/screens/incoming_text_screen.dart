import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/liquid_glass.dart';

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
    final p = GlassPalette(isWhiteTheme);
    final label = deviceLabel?.trim() ?? '';

    return LiquidBackground(
      isWhite: isWhiteTheme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(
                  child: GlassCard(
                    isWhite: isWhiteTheme,
                    radius: 999,
                    tint: p.accent,
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: Icon(Icons.phone_iphone_rounded, size: 44, color: p.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  senderName.isNotEmpty ? senderName : 'Устройство',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.fg,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                if (label.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: GlassChip(
                      label: label,
                      isWhite: isWhiteTheme,
                      mono: true,
                      onTap: null,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                Text(
                  'отправил вам сообщение:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.subtle, fontSize: 15),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  isWhite: isWhiteTheme,
                  radius: 28,
                  padding: const EdgeInsets.all(18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 110, maxHeight: 260),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          messageText,
                          style: TextStyle(color: p.fg, fontSize: 16, height: 1.45),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: 'Проверка',
                        icon: Icons.check_circle_outline_rounded,
                        isWhite: isWhiteTheme,
                        expand: true,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Сообщение получено'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassButton(
                        label: 'Копировать',
                        icon: Icons.copy_rounded,
                        isWhite: isWhiteTheme,
                        active: true,
                        expand: true,
                        onPressed: () async {
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
                    ),
                  ],
                ),
                const Spacer(flex: 3),
                Center(
                  child: GlassButton(
                    label: 'Закрыть',
                    icon: Icons.close_rounded,
                    isWhite: isWhiteTheme,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}