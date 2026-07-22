import 'package:flutter/material.dart';

/// Replaces Material's ripple/splash with the mockup's actual press feedback:
/// a plain scale-down on press, no splash overlay, no elevation change.
/// `.card.tap:active{transform:scale(.985)}` / `.btn:active{transform:scale(.97)}`
/// are pure CSS transforms with no fill/overlay — Material's ink splash has no
/// equivalent in the mockup at all, and is a large part of why a themed
/// Material widget still reads as "an Android app" rather than this product.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.985,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null && widget.onLongPress == null;
    return GestureDetector(
      // Without this, GestureDetector defaults to HitTestBehavior.deferToChild:
      // only pixels a descendant actually paints (icon, text glyphs) register a
      // hit, so the whitespace gaps in a Row (e.g. between a left-aligned title
      // and a trailing chevron) are dead space — most of a row's visual area.
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _setPressed(false),
      onTapCancel: disabled ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
