import 'package:flutter/material.dart';

/// Shared Lampa / Хаттабыч surface colors for dialogs & snackbars.
abstract final class LampaUi {
  static const bg = Color(0xff1a1208);
  static const bgDeep = Color(0xff0a0603);
  static const accent = Color(0xffffab40);
  static const accentDeep = Color(0xffff8f00);
  static const onSurface = Color(0xe6ffffff);
  static const muted = Color(0x99ffffff);
  static const border = Color(0x33ffffff);

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: accentDeep,
        foregroundColor: bgDeep,
      );

  static Future<T?> dialog<T>({
    required BuildContext context,
    required Widget title,
    required Widget content,
    required List<Widget> actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: border),
        ),
        title: DefaultTextStyle(
          style: const TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          child: title,
        ),
        content: DefaultTextStyle(
          style: const TextStyle(color: muted, fontSize: 14, height: 1.35),
          child: content,
        ),
        actions: actions,
      ),
    );
  }

  static SnackBar snack(String message, {SnackBarAction? action}) => SnackBar(
        content: Text(message, style: const TextStyle(color: onSurface)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border),
        ),
        action: action,
      );
}
