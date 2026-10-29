import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';

/// Draws the DESIGN_GUIDE focus ring (2px `focus` with a 2px offset) around
/// whatever has keyboard focus, on every screen and dialog (NFR-09,
/// ADR-050) [P1-26].
///
/// Only shown in keyboard mode ([FocusHighlightMode.traditional], after
/// Tab or an arrow key on Windows or a hardware keyboard), never for touch.
/// It follows the focused control as it scrolls or moves, and takes no
/// taps and no screen reader focus.
class FocusRingOverlay extends StatefulWidget {
  const FocusRingOverlay({super.key, required this.child});

  final Widget child;

  /// Gap between the control and the ring.
  static const double offset = 2;

  /// Ring thickness.
  static const double width = 2;

  @override
  State<FocusRingOverlay> createState() => _FocusRingOverlayState();
}

class _FocusRingOverlayState extends State<FocusRingOverlay> {
  Rect? _rect;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_schedule);
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_schedule);
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => _schedule();

  /// Measures after the next frame. While a ring shows it measures again
  /// after every frame, so it follows scrolling, without asking for frames
  /// of its own.
  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _measure();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _measure() {
    if (!mounted) return;
    final rect = _focusedRect();
    if (rect != _rect) setState(() => _rect = rect);
    if (rect != null && !_scheduled) {
      _scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        _measure();
      });
    }
  }

  Rect? _focusedRect() {
    final manager = FocusManager.instance;
    if (manager.highlightMode != FocusHighlightMode.traditional) return null;
    final node = manager.primaryFocus;
    if (node == null || node is FocusScopeNode) return null;
    final focused = node.context?.findRenderObject();
    final self = context.findRenderObject();
    if (focused is! RenderBox ||
        self is! RenderBox ||
        !focused.attached ||
        !focused.hasSize ||
        !self.hasSize) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      focused.getTransformTo(self),
      Offset.zero & focused.size,
    );
    if (rect.isEmpty || !(Offset.zero & self.size).overlaps(rect)) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final colour =
        Theme.of(context).extension<AttenlumeColors>()?.focus ??
        const Color(0xFF4392F1);
    const inset = FocusRingOverlay.offset + FocusRingOverlay.width;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (rect != null)
          Positioned.fromRect(
            key: const Key('focus-ring'),
            rect: rect.inflate(inset),
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colour,
                      width: FocusRingOverlay.width,
                    ),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(TokenRadius.radiusSm + inset),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
