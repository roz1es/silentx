import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

type VoiceProps = {
  dataUrl: string;
  durationMs?: number;
  mine: boolean;
};

/** Голосовое в духе Telegram: волна, круглая кнопка play, прогресс */
export function VoiceMessageBar({ dataUrl, durationMs, mine }: VoiceProps) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [dur, setDur] = useState(
    durationMs ? durationMs / 1000 : 0
  );

  const bars = useMemo(
    () => [0.35, 0.55, 0.4, 0.7, 0.5, 0.85, 0.45, 0.6, 0.38, 0.72, 0.48, 0.65],
    []
  );

  const fmt = (s: number) => {
    const x = Math.max(0, s);
    const m = Math.floor(x / 60);
    const sec = Math.floor(x % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  const totalSec =
    dur > 0 ? dur : durationMs ? durationMs / 1000 : 0;
  const remainingSec =
    totalSec > 0 ? Math.max(0, totalSec * (1 - progress)) : 0;

  const toggle = useCallback(() => {
    const a = audioRef.current;
    if (!a) return;
    if (playing) {
      a.pause();
      setPlaying(false);
    } else {
      void a.play();
      setPlaying(true);
    }
  }, [playing]);

  useEffect(() => {
    const a = audioRef.current;
    if (!a) return;
    const onTime = () => {
      if (a.duration && !Number.isNaN(a.duration)) {
        setProgress(a.currentTime / a.duration);
        setDur(a.duration);
      }
    };
    const onEnded = () => {
      setPlaying(false);
      setProgress(0);
      a.currentTime = 0;
    };
    const onMeta = () => {
      if (a.duration && !Number.isNaN(a.duration)) setDur(a.duration);
    };
    a.addEventListener('timeupdate', onTime);
    a.addEventListener('ended', onEnded);
    a.addEventListener('loadedmetadata', onMeta);
    return () => {
      a.removeEventListener('timeupdate', onTime);
      a.removeEventListener('ended', onEnded);
      a.removeEventListener('loadedmetadata', onMeta);
    };
  }, [dataUrl]);

  const bubbleClass = mine
    ? 'bg-[#d4edda] text-slate-800 dark:bg-emerald-900/35 dark:text-emerald-50'
    : 'bg-[#e8f5e9] text-slate-800 dark:bg-slate-700/80 dark:text-slate-100';

  return (
    <div
      className={`flex min-w-[220px] max-w-[280px] items-center gap-2 rounded-[1.35rem] px-2 py-2 pl-2.5 shadow-sm ${bubbleClass}`}
    >
      <audio ref={audioRef} src={dataUrl} preload="metadata" className="hidden" />
      <button
        type="button"
        onClick={toggle}
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white text-tg-accent shadow-md ring-1 ring-black/5 transition hover:scale-[1.03] dark:bg-slate-800 dark:ring-white/10"
        aria-label={playing ? 'Пауза' : 'Воспроизвести'}
      >
        {playing ? (
          <span className="flex gap-0.5">
            <span className="h-3 w-1 rounded-sm bg-current" />
            <span className="h-3 w-1 rounded-sm bg-current" />
          </span>
        ) : (
          <svg viewBox="0 0 24 24" className="ml-0.5 h-5 w-5 fill-current" aria-hidden>
            <path d="M8 5v14l11-7z" />
          </svg>
        )}
      </button>
      <div className="min-w-0 flex-1">
        <div className="flex h-8 items-end justify-between gap-0.5 px-0.5">
          {bars.map((h, i) => (
            <span
              key={i}
              className="w-0.5 rounded-full bg-current opacity-40"
              style={{
                height: `${Math.round(h * 100)}%`,
                opacity: playing ? 0.25 + (i / bars.length) * 0.45 : 0.35,
              }}
            />
          ))}
        </div>
        <div className="mt-1 h-1 overflow-hidden rounded-full bg-black/10 dark:bg-white/15">
          <div
            className="h-full rounded-full bg-tg-accent transition-[width] duration-100 ease-linear"
            style={{ width: `${progress * 100}%` }}
          />
        </div>
      </div>
      <span className="shrink-0 pr-1 font-mono text-[11px] tabular-nums opacity-80">
        {fmt(remainingSec)}
      </span>
    </div>
  );
}

type VideoNoteProps = {
  dataUrl: string;
};

/** Видеокружок: круг, кольцо как в Telegram, кастомный play */
export function VideoNoteCircle({ dataUrl }: VideoNoteProps) {
  const vRef = useRef<HTMLVideoElement | null>(null);
  const [playing, setPlaying] = useState(false);

  const toggle = useCallback(() => {
    const v = vRef.current;
    if (!v) return;
    if (playing) {
      v.pause();
      setPlaying(false);
    } else {
      void v.play();
      setPlaying(true);
    }
  }, [playing]);

  useEffect(() => {
    const v = vRef.current;
    if (!v) return;
    const onEnd = () => setPlaying(false);
    v.addEventListener('ended', onEnd);
    return () => v.removeEventListener('ended', onEnd);
  }, []);

  return (
    <div className="relative mx-auto flex h-52 w-52 items-center justify-center">
      <div className="absolute inset-0 rounded-full bg-gradient-to-br from-tg-accent/25 to-tg-accent/5 blur-md" />
      <div className="relative h-48 w-48 overflow-hidden rounded-full bg-slate-900 shadow-[0_4px_24px_rgba(0,0,0,0.35)] ring-[3px] ring-white/90 dark:ring-slate-400/40">
        <video
          ref={vRef}
          src={dataUrl}
          playsInline
          className="h-full w-full object-cover"
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
        />
        {!playing ? (
          <button
            type="button"
            onClick={toggle}
            className="absolute inset-0 flex items-center justify-center bg-black/25 transition hover:bg-black/35"
            aria-label="Воспроизвести кружок"
          >
            <span className="flex h-14 w-14 items-center justify-center rounded-full bg-white/95 text-tg-accent shadow-lg dark:bg-slate-800/95">
              <svg viewBox="0 0 24 24" className="ml-1 h-7 w-7 fill-current" aria-hidden>
                <path d="M8 5v14l11-7z" />
              </svg>
            </span>
          </button>
        ) : (
          <button
            type="button"
            onClick={toggle}
            className="absolute bottom-2 right-2 flex h-9 w-9 items-center justify-center rounded-full bg-black/50 text-white backdrop-blur-sm"
            aria-label="Пауза"
          >
            <span className="flex gap-0.5">
              <span className="h-3 w-1 rounded-sm bg-white" />
              <span className="h-3 w-1 rounded-sm bg-white" />
            </span>
          </button>
        )}
      </div>
    </div>
  );
}
