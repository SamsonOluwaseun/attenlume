import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/one_active_coordinator.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../domain/services/safety_prompt_service.dart';
import '../../presentation/components/bookmark_chip.dart';
import '../../presentation/components/record_button.dart';
import '../../presentation/components/storage_meter.dart';
import '../privacy/recording_privacy_check.dart';
import 'camera_screen.dart';
import 'mic_test_sheet.dart';
import 'one_active_prompt_dialog.dart';
import 'quick_thought_sheet.dart';
import 'recording_profile_selector.dart';
import 'recording_providers.dart';

/// Recording screen UI with live level meter, controls, bookmark chips,
/// mic test and photo capture (BUILD_GUIDE 5.3, FR-UI-01 to 06, FR-UI-08).
///
/// Rendered in navy (`live-surface`) in BOTH light and dark themes.
class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({
    super.key,
    required this.activityId,
    this.onBack,
    this.clock = DateTime.now,
    this.enableTicker = true,
  });

  final String activityId;
  final VoidCallback? onBack;
  final DateTime Function() clock;
  final bool enableTicker;

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  Activity? _activity;
  Conference? _conference;
  bool _isLoading = true;

  Timer? _ticker;
  Duration _priorSegmentsDuration = Duration.zero;
  Duration _elapsed = Duration.zero;
  double _currentLevelDbfs = -90.0;
  String _inputDeviceLabel = 'Microphone';
  int _photoCount = 0;
  int _bookmarkCount = 0;
  StreamSubscription<String>? _hardStopSub;
  StreamSubscription<SafetyPrompt>? _safetySub;
  SafetyPrompt? _safetyPrompt;

  @override
  void initState() {
    super.initState();
    _loadData();
    _safetySub = ref.read(safetyPromptServiceProvider).prompts.listen((prompt) {
      if (!mounted || prompt.activityId != widget.activityId) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() => _safetyPrompt = prompt);
    });
    _hardStopSub = ref
        .read(storageBudgetServiceProvider)
        .hardStopNoticeStream
        .listen((notice) {
          if (!mounted) return;
          final scheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              // danger with on-danger text: navy snack bar text on the
              // light danger fill failed contrast (NFR-09).
              content: Text(notice, style: TextStyle(color: scheme.onError)),
              backgroundColor: scheme.error,
              duration: const Duration(seconds: 4),
            ),
          );
        });
  }

  @override
  void dispose() {
    _safetySub?.cancel();
    _hardStopSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final actRepo = ref.read(activityRepositoryProvider);
    final confRepo = ref.read(conferenceRepositoryProvider);
    final mediaRepo = ref.read(mediaAssetRepositoryProvider);
    final routeProbe = ref.read(audioRouteProbeProvider);
    unawaited(
      ref
          .read(storageBudgetServiceProvider)
          .checkNow(activityId: widget.activityId),
    );

    final act = await actRepo.get(widget.activityId);
    if (act == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final conf = await confRepo.get(act.conferenceId);
    final segments = await mediaRepo.segmentsFor(widget.activityId);
    final photos = await mediaRepo.photosFor(widget.activityId);
    final bookmarks = await mediaRepo.bookmarksFor(widget.activityId);

    var finishedDuration = Duration.zero;
    for (final seg in segments) {
      if (seg.state == SegmentState.finalised ||
          seg.state == SegmentState.recovered) {
        if (seg.durationMs != null) {
          finishedDuration += Duration(milliseconds: seg.durationMs!);
        } else if (seg.endUtc != null) {
          finishedDuration += seg.endUtc!.difference(seg.startUtc);
        }
      }
    }

    String deviceLabel = 'Microphone';
    try {
      final input = await routeProbe.activeInput();
      if (input != null && input.label.isNotEmpty) {
        deviceLabel = input.label;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _activity = act;
        _conference = conf;
        _priorSegmentsDuration = finishedDuration;
        _elapsed = finishedDuration;
        _photoCount = photos.length;
        _bookmarkCount = bookmarks.length;
        _inputDeviceLabel = deviceLabel;
        _isLoading = false;
      });
    }
  }

  void _syncTicker(RecordingStatus status) {
    if (!widget.enableTicker) return;
    final isRecording =
        status.activityId == widget.activityId &&
        status.state == RecordingState.recording;
    if (isRecording) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 200), (_) async {
        if (!mounted) return;
        final recorder = ref.read(recordingServiceProvider);
        final curStatus = recorder.status;
        if (curStatus.activityId == widget.activityId &&
            curStatus.state == RecordingState.recording) {
          final startUtc = curStatus.segmentStartUtc ?? DateTime.now().toUtc();
          final currentSegmentSpan = DateTime.now().toUtc().difference(
            startUtc,
          );
          final totalElapsed = _priorSegmentsDuration + currentSegmentSpan;

          double level = -90.0;
          try {
            final engine = ref.read(audioCaptureEngineProvider);
            level = await engine.levelDbfs();
          } catch (_) {}

          if (mounted) {
            setState(() {
              _elapsed = totalElapsed;
              _currentLevelDbfs = level;
            });
          }
        } else {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Says why a start from this screen was refused. Notification and
  /// shortcut triggers get theirs from [OneActiveCoordinator] instead.
  String _startRefusalMessage(StartOutcome? outcome) => switch (outcome) {
    StartOutcome.microphoneDenied =>
      'Attenlume needs microphone access. Allow it in your device '
          'settings, then tap Record again.',
    StartOutcome.failed =>
      "Couldn't start recording. Check that a microphone is connected "
          'and not in use by another app.',
    StartOutcome.storageFull =>
      "Couldn't start recording: storage is nearly full (under 100 MB "
          'remaining).',
    StartOutcome.recordingNotPermitted =>
      'This activity is set to not record audio.',
    _ => "Couldn't start recording.",
  };

  Future<void> _handleStartRecord() async {
    // Policy reminder and conversation awareness check (FR-PRI-01).
    final privacy = await checkRecordingPrivacy(
      context,
      conferences: ref.read(conferenceRepositoryProvider),
      activities: ref.read(activityRepositoryProvider),
      activityId: widget.activityId,
    );
    if (!mounted) return;
    if (privacy != RecordingPrivacyCheck.proceed) {
      if (privacy == RecordingPrivacyCheck.notRecordingAudio) {
        await _loadData();
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _startRefusalMessage(StartOutcome.recordingNotPermitted),
            ),
          ),
        );
      }
      return;
    }
    final coordinator = ref.read(oneActiveCoordinatorProvider);
    final result = await startRecordingFromUi(
      context,
      coordinator,
      widget.activityId,
    );

    if (!mounted) return;

    if (result.outcome == RecordRequestOutcome.refused) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            result.confirmation ?? _startRefusalMessage(result.startOutcome),
          ),
        ),
      );
    } else if (result.outcome == RecordRequestOutcome.started ||
        result.outcome == RecordRequestOutcome.switched) {
      await _loadData();
    }
  }

  Future<void> _handlePause() async {
    final recorder = ref.read(recordingServiceProvider);
    await recorder.pause();
    await _loadData();
  }

  Future<void> _handleResume() async {
    final recorder = ref.read(recordingServiceProvider);
    await recorder.resume();
    await _loadData();
  }

  Future<void> _handleStop() async {
    final recorder = ref.read(recordingServiceProvider);
    await recorder.stop();
    await _loadData();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Saved'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_handleStartRecord()),
        ),
      ),
    );
  }

  /// Opens the in-app camera; recording carries on underneath [P1-14].
  Future<void> _handleTakePhoto() async {
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    final taken = await CameraScreen.open(context, widget.activityId);
    if (!mounted) return;
    setState(() => _photoCount += taken);
    if (taken > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(taken == 1 ? 'Photo saved' : '$taken photos saved'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleAddBookmark([
    String? label,
    BookmarkSource source = BookmarkSource.ui,
  ]) async {
    await HapticFeedback.lightImpact();
    final mediaRepo = ref.read(mediaAssetRepositoryProvider);

    try {
      await mediaRepo.addBookmark(
        activityId: _activity!.id,
        source: source,
        label: label ?? 'Bookmark',
      );

      if (mounted) {
        setState(() => _bookmarkCount++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              label != null ? 'Bookmarked: $label' : 'Bookmark added',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add bookmark: $e')));
      }
    }
  }

  void _handleOpenNote() {
    QuickThoughtSheet.show(
      context,
      activityId: widget.activityId,
      initialPrivate: _activity?.isPrivate ?? false,
    );
  }

  void _handleOpenMicTest() {
    MicTestSheet.show(context);
  }

  Future<void> _changeLiveProfile(RecordingProfile profile) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(recordingServiceProvider)
        .changeProfile(profile);

    final message = switch (result.outcome) {
      ProfileChangeOutcome.changed =>
        'Recording quality is now ${profile.label}.',
      ProfileChangeOutcome.alreadyInUse ||
      ProfileChangeOutcome.notRecording => null,
      ProfileChangeOutcome.declined ||
      ProfileChangeOutcome.failed => result.reason,
    };
    if (message != null && mounted) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
    await _loadData();
  }

  Future<void> _setProfileOverride(RecordingProfile profile) async {
    await ref
        .read(activityRepositoryProvider)
        .update(
          _activity!.id,
          ActivitiesCompanion(recordingProfileOverride: Value(profile)),
        );
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Theme(
        data: AppTheme.live(),
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final act = _activity!;
    final conf = _conference;
    final status =
        ref.watch(recordingStatusProvider).value ??
        ref.watch(recordingServiceProvider).status;
    _syncTicker(status);
    final isThisRecording = status.activityId == act.id;
    final liveState = isThisRecording ? status.state : RecordingState.idle;

    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();

    final liveSurface = attenlume?.liveSurface ?? const Color(0xFF00212B);
    final onLiveSurface = attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8);
    final onLiveSurfaceMuted =
        attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8);
    final warningFill = attenlume?.warningFill ?? const Color(0xFFFFF4C2);

    // Profile selector state
    final isHolding = liveState.holdsActivity;
    final profileInUse = isHolding
        ? (status.profile ??
              act.recordingProfileOverride ??
              conf?.defaultRecordingProfile ??
              RecordingProfile.balanced)
        : (act.recordingProfileOverride ??
              conf?.defaultRecordingProfile ??
              RecordingProfile.balanced);

    final budgetSnapshot =
        ref.watch(storageBudgetSnapshotProvider).value ??
        ref.watch(storageBudgetServiceProvider).currentSnapshot;

    // Ctrl+B adds a bookmark from a keyboard: the Windows hotkey
    // (FR-BMK-03) while the window has focus. Global hotkeys: ADR-033.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            unawaited(_handleAddBookmark(null, BookmarkSource.hotkey)),
      },
      child: Focus(
        autofocus: true,
        child: Theme(
          data: AppTheme.live(),
          child: Scaffold(
            key: const Key('recording-screen-scaffold'),
            backgroundColor: liveSurface,
            appBar: AppBar(
              backgroundColor: liveSurface,
              elevation: 0,
              leading: IconButton(
                key: const Key('recording-screen-back'),
                tooltip: 'Back',
                icon: Icon(Icons.arrow_back_rounded, color: onLiveSurface),
                onPressed:
                    widget.onBack ??
                    () => unawaited(Navigator.of(context).maybePop()),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    act.title,
                    key: const Key('recording-screen-title'),
                    style: TextStyle(
                      fontFamily: TokenType.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: onLiveSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conf != null)
                    Text(
                      '${conf.name}${act.room != null && act.room!.isNotEmpty ? " · ${act.room}" : ""}',
                      key: const Key('recording-screen-subtitle'),
                      style: TextStyle(
                        fontFamily: TokenType.fontFamily,
                        fontSize: 12,
                        color: onLiveSurfaceMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              actions: [
                IconButton(
                  key: const Key('recording-screen-mic-test'),
                  icon: Icon(
                    Icons.mic_external_on_rounded,
                    color: onLiveSurface,
                  ),
                  tooltip: 'Test microphone',
                  onPressed: _handleOpenMicTest,
                ),
              ],
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: TokenSpace.space4,
                  vertical: TokenSpace.space3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input source indicator row (FR-UI-06)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          size: 16,
                          color: onLiveSurfaceMuted,
                        ),
                        const SizedBox(width: TokenSpace.space1),
                        Text(
                          _inputDeviceLabel,
                          key: const Key('input-source-indicator'),
                          style: TextStyle(
                            fontFamily: TokenType.fontFamily,
                            fontSize: 12,
                            color: onLiveSurfaceMuted,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: TokenSpace.space3),

                    // Interruption or Error Banner (FR-REC-05, ADR-021)
                    if (isThisRecording &&
                        (status.interruption != null ||
                            status.state == RecordingState.userResumeRequired ||
                            status.state ==
                                RecordingState.errorRecoverable)) ...[
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Container(
                          key: const Key('recording-interruption-banner'),
                          padding: const EdgeInsets.all(TokenSpace.space3),
                          decoration: BoxDecoration(
                            color: warningFill.withValues(alpha: 0.15),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(TokenRadius.radiusMd),
                            ),
                            border: Border.all(color: warningFill),
                          ),
                          // The button sits below the message so both fit
                          // at 200% text on a phone (NFR-09).
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_disabled_rounded,
                                    color: onLiveSurface,
                                    size: 24,
                                  ),
                                  const SizedBox(width: TokenSpace.space3),
                                  Expanded(
                                    child: Text(
                                      status.errorMessage ?? 'Recording paused for a call or another app.',
                                      style: TextStyle(
                                        fontFamily: TokenType.fontFamily,
                                        fontSize: 14,
                                        color: onLiveSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: TokenSpace.space2),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                  key: const Key(
                                    'recording-resume-banner-button',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        attenlume?.surfaceBrand ??
                                        const Color(0xFF4392F1),
                                    foregroundColor:
                                        attenlume?.onBrandLarge ??
                                        const Color(0xFFFEFFF8),
                                  ),
                                  onPressed: _handleResume,
                                  child: const Text('Resume'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: TokenSpace.space3),
                    ],

                    // Safety prompt (FR-REC-06) [P1-13]. Never stops recording.
                    if (_safetyPrompt != null &&
                        isThisRecording &&
                        status.state.holdsActivity) ...[
                      _SafetyPromptBanner(
                        prompt: _safetyPrompt!,
                        activityTitle: act.title,
                        warningFill: warningFill,
                        onLiveSurface: onLiveSurface,
                        onKeep: () => setState(() => _safetyPrompt = null),
                        onStop: () {
                          setState(() => _safetyPrompt = null);
                          unawaited(_handleStop());
                        },
                      ),
                      const SizedBox(height: TokenSpace.space3),
                    ],

                    // Main RecordButton Anatomy (Status, Timer, LevelMeter, 96px controls, Secondary row)
                    RecordButton(
                      key: const Key('main-record-button'),
                      state: liveState,
                      elapsed: _elapsed,
                      activityTitle: act.title,
                      levelDbfs: _currentLevelDbfs,
                      storageMeter: StorageMeter(
                        key: const Key('recording-screen-storage-meter'),
                        freeBytes: budgetSnapshot.freeBytes,
                        totalBytes: budgetSnapshot.totalBytes,
                        minutesLeft: budgetSnapshot.minutesLeft,
                        profile: profileInUse,
                        level: budgetSnapshot.level,
                        conferenceBytes: budgetSnapshot.conferenceBytes,
                        compact: true,
                      ),
                      clock: widget.clock,
                      onRecord: _handleStartRecord,
                      onPause: _handlePause,
                      onResume: _handleResume,
                      onStop: _handleStop,
                      onPhoto: _handleTakePhoto,
                      onBookmark: _handleAddBookmark,
                      onNote: _handleOpenNote,
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Bookmark Chips Row (FR-UI-04)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'One-tap bookmarks',
                            style: TextStyle(
                              fontFamily: TokenType.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: onLiveSurfaceMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: TokenSpace.space2),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final chip
                                  in BookmarkChip.standardChips) ...[
                                BookmarkChip(
                                  key: Key('bookmark-chip-$chip'),
                                  label: chip,
                                  onLiveSurface: true,
                                  onPress: () => _handleAddBookmark(chip),
                                ),
                                const SizedBox(width: TokenSpace.space2),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: TokenSpace.space5),

                    // Quality Profile Selector (FR-UI-08)
                    RecordingProfileSelector(
                      key: const Key('recording-screen-profile-selector'),
                      selected: profileInUse,
                      live: isHolding,
                      onChanged: isHolding
                          ? _changeLiveProfile
                          : _setProfileOverride,
                    ),

                    const SizedBox(height: TokenSpace.space4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A safety prompt on the recording screen (FR-REC-06) [P1-13]. Both
/// actions are the user's choice: the prompt itself never stops anything.
class _SafetyPromptBanner extends StatelessWidget {
  const _SafetyPromptBanner({
    required this.prompt,
    required this.activityTitle,
    required this.warningFill,
    required this.onLiveSurface,
    required this.onKeep,
    required this.onStop,
  });

  final SafetyPrompt prompt;
  final String activityTitle;
  final Color warningFill;
  final Color onLiveSurface;
  final VoidCallback onKeep;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (prompt.kind) {
      SafetyPromptKind.longRecording => (
        Icons.schedule_rounded,
        "Still in '$activityTitle'? Recording has been running for "
            '${prompt.elapsed?.inHours ?? 2} hours.',
      ),
      SafetyPromptKind.silence => (
        Icons.hearing_disabled_rounded,
        'No sound detected. Still in the session?',
      ),
      SafetyPromptKind.lowBattery => (
        Icons.battery_alert_rounded,
        'Battery is at ${prompt.batteryPercent ?? 15} %. Recording carries '
            'on; plug in if you can.',
      ),
    };
    final textStyle = TextStyle(
      fontFamily: TokenType.fontFamily,
      fontSize: 14,
      color: onLiveSurface,
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        key: Key('safety-prompt-${prompt.kind.name}'),
        padding: const EdgeInsets.all(TokenSpace.space3),
        decoration: BoxDecoration(
          color: warningFill.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusMd),
          ),
          border: Border.all(color: warningFill),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // on-live-surface: warning-fill fails as an icon on navy.
                Icon(icon, color: onLiveSurface, size: 24),
                const SizedBox(width: TokenSpace.space3),
                Expanded(child: Text(message, style: textStyle)),
              ],
            ),
            const SizedBox(height: TokenSpace.space2),
            // Wrap, so both buttons fit at 200% text on a phone (NFR-09).
            Wrap(
              alignment: WrapAlignment.end,
              spacing: TokenSpace.space2,
              runSpacing: TokenSpace.space2,
              children: [
                if (prompt.kind != SafetyPromptKind.lowBattery)
                  TextButton(
                    key: const Key('safety-prompt-stop'),
                    onPressed: onStop,
                    style: TextButton.styleFrom(foregroundColor: onLiveSurface),
                    child: const Text('Stop and save'),
                  ),
                FilledButton(
                  key: const Key('safety-prompt-keep'),
                  onPressed: onKeep,
                  child: Text(
                    prompt.kind == SafetyPromptKind.lowBattery
                        ? 'OK'
                        : 'Keep recording',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
