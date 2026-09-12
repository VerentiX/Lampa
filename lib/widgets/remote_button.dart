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
    this.focusableWhenDisabled = false,
    this.circularFocus = false,
    this.showFocusHighlight = true,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final String? label;
  final bool focusableWhenDisabled;
  final bool circularFocus;
  final bool showFocusHighlight;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'remote-button');
  bool _focused = false;

  bool get _canFocus =>
      widget.onPressed != null || widget.focusableWhenDisabled;

  @override
  void initState() {
    super.initState();
    _requestInitialFocus();
  }

  @override
  void didUpdateWidget(covariant RemoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasFocusable =
        oldWidget.onPressed != null || oldWidget.focusableWhenDisabled;
    if (widget.autofocus && !wasFocusable && _canFocus) {
      _requestInitialFocus();
    }
  }

  void _requestInitialFocus() {
    if (!widget.autofocus || !_canFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _canFocus && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: _focusNode,
    enabled: _canFocus,
    autofocus: widget.autofocus,
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
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
      if (_focused != focused) setState(() => _focused = focused);
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
    child: Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: widget.circularFocus ? BoxShape.circle : BoxShape.rectangle,
          border: Border.all(
            color: _focused && widget.showFocusHighlight
                ? (widget.circularFocus
                      ? const Color(0xff66b3ff)
                      : const Color(0xffffb020))
                : Colors.transparent,
            width: 2,
          ),
          borderRadius: widget.circularFocus ? null : BorderRadius.circular(10),
          boxShadow: _focused && widget.showFocusHighlight
              ? [
                  BoxShadow(
                    color: widget.circularFocus
                        ? const Color(0x6666b3ff)
                        : const Color(0x55ff9900),
                    blurRadius: 7,
                  ),
                ]
              : null,
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

/// Popup menu with one predictable D-pad focus target and a visible TV ring.
class RemotePopupMenuButton<T> extends StatefulWidget {
  const RemotePopupMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    required this.icon,
    this.label,
    this.color,
    this.expandedChild,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final Widget icon;
  final String? label;
  final Color? color;
  final Widget? expandedChild;

  @override
  State<RemotePopupMenuButton<T>> createState() =>
      _RemotePopupMenuButtonState<T>();
}

class _RemotePopupMenuButtonState<T> extends State<RemotePopupMenuButton<T>> {
  final _anchorKey = GlobalKey();

  Future<void> _showMenu() async {
    final anchor = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null) return;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = anchor.localToGlobal(
      anchor.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final value = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: widget.color,
      requestFocus: true,
      items: widget.itemBuilder(context),
    );
    if (value != null && mounted) widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) => RemoteButton(
    label: widget.label,
    onPressed: _showMenu,
    child: SizedBox(
      key: _anchorKey,
      width: widget.expandedChild == null ? 36 : double.infinity,
      height: widget.expandedChild == null ? 36 : 44,
      child: widget.expandedChild ?? Center(child: widget.icon),
    ),
  );
}
