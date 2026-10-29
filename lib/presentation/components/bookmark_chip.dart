import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';

/// One-tap label chip that marks a moment in the recording without typing
/// (FR-UI-04, DESIGN_GUIDE BookmarkChip).
class BookmarkChip extends StatefulWidget {
  const BookmarkChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onLiveSurface = true,
    this.onPress,
  });

  /// Standard default chips recommended by FR-UI-04.
  static const List<String> standardChips = [
    'Important moment',
    'Question',
    'Follow-up',
    'Key slide',
    'Quote',
  ];

  final String label;
  final bool selected;
  final bool onLiveSurface;
  final VoidCallback? onPress;

  @override
  State<BookmarkChip> createState() => _BookmarkChipState();
}

class _BookmarkChipState extends State<BookmarkChip> {
  bool _flashing = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onPress == null) return;

    if (widget.onLiveSurface) {
      unawaited(HapticFeedback.lightImpact());
      setState(() => _flashing = true);
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() => _flashing = false);
        }
      });
    }

    widget.onPress!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();

    Color background;
    Color textColor;
    Border? border;

    if (widget.onLiveSurface) {
      if (_flashing || widget.selected) {
        background = attenlume?.live ?? const Color(0xFFDCFF38);
        textColor = attenlume?.onLive ?? const Color(0xFF00212B);
        border = Border.all(
          color: attenlume?.live ?? const Color(0xFFDCFF38),
          width: 1.5,
        );
      } else {
        background = Colors.transparent;
        textColor = attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8);
        border = Border.all(
          color: attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8),
          width: 1.5,
        );
      }
    } else {
      if (widget.selected) {
        background = theme.colorScheme.primaryContainer;
        textColor = theme.colorScheme.onPrimaryContainer;
        border = null;
      } else {
        background = Colors.transparent;
        textColor = theme.colorScheme.onSurface;
        border = Border.all(color: theme.colorScheme.outline, width: 1.5);
      }
    }

    const shape = StadiumBorder();

    return Semantics(
      button: true,
      label: 'Bookmark: ${widget.label}',
      selected: widget.selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TokenSize.tapMin),
        child: Material(
          color: background,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: widget.onPress == null ? null : _handleTap,
            // A minimum, not a fixed height, so the label can grow with
            // the text size (NFR-09).
            child: Container(
              constraints: const BoxConstraints(minHeight: TokenSize.tapMin),
              padding: const EdgeInsets.symmetric(
                horizontal: TokenSpace.space3,
                vertical: TokenSpace.space2,
              ),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(
                  Radius.circular(TokenRadius.radiusPill),
                ),
                border: border,
              ),
              alignment: Alignment.center,
              // The Semantics label above already says it.
              child: ExcludeSemantics(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: TokenType.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
