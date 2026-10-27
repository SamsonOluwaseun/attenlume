import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:flutter_test/flutter_test.dart';

CutRange cut(
  String id,
  int start,
  int end, {
  String? reason,
  bool isDeleted = false,
}) => CutRange(
  id: id,
  activityId: 'act-1',
  startOffsetMs: start,
  endOffsetMs: end,
  reason: reason,
  deletedAt: isDeleted ? DateTime.utc(2026, 11, 4, 12) : null,
  createdAt: DateTime.utc(2026, 11, 4, 10),
  updatedAt: DateTime.utc(2026, 11, 4, 10),
);

void main() {
  group('FR-REV-04 cut-range maths and merging [P0-14]', () {
    test('FR-REV-04 empty cuts produce empty merged list', () {
      expect(CutRangeMath.mergeOverlappingCutRanges([]), isEmpty);
    });

    test('FR-REV-04 soft-deleted cuts are ignored', () {
      final cuts = [
        cut('c1', 1000, 5000, isDeleted: true),
        cut('c2', 8000, 10000),
      ];
      final merged = CutRangeMath.mergeOverlappingCutRanges(cuts);
      expect(merged, [const TimeRange(8000, 10000)]);
    });

    test('FR-REV-04 sorts out-of-order non-overlapping cuts', () {
      final cuts = [cut('c2', 20000, 25000), cut('c1', 5000, 10000)];
      final merged = CutRangeMath.mergeOverlappingCutRanges(cuts);
      expect(merged, [
        const TimeRange(5000, 10000),
        const TimeRange(20000, 25000),
      ]);
    });

    test(
      'FR-REV-04 merges overlapping cut ranges (Product Spec edge case)',
      () {
        final cuts = [
          cut('c1', 5000, 15000),
          cut('c2', 10000, 20000), // overlaps c1
          cut('c3', 18000, 25000), // overlaps c2
        ];
        final merged = CutRangeMath.mergeOverlappingCutRanges(cuts);
        expect(merged, [const TimeRange(5000, 25000)]);
      },
    );

    test('FR-REV-04 merges contiguous adjacent cut ranges', () {
      final cuts = [cut('c1', 1000, 3000), cut('c2', 3000, 6000)];
      final merged = CutRangeMath.mergeOverlappingCutRanges(cuts);
      expect(merged, [const TimeRange(1000, 6000)]);
    });

    test('FR-REV-04 merges completely nested/enclosed cut ranges', () {
      final cuts = [
        cut('c1', 2000, 10000),
        cut('c2', 4000, 6000), // fully inside c1
      ];
      final merged = CutRangeMath.mergeOverlappingCutRanges(cuts);
      expect(merged, [const TimeRange(2000, 10000)]);
    });
  });

  group('FR-REV-04 keep ranges and trimmed duration [P0-14]', () {
    test('FR-REV-04 no cuts keeps entire duration', () {
      final keeps = CutRangeMath.calculateKeepRanges(
        totalDurationMs: 60000,
        cutRanges: [],
      );
      expect(keeps, [const TimeRange(0, 60000)]);
      expect(
        CutRangeMath.trimmedDurationMs(totalDurationMs: 60000, cutRanges: []),
        60000,
      );
    });

    test('FR-REV-04 trim start (head)', () {
      final cuts = [cut('c1', 0, 15000)];
      final keeps = CutRangeMath.calculateKeepRanges(
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(keeps, [const TimeRange(15000, 60000)]);
      expect(
        CutRangeMath.trimmedDurationMs(totalDurationMs: 60000, cutRanges: cuts),
        45000,
      );
    });

    test('FR-REV-04 trim end (tail)', () {
      final cuts = [cut('c1', 50000, 60000)];
      final keeps = CutRangeMath.calculateKeepRanges(
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(keeps, [const TimeRange(0, 50000)]);
      expect(
        CutRangeMath.trimmedDurationMs(totalDurationMs: 60000, cutRanges: cuts),
        50000,
      );
    });

    test('FR-REV-04 trim middle ranges (multiple cuts)', () {
      final cuts = [cut('c1', 10000, 20000), cut('c2', 40000, 45000)];
      final keeps = CutRangeMath.calculateKeepRanges(
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(keeps, [
        const TimeRange(0, 10000),
        const TimeRange(20000, 40000),
        const TimeRange(45000, 60000),
      ]);
      expect(
        CutRangeMath.trimmedDurationMs(totalDurationMs: 60000, cutRanges: cuts),
        45000,
      );
    });

    test('FR-REV-04 cuts extending past totalDuration are clamped safely', () {
      final cuts = [cut('c1', 50000, 80000)];
      final keeps = CutRangeMath.calculateKeepRanges(
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(keeps, [const TimeRange(0, 50000)]);
      expect(
        CutRangeMath.trimmedDurationMs(totalDurationMs: 60000, cutRanges: cuts),
        50000,
      );
    });

    test('FR-REV-04 all audio cut produces empty keep list', () {
      final cuts = [cut('c1', 0, 60000)];
      final keeps = CutRangeMath.calculateKeepRanges(
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(keeps, isEmpty);
      expect(
        CutRangeMath.trimmedDurationMs(totalDurationMs: 60000, cutRanges: cuts),
        0,
      );
    });
  });

  group('FR-REV-04 timeline offset mapping [P0-14]', () {
    test('FR-REV-04 maps timestamps before any cut identically', () {
      final cuts = [cut('c1', 10000, 20000)];
      final result = CutRangeMath.mapOriginalToTrimmedOffset(
        originalOffsetMs: 5000,
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(result.isInsideCut, isFalse);
      expect(result.trimmedOffsetMs, 5000);
    });

    test('FR-REV-04 maps timestamps after a cut with subtracted duration', () {
      final cuts = [cut('c1', 10000, 20000)]; // 10s cut
      final result = CutRangeMath.mapOriginalToTrimmedOffset(
        originalOffsetMs: 35000,
        totalDurationMs: 60000,
        cutRanges: cuts,
      );
      expect(result.isInsideCut, isFalse);
      expect(result.trimmedOffsetMs, 25000);
    });

    test(
      'FR-REV-04 flags timestamp inside a cut range and points to cut boundary',
      () {
        final cuts = [cut('c1', 10000, 20000)];
        final result = CutRangeMath.mapOriginalToTrimmedOffset(
          originalOffsetMs: 15000,
          totalDurationMs: 60000,
          cutRanges: cuts,
        );
        expect(result.isInsideCut, isTrue);
        expect(result.trimmedOffsetMs, 10000);
      },
    );

    test(
      'FR-REV-04 reverse maps trimmed timestamp back to original timeline',
      () {
        final cuts = [cut('c1', 10000, 20000)]; // cuts 10s..20s
        expect(
          CutRangeMath.mapTrimmedToOriginalOffset(
            trimmedOffsetMs: 5000,
            totalDurationMs: 60000,
            cutRanges: cuts,
          ),
          5000,
        );
        expect(
          CutRangeMath.mapTrimmedToOriginalOffset(
            trimmedOffsetMs: 15000,
            totalDurationMs: 60000,
            cutRanges: cuts,
          ),
          25000, // 15000 + 10000 cut
        );
      },
    );
  });
}
