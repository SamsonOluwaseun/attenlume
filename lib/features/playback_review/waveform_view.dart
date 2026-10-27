import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../shared/utilities/date_formatters.dart';
import 'waveform_pages.dart';

/// One page of the waveform at a time, following the playhead, with
/// previous and next page buttons. Only the shown page is read from disk
/// (FR-REV-03) [P1-17].
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.pager,
    required this.positionMs,
    required this.onSeek,
    this.height = 96,
  });

  final WaveformPager pager;
  final int positionMs;
  final ValueChanged<int> onSeek;
  final double height;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  WaveformPage? _page;
  late int _index;
  int _followed = -1;

  @override
  void initState() {
    super.initState();
    _index = widget.pager.pageOf(widget.positionMs);
    _followed = _index;
    _load(_index);
  }

  @override
  void didUpdateWidget(WaveformView old) {
    super.didUpdateWidget(old);
    // Follow the playhead when it moves to another page, but leave the
    // user's own browsing alone until it does.
    final playheadPage = widget.pager.pageOf(widget.positionMs);
    if (playheadPage != _followed) {
      _followed = playheadPage;
      if (playheadPage != _index) _show(playheadPage);
    }
  }

  void _show(int index) {
    setState(() => _index = index);
    _load(index);
  }

  Future<void> _load(int index) async {
    final page = await widget.pager.load(index);
    if (mounted && index == _index) setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pager = widget.pager;
    final page = _page;
    final start = pager.timeline.startMs + _index * pager.pageMs;
    final end = start + pager.pageMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('waveform-previous'),
              tooltip: 'Previous page',
              onPressed: _index > 0 ? () => _show(_index - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${formatOffset(start)} to ${formatOffset(end)}',
                key: const Key('waveform-page-range'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              key: const Key('waveform-next'),
              tooltip: 'Next page',
              onPressed: _index < pager.pageCount - 1
                  ? () => _show(_index + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Semantics(
          label:
              'Waveform, page ${_index + 1} of ${pager.pageCount}. '
              'Tap to play from a point.',
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                key: const Key('waveform-canvas'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  final f = (d.localPosition.dx / constraints.maxWidth).clamp(
                    0.0,
                    1.0,
                  );
                  widget.onSeek(start + (f * pager.pageMs).round());
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: page == null || page.index != _index
                      ? null
                      : _WaveformPainter(
                          page: page,
                          positionMs: widget.positionMs,
                          bar: scheme.primary,
                          flat: scheme.outline,
                          playhead: scheme.onSurface,
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

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.page,
    required this.positionMs,
    required this.bar,
    required this.flat,
    required this.playhead,
  });

  final WaveformPage page;
  final int positionMs;
  final Color bar;
  final Color flat;
  final Color playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final length = page.lengthMs;
    if (length <= 0 || size.width <= 0) return;
    double xOf(int ms) => (ms - page.startMs) / length * size.width;
    final mid = size.height / 2;

    final flatPaint = Paint()
      ..color = flat
      ..strokeWidth = 1;
    for (final m in page.missing) {
      canvas.drawLine(
        Offset(xOf(m.startMs), mid),
        Offset(xOf(m.endMs), mid),
        flatPaint,
      );
    }

    // One bar per pixel column, using the loudest bucket in it.
    final columns = size.width.floor();
    final peaks = List<int>.filled(columns, -1);
    for (final span in page.spans) {
      for (var i = 0; i < span.levels.length; i++) {
        final x = xOf(span.startMs + i * span.bucketMs).floor();
        if (x < 0 || x >= columns) continue;
        peaks[x] = math.max(peaks[x], span.levels[i]);
      }
    }
    final barPaint = Paint()
      ..color = bar
      ..strokeWidth = 1;
    for (var x = 0; x < columns; x++) {
      final level = peaks[x];
      if (level < 0) continue;
      final h = math.max(1.0, level / 255 * (size.height - 8) / 2);
      canvas.drawLine(
        Offset(x + 0.5, mid - h),
        Offset(x + 0.5, mid + h),
        barPaint,
      );
    }

    if (positionMs >= page.startMs && positionMs <= page.endMs) {
      final x = xOf(positionMs);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = playhead
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.page != page || old.positionMs != positionMs || old.bar != bar;
}
