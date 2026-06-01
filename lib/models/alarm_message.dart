/// Alarm message model — represents an alarm received from the server.
/// 
/// Safety-Critical: This model includes validation (Acceptance Test)
/// to ensure data integrity before triggering a nuclear alarm.
class AlarmMessage {
  final String id;
  final String title;
  final String body;
  final String priority;
  final String missionId;
  final DateTime timestamp;

  AlarmMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.priority,
    required this.missionId,
    required this.timestamp,
  });

  /// Parse from WebSocket JSON message
  factory AlarmMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? json;
    return AlarmMessage(
      id: json['id'] as String? ?? '',
      title: payload['title'] as String? ?? '',
      body: payload['body'] as String? ?? '',
      priority: payload['priority'] as String? ?? 'critical',
      missionId: payload['mission_id'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'payload': {
      'title': title,
      'body': body,
      'priority': priority,
      'mission_id': missionId,
    },
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}
