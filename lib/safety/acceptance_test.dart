/// Acceptance Test Module (Safety-Critical: Chapter 4)
///
/// Every alarm message must pass these validation checks before
/// triggering a nuclear alarm. This prevents:
/// - Stale alarms from waking users unnecessarily
/// - Malformed payloads from crashing the alarm screen
/// - Duplicate alarms from firing multiple times
///
/// Reference: "Is this value physically possible?" — AT Design Principle
import '../models/alarm_message.dart';

class AcceptanceResult {
  final bool passed;
  final String? reason;

  const AcceptanceResult._(this.passed, this.reason);
  
  factory AcceptanceResult.accept() => const AcceptanceResult._(true, null);
  factory AcceptanceResult.reject(String reason) => AcceptanceResult._(false, reason);

  @override
  String toString() => passed ? 'AT: PASS' : 'AT: REJECT — $reason';
}

class AlarmAcceptanceTest {
  /// Maximum age of an alarm before it's considered stale (30 seconds)
  static const maxAlarmAgeSeconds = 30;

  /// Maximum body length to prevent overflow attacks
  static const maxBodyLength = 1000;

  /// Recently seen alarm IDs for duplicate detection
  static final Set<String> _recentAlarmIds = {};

  /// Maximum number of recent IDs to track
  static const maxRecentIds = 100;

  /// Validate an alarm message against all acceptance criteria.
  /// Returns AcceptanceResult.accept() if all tests pass.
  static AcceptanceResult validate(AlarmMessage msg) {
    // AT-1: Required fields
    if (msg.id.isEmpty) {
      return AcceptanceResult.reject('AT-1: Alarm ID is empty');
    }
    if (msg.title.isEmpty) {
      return AcceptanceResult.reject('AT-2: Title is empty');
    }
    if (msg.body.isEmpty) {
      return AcceptanceResult.reject('AT-3: Body is empty');
    }

    // AT-4: Body sanity check
    if (msg.body.length > maxBodyLength) {
      return AcceptanceResult.reject('AT-4: Body exceeds $maxBodyLength characters');
    }

    // AT-5: Timestamp freshness — reject alarms older than 30 seconds
    final age = DateTime.now().difference(msg.timestamp).inSeconds;
    if (age > maxAlarmAgeSeconds) {
      return AcceptanceResult.reject('AT-5: Alarm is ${age}s old (max: ${maxAlarmAgeSeconds}s)');
    }

    // AT-6: Duplicate detection
    if (_recentAlarmIds.contains(msg.id)) {
      return AcceptanceResult.reject('AT-6: Duplicate alarm (${msg.id})');
    }

    // All tests passed — register this alarm ID
    _recentAlarmIds.add(msg.id);
    if (_recentAlarmIds.length > maxRecentIds) {
      _recentAlarmIds.remove(_recentAlarmIds.first);
    }

    return AcceptanceResult.accept();
  }

  /// Clear the recent alarm IDs (for testing)
  static void reset() {
    _recentAlarmIds.clear();
  }
}
