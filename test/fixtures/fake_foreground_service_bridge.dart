import 'dart:async';

import 'package:attenlume/platform/foreground_service/foreground_service_bridge.dart';

/// A [ForegroundServiceBridge] test double for unit and widget tests [P1-11, FR-REC-10].
class FakeForegroundServiceBridge implements ForegroundServiceBridge {
  final _actionsController =
      StreamController<ForegroundServiceAction>.broadcast();
  final List<NotificationDetails> startCalls = [];
  final List<NotificationDetails> updateCalls = [];
  int stopCallCount = 0;
  bool _running = false;

  void sendAction(ForegroundServiceAction action) =>
      _actionsController.add(action);

  @override
  bool get isRunning => _running;

  set isRunning(bool value) => _running = value;

  @override
  Stream<ForegroundServiceAction> get actions => _actionsController.stream;

  @override
  Future<void> startService(NotificationDetails details) async {
    startCalls.add(details);
    _running = true;
  }

  @override
  Future<void> updateNotification(NotificationDetails details) async {
    updateCalls.add(details);
  }

  @override
  Future<void> stopService() async {
    stopCallCount++;
    _running = false;
  }

  Future<void> close() => _actionsController.close();
}
