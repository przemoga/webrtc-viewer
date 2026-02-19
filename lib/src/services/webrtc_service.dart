import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/crypto_utils.dart';

class WebrtcService {
  static const String _signalBase = "wss://przemoga-135868799691.us-central1.run.app";

  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;

  String? _sessionId;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];
  String? _lastOfferSdp;

  int _attemptId = 0;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _streamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get streamStream => _streamController.stream;

  final _connectedController = StreamController<bool>.broadcast();
  Stream<bool> get connectedStream => _connectedController.stream;

  Future<void> connect({required String roomId, required String password}) async {
    final int myAttempt = ++_attemptId;

    await _resetSession();

    _updateStatus("Connecting WebSocket...");
    _updateConnected(false);

    try {
      final pwEnc = Uri.encodeQueryComponent(password);
      final viewerWsSessionId = CryptoUtils.newSessionId();
      final hmac = CryptoUtils.buildHmacParams(
        roomId: roomId,
        role: "viewer",
        sessionId: viewerWsSessionId,
      );

      final wsUrl = Uri.parse(
        "$_signalBase/ws?roomId=$roomId&role=viewer&pw=$pwEnc"
        "&sessionId=${Uri.encodeQueryComponent(hmac['sessionId']!)}"
        "&ts=${hmac['ts']}"
        "&nonce=${Uri.encodeQueryComponent(hmac['nonce']!)}"
        "&sig=${hmac['sig']}",
      );

      _ws = WebSocketChannel.connect(wsUrl);

      // Create new sessionId for this attempt and tell host
      _sessionId = CryptoUtils.newSessionId();
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
          _streamController.add(event.streams[0]);
          _updateStatus("Receiving video ✅");
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
            await _handleOffer(msg, myAttempt);
          } else if (type == "candidate") {
            await _handleCandidate(msg);
          }
        },
        onError: (e) async {
          if (myAttempt != _attemptId) return;
          await _disconnect(statusAfter: "Connection error (wrong password or room not found)");
        },
        onDone: () async {
          if (myAttempt != _attemptId) return;
          await _disconnect(statusAfter: "Disconnected");
        },
      );

      _updateStatus("Waiting for host offer...");
    } catch (e) {
      if (myAttempt != _attemptId) return;
      await _disconnect(statusAfter: "Connection failed: $e");
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> msg, int myAttempt) async {
    final offer = msg["data"];
    final offerSdp = offer["sdp"] as String?;

    // Ignore duplicate offers within same session
    if (offerSdp != null && offerSdp == _lastOfferSdp) return;
    _lastOfferSdp = offerSdp;

    _updateStatus("Got offer, creating answer...");

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

    if (myAttempt == _attemptId) {
      _updateStatus("Answer sent, waiting for media...");
      _updateConnected(true);
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> msg) async {
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

  Future<void> disconnect() async {
    await _disconnect(statusAfter: "Disconnected");
  }

  Future<void> cancel() async {
    await _disconnect(statusAfter: "Cancelled");
  }

  Future<void> _disconnect({required String statusAfter}) async {
    _attemptId++;
    await _resetSession();
    _updateStatus(statusAfter);
    _updateConnected(false);
    _streamController.add(null);
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

    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _lastOfferSdp = null;
    _sessionId = null;
  }

  void _send(Map<String, dynamic> msg) {
    _ws?.sink.add(jsonEncode(msg));
  }

  void _updateStatus(String status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _updateConnected(bool connected) {
    if (!_connectedController.isClosed) {
      _connectedController.add(connected);
    }
  }

  void dispose() {
    _statusController.close();
    _streamController.close();
    _connectedController.close();
    _disconnect(statusAfter: "Disposed");
  }
}
