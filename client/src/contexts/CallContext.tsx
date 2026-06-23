import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import * as api from '@/lib/api';
import {
  IconMic,
  IconMicOff,
  IconPhone,
  IconVideoCam,
  IconVideoOff,
  IconVolume,
  IconVolumeOff,
} from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { participantLabel } from '@/lib/userDisplay';

const FALLBACK_ICE: RTCConfiguration = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun.cloudflare.com:3478' },
  ],
};

function createCallId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

type Phase = 'idle' | 'outgoing' | 'incoming' | 'connected';
type SpeakingSide = 'local' | 'remote' | 'both' | null;

type CallCtx = {
  phase: Phase;
  peerId: string | null;
  callType: 'audio' | 'video';
  startCall: (peerUserId: string, type: 'audio' | 'video') => Promise<void>;
  acceptIncoming: () => Promise<void>;
  rejectIncoming: () => void;
  hangup: () => void;
  remoteVideoRef: React.RefObject<HTMLVideoElement | null>;
};

const CallContext = createContext<CallCtx | null>(null);

export function CallProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const { getSocket, chats } = useMessenger();

  const [phase, setPhase] = useState<Phase>('idle');
  const [peerId, setPeerId] = useState<string | null>(null);
  const [callType, setCallType] = useState<'audio' | 'video'>('audio');
  const [callError, setCallError] = useState<string | null>(null);
  const [micMuted, setMicMuted] = useState(false);
  const [speakerMuted, setSpeakerMuted] = useState(false);
  const [cameraOff, setCameraOff] = useState(false);
  const [connectionHint, setConnectionHint] = useState<string | null>(null);
  const [localVideoLarge, setLocalVideoLarge] = useState(false);
  const [speakingSide, setSpeakingSide] = useState<SpeakingSide>(null);

  const peerProfile = useMemo(() => {
    if (!peerId) return null;
    for (const c of chats) {
      const p = c.participants?.find((x) => x.id === peerId);
      if (p) return p;
    }
    return {
      id: peerId,
      username: 'user',
      displayName: undefined as string | undefined,
      avatarUrl: undefined as string | undefined,
    };
  }, [chats, peerId]);

  const pcRef = useRef<RTCPeerConnection | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const localVideoRef = useRef<HTMLVideoElement | null>(null);
  const remoteVideoRef = useRef<HTMLVideoElement | null>(null);
  const remoteAudioRef = useRef<HTMLAudioElement | null>(null);
  const audioLevelContextRef = useRef<AudioContext | null>(null);
  const audioLevelFrameRef = useRef<number | null>(null);
  const audioLevelSourcesRef = useRef<
    Partial<
      Record<
        Exclude<SpeakingSide, null | 'both'>,
        {
          analyser: AnalyserNode;
          data: Uint8Array<ArrayBuffer>;
          source: MediaStreamAudioSourceNode;
        }
      >
    >
  >({});
  const speakingSideRef = useRef<SpeakingSide>(null);
  const signalTargetRef = useRef<string | null>(null);
  const pendingOfferRef = useRef<{
    fromUserId: string;
    callId: string;
    sdp: string;
    callType: 'audio' | 'video';
  } | null>(null);
  const callIdRef = useRef<string | null>(null);
  const iceConfigRef = useRef<RTCConfiguration>(FALLBACK_ICE);
  const iceQueueRef = useRef<RTCIceCandidateInit[]>([]);
  const phaseRef = useRef<Phase>('idle');
  phaseRef.current = phase;
  const peerIdRef = useRef<string | null>(null);
  peerIdRef.current = peerId;

  const refreshIceConfig = useCallback(async () => {
    try {
      const { iceServers } = await api.fetchCallIceServers();
      if (iceServers.length) {
        iceConfigRef.current = { iceServers };
      }
    } catch {
      iceConfigRef.current = FALLBACK_ICE;
    }
    return iceConfigRef.current;
  }, []);

  const flushIce = useCallback(async (pc: RTCPeerConnection) => {
    const q = iceQueueRef.current;
    iceQueueRef.current = [];
    for (const c of q) {
      try {
        await pc.addIceCandidate(c);
      } catch {
        /* noop */
      }
    }
  }, []);

  const stopAudioLevelMonitors = useCallback(() => {
    if (audioLevelFrameRef.current !== null) {
      cancelAnimationFrame(audioLevelFrameRef.current);
      audioLevelFrameRef.current = null;
    }
    Object.values(audioLevelSourcesRef.current).forEach((entry) => {
      try {
        entry?.source.disconnect();
      } catch {
        /* noop */
      }
    });
    audioLevelSourcesRef.current = {};
    const ctx = audioLevelContextRef.current;
    audioLevelContextRef.current = null;
    if (ctx && ctx.state !== 'closed') {
      void ctx.close().catch(() => {});
    }
    speakingSideRef.current = null;
    setSpeakingSide(null);
  }, []);

  const startAudioLevelMonitor = useCallback(
    (side: Exclude<SpeakingSide, null | 'both'>, stream: MediaStream) => {
      const tracks = stream.getAudioTracks();
      if (!tracks.length || typeof window === 'undefined') return;
      const AudioCtor =
        window.AudioContext ??
        (window as unknown as { webkitAudioContext?: typeof AudioContext })
          .webkitAudioContext;
      if (!AudioCtor) return;

      try {
        const ctx = audioLevelContextRef.current ?? new AudioCtor();
        audioLevelContextRef.current = ctx;
        if (ctx.state === 'suspended') {
          void ctx.resume().catch(() => {});
        }

        const previous = audioLevelSourcesRef.current[side];
        if (previous) {
          try {
            previous.source.disconnect();
          } catch {
            /* noop */
          }
        }

        const source = ctx.createMediaStreamSource(new MediaStream(tracks));
        const analyser = ctx.createAnalyser();
        analyser.fftSize = 512;
        analyser.smoothingTimeConstant = 0.72;
        source.connect(analyser);
        audioLevelSourcesRef.current[side] = {
          analyser,
          data: new Uint8Array(new ArrayBuffer(analyser.fftSize)),
          source,
        };

        if (audioLevelFrameRef.current !== null) return;

        const readLevel = (entry?: {
          analyser: AnalyserNode;
          data: Uint8Array<ArrayBuffer>;
        }) => {
          if (!entry) return 0;
          entry.analyser.getByteTimeDomainData(entry.data);
          let sum = 0;
          for (let i = 0; i < entry.data.length; i += 1) {
            const value = (entry.data[i] - 128) / 128;
            sum += value * value;
          }
          return Math.sqrt(sum / entry.data.length);
        };

        const tick = () => {
          const local = readLevel(audioLevelSourcesRef.current.local);
          const remote = readLevel(audioLevelSourcesRef.current.remote);
          const localActive = local > 0.045;
          const remoteActive = remote > 0.045;
          const next: SpeakingSide =
            localActive && remoteActive
              ? 'both'
              : localActive
                ? 'local'
                : remoteActive
                  ? 'remote'
                  : null;
          if (speakingSideRef.current !== next) {
            speakingSideRef.current = next;
            setSpeakingSide(next);
          }
          audioLevelFrameRef.current = requestAnimationFrame(tick);
        };

        audioLevelFrameRef.current = requestAnimationFrame(tick);
      } catch {
        /* Подсветка говорящего не должна ломать сам звонок. */
      }
    },
    []
  );

  const cleanupMedia = useCallback(() => {
    pcRef.current?.close();
    pcRef.current = null;
    stopAudioLevelMonitors();
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    localStreamRef.current = null;
    iceQueueRef.current = [];
    signalTargetRef.current = null;
    callIdRef.current = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    const a = remoteAudioRef.current;
    if (a) a.srcObject = null;
    setMicMuted(false);
    setSpeakerMuted(false);
    setCameraOff(false);
    setConnectionHint(null);
    setLocalVideoLarge(false);
  }, [stopAudioLevelMonitors]);

  const hangup = useCallback(() => {
    const socket = getSocket();
    const to = signalTargetRef.current ?? peerId;
    const callId = callIdRef.current ?? pendingOfferRef.current?.callId;
    if (socket && to) {
      socket.emit('call_signal', { toUserId: to, kind: 'end', callId });
    }
    cleanupMedia();
    setPhase('idle');
    setPeerId(null);
    setCallError(null);
    pendingOfferRef.current = null;
  }, [getSocket, peerId, cleanupMedia]);

  const attachRemote = useCallback((stream: MediaStream, type: 'audio' | 'video') => {
    startAudioLevelMonitor('remote', stream);
    const v = remoteVideoRef.current;
    const a = remoteAudioRef.current;
    if (type === 'video' && v) {
      v.srcObject = stream;
      void v.play().catch(() => {});
    } else if (a) {
      a.srcObject = stream;
      void a.play().catch(() => {});
    }
  }, []);

  const makePc = useCallback(
    (type: 'audio' | 'video') => {
      const pc = new RTCPeerConnection(iceConfigRef.current);
      pc.ontrack = (ev) => {
        const [stream] = ev.streams;
        if (stream) attachRemote(stream, type);
      };
      pc.onicecandidate = (ev) => {
        const socket = getSocket();
        const target = signalTargetRef.current;
        const callId = callIdRef.current;
        if (ev.candidate && socket && target) {
          socket.emit('call_signal', {
            toUserId: target,
            kind: 'ice',
            callId,
            candidate: ev.candidate.toJSON(),
          });
        }
      };
      pc.onconnectionstatechange = () => {
        if (pc.connectionState === 'connecting') {
          setConnectionHint('Соединяем…');
        }
        if (pc.connectionState === 'connected') {
          setConnectionHint(null);
          setCallError(null);
        }
        if (pc.connectionState === 'disconnected') {
          setConnectionHint('Пробуем восстановить соединение…');
        }
        if (pc.connectionState === 'failed') {
          setConnectionHint(null);
          setCallError('Соединение оборвалось. Попробуйте перезвонить.');
        }
        if (pc.connectionState === 'closed') {
          setPhase((cur) => (cur === 'connected' ? 'idle' : cur));
        }
      };
      pc.oniceconnectionstatechange = () => {
        if (pc.iceConnectionState === 'checking') {
          setConnectionHint('Проверяем маршрут звонка…');
        }
        if (
          pc.iceConnectionState === 'connected' ||
          pc.iceConnectionState === 'completed'
        ) {
          setConnectionHint(null);
          setCallError(null);
        }
        if (pc.iceConnectionState === 'disconnected') {
          setConnectionHint('Пробуем восстановить звонок…');
        }
        if (pc.iceConnectionState === 'failed') {
          setConnectionHint(null);
          setCallError('Не удалось установить соединение. Попробуйте ещё раз.');
        }
      };
      return pc;
    },
    [getSocket, attachRemote]
  );

  const startCall = useCallback(
    async (toUserId: string, type: 'audio' | 'video') => {
      const socket = getSocket();
      if (!socket) return;
      cleanupMedia();
      const callId = createCallId();
      callIdRef.current = callId;
      signalTargetRef.current = toUserId;
      setCallType(type);
      setPeerId(toUserId);
      setPhase('outgoing');
      setCallError(null);
      setConnectionHint('Соединяем…');
      try {
        await refreshIceConfig();
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
          video: type === 'video',
        });
        localStreamRef.current = stream;
        startAudioLevelMonitor('local', stream);
        requestAnimationFrame(() => {
          if (type !== 'video' || !localVideoRef.current) return;
          localVideoRef.current.srcObject = stream;
          void localVideoRef.current.play().catch(() => {});
        });
        const pc = makePc(type);
        pcRef.current = pc;
        stream.getTracks().forEach((t) => pc.addTrack(t, stream));
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        socket.emit('call_signal', {
          toUserId,
          kind: 'offer',
          callId,
          callType: type,
          sdp: offer.sdp,
        });
      } catch {
        const socket = getSocket();
        if (socket) {
          socket.emit('call_signal', { toUserId, kind: 'end', callId });
        }
        cleanupMedia();
        setCallError(
          type === 'video'
            ? 'Нет доступа к камере или микрофону'
            : 'Нет доступа к микрофону'
        );
      }
    },
    [getSocket, cleanupMedia, makePc, refreshIceConfig, startAudioLevelMonitor]
  );

  const acceptIncoming = useCallback(async () => {
    const pending = pendingOfferRef.current;
    const socket = getSocket();
    if (!pending || !socket) return;
    const { fromUserId, callId, sdp, callType: ctype } = pending;
    pendingOfferRef.current = null;
    const queuedIce = iceQueueRef.current.filter((candidate) => candidate);
    cleanupMedia();
    iceQueueRef.current = queuedIce;
    callIdRef.current = callId;
    signalTargetRef.current = fromUserId;
    setPeerId(fromUserId);
    setCallType(ctype);
    setCallError(null);
    setConnectionHint('Соединяем…');
    try {
      await refreshIceConfig();
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: ctype === 'video',
      });
      localStreamRef.current = stream;
      startAudioLevelMonitor('local', stream);
      requestAnimationFrame(() => {
        if (ctype !== 'video' || !localVideoRef.current) return;
        localVideoRef.current.srcObject = stream;
        void localVideoRef.current.play().catch(() => {});
      });
      const pc = makePc(ctype);
      pcRef.current = pc;
      stream.getTracks().forEach((t) => pc.addTrack(t, stream));
      await pc.setRemoteDescription({ type: 'offer', sdp });
      await flushIce(pc);
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      socket.emit('call_signal', {
        toUserId: fromUserId,
        kind: 'answer',
        callId,
        sdp: answer.sdp,
      });
      setPhase('connected');
    } catch {
      const socket = getSocket();
      if (socket) {
        socket.emit('call_signal', { toUserId: fromUserId, kind: 'end', callId });
      }
      cleanupMedia();
      setCallError(
        ctype === 'video'
          ? 'Нет доступа к камере или микрофону'
          : 'Нет доступа к микрофону'
      );
      setConnectionHint(null);
    }
  }, [
    getSocket,
    cleanupMedia,
    makePc,
    refreshIceConfig,
    flushIce,
    startAudioLevelMonitor,
  ]);

  const rejectIncoming = useCallback(() => {
    const p = pendingOfferRef.current;
    const socket = getSocket();
    if (p && socket) {
      socket.emit('call_signal', {
        toUserId: p.fromUserId,
        kind: 'end',
        callId: p.callId,
      });
    }
    pendingOfferRef.current = null;
    cleanupMedia();
    setPhase('idle');
    setPeerId(null);
    setCallError(null);
  }, [getSocket, cleanupMedia]);

  useEffect(() => {
    const socket = getSocket();
    if (!socket) return;

    const onSignal = async (payload: {
      fromUserId: string;
      kind: string;
      callId?: string;
      callType?: 'audio' | 'video';
      sdp?: string;
      candidate?: RTCIceCandidateInit;
    }) => {
      if (payload.fromUserId === user?.id) return;

      if (payload.kind === 'offer' && payload.sdp) {
        if (phaseRef.current !== 'idle') {
          socket.emit('call_signal', {
            toUserId: payload.fromUserId,
            kind: 'end',
            callId: payload.callId,
          });
          return;
        }
        pendingOfferRef.current = {
          fromUserId: payload.fromUserId,
          callId: payload.callId ?? createCallId(),
          sdp: payload.sdp,
          callType: payload.callType ?? 'audio',
        };
        setPeerId(payload.fromUserId);
        setCallType(payload.callType ?? 'audio');
        setPhase('incoming');
        setCallError(null);
        setConnectionHint(null);
        if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
          navigator.vibrate?.([220, 120, 220]);
        }
        if (
          typeof Notification !== 'undefined' &&
          Notification.permission === 'granted'
        ) {
          let name = 'БренксЧат';
          for (const chat of chats) {
            const p = chat.participants?.find((x) => x.id === payload.fromUserId);
            if (p) {
              name = participantLabel(p);
              break;
            }
          }
          new Notification('Входящий звонок БренксЧат', {
            body: `${name} звонит вам`,
            icon: '/icon-192.png',
            tag: `call-${payload.fromUserId}`,
          });
        }
        return;
      }

      if (payload.kind === 'answer' && payload.sdp) {
        if (payload.callId && callIdRef.current !== payload.callId) return;
        const pc = pcRef.current;
        if (!pc) return;
        try {
          await pc.setRemoteDescription({ type: 'answer', sdp: payload.sdp });
          await flushIce(pc);
          setPhase('connected');
        } catch {
          hangup();
        }
        return;
      }

      if (payload.kind === 'ice' && payload.candidate) {
        if (
          payload.callId &&
          callIdRef.current !== payload.callId &&
          pendingOfferRef.current?.callId !== payload.callId
        ) {
          return;
        }
        const pc = pcRef.current;
        if (pc?.remoteDescription) {
          try {
            await pc.addIceCandidate(payload.candidate);
          } catch {
            /* noop */
          }
        } else {
          iceQueueRef.current.push(payload.candidate);
        }
        return;
      }

      if (payload.kind === 'end') {
        if (
          payload.callId &&
          callIdRef.current !== payload.callId &&
          pendingOfferRef.current?.callId !== payload.callId
        ) {
          return;
        }
        if (
          phaseRef.current === 'incoming' &&
          pendingOfferRef.current?.fromUserId === payload.fromUserId
        ) {
          pendingOfferRef.current = null;
          setPhase('idle');
          setPeerId(null);
          setCallError(null);
          setConnectionHint(null);
          return;
        }
        if (
          signalTargetRef.current === payload.fromUserId ||
          peerIdRef.current === payload.fromUserId
        ) {
          cleanupMedia();
          setPhase('idle');
          setPeerId(null);
          setCallError(null);
          setConnectionHint(null);
        }
      }
    };

    socket.on('call_signal', onSignal);
    return () => {
      socket.off('call_signal', onSignal);
    };
  }, [getSocket, user?.id, chats, flushIce, hangup, cleanupMedia]);

  useEffect(() => () => cleanupMedia(), [cleanupMedia]);

  useEffect(() => {
    if (remoteAudioRef.current) remoteAudioRef.current.muted = speakerMuted;
    if (remoteVideoRef.current) remoteVideoRef.current.muted = speakerMuted;
  }, [speakerMuted]);

  const toggleMic = useCallback(() => {
    setMicMuted((cur) => {
      const next = !cur;
      localStreamRef.current
        ?.getAudioTracks()
        .forEach((track) => {
          track.enabled = !next;
        });
      return next;
    });
  }, [startAudioLevelMonitor]);

  const toggleSpeaker = useCallback(() => {
    setSpeakerMuted((cur) => !cur);
  }, []);

  const toggleCamera = useCallback(() => {
    setCameraOff((cur) => {
      const next = !cur;
      localStreamRef.current
        ?.getVideoTracks()
        .forEach((track) => {
          track.enabled = !next;
        });
      return next;
    });
  }, []);

  const value: CallCtx = {
    phase,
    peerId,
    callType,
    startCall,
    acceptIncoming,
    rejectIncoming,
    hangup,
    remoteVideoRef,
  };

  const localSpeaking =
    speakingSide === 'local' || speakingSide === 'both';
  const remoteSpeaking =
    speakingSide === 'remote' || speakingSide === 'both';

  return (
    <CallContext.Provider value={value}>
      {children}
      <audio ref={remoteAudioRef} className="hidden" playsInline />
      {phase !== 'idle' && user ? (
        <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center overflow-hidden bg-[radial-gradient(circle_at_50%_0%,rgba(56,189,248,0.22),transparent_42%),linear-gradient(180deg,rgba(24,28,36,0.98),rgba(10,12,16,0.99))] p-4 text-white backdrop-blur-md">
          <div className="mb-4 flex items-center gap-2 rounded-full border border-white/10 bg-white/8 px-3 py-1.5 text-sm font-medium text-white/76 shadow-lg backdrop-blur-xl">
            {callType === 'video' ? (
              <IconVideoCam className="h-5 w-5 shrink-0 text-sky-400" />
            ) : (
              <IconPhone className="h-5 w-5 shrink-0 text-emerald-400" />
            )}
            <span>
              {phase === 'incoming'
                ? 'Входящий звонок'
                : phase === 'outgoing'
                  ? 'Исходящий вызов'
                  : callType === 'video'
                    ? 'Видеозвонок'
                    : 'Аудиозвонок'}
            </span>
          </div>

          <div className="flex w-full max-w-md flex-col items-stretch gap-6 rounded-[2rem] border border-white/10 bg-white/[0.07] p-6 shadow-2xl shadow-black/35 ring-1 ring-white/5 backdrop-blur-2xl">
            <div className="flex items-center justify-between gap-4">
              <div className="flex min-w-0 flex-1 flex-col items-center gap-2 text-center">
                <UserAvatar
                  username={participantLabel(user)}
                  avatarUrl={user.avatarUrl}
                  size="lg"
                  className={`transition duration-300 ${
                    localSpeaking
                      ? 'ring-4 ring-emerald-300/80 shadow-[0_0_30px_rgba(52,211,153,0.35)]'
                      : 'ring-2 ring-white/20'
                  }`}
                />
                <span className="text-[11px] uppercase tracking-wide text-white/50">
                  Вы
                </span>
                <span className="truncate text-sm font-semibold">
                  {participantLabel(user)}
                </span>
              </div>

              <div className="flex shrink-0 flex-col items-center gap-1 px-1">
                <span className="flex h-12 w-12 items-center justify-center rounded-full border border-white/10 bg-white/8 text-white/55 shadow-inner">
                  {callType === 'video' ? (
                    <IconVideoCam className="h-5 w-5" />
                  ) : (
                    <IconPhone className="h-5 w-5" />
                  )}
                </span>
                <span className="text-[10px] text-white/35">BrenksCall</span>
              </div>

              <div className="flex min-w-0 flex-1 flex-col items-center gap-2 text-center">
                {peerProfile ? (
                  <>
                    <UserAvatar
                      username={participantLabel(peerProfile)}
                      avatarUrl={peerProfile.avatarUrl}
                      size="lg"
                      className={`transition duration-300 ${
                        remoteSpeaking
                          ? 'ring-4 ring-sky-300/85 shadow-[0_0_30px_rgba(56,189,248,0.36)]'
                          : 'ring-2 ring-sky-400/50'
                      }`}
                    />
                    <span className="text-[11px] uppercase tracking-wide text-white/50">
                      {phase === 'incoming' ? 'Звонит' : 'Абонент'}
                    </span>
                    <span className="truncate text-sm font-semibold text-sky-100">
                      {participantLabel(peerProfile)}
                    </span>
                    <span className="truncate text-xs text-white/45">
                      @{peerProfile.username}
                    </span>
                  </>
                ) : (
                  <p className="text-sm text-white/60">…</p>
                )}
              </div>
            </div>

            <p className="text-center text-xs text-white/55">
              {phase === 'incoming'
                ? `${peerProfile ? participantLabel(peerProfile) : 'Собеседник'} звонит вам`
                : phase === 'outgoing'
                  ? `Звонок ${peerProfile ? participantLabel(peerProfile) : '…'}`
                  : 'Соединение установлено'}
            </p>
            {callError ? (
              <p className="rounded-2xl border border-red-400/20 bg-red-500/10 px-3 py-2 text-center text-xs font-medium text-red-100">
                {callError}
              </p>
            ) : null}
            {connectionHint && !callError ? (
              <p className="rounded-2xl border border-sky-300/15 bg-sky-400/10 px-3 py-2 text-center text-xs font-medium text-sky-100">
                {connectionHint}
              </p>
            ) : null}
          </div>

          {callType === 'video' ? (
            <div className="relative mt-4 w-full max-w-md">
              <video
                ref={remoteVideoRef}
                autoPlay
                playsInline
                onClick={() => setLocalVideoLarge(false)}
                className={`max-h-[42vh] min-h-48 w-full rounded-[1.6rem] border bg-black object-cover shadow-xl transition duration-300 ${
                  remoteSpeaking
                    ? 'border-sky-300/80 shadow-[0_0_34px_rgba(56,189,248,0.28)]'
                    : 'border-white/10'
                } ${
                  localVideoLarge ? 'opacity-70 scale-[0.985]' : 'opacity-100 scale-100'
                }`}
              />
              <video
                ref={localVideoRef}
                autoPlay
                muted
                playsInline
                onClick={() => setLocalVideoLarge((value) => !value)}
                className={`absolute cursor-pointer border bg-black object-cover shadow-xl transition-all duration-300 ${
                  localSpeaking
                    ? 'border-emerald-300/85 shadow-[0_0_28px_rgba(52,211,153,0.30)]'
                    : 'border-white/20'
                } ${
                  localVideoLarge
                    ? 'inset-0 h-full w-full rounded-[1.6rem]'
                    : 'bottom-3 right-3 h-24 w-16 rounded-2xl sm:h-28 sm:w-20'
                }`}
              />
              <p className="pointer-events-none absolute bottom-3 left-3 rounded-full bg-black/40 px-3 py-1 text-[11px] font-semibold text-white/80 backdrop-blur">
                Нажмите на своё видео, чтобы увеличить
              </p>
            </div>
          ) : null}
          <div className="mt-6 flex flex-wrap items-center justify-center gap-3 rounded-[1.7rem] border border-white/10 bg-white/[0.07] p-3 shadow-2xl shadow-black/25 backdrop-blur-2xl">
            {phase === 'incoming' ? (
              <>
                <button
                  type="button"
                  onClick={() => void acceptIncoming()}
                  className="flex h-12 min-w-32 items-center justify-center gap-2 rounded-full bg-emerald-500 px-7 py-3 text-sm font-semibold shadow-lg shadow-emerald-500/30 transition hover:bg-emerald-400"
                >
                  <IconPhone className="h-4 w-4" />
                  Принять
                </button>
                <button
                  type="button"
                  onClick={rejectIncoming}
                  className="flex h-12 min-w-32 items-center justify-center gap-2 rounded-full bg-red-500 px-7 py-3 text-sm font-semibold shadow-lg shadow-red-500/25 transition hover:bg-red-400"
                >
                  Отклонить
                </button>
              </>
            ) : (
              <>
                <CallControlButton
                  active={micMuted}
                  label={micMuted ? 'Микрофон выкл.' : 'Микрофон'}
                  onClick={toggleMic}
                >
                  {micMuted ? (
                    <IconMicOff className="h-5 w-5" />
                  ) : (
                    <IconMic className="h-5 w-5" />
                  )}
                </CallControlButton>
                <CallControlButton
                  active={speakerMuted}
                  label={speakerMuted ? 'Звук выкл.' : 'Звук'}
                  onClick={toggleSpeaker}
                >
                  {speakerMuted ? (
                    <IconVolumeOff className="h-5 w-5" />
                  ) : (
                    <IconVolume className="h-5 w-5" />
                  )}
                </CallControlButton>
                {callType === 'video' ? (
                  <CallControlButton
                    active={cameraOff}
                    label={cameraOff ? 'Камера выкл.' : 'Камера'}
                    onClick={toggleCamera}
                  >
                    {cameraOff ? (
                      <IconVideoOff className="h-5 w-5" />
                    ) : (
                      <IconVideoCam className="h-5 w-5" />
                    )}
                  </CallControlButton>
                ) : null}
                <button
                  type="button"
                  onClick={hangup}
                  className="flex h-14 min-w-32 items-center justify-center gap-2 rounded-full bg-red-500 px-7 text-sm font-semibold shadow-lg shadow-red-500/25 transition hover:bg-red-400 active:scale-95"
                >
                  Завершить
                </button>
              </>
            )}
          </div>
        </div>
      ) : null}
    </CallContext.Provider>
  );
}

function CallControlButton({
  active,
  label,
  children,
  onClick,
}: {
  active: boolean;
  label: string;
  children: ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex h-14 w-20 flex-col items-center justify-center gap-1 rounded-2xl border text-[11px] font-semibold transition active:scale-95 ${
        active
          ? 'border-red-300/30 bg-red-500/18 text-red-100 shadow-lg shadow-red-500/10'
          : 'border-white/10 bg-white/10 text-white/82 hover:bg-white/16'
      }`}
    >
      {children}
      <span className="max-w-full truncate px-1">{label}</span>
    </button>
  );
}

export function useCall(): CallCtx {
  const ctx = useContext(CallContext);
  if (!ctx) throw new Error('useCall outside CallProvider');
  return ctx;
}
