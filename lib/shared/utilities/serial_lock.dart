import 'dart:async';

/// Runs async actions one at a time, in the order they were requested
/// (FR-REC-09) [P1-04].
///
/// An action that throws does not block the ones queued after it.
class SerialLock {
  Future<void> _tail = Future<void>.value();

  /// Whether an action is running or queued.
  bool get isBusy => _pending > 0;
  int _pending = 0;

  Future<T> run<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending++;
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _pending--;
      }
    });
    return result.future;
  }
}
