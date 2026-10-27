import 'package:uuid/uuid.dart';

/// Current time, always UTC. Injected so tests control time [P0-09].
typedef UtcClock = DateTime Function();

/// New row ID, UUID v4 by default (BUILD_GUIDE 9.4).
typedef IdGenerator = String Function();

DateTime systemUtcClock() => DateTime.now().toUtc();

const _uuid = Uuid();
String uuidV4() => _uuid.v4();
