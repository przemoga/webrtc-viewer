import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
  static const String signalBase = "wss://przemoga-135868799691.us-central1.run.app";

  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final TextEditingController _roomController = TextEditingController();

  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;

  String _status = "Idle";
  bool _connected = false;
  bool _connecting = false;

  // Session + safety
  String? _sessionId;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];
  String? _lastOfferSdp;

  int _attemptId = 0;
  String _lastPassword = "";

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();

    final uri = Uri.base;
    final room = uri.queryParameters['room'];
    if (room != null && room.isNotEmpty) {
      _roomController.text = room;
    }
  }

  String _newSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
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

    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _status = "Please enter a Room ID");
      return;
    }

    final password = await _askPasswordModal(initialValue: _lastPassword);
    if (password == null) return;

    _lastPassword = password;
    await _connectViewer(password: password);
  }

  Future<String?> _askPasswordModal({required String initialValue}) async {
    final TextEditingController pwCtrl = TextEditingController(text: initialValue);

    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
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
                      labelText: "Password (optional)",
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(showPw ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setStateDialog(() => showPw = !showPw),
                      ),
                    ),
                    onSubmitted: (_) => Navigator.of(context).pop(pwCtrl.text.trim()),
                  ),
                ],
              ),
              actions: [
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

  Future<void> _resetSession() async {
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      await _renderer.srcObject?.dispose();
    } catch (_) {}
    _renderer.srcObject = null;

    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _lastOfferSdp = null;
    _sessionId = null;
  }

  void _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null) return;
    ws.sink.add(jsonEncode(msg));
  }

  Future<void> _connectViewer({required String password}) async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _status = "Please enter a Room ID");
      return;
    }

    final int myAttempt = ++_attemptId;

    await _resetSession();

    if (!mounted) return;
    setState(() {
      _status = "Connecting WebSocket...";
      _connected = false;
      _connecting = true;
    });

    try {
      final pwEnc = Uri.encodeQueryComponent(password);

      final wsUrl = Uri.parse("$signalBase/ws?roomId=$roomId&role=viewer&pw=$pwEnc");
      _ws = WebSocketChannel.connect(wsUrl);

      // Create new sessionId for this attempt and tell host
      _sessionId = _newSessionId();
      _send({"type": "viewer-ready", "sessionId": _sessionId});

      _pc = await createPeerConnection({
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"},
        ],
        "sdpSemantics": "unified-plan",
      });

      _pc!.onTrack = (RTCTrackEvent event) {
        if (myAttempt != _attemptId) return;
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          _renderer.srcObject = event.streams[0];
          if (mounted) setState(() => _status = "Receiving video ✅");
        }
      };

      _pc!.onIceCandidate = (RTCIceCandidate candidate) {
        if (myAttempt != _attemptId) return;
        _send({"type": "candidate", "sessionId": _sessionId, "data": candidate.toMap()});
      };

      _ws!.stream.listen(
        (message) async {
          if (myAttempt != _attemptId) return;

          final Map<String, dynamic> msg = jsonDecode(message as String);
          final type = msg["type"] as String?;
          final sid = msg["sessionId"] as String?;

          // Ignore stale signaling from previous sessions
          if (_sessionId != null && sid != null && sid != _sessionId) {
            return;
          }

          if (type == "offer") {
            final offer = msg["data"];
            final offerSdp = offer["sdp"] as String?;

            // Ignore duplicate offers within same session
            if (offerSdp != null && offerSdp == _lastOfferSdp) return;
            _lastOfferSdp = offerSdp;

            if (!mounted) return;
            setState(() => _status = "Got offer, creating answer...");

            await _pc!.setRemoteDescription(RTCSessionDescription(offer["sdp"], offer["type"]));
            _remoteDescriptionSet = true;

            // Apply queued ICE
            if (_pendingCandidates.isNotEmpty) {
              for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
                try {
                  await _pc!.addCandidate(c);
                } catch (_) {}
              }
              _pendingCandidates.clear();
            }

            final s = _pc!.signalingState;
            if (s != RTCSignalingState.RTCSignalingStateHaveRemoteOffer) return;

            final answer = await _pc!.createAnswer({});
            await _pc!.setLocalDescription(answer);

            _send({
              "type": "answer",
              "sessionId": _sessionId,
              "data": {"type": answer.type, "sdp": answer.sdp},
            });

            if (mounted && myAttempt == _attemptId) {
              setState(() {
                _status = "Answer sent, waiting for media...";
                _connected = true;
                _connecting = false;
              });
            }
          } else if (type == "candidate") {
            final c = msg["data"];
            final ice = RTCIceCandidate(c["candidate"], c["sdpMid"], c["sdpMLineIndex"]);

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
          if (myAttempt != _attemptId) return;
          if (!mounted) return;
          await _disconnect(statusAfter: "Connection error (wrong password or room not found)");
        },
        onDone: () async {
          if (myAttempt != _attemptId) return;
          if (!mounted) return;
          await _disconnect(statusAfter: "Disconnected");
        },
      );

      if (mounted && myAttempt == _attemptId) {
        setState(() => _status = "Waiting for host offer...");
      }
    } catch (e) {
      if (myAttempt != _attemptId) return;
      if (!mounted) return;
      await _disconnect(statusAfter: "Connection failed: $e");
    }
  }

  Future<void> _disconnect({required String statusAfter}) async {
    _attemptId++;
    await _resetSession();
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
              Text("XSPECTION", style: AppStyles.titleLine),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text("CCTV Remote Viewer", style: AppStyles.subTitleLine),
                  const Spacer(),
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

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

              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: AppStyles.videoFrameDecoration,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
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
