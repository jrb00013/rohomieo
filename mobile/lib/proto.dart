/// Mirrors crates/proto and web/src/proto.ts

enum Role { host, viewer }

Map<String, dynamic> registerViewer({
  required String sessionId,
  required String pin,
}) =>
    {
      'type': 'register_viewer',
      'session_id': sessionId,
      'pin': pin,
    };

Map<String, dynamic> heartbeat() => {'type': 'heartbeat'};

Map<String, dynamic> answer(String sdp) => {'type': 'answer', 'sdp': sdp};

Map<String, dynamic> iceCandidate({
  required String candidate,
  String? sdpMid,
  int? sdpMLineIndex,
}) =>
    {
      'type': 'ice_candidate',
      'candidate': candidate,
      if (sdpMid != null) 'sdpMid': sdpMid,
      if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
    };

Map<String, dynamic> pointerEvent({
  required double x,
  required double y,
  required int action,
}) =>
    {
      'type': 'pointer',
      'x': x,
      'y': y,
      'action': action,
    };

Map<String, dynamic> keyEvent({required String key, required bool down}) =>
    {'type': 'key', 'key': key, 'down': down};
