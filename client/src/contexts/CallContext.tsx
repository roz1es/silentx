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
import { IconPhone, IconVideoCam } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { participantLabel } from '@/lib/userDisplay';

const ICE: RTCConfiguration = {
  iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
};

type Phase = 'idle' | 'outgoing' | 'incoming' | 'connected';

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
  const remoteVideoRef = useRef<HTMLVideoElement | null>(null);
  const remoteAudioRef = useRef<HTMLAudioElement | null>(null);
  const signalTargetRef = useRef<string | null>(null);
  const pendingOfferRef = useRef<{
    fromUserId: string;
    sdp: string;
    callType: 'audio' | 'video';
  } | null>(null);
  const iceQueueRef = useRef<RTCIceCandidateInit[]>([]);
  const phaseRef = useRef<Phase>('idle');
  phaseRef.current = phase;
  const peerIdRef = useRef<string | null>(null);
  peerIdRef.current = peerId;

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

  const cleanupMedia = useCallback(() => {
    pcRef.current?.close();
    pcRef.current = null;
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    localStreamRef.current = null;
    iceQueueRef.current = [];
    signalTargetRef.current = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    const a = remoteAudioRef.current;
    if (a) a.srcObject = null;
  }, []);

  const hangup = useCallback(() => {
    const socket = getSocket();
    const to = signalTargetRef.current ?? peerId;
    if (socket && to) {
      socket.emit('call_signal', { toUserId: to, kind: 'end' });
    }
    cleanupMedia();
    setPhase('idle');
    setPeerId(null);
    pendingOfferRef.current = null;
  }, [getSocket, peerId, cleanupMedia]);

  const attachRemote = useCallback((stream: MediaStream, type: 'audio' | 'video') => {
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
      const pc = new RTCPeerConnection(ICE);
      pc.ontrack = (ev) => {
        const [stream] = ev.streams;
        if (stream) attachRemote(stream, type);
      };
      pc.onicecandidate = (ev) => {
        const socket = getSocket();
        const target = signalTargetRef.current;
        if (ev.candidate && socket && target) {
          socket.emit('call_signal', {
            toUserId: target,
            kind: 'ice',
            candidate: ev.candidate.toJSON(),
          });
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
      signalTargetRef.current = toUserId;
      setCallType(type);
      setPeerId(toUserId);
      setPhase('outgoing');
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: true,
          video: type === 'video',
        });
        localStreamRef.current = stream;
        const pc = makePc(type);
        pcRef.current = pc;
        stream.getTracks().forEach((t) => pc.addTrack(t, stream));
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        socket.emit('call_signal', {
          toUserId,
          kind: 'offer',
          callType: type,
          sdp: offer.sdp,
        });
      } catch {
        hangup();
      }
    },
    [getSocket, cleanupMedia, makePc, hangup]
  );

  const acceptIncoming = useCallback(async () => {
    const pending = pendingOfferRef.current;
    const socket = getSocket();
    if (!pending || !socket) return;
    const { fromUserId, sdp, callType: ctype } = pending;
    pendingOfferRef.current = null;
    cleanupMedia();
    signalTargetRef.current = fromUserId;
    setPeerId(fromUserId);
    setCallType(ctype);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: ctype === 'video',
      });
      localStreamRef.current = stream;
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
        sdp: answer.sdp,
      });
      setPhase('connected');
    } catch {
      hangup();
    }
  }, [getSocket, cleanupMedia, makePc, flushIce, hangup]);

  const rejectIncoming = useCallback(() => {
    const p = pendingOfferRef.current;
    const socket = getSocket();
    if (p && socket) {
      socket.emit('call_signal', { toUserId: p.fromUserId, kind: 'end' });
    }
    pendingOfferRef.current = null;
    cleanupMedia();
    setPhase('idle');
    setPeerId(null);
  }, [getSocket, cleanupMedia]);

  useEffect(() => {
    const socket = getSocket();
    if (!socket) return;

    const onSignal = async (payload: {
      fromUserId: string;
      kind: string;
      callType?: 'audio' | 'video';
      sdp?: string;
      candidate?: RTCIceCandidateInit;
    }) => {
      if (payload.fromUserId === user?.id) return;

      if (payload.kind === 'offer' && payload.sdp) {
        pendingOfferRef.current = {
          fromUserId: payload.fromUserId,
          sdp: payload.sdp,
          callType: payload.callType ?? 'audio',
        };
        setPeerId(payload.fromUserId);
        setCallType(payload.callType ?? 'audio');
        setPhase('incoming');
        return;
      }

      if (payload.kind === 'answer' && payload.sdp) {
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
          phaseRef.current === 'incoming' &&
          pendingOfferRef.current?.fromUserId === payload.fromUserId
        ) {
          pendingOfferRef.current = null;
          setPhase('idle');
          setPeerId(null);
          return;
        }
        if (
          signalTargetRef.current === payload.fromUserId ||
          peerIdRef.current === payload.fromUserId
        ) {
          cleanupMedia();
          setPhase('idle');
          setPeerId(null);
        }
      }
    };

    socket.on('call_signal', onSignal);
    return () => {
      socket.off('call_signal', onSignal);
    };
  }, [getSocket, user?.id, flushIce, hangup, cleanupMedia]);

  useEffect(() => () => cleanupMedia(), [cleanupMedia]);

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

  return (
    <CallContext.Provider value={value}>
      {children}
      <audio ref={remoteAudioRef} className="hidden" playsInline />
      {phase !== 'idle' && user ? (
        <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center bg-gradient-to-b from-slate-900/95 via-slate-950/98 to-black p-4 text-white backdrop-blur-md">
          <div className="mb-2 flex items-center gap-2 text-sm font-medium text-white/70">
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

          <div className="flex w-full max-w-md flex-col items-stretch gap-6 rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl">
            <div className="flex items-center justify-between gap-4">
              <div className="flex min-w-0 flex-1 flex-col items-center gap-2 text-center">
                <UserAvatar
                  username={participantLabel(user)}
                  avatarUrl={user.avatarUrl}
                  size="lg"
                  className="ring-2 ring-white/20"
                />
                <span className="text-[11px] uppercase tracking-wide text-white/50">
                  Вы
                </span>
                <span className="truncate text-sm font-semibold">
                  {participantLabel(user)}
                </span>
              </div>

              <div className="flex shrink-0 flex-col items-center gap-1 px-1">
                <IconPhone className="h-6 w-6 text-white/40" />
                <span className="text-[10px] text-white/35">⟷</span>
              </div>

              <div className="flex min-w-0 flex-1 flex-col items-center gap-2 text-center">
                {peerProfile ? (
                  <>
                    <UserAvatar
                      username={participantLabel(peerProfile)}
                      avatarUrl={peerProfile.avatarUrl}
                      size="lg"
                      className="ring-2 ring-sky-400/50"
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
          </div>

          {callType === 'video' ? (
            <video
              ref={remoteVideoRef}
              autoPlay
              playsInline
              className="mt-4 max-h-[42vh] w-full max-w-md rounded-2xl border border-white/10 bg-black object-cover shadow-xl"
            />
          ) : null}
          <div className="mt-8 flex flex-wrap justify-center gap-4">
            {phase === 'incoming' ? (
              <>
                <button
                  type="button"
                  onClick={() => void acceptIncoming()}
                  className="rounded-full bg-emerald-500 px-8 py-3 text-sm font-semibold shadow-lg shadow-emerald-500/30 transition hover:bg-emerald-400"
                >
                  Принять
                </button>
                <button
                  type="button"
                  onClick={rejectIncoming}
                  className="rounded-full bg-red-500 px-8 py-3 text-sm font-semibold shadow-lg shadow-red-500/25 transition hover:bg-red-400"
                >
                  Отклонить
                </button>
              </>
            ) : (
              <button
                type="button"
                onClick={hangup}
                className="rounded-full bg-red-500 px-10 py-3 text-sm font-semibold shadow-lg shadow-red-500/25 transition hover:bg-red-400"
              >
                Завершить
              </button>
            )}
          </div>
        </div>
      ) : null}
    </CallContext.Provider>
  );
}

export function useCall(): CallCtx {
  const ctx = useContext(CallContext);
  if (!ctx) throw new Error('useCall outside CallProvider');
  return ctx;
}
