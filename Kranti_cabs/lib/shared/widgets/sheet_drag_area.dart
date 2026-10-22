import 'package:flutter/material.dart';

/// Makes [child] slide a [DraggableScrollableSheet].
///
/// A DraggableScrollableSheet only moves with the scrollable that owns its
/// scroll controller - on the ride screen, the vehicle list. Its handle bar
/// and header were decoration, so grabbing them (where everyone reaches to
/// slide a sheet) did nothing. Wrap them in this, sharing the sheet's
/// [controller], and they slide it too.
///
/// Follows the finger; a flick up opens the sheet fully, a flick down returns
/// it to [restExtent] or, if already there or lower, to [minExtent]. A slow drag
/// stays where it is let go. Taps inside [child] still work - only vertical
/// drags are taken.
class SheetDragArea extends StatelessWidget {
  final DraggableScrollableController controller;
  final double minExtent;
  final double maxExtent;
  final double restExtent;
  final Widget child;

  const SheetDragArea({
    super.key,
    required this.controller,
    required this.minExtent,
    required this.maxExtent,
    required this.restExtent,
    required this.child,
  });

  static const double _flickVelocity = 600;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (!controller.isAttached) return;
        final height = MediaQuery.sizeOf(context).height;
        final next = (controller.size - details.delta.dy / height).clamp(minExtent, maxExtent);
        controller.jumpTo(next);
      },
      onVerticalDragEnd: (details) {
        if (!controller.isAttached) return;
        final velocity = details.primaryVelocity ?? 0;
        final double target;
        if (velocity < -_flickVelocity) {
          target = maxExtent;
        } else if (velocity > _flickVelocity) {
          target = controller.size > restExtent + 0.01 ? restExtent : minExtent;
        } else {
          return;
        }
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      },
      child: child,
    );
  }
}
