import 'dart:async';

/// A [Timer] that fires only when a test says so [P1-05].
class FakeTimer implements Timer {
  FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  /// Runs the callback as the real timer would when it fires.
  void fire() {
    _active = false;
    _callback();
  }

  /// Runs the callback even if the timer was cancelled, as a late timer
  /// event racing a cancel would.
  void fireLate() => _callback();
}

/// Hands out [FakeTimer]s and keeps every one, newest last [P1-05].
class FakeTimers {
  final List<FakeTimer> created = [];

  Iterable<FakeTimer> get active => created.where((t) => t.isActive);

  Timer call(Duration duration, void Function() callback) {
    final timer = FakeTimer(duration, callback);
    created.add(timer);
    return timer;
  }
}
