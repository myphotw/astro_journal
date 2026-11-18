import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Keeps a wheel event inside its panel when the panel reaches a scroll edge.
class PcScrollBoundary extends StatelessWidget {
  const PcScrollBoundary({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
      }
    },
    child: child,
  );
}

/// Shows working navigation buttons only while the paired viewport overflows.
class PcScrollEdgeButtons extends StatefulWidget {
  const PcScrollEdgeButtons({
    super.key,
    required this.controller,
    this.axis = Axis.vertical,
  });

  final ScrollController controller;
  final Axis axis;

  @override
  State<PcScrollEdgeButtons> createState() => _PcScrollEdgeButtonsState();
}

class _PcScrollEdgeButtonsState extends State<PcScrollEdgeButtons> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _refreshAfterLayout();
  }

  @override
  void didUpdateWidget(covariant PcScrollEdgeButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
    _refreshAfterLayout();
  }

  void _refreshAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _move(bool forward) {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    final step = position.viewportDimension * 0.7;
    final target = (position.pixels + (forward ? step : -step))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    widget.controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.hasClients) return const SizedBox(width: 56);
    final position = widget.controller.position;
    if (position.maxScrollExtent <= position.minScrollExtent + 0.5) {
      return const SizedBox(width: 56);
    }
    final canBack = position.pixels > position.minScrollExtent + 0.5;
    final canForward = position.pixels < position.maxScrollExtent - 0.5;
    final horizontal = widget.axis == Axis.horizontal;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        tooltip: horizontal ? '왼쪽으로 이동' : '위로 이동',
        onPressed: canBack ? () => _move(false) : null,
        icon: Icon(horizontal ? Icons.chevron_left : Icons.keyboard_arrow_up,
            size: 19),
      ),
      IconButton(
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        tooltip: horizontal ? '오른쪽으로 이동' : '아래로 이동',
        onPressed: canForward ? () => _move(true) : null,
        icon: Icon(horizontal ? Icons.chevron_right : Icons.keyboard_arrow_down,
            size: 19),
      ),
    ]);
  }
}
