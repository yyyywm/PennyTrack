import 'package:flutter/material.dart';

/// 在屏幕中央显示一个自定义 Toast 提示
void showCenterToast({
  required BuildContext context,
  required String message,
  IconData? icon,
  Color backgroundColor = const Color(0xFF333333),
  Color textColor = Colors.white,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlayEntry = OverlayEntry(
    builder: (ctx) => Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: backgroundColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) Icon(icon, color: textColor, size: 22),
                    if (icon != null) const SizedBox(width: 8),
                    Text(
                      message,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Overlay.of(context).insert(overlayEntry);

  Future.delayed(duration, () {
    if (overlayEntry.mounted) {
      overlayEntry.remove();
    }
  });
}
