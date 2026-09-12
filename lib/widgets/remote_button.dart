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
  final FocusNode _focusNode = FocusNode(debugLabel: 'remote-button');
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _requestInitialFocus();
  }

  @override
  void didUpdateWidget(covariant RemoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && oldWidget.onPressed == null && _enabled) {
      _requestInitialFocus();
    }
  }

  void _requestInitialFocus() {
    if (!widget.autofocus || !_enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _enabled && !_focusNode.hasFocus) {
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
    enabled: _enabled,
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
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? const Color(0xffffcc33) : Colors.transparent,
            width: 5,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _focused
              ? const [BoxShadow(color: Color(0xaaff9900), blurRadius: 14)]
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
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final Widget icon;
  final String? label;
  final Color? color;

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
      width: 36,
      height: 36,
      child: Center(child: widget.icon),
    ),
  );
}
