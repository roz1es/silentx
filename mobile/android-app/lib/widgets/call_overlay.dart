import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models.dart';
import '../services/call_service.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import 'brenks_avatar.dart';

/// Полноэкранный оверлей активного звонка (поверх всего приложения).
class CallOverlay extends StatelessWidget {
  const CallOverlay({super.key, required this.controller});

  final MessengerController controller;

  ChatParticipant? _peer(String? peerId) {
    if (peerId == null) return null;
    for (final chat in controller.chats) {
      for (final p in chat.participants) {
        if (p.id == peerId) return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final call = controller.call;
    return AnimatedBuilder(
      animation: call,
      builder: (context, _) {
        if (call.phase == CallPhase.idle) return const SizedBox.shrink();
        final peer = _peer(call.peerId);
        final name = peer == null
            ? 'Собеседник'
            : (peer.displayName?.trim().isNotEmpty == true
                ? peer.displayName!.trim()
                : peer.username);
        final isVideo = call.callType == 'video';
        final showRemoteVideo =
            call.phase == CallPhase.connected && call.hasRemoteVideo;

        return Material(
          color: const Color(0xFF0E0F12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Видео собеседника на весь экран (когда есть).
              if (showRemoteVideo)
                RTCVideoView(
                  call.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                _avatarStage(name, peer, call),

              // Своё видео — маленьким окном сверху справа.
              if (isVideo && call.phase != CallPhase.incoming)
                Positioned(
                  top: 50,
                  right: 16,
                  child: GestureDetector(
                    onTap: call.switchCamera,
                    child: Container(
                      width: 104,
                      height: 150,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25)),
                        color: Colors.black,
                      ),
                      child: call.cameraOff
                          ? const Center(
                              child: Icon(Icons.videocam_off_rounded,
                                  color: Colors.white54))
                          : RTCVideoView(
                              call.localRenderer,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                    ),
                  ),
                ),

              // Верхняя плашка статуса.
              Positioned(
                top: 54,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(
                      _statusText(call),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                    if (showRemoteVideo) ...[
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
              ),

              // Нижние кнопки управления.
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: _controls(call),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatarStage(String name, ChatParticipant? peer, CallService call) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2128), Color(0xFF0E0F12)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrenksAvatar(
            title: name,
            imageUrl: peer?.avatarUrl,
            baseUrl: controller.serverUrl,
            size: 132,
          ),
          const SizedBox(height: 20),
          Text(
            name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText(call),
            style: const TextStyle(color: Colors.white60, fontSize: 15),
          ),
          if (call.error != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                call.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: danger, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusText(CallService call) {
    switch (call.phase) {
      case CallPhase.outgoing:
        return call.hint ?? 'Вызов…';
      case CallPhase.incoming:
        return call.callType == 'video'
            ? 'Входящий видеозвонок'
            : 'Входящий звонок';
      case CallPhase.connected:
        if (call.mediaConnected) return _fmtDur(call.elapsed);
        return call.hint ?? 'Соединяем…';
      case CallPhase.idle:
        return '';
    }
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _controls(CallService call) {
    if (call.phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bigButton(
            icon: Icons.call_end_rounded,
            color: danger,
            label: 'Отклонить',
            onTap: call.rejectIncoming,
          ),
          _bigButton(
            icon: Icons.call_rounded,
            color: const Color(0xFF3EB57A),
            label: 'Принять',
            onTap: call.acceptIncoming,
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _smallButton(
              icon: call.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              active: call.micMuted,
              onTap: call.toggleMic,
            ),
            const SizedBox(width: 18),
            _smallButton(
              icon: call.speakerOn
                  ? Icons.volume_up_rounded
                  : Icons.volume_down_rounded,
              active: call.speakerOn,
              onTap: call.toggleSpeaker,
            ),
            const SizedBox(width: 18),
            _smallButton(
              icon: call.callType == 'video' && !call.cameraOff
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              active: call.callType == 'video' && call.cameraOff,
              onTap: call.toggleVideo,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _bigButton(
          icon: Icons.call_end_rounded,
          color: danger,
          label: 'Завершить',
          onTap: call.hangup,
        ),
      ],
    );
  }

  Widget _bigButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 66,
              height: 66,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _smallButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? Colors.white : Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon,
              color: active ? const Color(0xFF0E0F12) : Colors.white, size: 26),
        ),
      ),
    );
  }
}
