import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../domain/services/recording_state.dart';
import '../../features/capture/level_meter.dart';

/// The recording controls on the navy recording screen (DESIGN_GUIDE RecordButton,
/// FR-UI-01, FR-REC-09).
///
/// Features:
/// - Status indicator with pulsing lime dot while recording
/// - Large elapsed timer in `timer` typography (tabular figures)
/// - Integrated live level meter
/// - Debounced 96px primary controls (Record, Pause/Resume, Stop)
/// - 56px secondary actions row (Photo, Bookmark, Note)
class RecordButton extends StatefulWidget {
  const RecordButton({
    super.key,
    required this.state,
    required this.elapsed,
    required this.activityTitle,
    this.levelDbfs = -60.0,
    this.onRecord,
    this.onPause,
    this.onResume,
    this.onStop,
    this.onPhoto,
    this.onBookmark,
    this.onNote,
    this.debounceDuration = const Duration(milliseconds: 600),
    this.clock = DateTime.now,
  });

  final RecordingState state;
  final Duration elapsed;
  final String activityTitle;
  final double levelDbfs;
  final VoidCallback? onRecord;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final VoidCallback? onPhoto;
  final VoidCallback? onBookmark;
  final VoidCallback? onNote;
  final Duration debounceDuration;
  final DateTime Function() clock;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.state == RecordingState.recording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == RecordingState.recording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool _isDebounced() {
    final now = widget.clock();
    if (now.difference(_lastTapTime) < widget.debounceDuration) {
      return true;
    }
    _lastTapTime = now;
    unawaited(HapticFeedback.selectionClick());
    return false;
  }

  void _tap(VoidCallback? action) {
    if (action == null) return;
    if (_isDebounced()) return;
    action();
  }

  String _formatTimer(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = d.inHours;

    if (hours > 0) {
      final hoursStr = hours.toString().padLeft(2, '0');
      return '$hoursStr:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final isRecording = widget.state == RecordingState.recording;
    final isPaused = widget.state == RecordingState.paused;
    final isInterrupted =
        widget.state == RecordingState.interrupted ||
        widget.state == RecordingState.userResumeRequired;
    final isHeld = widget.state.holdsActivity;

    final timerStyle =
        (attenlume?.timer ??
                theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ) ??
                const TextStyle(fontSize: 56, fontWeight: FontWeight.bold))
            .copyWith(
              color: attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
              fontFeatures: const [FontFeature.tabularFigures()],
            );

    final timerString = _formatTimer(widget.elapsed);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Top status pill (LIVE / Paused / Interrupted / Idle)
        _buildStatusHeader(
          attenlume,
          isRecording: isRecording,
          isPaused: isPaused,
          isInterrupted: isInterrupted,
          reduceMotion: reduceMotion,
        ),

        const SizedBox(height: TokenSpace.space3),

        // Timer
        Semantics(
          label: 'Elapsed time: $timerString',
          child: Text(
            timerString,
            key: const Key('record-timer-text'),
            style: timerStyle,
          ),
        ),

        const SizedBox(height: TokenSpace.space4),

        // Live level meter waveform
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TokenSpace.space4),
          child: LevelMeter(
            key: const Key('record-level-meter'),
            levelDbfs: widget.levelDbfs,
            isRecording: isRecording,
            isPaused: isPaused,
          ),
        ),

        const SizedBox(height: TokenSpace.space5),

        // Primary Control Buttons (Record or Pause + Stop)
        if (!isHeld)
          _buildIdleRecordControl(attenlume)
        else
          _buildActiveRecordControls(
            attenlume,
            isRecording: isRecording,
            isPaused: isPaused,
            isInterrupted: isInterrupted,
          ),

        const SizedBox(height: TokenSpace.space5),

        // Secondary Row: Photo, Bookmark, Note
        _buildSecondaryRow(attenlume),
      ],
    );
  }

  Widget _buildStatusHeader(
    AttenlumeColors? attenlume, {
    required bool isRecording,
    required bool isPaused,
    required bool isInterrupted,
    required bool reduceMotion,
  }) {
    if (isRecording) {
      final dot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: attenlume?.live ?? const Color(0xFFDCFF38),
          shape: BoxShape.circle,
        ),
      );

      final animatedDot = reduceMotion
          ? dot
          : FadeTransition(opacity: _pulseAnimation, child: dot);

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animatedDot,
          const SizedBox(width: TokenSpace.space2),
          Text(
            'LIVE',
            key: const Key('record-status-live'),
            style: TextStyle(
              fontFamily: TokenType.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: attenlume?.live ?? const Color(0xFFDCFF38),
            ),
          ),
        ],
      );
    }

    if (isPaused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: 16,
            color: attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8),
          ),
          const SizedBox(width: TokenSpace.space1),
          Text(
            'Paused',
            key: const Key('record-status-paused'),
            style: TextStyle(
              fontFamily: TokenType.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8),
            ),
          ),
        ],
      );
    }

    if (isInterrupted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.phone_disabled_rounded,
            size: 16,
            color: attenlume?.warningFill ?? const Color(0xFFFFF4C2),
          ),
          const SizedBox(width: TokenSpace.space1),
          Text(
            'Interrupted',
            key: const Key('record-status-interrupted'),
            style: TextStyle(
              fontFamily: TokenType.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: attenlume?.warningFill ?? const Color(0xFFFFF4C2),
            ),
          ),
        ],
      );
    }

    return Text(
      'Ready to record',
      key: const Key('record-status-idle'),
      style: TextStyle(
        fontFamily: TokenType.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8),
      ),
    );
  }

  Widget _buildIdleRecordControl(AttenlumeColors? attenlume) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Record, ${widget.activityTitle}',
          child: Material(
            color: attenlume?.surfaceBrand ?? const Color(0xFF4392F1),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('record-button-start'),
              onTap: () => _tap(widget.onRecord),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: TokenSize.recordButton,
                height: TokenSize.recordButton,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color:
                          attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: TokenSpace.space2),
        Text(
          'Record',
          style: TextStyle(
            fontFamily: TokenType.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveRecordControls(
    AttenlumeColors? attenlume, {
    required bool isRecording,
    required bool isPaused,
    required bool isInterrupted,
  }) {
    final pauseOrResumeLabel = isRecording ? 'Pause' : 'Resume';
    final pauseOrResumeIcon = isRecording
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final pauseOrResumeAction = isRecording ? widget.onPause : widget.onResume;
    final semanticPauseLabel = isRecording
        ? 'Pause recording, ${widget.activityTitle}, ${widget.elapsed.inMinutes} minutes'
        : 'Resume recording, ${widget.activityTitle}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pause / Resume button (96px live-raised circle)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: semanticPauseLabel,
              child: Material(
                color: attenlume?.liveRaised ?? const Color(0xFF0E3542),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('record-button-pause-resume'),
                  onTap: () => _tap(pauseOrResumeAction),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: TokenSize.recordButton,
                    height: TokenSize.recordButton,
                    child: Center(
                      child: Icon(
                        pauseOrResumeIcon,
                        size: 40,
                        color:
                            attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TokenSpace.space2),
            Text(
              pauseOrResumeLabel,
              style: TextStyle(
                fontFamily: TokenType.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
              ),
            ),
          ],
        ),

        const SizedBox(width: TokenSpace.space6),

        // Stop button (96px circle with 2px onLiveSurfaceMuted ring and red stop square inside)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: 'Stop and save recording, ${widget.activityTitle}',
              child: Material(
                color: Colors.transparent,
                shape: CircleBorder(
                  side: BorderSide(
                    color:
                        attenlume?.onLiveSurfaceMuted ??
                        const Color(0xFF9FB3B8),
                    width: 2.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('record-button-stop'),
                  onTap: () => _tap(widget.onStop),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: TokenSize.recordButton,
                    height: TokenSize.recordButton,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: attenlume?.stop ?? const Color(0xFFEF4444),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TokenSpace.space2),
            Text(
              'Stop',
              style: TextStyle(
                fontFamily: TokenType.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecondaryRow(AttenlumeColors? attenlume) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(
        horizontal: TokenSpace.space3,
        vertical: TokenSpace.space2,
      ),
      decoration: BoxDecoration(
        color: attenlume?.liveRaised ?? const Color(0xFF0E3542),
        borderRadius: const BorderRadius.all(
          Radius.circular(TokenRadius.radiusLg),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Photo
          _buildSecondaryButton(
            key: const Key('record-action-photo'),
            icon: Icons.camera_alt_rounded,
            label: 'Photo',
            semanticLabel: 'Take photo',
            onTap: widget.onPhoto,
            attenlume: attenlume,
          ),

          Container(
            width: 1,
            height: 36,
            color: (attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8))
                .withValues(alpha: 0.25),
          ),

          // Bookmark
          _buildSecondaryButton(
            key: const Key('record-action-bookmark'),
            icon: Icons.bookmark_rounded,
            label: 'Bookmark',
            semanticLabel: 'Add bookmark',
            onTap: widget.onBookmark,
            attenlume: attenlume,
          ),

          Container(
            width: 1,
            height: 36,
            color: (attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8))
                .withValues(alpha: 0.25),
          ),

          // Note
          _buildSecondaryButton(
            key: const Key('record-action-note'),
            icon: Icons.edit_note_rounded,
            label: 'Note',
            semanticLabel: 'Add quick note',
            onTap: widget.onNote,
            attenlume: attenlume,
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryButton({
    required Key key,
    required IconData icon,
    required String label,
    required String semanticLabel,
    required VoidCallback? onTap,
    required AttenlumeColors? attenlume,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          onTap: onTap == null ? null : () => _tap(onTap),
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TokenSpace.space3,
              vertical: TokenSpace.space2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: TokenType.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
