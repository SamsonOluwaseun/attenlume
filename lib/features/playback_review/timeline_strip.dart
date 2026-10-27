import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/services/review_timeline.dart';

/// The whole activity at a glance: segments as blocks, gaps as a thin
/// line, interruptions, photos and bookmarks at their offsets, and the
/// playhead. Tap or drag to scrub (FR-REV-01, FR-REV-02) [P1-17].
class TimelineStrip extends StatelessWidget {
  const TimelineStrip({
    super.key,
    required this.timeline,
    required this.positionMs,
    required this.onSeek,
  });

  final ReviewTimeline timeline;
  final int positionMs;
  final ValueChanged<int> onSeek;

  static const _markerRow = 20.0;
  static const _barHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('review-timeline'),
      label: _describe(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double xOf(int ms) => timeline.spanMs <= 0
              ? 0
              : (ms - timeline.startMs) / timeline.spanMs * width;
          void seekAt(double dx) {
            if (width <= 0) return;
            final f = (dx / width).clamp(0.0, 1.0);
            onSeek(timeline.startMs + (f * timeline.spanMs).round());
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: _markerRow * 2 + _barHeight + TokenSpace.space2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _markerRow + TokenSpace.space1,
                    height: _barHeight,
                    child: CustomPaint(
                      painter: _StripPainter(
                        timeline: timeline,
                        positionMs: positionMs,
                        segment: scheme.primary,
                        unplayable: scheme.outline,
                        gap: scheme.outlineVariant,
                        playhead: scheme.onSurface,
                      ),
                    ),
                  ),
                  for (final m in timeline.markers)
                    Positioned(
                      key: Key('review-marker-${m.kind.name}-${m.id}'),
                      left: xOf(m.offsetMs) - 8,
                      top: m.kind == TimelineMarkerKind.interruption
                          ? _markerRow + _barHeight + TokenSpace.space2
                          : 0,
                      child: ExcludeSemantics(
                        child: Icon(
                          _iconFor(m.kind),
                          size: 16,
                          color: m.kind == TimelineMarkerKind.interruption
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static IconData _iconFor(TimelineMarkerKind kind) => switch (kind) {
    TimelineMarkerKind.photo => Icons.photo_camera_rounded,
    TimelineMarkerKind.bookmark => Icons.bookmark_rounded,
    TimelineMarkerKind.interruption => Icons.phone_disabled_rounded,
  };

  String _describe() {
    String count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    return 'Timeline: ${count(timeline.segments.length, 'segment')}, '
        '${count(timeline.gaps.length, 'gap')}, '
        '${count(timeline.markersOf(TimelineMarkerKind.bookmark).length, 'bookmark')}, '
        '${count(timeline.markersOf(TimelineMarkerKind.photo).length, 'photo')}, '
        '${count(timeline.markersOf(TimelineMarkerKind.interruption).length, 'interruption')}';
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.timeline,
    required this.positionMs,
    required this.segment,
    required this.unplayable,
    required this.gap,
    required this.playhead,
  });

  final ReviewTimeline timeline;
  final int positionMs;
  final Color segment;
  final Color unplayable;
  final Color gap;
  final Color playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final span = timeline.spanMs;
    if (span <= 0) return;
    double xOf(int ms) => (ms - timeline.startMs) / span * size.width;

    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = gap
        ..strokeWidth = 2,
    );
    for (final s in timeline.segments) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          xOf(s.startMs),
          0,
          // At least 2 px so a short segment is still visible.
          xOf(s.endMs).clamp(xOf(s.startMs) + 2, size.width),
          size.height,
        ),
        const Radius.circular(TokenRadius.radiusSm / 2),
      );
      canvas.drawRRect(
        rect,
        s.playable
            ? (Paint()..color = segment)
            : (Paint()
                ..color = unplayable
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5),
      );
    }
    final x = xOf(positionMs);
    canvas.drawLine(
      Offset(x, -4),
      Offset(x, size.height + 4),
      Paint()
        ..color = playhead
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.positionMs != positionMs ||
      old.timeline != timeline ||
      old.segment != segment;
}
