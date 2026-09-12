import 'package:flutter/material.dart';

/// Paint above opaque card backgrounds, where Material's ink is hidden.
class LampaInkWell extends StatefulWidget {
  const LampaInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.customBorder,
  });
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  @override
  State<LampaInkWell> createState() => _LampaInkWellState();
}

class _LampaInkWellState extends State<LampaInkWell> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
      border: Border.all(
        width: 3,
        color: _focused ? const Color(0xffffcc33) : Colors.transparent,
      ),
    ),
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: widget.borderRadius,
      customBorder: widget.customBorder,
      onFocusChange: (value) => setState(() => _focused = value),
      child: widget.child,
    ),
  );
}

/// Lampa / Хаттабыч UI — фильм «Хоттабыч» (2006) + старый рунет:
/// чёрный фон, CRT-зелень, синие ссылки, оранж Mail.ru, monospace.
abstract final class LampaUi {
  static const bg = Color(0xff0c1020);
  static const bgDeep = Color(0xff05070e);
  static const accent = Color(0xffff9900); // mail.ru / banner orange
  static const accentDeep = Color(0xffe07800);
  static const link = Color(0xff66b3ff); // hyperlink on dark
  static const crt = Color(0xff33ff66); // CRT / dial-up online
  static const crtDim = Color(0xff1a9944);
  static const warn = Color(0xffff4466);
  static const onSurface = Color(0xffe8f0ff);
  static const muted = Color(0x99a8b8d0);
  static const border = Color(0x6644aaff);
  static const panel = Color(0xff101828);

  static const mono = TextStyle(
    fontFamily: 'monospace',
    letterSpacing: 0.4,
    height: 1.25,
  );

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: bgDeep,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
      barrierColor: const Color(0xcc000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 2),
        ),
        title: DefaultTextStyle(
          style: mono.copyWith(
            color: accent,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          child: title,
        ),
        content: DefaultTextStyle(
          style: mono.copyWith(color: muted, fontSize: 13),
          child: content,
        ),
        actions: actions,
      ),
    );
  }

  static SnackBar snack(String message, {SnackBarAction? action}) => SnackBar(
    content: Text(
      message,
      style: mono.copyWith(color: onSurface, fontSize: 13),
    ),
    backgroundColor: bg,
    behavior: SnackBarBehavior.floating,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: border, width: 1),
    ),
    action: action,
  );
}
