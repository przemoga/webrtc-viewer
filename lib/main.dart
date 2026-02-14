import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'style.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCTV Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppStyles.blackColor,
        colorScheme: ColorScheme.dark(
          primary: AppStyles.themeColor,
          surface: AppStyles.surfaceColor,
          onSurface: AppStyles.whiteColor,
        ),
      ),
      home: const ViewerPage(),
    );
  }
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  // Your Cloud Run service base (no trailing slash)
  static const String signalBase = "wss://przemoga-135868799691.us-central1.run.app";

  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final TextEditingController _roomController = TextEditingController();

  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;

  String _status = "Idle";
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();

    final uri = Uri.base; // e.g. https://host/?room=abc
    final room = uri.queryParameters['room'];
    if (room != null && room.isNotEmpty) {
      _roomController.text = room;
    }
  }

  Future<void> _connectViewer() async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _status = "Please enter a Room ID");
      return;
    }

    if (_connected) {
      await _disconnect();
    }

    setState(() {
      _status = "Connecting WebSocket...";
      _connected = false;
    });

    try {
      // 1) Connect to signaling websocket
      final wsUrl = Uri.parse("$signalBase/ws?roomId=$roomId&role=viewer");
      _ws = WebSocketChannel.connect(wsUrl);

      // 2) Create RTCPeerConnection
      _pc = await createPeerConnection({
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"},
        ],
        "sdpSemantics": "unified-plan",
      });

      // Receive remote tracks
      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          _renderer.srcObject = event.streams[0];
          setState(() => _status = "Receiving video ✅");
        }
      };

      // Send ICE candidates to host
      _pc!.onIceCandidate = (RTCIceCandidate candidate) {
        _send({"type": "candidate", "data": candidate.toMap()});
      };

      // Listen for signaling messages
      _ws!.stream.listen(
        (message) async {
          final Map<String, dynamic> msg = jsonDecode(message as String);
          final type = msg["type"] as String?;

          if (type == "offer") {
            setState(() => _status = "Got offer, creating answer...");

            final offer = msg["data"];
            await _pc!.setRemoteDescription(RTCSessionDescription(offer["sdp"], offer["type"]));

            final answer = await _pc!.createAnswer({});
            await _pc!.setLocalDescription(answer);

            _send({
              "type": "answer",
              "data": {"type": answer.type, "sdp": answer.sdp},
            });

            setState(() {
              _status = "Answer sent, waiting for media...";
              _connected = true;
            });
          } else if (type == "candidate") {
            final c = msg["data"];
            try {
              await _pc!.addCandidate(
                RTCIceCandidate(c["candidate"], c["sdpMid"], c["sdpMLineIndex"]),
              );
            } catch (_) {
              // Sometimes candidates arrive early; ignore minor timing issues in MVP
            }
          }
        },
        onError: (e) {
          setState(() => _status = "WebSocket error: $e");
          _disconnect();
        },
        onDone: () {
          if (_connected) {
            setState(() => _status = "WebSocket closed");
            _disconnect();
          }
        },
      );

      setState(() => _status = "Waiting for host offer...");
    } catch (e) {
      setState(() => _status = "Connection failed: $e");
      _disconnect();
    }
  }

  void _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null) return;
    ws.sink.add(jsonEncode(msg));
  }

  Future<void> _disconnect() async {
    // avoid recursive disconnect if called from onDone/onError
    if (!_connected && _ws == null) return;

    setState(() => _status = "Disconnecting...");

    try {
      await _pc?.close();
      _pc = null;

      await _renderer.srcObject?.dispose();
      _renderer.srcObject = null; // Prepare for next connection

      await _ws?.sink.close();
      _ws = null;
    } catch (e) {
      print("Error disconnecting: $e");
    }

    if (mounted) {
      setState(() {
        _status = "Disconnected";
        _connected = false;
      });
    }
  }

  @override
  void dispose() {
    _disconnect();
    _renderer.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.blackColor,
      body: SafeArea(
        child: Padding(
          padding: AppStyles.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text("XSPECTION", style: AppStyles.titleLine),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text("CCTV Remote Viewer", style: AppStyles.subTitleLine),
                  const Spacer(),
                  // Discrete Status Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppStyles.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppStyles.innerBoarderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: _connected ? Colors.green : AppStyles.greyColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _status,
                          style: AppStyles.captionLine.copyWith(
                            color: AppStyles.whiteColor.withValues(alpha: 0.7),
                            fontStyle: FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Controls Section - Always in a Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _roomController,
                      style: const TextStyle(color: AppStyles.whiteColor),
                      decoration: AppStyles.textFieldDecoration(
                        "Room ID",
                        const Icon(Icons.meeting_room),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _connectViewer,
                    style: AppStyles.primaryButtonStyle(AppStyles.themeColor),
                    child: Text(
                      _connected ? "Reconnect" : "Connect",
                      style: AppStyles.buttonTextStyle,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Video Section
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: AppStyles.videoFrameDecoration,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        // The Video
                        RTCVideoView(
                          _renderer,
                          mirror: false,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          placeholderBuilder: (context) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_off,
                                  size: 64,
                                  color: AppStyles.greyColor.withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "No Video Feed",
                                  style: AppStyles.subTitleLine.copyWith(
                                    color: AppStyles.greyColor.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Overlay status badge if connected
                        if (_connected)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppStyles.themeColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.greenAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "LIVE",
                                    style: AppStyles.captionLine.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
