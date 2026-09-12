import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One focus target for custom controls, including embedded Android views.
class RemoteButton extends StatefulWidget {
  const RemoteButton({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.label,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final String? label;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  bool _highlight = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.onPressed != null,
    autofocus: widget.autofocus,
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        },
      ),
    },
    onFocusChange: (focused) {
      if (focused) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Scrollable.ensureVisible(
              context,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          }
        });
      }
    },
    onShowFocusHighlight: (value) => setState(() => _highlight = value),
    child: Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.label,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: _highlight ? const Color(0xffffcc33) : Colors.transparent,
            width: 4,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ExcludeFocus(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}
