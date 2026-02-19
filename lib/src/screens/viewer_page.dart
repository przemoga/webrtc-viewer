import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../style.dart';
import '../services/webrtc_service.dart';
import '../widgets/password_dialog.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  final _service = WebrtcService();
  final _renderer = RTCVideoRenderer();
  final _roomController = TextEditingController();

  String _status = "Idle";
  bool _connected = false;
  bool _connecting = false;
  String _lastPassword = "";

  StreamSubscription? _statusSub;
  StreamSubscription? _connectedSub;
  StreamSubscription? _streamSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();

    _statusSub = _service.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });

    _connectedSub = _service.connectedStream.listen((c) {
      if (mounted) {
        setState(() {
          _connected = c;
          _connecting =
              !c &&
              (_status.startsWith("Connecting") ||
                  _status.startsWith("Waiting") ||
                  _status.startsWith("Got offer") ||
                  _status.startsWith("Answer sent"));
          // Adjust logic for _connecting based on status text is brittle, but fine for now or improve service to expose connecting state.
          // Better: WebrtcService could expose specific states enum.
          // For now, let's rely on button logic which checks _connected and _connecting.
          // Re-evaluating _connecting logic:
          if (c) _connecting = false;
        });
      }
    });

    _streamSub = _service.streamStream.listen((stream) {
      _renderer.srcObject = stream;
    });

    final uri = Uri.base;
    final room = uri.queryParameters['room'];
    if (room != null && room.isNotEmpty) {
      _roomController.text = room;
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _connectedSub?.cancel();
    _streamSub?.cancel();
    _service.dispose();
    _renderer.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _onMainButtonPressed() async {
    if (_connected) {
      await _service.disconnect();
      return;
    }

    // Check if we are physically connecting (status check is a bit weak, but service should track this)
    // Let's assume if not connected and status implies activity, we are connecting.
    // Or we can just track local _connecting state when we call connect.
    if (_connecting) {
      await _service.cancel();
      setState(() => _connecting = false);
      return;
    }

    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _status = "Please enter a Room ID");
      return;
    }

    final password = await PasswordDialog.show(context, initialValue: _lastPassword);
    if (password == null) return;

    _lastPassword = password;

    setState(() => _connecting = true);
    await _service.connect(roomId: roomId, password: password);
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
