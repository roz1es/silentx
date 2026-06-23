import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

type VoiceProps = {
  dataUrl: string;
  durationMs?: number;
  mine: boolean;
};

/** Голосовое в духе Telegram: волна, круглая кнопка play, прогресс */
export function VoiceMessageBar({ dataUrl, durationMs, mine }: VoiceProps) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const progressRef = useRef<HTMLButtonElement | null>(null);
  const fallbackDurationSec =
    Number.isFinite(durationMs) && (durationMs ?? 0) > 0
      ? (durationMs as number) / 1000
      : 0;
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [dur, setDur] = useState(fallbackDurationSec);
  const [speed, setSpeed] = useState<1 | 1.5 | 2>(1);

  const bars = useMemo(
    () => [
      0.38, 0.56, 0.44, 0.72, 0.52, 0.86, 0.46, 0.64, 0.4, 0.76, 0.5,
      0.68, 0.42, 0.82, 0.58, 0.9, 0.48, 0.7, 0.54, 0.78,
    ],
    []
  );

  const fmt = (s: number) => {
    const x = Number.isFinite(s) ? Math.max(0, s) : 0;
    const m = Math.floor(x / 60);
    const sec = Math.floor(x % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  const totalSec = Number.isFinite(dur) && dur > 0 ? dur : fallbackDurationSec;
  const remainingSec =
    totalSec > 0 ? Math.max(0, totalSec * (1 - progress)) : 0;

  const toggle = useCallback(() => {
    const a = audioRef.current;
    if (!a) return;
    if (playing) {
      a.pause();
      setPlaying(false);
    } else {
      void a
        .play()
        .then(() => setPlaying(true))
        .catch(() => setPlaying(false));
    }
  }, [playing]);

  const cycleSpeed = useCallback(() => {
    setSpeed((current) => {
      const next = current === 1 ? 1.5 : current === 1.5 ? 2 : 1;
      if (audioRef.current) audioRef.current.playbackRate = next;
      return next;
    });
  }, []);

  useEffect(() => {
    const a = audioRef.current;
    if (!a) return;
    setDur(fallbackDurationSec);
    setProgress(0);
    const mediaDuration = () =>
      Number.isFinite(a.duration) && a.duration > 0
        ? a.duration
        : fallbackDurationSec;
    const onTime = () => {
      const duration = mediaDuration();
      if (duration > 0 && Number.isFinite(a.currentTime)) {
        setProgress(Math.min(1, Math.max(0, a.currentTime / duration)));
        setDur(duration);
      }
    };
    const onEnded = () => {
      setPlaying(false);
      setProgress(0);
      a.currentTime = 0;
    };
    const onMeta = () => {
      const duration = mediaDuration();
      if (duration > 0) setDur(duration);
    };
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    a.addEventListener('timeupdate', onTime);
    a.addEventListener('ended', onEnded);
    a.addEventListener('loadedmetadata', onMeta);
    a.addEventListener('durationchange', onMeta);
    a.addEventListener('play', onPlay);
    a.addEventListener('pause', onPause);
    return () => {
      a.removeEventListener('timeupdate', onTime);
      a.removeEventListener('ended', onEnded);
      a.removeEventListener('loadedmetadata', onMeta);
      a.removeEventListener('durationchange', onMeta);
      a.removeEventListener('play', onPlay);
      a.removeEventListener('pause', onPause);
    };
  }, [dataUrl, fallbackDurationSec]);

  useEffect(() => {
    if (audioRef.current) audioRef.current.playbackRate = speed;
  }, [speed]);

  const seek = (event: React.PointerEvent<HTMLButtonElement>) => {
    const audio = audioRef.current;
    const track = progressRef.current;
    if (!audio || !track) return;
    const duration =
      Number.isFinite(audio.duration) && audio.duration > 0
        ? audio.duration
        : fallbackDurationSec;
    if (duration <= 0) return;
    const rect = track.getBoundingClientRect();
    const ratio = Math.min(
      1,
      Math.max(0, (event.clientX - rect.left) / rect.width)
    );
    audio.currentTime = duration * ratio;
    setProgress(ratio);
  };

  return (
    <div
      className={`voice-glass flex min-w-[13.25rem] max-w-[min(78vw,20.5rem)] items-center gap-2.5 rounded-[1.45rem] border px-2 py-2 pr-2.5 shadow-[0_12px_30px_rgba(15,23,42,0.10)] backdrop-blur-xl ${
        mine
          ? 'border-sky-200/55 bg-sky-50/62 text-slate-700 dark:border-sky-300/12 dark:bg-slate-700/52 dark:text-slate-100'
          : 'border-white/75 bg-white/68 text-slate-700 dark:border-white/10 dark:bg-zinc-700/58 dark:text-slate-100'
      }`}
    >
      <audio ref={audioRef} src={dataUrl} preload="metadata" className="hidden" />
      <button
        type="button"
        onClick={toggle}
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-white/80 bg-white/85 text-sky-600 shadow-md ring-1 ring-black/5 backdrop-blur-xl transition duration-200 hover:scale-[1.04] hover:bg-white active:scale-95 dark:border-white/10 dark:bg-zinc-800/88 dark:text-sky-300 dark:ring-white/10"
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
        <button
          ref={progressRef}
          type="button"
          onPointerDown={seek}
          className="group/voice relative flex h-8 w-full touch-none items-center gap-[2px] overflow-hidden rounded-lg px-0.5"
          aria-label="Перемотать голосовое"
        >
          {bars.map((h, i) => (
            <span
              key={i}
              className="relative h-full min-w-0 flex-1"
              aria-hidden
            >
              <span
                className="absolute bottom-0 left-0 right-0 rounded-full bg-slate-400/55 transition-colors dark:bg-slate-400/45"
                style={{ height: `${Math.round(h * 100)}%` }}
              />
              <span
                className="absolute bottom-0 left-0 right-0 rounded-full bg-sky-500 transition-[clip-path] duration-75 ease-linear dark:bg-sky-300"
                style={{
                  height: `${Math.round(h * 100)}%`,
                  clipPath:
                    i / bars.length < progress
                      ? 'inset(0 0 0 0)'
                      : 'inset(100% 0 0 0)',
                }}
              />
            </span>
          ))}
          <span
            className="pointer-events-none absolute bottom-0 left-0 top-0 border-r border-sky-500/50 transition-[width] duration-75 ease-linear dark:border-sky-300/45"
            style={{
              width: `${Number.isFinite(progress) ? progress * 100 : 0}%`,
            }}
          />
        </button>
        <div className="mt-1 flex items-center justify-between gap-2">
          <span className="text-[10px] font-semibold text-tg-muted">
            {playing ? 'воспроизведение' : 'голосовое'}
          </span>
          <div className="flex items-center gap-1.5">
            <button
              type="button"
              onClick={cycleSpeed}
              className="rounded-full border border-white/55 bg-white/45 px-2 py-0.5 text-[10px] font-black tabular-nums text-slate-600 transition hover:bg-white/75 dark:border-white/10 dark:bg-white/8 dark:text-slate-200 dark:hover:bg-white/14"
              title="Скорость воспроизведения"
            >
              {speed}x
            </button>
            <span className="font-mono text-[11px] tabular-nums text-tg-muted">
              {fmt(remainingSec)}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

type VideoNoteProps = {
  dataUrl: string;
  size?: 'md' | 'lg';
};

function normalizeMediaDataUrl(dataUrl: string): string {
  return dataUrl.replace(
    /^data:(video\/[^;]+);codecs=[^;]+;base64,/,
    'data:$1;base64,'
  );
}

function dataUrlToObjectUrl(dataUrl: string): string | null {
  const marker = ';base64,';
  const markerIndex = dataUrl.indexOf(marker);
  if (!dataUrl.startsWith('data:') || markerIndex === -1) return null;
  const mime = dataUrl.slice(5, markerIndex).split(';', 1)[0] || 'video/mp4';
  const base64 = dataUrl.slice(markerIndex + marker.length);
  try {
    const binary = window.atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return URL.createObjectURL(new Blob([bytes], { type: mime }));
  } catch {
    return null;
  }
}

/** Видеокружок: круг, кольцо как в Telegram, кастомный play */
export function VideoNoteCircle({ dataUrl, size = 'lg' }: VideoNoteProps) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const vRef = useRef<HTMLVideoElement | null>(null);
  const normalizedDataUrl = useMemo(() => normalizeMediaDataUrl(dataUrl), [dataUrl]);
  const [shouldLoad, setShouldLoad] = useState(false);
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const srcCandidates = useMemo(
    () =>
      shouldLoad
        ? [
            ...new Set(
              [blobUrl, normalizedDataUrl, dataUrl].filter(Boolean) as string[]
            ),
          ]
        : [],
    [blobUrl, dataUrl, normalizedDataUrl, shouldLoad]
  );
  const [srcIndex, setSrcIndex] = useState(0);
  const src = srcCandidates[srcIndex] ?? '';
  const [playing, setPlaying] = useState(false);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const root = rootRef.current;
    if (!root || typeof IntersectionObserver === 'undefined') {
      setShouldLoad(true);
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setShouldLoad(true);
          observer.disconnect();
        }
      },
      { rootMargin: '240px' }
    );
    observer.observe(root);
    return () => observer.disconnect();
  }, []);

  const toggle = useCallback(() => {
    const v = vRef.current;
    if (!v || failed) return;
    if (playing) {
      v.pause();
      setPlaying(false);
    } else {
      v.muted = false;
      v.volume = 1;
      void v
        .play()
        .then(() => setPlaying(true))
        .catch(() => {
          setPlaying(false);
          if (srcIndex + 1 < srcCandidates.length) setSrcIndex((i) => i + 1);
          else setFailed(true);
        });
    }
  }, [failed, playing, srcCandidates.length, srcIndex]);

  useEffect(() => {
    setSrcIndex(0);
    if (!shouldLoad) {
      setBlobUrl(null);
      return;
    }
    const url = dataUrlToObjectUrl(normalizedDataUrl) ?? dataUrlToObjectUrl(dataUrl);
    setBlobUrl(url);
    return () => {
      if (url) URL.revokeObjectURL(url);
    };
  }, [dataUrl, normalizedDataUrl, shouldLoad]);

  useEffect(() => {
    if (!shouldLoad || !src) return;
    setReady(false);
    setFailed(false);
    setPlaying(false);
    const v = vRef.current;
    if (!v) return;
    v.load();
    const onEnd = () => setPlaying(false);
    const onReady = () => setReady(true);
    const onError = () => {
      setPlaying(false);
      if (srcIndex + 1 < srcCandidates.length) setSrcIndex((i) => i + 1);
      else setFailed(true);
    };
    v.addEventListener('ended', onEnd);
    v.addEventListener('loadedmetadata', onReady);
    v.addEventListener('canplay', onReady);
    v.addEventListener('error', onError);
    return () => {
      v.removeEventListener('ended', onEnd);
      v.removeEventListener('loadedmetadata', onReady);
      v.removeEventListener('canplay', onReady);
      v.removeEventListener('error', onError);
    };
  }, [shouldLoad, src, srcCandidates.length, srcIndex]);

  const outerSize = size === 'md' ? 'h-44 w-44' : 'h-52 w-52';
  const innerSize = size === 'md' ? 'h-40 w-40' : 'h-48 w-48';
  const playSize = size === 'md' ? 'h-12 w-12' : 'h-14 w-14';
  const playIconSize = size === 'md' ? 'h-6 w-6' : 'h-7 w-7';

  return (
    <div
      ref={rootRef}
      className={`relative mx-auto flex ${outerSize} items-center justify-center`}
    >
      <div
        className={`absolute inset-0 rounded-full bg-gradient-to-br from-sky-400/25 via-blue-400/10 to-violet-400/20 blur-md transition-all duration-300 ease-out ${
          playing ? 'scale-105 opacity-100' : 'scale-95 opacity-70'
        }`}
      />
      <div
        className={`group relative ${innerSize} overflow-hidden rounded-full bg-transparent shadow-[0_18px_42px_rgba(15,23,42,0.28)] ring-[3px] ring-white/90 transition-transform duration-300 ease-out dark:ring-slate-400/40 ${
          playing ? 'scale-[1.045]' : 'scale-100'
        }`}
      >
        <video
          ref={vRef}
          src={src || undefined}
          playsInline
          preload="metadata"
          className={`h-full w-full cursor-pointer object-cover transition-opacity duration-150 ease-out ${
            ready ? 'opacity-100' : 'opacity-0'
          }`}
          onClick={toggle}
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
        />
        {shouldLoad && !ready && !failed ? (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center text-white">
            <span className="h-8 w-8 animate-spin rounded-full border-2 border-white/55 border-t-white drop-shadow" />
          </div>
        ) : null}
        {!shouldLoad ? (
          <div className="pointer-events-none absolute inset-0 bg-tg-hover/55" />
        ) : null}
        {failed ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-black/62 px-5 text-center text-xs font-semibold text-white">
            <span>Формат кружка не поддерживается этим браузером</span>
            <a
              href={dataUrl}
              download="video-note"
              className="rounded-full bg-white/18 px-3 py-1.5 text-[11px] text-white backdrop-blur transition hover:bg-white/28"
            >
              Скачать
            </a>
          </div>
        ) : null}
        {!playing && !failed && (
          <button
            type="button"
            onClick={toggle}
            className="absolute inset-0 flex items-center justify-center bg-transparent transition"
            aria-label="Воспроизвести кружок"
          >
            <span className={`flex ${playSize} items-center justify-center rounded-full bg-white/95 text-tg-accent shadow-lg shadow-black/15 ring-1 ring-black/5 transition duration-200 hover:scale-105 dark:bg-slate-800/95 dark:ring-white/10`}>
              <svg viewBox="0 0 24 24" className={`ml-1 ${playIconSize} fill-current`} aria-hidden>
                <path d="M8 5v14l11-7z" />
              </svg>
            </span>
          </button>
        )}
        {playing && !failed && (
          <button
            type="button"
            onClick={toggle}
            className="absolute bottom-2 right-2 flex h-9 w-9 items-center justify-center rounded-full bg-black/40 text-white opacity-0 backdrop-blur-sm transition hover:bg-black/60 group-hover:opacity-100"
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

export function VideoNoteCard({ dataUrl }: { dataUrl: string }) {
  return (
    <div className="relative w-[14.75rem] max-w-full overflow-hidden rounded-[1.75rem] border border-slate-300/65 bg-slate-200/75 p-3 shadow-[0_16px_38px_rgba(15,23,42,0.16)] backdrop-blur-md dark:border-white/10 dark:bg-slate-700/55 dark:shadow-[0_18px_44px_rgba(0,0,0,0.26)]">
      <div className="mb-2 flex items-center justify-between gap-2 px-1">
        <div className="min-w-0">
          <p className="truncate text-xs font-bold tracking-wide text-slate-700 dark:text-slate-100">
            БренксЧат
          </p>
          <p className="text-[10px] font-medium uppercase tracking-[0.16em] text-slate-500 dark:text-slate-400">
            видеокружок
          </p>
        </div>
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/55 bg-white/55 text-[13px] font-bold text-slate-600 shadow-sm dark:border-white/10 dark:bg-white/10 dark:text-slate-200">
          B
        </span>
      </div>
      <div className="rounded-[1.45rem] border border-white/55 bg-slate-100/55 py-1.5 shadow-inner dark:border-white/10 dark:bg-slate-900/18">
        <VideoNoteCircle dataUrl={dataUrl} size="md" />
      </div>
    </div>
  );
}
