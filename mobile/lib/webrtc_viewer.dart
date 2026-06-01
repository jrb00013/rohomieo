import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'proto.dart';

typedef StateCallback = void Function(String state, [String? detail]);

class RohomieoViewer {
  RohomieoViewer(this.onState);

  final StateCallback onState;
  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  Timer? _heartbeat;

  final _remoteRenderer = RTCVideoRenderer();

  RTCVideoRenderer get renderer => _remoteRenderer;

  Future<void> initRenderer() => _remoteRenderer.initialize();

  Future<void> dispose() async {
    _heartbeat?.cancel();
    await _ws?.sink.close();
    await _dc?.close();
    await _pc?.close();
    await _remoteRenderer.dispose();
  }

  Future<void> connect(String signalingUrl, String sessionId, String pin) async {
    _heartbeat?.cancel();
    await _ws?.sink.close();
    await _dc?.close();
    await _pc?.close();
    _ws = null;
    _dc = null;
    _pc = null;
    onState('connecting');

    _ws = WebSocketChannel.connect(Uri.parse(signalingUrl));
    _ws!.sink.add(jsonEncode(registerViewer(sessionId: sessionId, pin: pin)));

    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      _ws?.sink.add(jsonEncode(heartbeat()));
    });

    _ws!.stream.listen((data) async {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      await _handleSignal(msg);
    }, onError: (_) => onState('error', 'WebSocket failed'), onDone: () => onState('disconnected'));
  }

  Future<void> _ensurePeer() async {
    if (_pc != null) return;
    _pc = await createPeerConnection({'iceServers': []});
    _pc!.onTrack = (ev) {
      if (ev.streams.isNotEmpty) {
        _remoteRenderer.srcObject = ev.streams[0];
        onState('connected');
      }
    };
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _ws?.sink.add(jsonEncode(iceCandidate(
          candidate: c.candidate!,
          sdpMid: c.sdpMid,
          sdpMLineIndex: c.sdpMLineIndex,
        )));
      }
    };
    _pc!.onDataChannel = (dc) {
      _dc = dc;
    };
  }

  Future<void> _handleSignal(Map<String, dynamic> msg) async {
    switch (msg['type']) {
      case 'registered':
        onState('waiting_host');
        break;
      case 'error':
        onState('error', msg['message'] as String?);
        break;
      case 'offer':
        onState('negotiating');
        await _ensurePeer();
        await _pc!.setRemoteDescription(
          RTCSessionDescription(msg['sdp'] as String, 'offer'),
        );
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _ws?.sink.add(jsonEncode(answer(answer.sdp!)));
        break;
      case 'ice_candidate':
        await _pc?.addCandidate(
          RTCIceCandidate(
            msg['candidate'] as String,
            msg['sdpMid'] as String?,
            msg['sdpMLineIndex'] as int?,
          ),
        );
        break;
      case 'peer_left':
        onState('waiting_host', 'Host disconnected');
        break;
    }
  }

  void sendPointer(double x, double y, int action) {
    final payload = jsonEncode(pointerEvent(x: x, y: y, action: action));
    _dc?.send(RTCDataChannelMessage(payload));
  }

  void sendKey(String key, bool down) {
    final payload = jsonEncode(keyEvent(key: key, down: down));
    _dc?.send(RTCDataChannelMessage(payload));
  }
}
