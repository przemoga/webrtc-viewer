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
  bool _connecting = false;

  // Robustness for late-join buffering / duplicate offers / early candidates
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];
  String? _lastOfferSdp; // to ignore duplicate offer replay

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

  Future<void> _onMainButtonPressed() async {
    if (_connected) {
      await _disconnect(statusAfter: "Disconnected");
      return;
    }

    if (_connecting) {
      await _disconnect(statusAfter: "Cancelled");
      return;
    }

    // Not connected, not connecting => start flow
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _status = "Please enter a Room ID");
      return;
    }

    final password = await _askPasswordModal();
    if (password == null) {
      // user pressed Cancel in modal => do nothing, back to normal view
      return;
    }

    await _connectViewer(password: password);
  }

  Future<String?> _askPasswordModal() async {
    final TextEditingController pwCtrl = TextEditingController();

    return showDialog<String?>(
      context: context,
      barrierDismissible: false, // force user to choose Connect/Cancel
      builder: (context) {
        bool showPw = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppStyles.surfaceColor,
              title: Text(
                "Room password",
                style: AppStyles.subTitleLine.copyWith(color: AppStyles.whiteColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "If the room is public, leave it empty.",
                    style: AppStyles.captionLine.copyWith(
                      color: AppStyles.whiteColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwCtrl,
                    autofocus: true,
                    obscureText: !showPw,
                    style: const TextStyle(color: AppStyles.whiteColor),
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(showPw ? Icons.visibility_off : Icons.visibility),
                        onPressed: () {},
                      ),
                    ),
                    onSubmitted: (_) => Navigator.of(context).pop(pwCtrl.text.trim()),
                  ),
                ],
              ),
              actions: [
                // Cancel button EXACTLY same style as Connect
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: AppStyles.primaryButtonStyle(AppStyles.themeColor),
                  child: Text("Cancel", style: AppStyles.buttonTextStyle),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(pwCtrl.text.trim()),
                  style: AppStyles.primaryButtonStyle(AppStyles.themeColor),
                  child: Text("Connect", style: AppStyles.buttonTextStyle),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _connectViewer({required String password}) async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _status = "Please enter a Room ID");
      return;
    }

    setState(() {
      _status = "Connecting WebSocket...";
      _connected = false;
      _connecting = true;
    });

    // Reset WebRTC state flags for a fresh connection attempt
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _lastOfferSdp = null;

    try {
      final pwEnc = Uri.encodeQueryComponent(password);

      // 1) Connect to signaling websocket (pw can be empty)
      final wsUrl = Uri.parse("$signalBase/ws?roomId=$roomId&role=viewer&pw=$pwEnc");
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
          if (mounted) setState(() => _status = "Receiving video ✅");
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
            final offer = msg["data"];
            final offerSdp = offer["sdp"] as String?;

            // Ignore duplicate offers (can happen when server replays lastOffer, or reconnect races)
            if (offerSdp != null && offerSdp == _lastOfferSdp) {
              return;
            }
            _lastOfferSdp = offerSdp;

            if (!mounted) return;
            setState(() => _status = "Got offer, creating answer...");

            // Set remote description
            await _pc!.setRemoteDescription(RTCSessionDescription(offer["sdp"], offer["type"]));
            _remoteDescriptionSet = true;

            // Apply candidates that arrived early
            if (_pendingCandidates.isNotEmpty) {
              for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
                try {
                  await _pc!.addCandidate(c);
                } catch (_) {}
              }
              _pendingCandidates.clear();
            }

            // Guard: only answer if state is correct, otherwise ignore
            final s = _pc!.signalingState;
            if (s != RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
              return; // prevents "Called in wrong state: stable"
            }

            final answer = await _pc!.createAnswer({});
            await _pc!.setLocalDescription(answer);

            _send({
              "type": "answer",
              "data": {"type": answer.type, "sdp": answer.sdp},
            });

            if (mounted) {
              setState(() {
                _status = "Answer sent, waiting for media...";
                _connected = true;
                _connecting = false;
              });
            }
          } else if (type == "candidate") {
            final c = msg["data"];
            final ice = RTCIceCandidate(c["candidate"], c["sdpMid"], c["sdpMLineIndex"]);

            // If remote description not set yet, store for later
            if (!_remoteDescriptionSet) {
              _pendingCandidates.add(ice);
              return;
            }

            try {
              await _pc!.addCandidate(ice);
            } catch (_) {}
          }
        },
        onError: (e) async {
          if (!mounted) return;
          // Typical cases:
          // - wrong password => WS upgrade fails
          // - room not found => 404
          await _disconnect(statusAfter: "Connection error (wrong password or room not found)");
        },
        onDone: () async {
          if (!mounted) return;
          await _disconnect(statusAfter: _connected ? "Disconnected" : "Disconnected");
        },
      );

      if (mounted) setState(() => _status = "Waiting for host offer...");
    } catch (e) {
      if (!mounted) return;
      await _disconnect(statusAfter: "Connection failed: $e");
    }
  }

  void _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null) return;
    ws.sink.add(jsonEncode(msg));
  }

  Future<void> _disconnect({required String statusAfter}) async {
    // Close everything and reset UI
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      await _renderer.srcObject?.dispose();
    } catch (_) {}
    _renderer.srcObject = null;

    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _lastOfferSdp = null;

    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _status = statusAfter;
      });
    }
  }

  @override
  void dispose() {
    _disconnect(statusAfter: "Disposed");
    _renderer.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String buttonLabel = _connected ? "Disconnect" : (_connecting ? "Cancel" : "Connect");

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

              // Controls Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _roomController,
                      enabled: !_connecting && !_connected,
                      style: const TextStyle(color: AppStyles.whiteColor),
                      decoration: AppStyles.textFieldDecoration(
                        "Room ID",
                        const Icon(Icons.meeting_room),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _onMainButtonPressed,
                    style: AppStyles.primaryButtonStyle(AppStyles.themeColor),
                    child: Text(buttonLabel, style: AppStyles.buttonTextStyle),
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
