import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallPhase { idle, outgoing, incoming, connected }

/// Аудио/видео-звонки по WebRTC. Сигналинг — через серверное событие
/// `call_signal` (контракт совпадает с веб-клиентом, сервер не меняется).
class CallService extends ChangeNotifier {
  CallService({
    required this.currentUserId,
    required this.emitSignal,
    required this.fetchIce,
  });

  final String currentUserId;
  final void Function(Map<String, dynamic> data) emitSignal;
  final Future<List<Map<String, dynamic>>> Function() fetchIce;

  static const List<Map<String, dynamic>> _fallbackIce = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  CallPhase phase = CallPhase.idle;
  String? peerId;
  String callType = 'audio'; // 'audio' | 'video'
  String? error;
  String? hint;
  bool micMuted = false;
  bool speakerOn = false;
  bool cameraOff = false;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  String? _callId;
  String? _signalTarget;
  Map<String, dynamic>? _pendingOffer;
  final List<RTCIceCandidate> _iceQueue = [];
  List<Map<String, dynamic>> _iceServers = _fallbackIce;

  bool get hasRemoteVideo => remoteRenderer.srcObject != null;

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> _refreshIce() async {
    try {
      final servers = await fetchIce();
      _iceServers = servers.isNotEmpty ? servers : _fallbackIce;
    } on Object {
      _iceServers = _fallbackIce;
    }
  }

  Future<RTCPeerConnection> _makePc() async {
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        notifyListeners();
      }
    };
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final target = _signalTarget;
      if (target == null) return;
      emitSignal({
        'toUserId': target,
        'kind': 'ice',
        'callId': _callId,
        'candidate': candidate.toMap(),
      });
    };
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        hint = null;
        error = null;
        notifyListeners();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = 'Соединение оборвалось. Попробуйте перезвонить.';
        notifyListeners();
      }
    };
    return pc;
  }

  Future<MediaStream> _getMedia(String type) {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': type == 'video' ? {'facingMode': 'user'} : false,
    });
  }

  void _applyAudioRoute() {
    speakerOn = callType == 'video';
    try {
      Helper.setSpeakerphoneOn(speakerOn);
    } on Object {
      // не критично
    }
  }

  Future<void> startCall(String toUserId, String type) async {
    if (phase != CallPhase.idle) return;
    await _ensureRenderers();
    _cleanup(notify: false);
    _callId = _genId();
    _signalTarget = toUserId;
    callType = type;
    peerId = toUserId;
    phase = CallPhase.outgoing;
    error = null;
    hint = 'Соединяем…';
    notifyListeners();
    try {
      await _refreshIce();
      final stream = await _getMedia(type);
      _localStream = stream;
      if (type == 'video') localRenderer.srcObject = stream;
      _applyAudioRoute();
      final pc = await _makePc();
      _pc = pc;
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      emitSignal({
        'toUserId': toUserId,
        'kind': 'offer',
        'callId': _callId,
        'callType': type,
        'sdp': offer.sdp,
      });
      notifyListeners();
    } on Object {
      emitSignal({'toUserId': toUserId, 'kind': 'end', 'callId': _callId});
      _cleanup(notify: false);
      phase = CallPhase.idle;
      peerId = null;
      error = type == 'video'
          ? 'Нет доступа к камере или микрофону'
          : 'Нет доступа к микрофону';
      notifyListeners();
    }
  }

  Future<void> acceptIncoming() async {
    final pending = _pendingOffer;
    if (pending == null) return;
    await _ensureRenderers();
    final from = pending['fromUserId'] as String;
    final cid = pending['callId'] as String;
    final sdp = pending['sdp'] as String;
    final ctype = pending['callType'] as String;
    _pendingOffer = null;
    final queued = List<RTCIceCandidate>.from(_iceQueue);
    _cleanup(notify: false);
    _iceQueue.addAll(queued);
    _callId = cid;
    _signalTarget = from;
    peerId = from;
    callType = ctype;
    error = null;
    hint = 'Соединяем…';
    notifyListeners();
    try {
      await _refreshIce();
      final stream = await _getMedia(ctype);
      _localStream = stream;
      if (ctype == 'video') localRenderer.srcObject = stream;
      _applyAudioRoute();
      final pc = await _makePc();
      _pc = pc;
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      await _flushIce(pc);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      emitSignal({
        'toUserId': from,
        'kind': 'answer',
        'callId': cid,
        'sdp': answer.sdp,
      });
      phase = CallPhase.connected;
      hint = null;
      notifyListeners();
    } on Object {
      emitSignal({'toUserId': from, 'kind': 'end', 'callId': cid});
      _cleanup(notify: false);
      phase = CallPhase.idle;
      peerId = null;
      error = ctype == 'video'
          ? 'Нет доступа к камере или микрофону'
          : 'Нет доступа к микрофону';
      notifyListeners();
    }
  }

  void rejectIncoming() {
    final p = _pendingOffer;
    if (p != null) {
      emitSignal({
        'toUserId': p['fromUserId'],
        'kind': 'end',
        'callId': p['callId'],
      });
    }
    _pendingOffer = null;
    _cleanup(notify: false);
    phase = CallPhase.idle;
    peerId = null;
    error = null;
    notifyListeners();
  }

  void hangup() {
    final to = _signalTarget ?? peerId;
    final cid = _callId ?? _pendingOffer?['callId'];
    if (to != null) {
      emitSignal({'toUserId': to, 'kind': 'end', 'callId': cid});
    }
    _cleanup(notify: false);
    _pendingOffer = null;
    phase = CallPhase.idle;
    peerId = null;
    error = null;
    notifyListeners();
  }

  Future<void> handleSignal(Map<String, dynamic> payload) async {
    final from = payload['fromUserId']?.toString();
    final kind = payload['kind']?.toString();
    if (from == null || from == currentUserId) return;

    if (kind == 'offer' && payload['sdp'] != null) {
      if (phase != CallPhase.idle) {
        emitSignal({
          'toUserId': from,
          'kind': 'end',
          'callId': payload['callId'],
        });
        return;
      }
      _pendingOffer = {
        'fromUserId': from,
        'callId': payload['callId']?.toString() ?? _genId(),
        'sdp': payload['sdp'].toString(),
        'callType': payload['callType']?.toString() ?? 'audio',
      };
      peerId = from;
      callType = payload['callType']?.toString() ?? 'audio';
      phase = CallPhase.incoming;
      error = null;
      hint = null;
      notifyListeners();
      return;
    }

    if (kind == 'answer' && payload['sdp'] != null) {
      if (payload['callId'] != null && _callId != payload['callId']) return;
      final pc = _pc;
      if (pc == null) return;
      try {
        await pc.setRemoteDescription(
            RTCSessionDescription(payload['sdp'].toString(), 'answer'));
        await _flushIce(pc);
        phase = CallPhase.connected;
        hint = null;
        notifyListeners();
      } on Object {
        hangup();
      }
      return;
    }

    if (kind == 'ice' && payload['candidate'] is Map) {
      final cid = payload['callId'];
      if (cid != null && _callId != cid && _pendingOffer?['callId'] != cid) {
        return;
      }
      final c = (payload['candidate'] as Map).cast<String, dynamic>();
      final candidate = RTCIceCandidate(
        c['candidate']?.toString(),
        c['sdpMid']?.toString(),
        (c['sdpMLineIndex'] as num?)?.toInt(),
      );
      final pc = _pc;
      if (pc != null && await _hasRemote(pc)) {
        try {
          await pc.addCandidate(candidate);
        } on Object {
          // noop
        }
      } else {
        _iceQueue.add(candidate);
      }
      return;
    }

    if (kind == 'end') {
      final cid = payload['callId'];
      if (cid != null && _callId != cid && _pendingOffer?['callId'] != cid) {
        return;
      }
      if (phase == CallPhase.incoming &&
          _pendingOffer?['fromUserId'] == from) {
        _pendingOffer = null;
        phase = CallPhase.idle;
        peerId = null;
        notifyListeners();
        return;
      }
      if (_signalTarget == from || peerId == from) {
        _cleanup(notify: false);
        phase = CallPhase.idle;
        peerId = null;
        notifyListeners();
      }
    }
  }

  Future<bool> _hasRemote(RTCPeerConnection pc) async {
    try {
      final desc = await pc.getRemoteDescription();
      return desc != null;
    } on Object {
      return false;
    }
  }

  Future<void> _flushIce(RTCPeerConnection pc) async {
    final q = List<RTCIceCandidate>.from(_iceQueue);
    _iceQueue.clear();
    for (final c in q) {
      try {
        await pc.addCandidate(c);
      } on Object {
        // noop
      }
    }
  }

  void toggleMic() {
    micMuted = !micMuted;
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      t.enabled = !micMuted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    for (final t in _localStream?.getVideoTracks() ?? const []) {
      t.enabled = !cameraOff;
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    speakerOn = !speakerOn;
    try {
      Helper.setSpeakerphoneOn(speakerOn);
    } on Object {
      // noop
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isNotEmpty) {
      try {
        await Helper.switchCamera(tracks.first);
      } on Object {
        // noop
      }
    }
  }

  void _cleanup({bool notify = true}) {
    _pc?.close();
    _pc = null;
    for (final t in _localStream?.getTracks() ?? const []) {
      t.stop();
    }
    _localStream?.dispose();
    _localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _iceQueue.clear();
    _signalTarget = null;
    _callId = null;
    micMuted = false;
    speakerOn = false;
    cameraOff = false;
    hint = null;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _cleanup(notify: false);
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }

  String _genId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch}-${r.nextInt(1 << 31)}';
  }
}
