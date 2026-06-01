import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'webrtc_viewer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RohomieoApp());
}

class RohomieoApp extends StatelessWidget {
  const RohomieoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rohomieo',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D9EFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ConnectPage(),
    );
  }
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _signalingCtrl =
      TextEditingController(text: 'wss://10.8.0.20:8443/ws');
  final _sessionCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _status = 'disconnected';
  String? _detail;

  RohomieoViewer? _viewer;

  @override
  void dispose() {
    _signalingCtrl.dispose();
    _sessionCtrl.dispose();
    _pinCtrl.dispose();
    _viewer?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final viewer = RohomieoViewer((s, [d]) {
      setState(() {
        _status = s;
        _detail = d;
      });
      if (s == 'connected' && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ViewerPage(viewer: viewer),
          ),
        );
      }
    });
    _viewer = viewer;
    await viewer.initRenderer();
    await viewer.connect(
      _signalingCtrl.text.trim(),
      _sessionCtrl.text.trim(),
      _pinCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rohomieo')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Connect WireGuard first, then enter the host session ID and PIN.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _signalingCtrl,
              decoration: const InputDecoration(labelText: 'Signaling WebSocket'),
            ),
            TextField(
              controller: _sessionCtrl,
              decoration: const InputDecoration(labelText: 'Session ID'),
            ),
            TextField(
              controller: _pinCtrl,
              decoration: const InputDecoration(labelText: 'PIN'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _connect,
              child: const Text('Connect'),
            ),
            const SizedBox(height: 12),
            Text('$_status${_detail != null ? ' — $_detail' : ''}'),
          ],
        ),
      ),
    );
  }
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.viewer});

  final RohomieoViewer viewer;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onTapDown(TapDownDetails d, BoxConstraints constraints) {
    final x = d.localPosition.dx / constraints.maxWidth;
    final y = d.localPosition.dy / constraints.maxHeight;
    widget.viewer.sendPointer(x, y, 1);
  }

  void _onTapUp(TapUpDetails d, BoxConstraints constraints) {
    final x = d.localPosition.dx / constraints.maxWidth;
    final y = d.localPosition.dy / constraints.maxHeight;
    widget.viewer.sendPointer(x, y, 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (d) => _onTapDown(d, constraints),
                onTapUp: (d) => _onTapUp(d, constraints),
                onPanUpdate: (d) {
                  final x = d.localPosition.dx / constraints.maxWidth;
                  final y = d.localPosition.dy / constraints.maxHeight;
                  widget.viewer.sendPointer(x, y, 0);
                },
                child: RTCVideoView(
                  widget.viewer.renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
