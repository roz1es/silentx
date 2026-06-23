import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import type { MessageMedia } from '@/types';
import { EmojiPicker } from '@/components/EmojiPicker';
import {
  IconClose,
  IconMic,
  IconPaperclip,
  IconSend,
  IconVideoCircle,
} from '@/components/icons';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';

const MAX_BYTES = 12 * 1024 * 1024;
const MAX_MEDIA_DATA_URL_LEN = 13_500_000;

function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(new Error('read'));
    r.readAsDataURL(file);
  });
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(new Error('read'));
    r.readAsDataURL(blob);
  });
}

function baseMimeType(mime: string): string {
  return mime.split(';', 1)[0]?.trim() || mime;
}

function pickAudioMime(): string {
  if (typeof MediaRecorder === 'undefined') return '';
  // Safari чаще всего поддерживает MediaRecorder только для MP4/AAC,
  // а Chromium/Firefox — для WebM/Opus. Держим оба варианта.
  const types = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/mp4;codecs=mp4a.40.2',
    'audio/mp4',
    'audio/aac',
  ];
  for (const t of types) {
    if (MediaRecorder.isTypeSupported?.(t)) return t;
  }
  return '';
}

function pickVideoMime(): string {
  if (typeof MediaRecorder === 'undefined') return '';
  const mp4Types = [
    'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
    'video/mp4;codecs=avc1.42E01E',
    'video/mp4',
  ];
  const webmTypes = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
  ];
  const ua = navigator.userAgent;
  const safariLike = /^((?!chrome|chromium|android|edg|opr|firefox).)*safari/i.test(ua);
  const types = safariLike ? [...mp4Types, ...webmTypes] : [...webmTypes, ...mp4Types];
  for (const t of types) {
    if (MediaRecorder.isTypeSupported?.(t)) return t;
  }
  return '';
}

function createRecorder(
  stream: MediaStream,
  mime: string,
  kind: 'voice' | 'video'
): MediaRecorder {
  const bitrate: MediaRecorderOptions =
    kind === 'video'
      ? { videoBitsPerSecond: 650_000, audioBitsPerSecond: 64_000 }
      : { audioBitsPerSecond: 64_000 };
  const opts: MediaRecorderOptions = mime ? { mimeType: mime, ...bitrate } : bitrate;
  try {
    return new MediaRecorder(stream, opts);
  } catch {
    try {
      return new MediaRecorder(stream, bitrate);
    } catch {
      return new MediaRecorder(stream);
    }
  }
}

function formatRecTime(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

const recordingWaveScales = [
  0.42, 0.72, 0.5, 0.86, 0.58, 0.96, 0.48, 0.78, 0.62, 0.9, 0.55, 1, 0.7,
  0.46, 0.84, 0.6, 0.94, 0.52, 0.76, 0.66, 0.88, 0.56,
];

function waveStyle(index: number, duration = 980) {
  const scale = recordingWaveScales[index % recordingWaveScales.length];
  return {
    '--wave-scale': scale.toString(),
    animationDelay: `${index * -52}ms`,
    animationDuration: `${duration + (index % 5) * 34}ms`,
  } as React.CSSProperties & Record<'--wave-scale', string>;
}

function draftStorageKey(userId: string): string {
  return `brenkschat:drafts:${userId}`;
}

function readDraft(userId: string, chatId: string): string {
  try {
    const raw = window.localStorage.getItem(draftStorageKey(userId));
    if (!raw) return '';
    const parsed = JSON.parse(raw) as Record<string, string>;
    return typeof parsed[chatId] === 'string' ? parsed[chatId] : '';
  } catch {
    return '';
  }
}

function writeDraft(userId: string, chatId: string, text: string): void {
  try {
    const key = draftStorageKey(userId);
    const raw = window.localStorage.getItem(key);
    const parsed = raw ? (JSON.parse(raw) as Record<string, string>) : {};
    if (text.trim()) parsed[chatId] = text;
    else delete parsed[chatId];
    window.localStorage.setItem(key, JSON.stringify(parsed));
  } catch {
    /* localStorage may be blocked */
  }
}

export function MessageInput() {
  const { user } = useAuth();
  const {
    sendPayload,
    notifyTyping,
    activeChat,
    messages,
    replyTarget,
    clearReply,
    editTarget,
    setEditTarget,
    clearEdit,
    editMessage,
  } = useMessenger();
  const [text, setText] = useState('');
  const [dragOver, setDragOver] = useState(false);
  const [rec, setRec] = useState<'idle' | 'voice' | 'video'>('idle');
  const [quickMedia, setQuickMedia] = useState<'voice' | 'video'>('voice');
  const [recError, setRecError] = useState<string | null>(null);
  const [recElapsedMs, setRecElapsedMs] = useState(0);
  const [videoPreviewReady, setVideoPreviewReady] = useState(false);
  const typingSent = useRef(false);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const recorderMimeRef = useRef('');
  const chunksRef = useRef<Blob[]>([]);
  const videoPreviewRef = useRef<HTMLVideoElement | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const startedAtRef = useRef(0);
  const loadingDraftRef = useRef(false);
  const draftBeforeEditRef = useRef('');
  const activeChatId = activeChat?.id ?? null;

  const stopStreams = useCallback(() => {
    mediaStreamRef.current?.getTracks().forEach((t) => t.stop());
    mediaStreamRef.current = null;
    recorderRef.current = null;
    recorderMimeRef.current = '';
    chunksRef.current = [];
  }, []);

  useEffect(() => () => stopStreams(), [stopStreams]);

  useEffect(() => {
    if (rec === 'idle') {
      setRecElapsedMs(0);
      setVideoPreviewReady(false);
      return;
    }
    const tick = () => setRecElapsedMs(Date.now() - startedAtRef.current);
    tick();
    const id = window.setInterval(tick, 250);
    return () => window.clearInterval(id);
  }, [rec]);

  useEffect(() => {
    if (rec !== 'video') return;
    const video = videoPreviewRef.current;
    const stream = mediaStreamRef.current;
    if (!video || !stream) return;
    setVideoPreviewReady(false);
    video.srcObject = stream;
    video.muted = true;
    video.autoplay = true;
    video.playsInline = true;
    void video.play().catch(() => {
      setRecError('Не удалось показать камеру. Проверьте разрешение браузера.');
    });
    return () => {
      if (video.srcObject === stream) video.srcObject = null;
    };
  }, [rec]);

  const INPUT_MAX_PX = 92;

  useEffect(() => {
    loadingDraftRef.current = true;
    setText(user && activeChatId ? readDraft(user.id, activeChatId) : '');
    const id = window.requestAnimationFrame(() => {
      loadingDraftRef.current = false;
    });
    return () => window.cancelAnimationFrame(id);
  }, [activeChatId, user?.id]);

  useEffect(() => {
    if (
      !user ||
      !activeChatId ||
      loadingDraftRef.current ||
      editTarget
    ) {
      return;
    }
    writeDraft(user.id, activeChatId, text);
  }, [text, activeChatId, user?.id, editTarget]);

  const focusComposer = useCallback(() => {
    window.requestAnimationFrame(() => {
      const el = textareaRef.current;
      if (!el || el.disabled) return;
      el.focus({ preventScroll: true });
      const end = el.value.length;
      el.setSelectionRange(end, end);
    });
  }, []);

  useEffect(() => {
    if (!activeChatId || rec !== 'idle') return;
    focusComposer();
  }, [activeChatId, focusComposer, rec]);

  useEffect(() => {
    if (!replyTarget || rec !== 'idle') return;
    focusComposer();
  }, [replyTarget?.id, focusComposer, rec]);

  useEffect(() => {
    if (!editTarget) return;
    setText((current) => {
      draftBeforeEditRef.current = current;
      return editTarget.text;
    });
    focusComposer();
  }, [editTarget?.id, focusComposer]);

  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    const next = Math.min(el.scrollHeight, INPUT_MAX_PX);
    el.style.height = `${Math.max(next, 44)}px`;
    el.style.overflowY = el.scrollHeight > INPUT_MAX_PX ? 'auto' : 'hidden';
  }, [text, activeChat?.id]);

  const flushTyping = useCallback(() => {
    if (typingSent.current) {
      notifyTyping(false);
      typingSent.current = false;
    }
  }, [notifyTyping]);

  const onSend = useCallback(async () => {
    const t = text.trim();
    if (!t) return;
    try {
      setRecError(null);
      if (editTarget) {
        await editMessage(editTarget.id, t);
        const restoredDraft = draftBeforeEditRef.current;
        clearEdit();
        setText(restoredDraft);
        if (user && activeChatId) {
          writeDraft(user.id, activeChatId, restoredDraft);
        }
      } else {
        await sendPayload({ text: t, replyToMessageId: replyTarget?.id });
        setText('');
        if (user && activeChatId) writeDraft(user.id, activeChatId, '');
        clearReply();
      }
      flushTyping();
    } catch (error) {
      setRecError(
        error instanceof Error
          ? error.message
          : editTarget
            ? 'Не удалось изменить сообщение'
            : 'Не удалось отправить сообщение'
      );
    }
  }, [
    text,
    editTarget,
    editMessage,
    clearEdit,
    sendPayload,
    replyTarget?.id,
    user,
    activeChatId,
    clearReply,
    flushTyping,
  ]);

  const cancelEditing = useCallback(() => {
    const restoredDraft = draftBeforeEditRef.current;
    clearEdit();
    setText(restoredDraft);
    if (user && activeChatId) {
      writeDraft(user.id, activeChatId, restoredDraft);
    }
    focusComposer();
  }, [activeChatId, clearEdit, focusComposer, user]);

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Escape' && editTarget) {
      e.preventDefault();
      cancelEditing();
      return;
    }
    if (
      e.key === 'ArrowUp' &&
      rec === 'idle' &&
      !text.trim() &&
      !editTarget
    ) {
      const lastOwnTextMessage = [...messages]
        .reverse()
        .find(
          (message) =>
            message.senderId === user?.id &&
            !message.deleted &&
            !message.media &&
            !message.imageUrl &&
            Boolean(message.text.trim())
        );
      if (lastOwnTextMessage) {
        e.preventDefault();
        clearReply();
        setEditTarget(lastOwnTextMessage);
      }
      return;
    }
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void onSend();
    }
  };

  const onChange = (v: string) => {
    setText(v);
    if (v.length > 0 && !typingSent.current) {
      typingSent.current = true;
      notifyTyping(true);
    }
    if (v.length === 0) flushTyping();
  };

  const insertEmoji = useCallback((emoji: string) => {
    const el = textareaRef.current;
    if (!el) {
      setText((t) => t + emoji);
      return;
    }
    const start = el.selectionStart;
    const end = el.selectionEnd;
    setText((t) => t.slice(0, start) + emoji + t.slice(end));
    requestAnimationFrame(() => {
      el.focus();
      const pos = start + emoji.length;
      el.setSelectionRange(pos, pos);
    });
  }, []);

  const sendFile = useCallback(
    async (file: File) => {
      if (!activeChat) return;
      if (file.size > MAX_BYTES) {
        setRecError('Файл больше 12 МБ');
        return;
      }
      setRecError(null);
      const dataUrl = await readFileAsDataUrl(file);
      const isImg = file.type.startsWith('image/');
      const media: MessageMedia = isImg
        ? {
            kind: 'image',
            dataUrl,
            fileName: file.name,
            mimeType: file.type,
          }
        : {
            kind: 'file',
            dataUrl,
            fileName: file.name,
            mimeType: file.type || 'application/octet-stream',
          };
      await sendPayload({
        text: '',
        media,
        replyToMessageId: replyTarget?.id,
      });
      clearReply();
      flushTyping();
    },
    [activeChat, sendPayload, replyTarget?.id, clearReply, flushTyping]
  );

  const onFiles = useCallback(
    async (files: FileList | null) => {
      if (!files?.length || !activeChat) return;
      await sendFile(files[0]);
    },
    [activeChat, sendFile]
  );

  const onPaste = useCallback(
    (event: React.ClipboardEvent<HTMLTextAreaElement>) => {
      const imageItem = Array.from(event.clipboardData.items).find(
        (item) => item.kind === 'file' && item.type.startsWith('image/')
      );
      const image = imageItem?.getAsFile();
      if (!image) return;
      event.preventDefault();
      const extension = image.type.split('/')[1]?.replace('jpeg', 'jpg') || 'png';
      const namedImage = new File(
        [image],
        `clipboard-${Date.now()}.${extension}`,
        { type: image.type || 'image/png' }
      );
      void sendFile(namedImage);
    },
    [sendFile]
  );

  const finishRecording = useCallback(
    async (kind: 'voice' | 'video_note') => {
      const recObj = recorderRef.current;
      if (!recObj) return;
      await new Promise<void>((resolve) => {
        recObj.onstop = () => resolve();
        recObj.stop();
      });
      const recordedMime =
        baseMimeType(recObj.mimeType || recorderMimeRef.current) ||
        (kind === 'voice' ? 'audio/webm' : 'video/webm');
      const blob = new Blob(chunksRef.current, { type: recordedMime });
      if (videoPreviewRef.current) videoPreviewRef.current.srcObject = null;
      stopStreams();
      setRec('idle');
      setRecElapsedMs(0);
      if (!blob.size) {
        setRecError('Запись получилась пустой. Попробуйте ещё раз.');
        return;
      }
      setRecError(null);
      const dataUrl = await blobToDataUrl(blob);
      if (dataUrl.length > MAX_MEDIA_DATA_URL_LEN) {
        setRecError(
          kind === 'voice'
            ? 'Голосовое слишком большое. Запишите чуть короче.'
            : 'Кружок слишком большой. Запишите чуть короче.'
        );
        return;
      }
      const durationMs = Date.now() - startedAtRef.current;
      const media: MessageMedia = {
        kind: kind === 'voice' ? 'voice' : 'video_note',
        dataUrl,
        mimeType: blob.type,
        durationMs,
      };
      await sendPayload({
        text: '',
        media,
        replyToMessageId: replyTarget?.id,
      });
      clearReply();
      flushTyping();
    },
    [sendPayload, replyTarget?.id, clearReply, flushTyping, stopStreams]
  );

  const startVoice = async () => {
    setRecError(null);
    try {
      if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
        setRecError('Браузер не поддерживает запись голосовых');
        return;
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          channelCount: 1,
        },
      });
      mediaStreamRef.current = stream;
      const mime = pickAudioMime();
      const mr = createRecorder(stream, mime, 'voice');
      recorderRef.current = mr;
      recorderMimeRef.current = mr.mimeType || mime;
      chunksRef.current = [];
      mr.ondataavailable = (e) => {
        if (e.data.size) chunksRef.current.push(e.data);
      };
      startedAtRef.current = Date.now();
      mr.start(1000);
      setQuickMedia('voice');
      setRec('voice');
    } catch {
      setRecError('Нет доступа к микрофону');
    }
  };

  const startVideo = async () => {
    setRecError(null);
    try {
      if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
        setRecError('Браузер не поддерживает видеокружки');
        return;
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: 'user',
          width: { ideal: 360, max: 480 },
          height: { ideal: 360, max: 480 },
          frameRate: { ideal: 24, max: 30 },
        },
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });
      mediaStreamRef.current = stream;
      setVideoPreviewReady(false);
      setRec('video');
      const mime = pickVideoMime();
      const mr = createRecorder(stream, mime, 'video');
      recorderRef.current = mr;
      recorderMimeRef.current = mr.mimeType || mime;
      chunksRef.current = [];
      mr.ondataavailable = (e) => {
        if (e.data.size) chunksRef.current.push(e.data);
      };
      startedAtRef.current = Date.now();
      mr.start();
      setQuickMedia('video');
    } catch {
      setRecError('Нет доступа к камере');
      stopStreams();
      setRec('idle');
    }
  };

  const runMainAction = () => {
    if (rec !== 'idle') return;
    if (text.trim()) {
      onSend();
      return;
    }
    if (quickMedia === 'voice') void startVoice();
    else void startVideo();
  };

  const stopRecording = () => {
    if (rec === 'voice') void finishRecording('voice');
    else if (rec === 'video') void finishRecording('video_note');
  };

  const cancelRecording = useCallback(() => {
    const recObj = recorderRef.current;
    if (recObj && recObj.state !== 'inactive') {
      try {
        recObj.onstop = () => {};
        recObj.stop();
      } catch {
        /* noop */
      }
    }
    if (videoPreviewRef.current) {
      videoPreviewRef.current.srcObject = null;
    }
    stopStreams();
    setRec('idle');
    setRecElapsedMs(0);
    setRecError(null);
    flushTyping();
  }, [stopStreams, flushTyping]);

  if (!activeChat) {
    return (
      <div className="border-t border-tg-border bg-tg-panel px-4 py-6 text-center text-sm text-tg-muted">
        Выберите чат
      </div>
    );
  }

  const channelReadOnly =
    activeChat.type === 'channel' &&
    (!user || user.id !== activeChat.channelOwnerId);

  if (channelReadOnly) {
    return (
      <div className="border-t border-tg-border bg-tg-panel px-4 py-6 text-center text-sm text-tg-muted">
        В этом канале писать может только владелец. Вы подписаны и получаете
        сообщения.
      </div>
    );
  }

  const hasText = text.trim().length > 0;
  const mainActionTitle = editTarget
    ? 'Сохранить изменения'
    : hasText
      ? 'Отправить'
    : quickMedia === 'voice'
      ? 'Записать голосовое'
      : 'Записать кружок';
  const mainActionClass = hasText
    ? 'bg-sky-500 text-white shadow-[0_8px_20px_rgba(14,165,233,0.28)] hover:bg-sky-400 hover:shadow-[0_10px_24px_rgba(14,165,233,0.34)]'
    : quickMedia === 'voice'
      ? 'border border-emerald-300/55 bg-emerald-500/10 text-emerald-600 shadow-sm hover:bg-emerald-500/16 dark:border-emerald-300/15 dark:bg-emerald-400/10 dark:text-emerald-300'
      : 'border border-sky-300/55 bg-sky-500/10 text-sky-600 shadow-sm hover:bg-sky-500/16 dark:border-sky-300/15 dark:bg-sky-400/10 dark:text-sky-300';

  return (
    <div
      className={`border-t border-tg-border/80 bg-tg-panel/95 px-3 py-2 shadow-[0_-10px_30px_rgba(15,23,42,0.05)] backdrop-blur-xl transition-colors dark:bg-zinc-800/80 dark:shadow-[0_-12px_34px_rgba(0,0,0,0.35)] ${
        dragOver ? 'ring-2 ring-tg-accent/50 ring-inset' : ''
      }`}
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDragOver(false);
        void onFiles(e.dataTransfer.files);
      }}
    >
      {recError ? (
        <p className="mb-2 text-center text-xs text-red-500">{recError}</p>
      ) : null}

      <div className="mx-auto max-w-[min(96vw,58rem)] px-1 pb-2 sm:px-2 sm:pb-3">
        {editTarget && !editTarget.deleted ? (
          <div className="composer-reference mx-auto mb-2 flex max-w-[min(96vw,58rem)] items-center gap-3 px-3 py-2 text-left">
            <div className="h-9 w-1 rounded-full bg-sky-500" aria-hidden />
            <div className="min-w-0 flex-1">
              <p className="text-xs font-semibold text-sky-600 dark:text-sky-300">
                Изменение сообщения
              </p>
              <p className="truncate text-sm text-slate-700 dark:text-slate-200">
                {editTarget.text}
              </p>
            </div>
            <button
              type="button"
              onClick={cancelEditing}
              className="composer-icon-button h-8 w-8"
              title="Отменить изменение"
            >
              <IconClose className="h-4 w-4" />
            </button>
          </div>
        ) : null}
        {replyTarget && !replyTarget.deleted ? (
          <div className="composer-reference mx-auto mb-2 flex max-w-[min(96vw,58rem)] items-center gap-3 px-3 py-2 text-left">
            <div className="h-9 w-1 rounded-full bg-tg-accent" aria-hidden />
            <div className="min-w-0 flex-1">
              <p className="text-xs font-semibold text-tg-accent">Ответ</p>
              <p className="truncate text-sm text-slate-700 dark:text-slate-200">
                {replyTarget.text.trim() ||
                  (replyTarget.media?.kind === 'image'
                    ? 'Фото'
                    : replyTarget.media
                      ? 'Медиа'
                      : 'Сообщение')}
              </p>
            </div>
            <button
              type="button"
              onClick={clearReply}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-900 dark:hover:text-slate-100"
              title="Убрать ответ"
            >
              <IconClose className="h-4 w-4" />
            </button>
          </div>
        ) : null}
        {rec === 'video' ? (
          <div className="mx-auto mb-3 flex max-w-[min(96vw,58rem)] items-center justify-center">
            <div className="relative overflow-hidden rounded-[2rem] border border-tg-border/80 bg-tg-panel/96 px-5 py-4 shadow-[0_18px_48px_rgba(15,23,42,0.16)] backdrop-blur-2xl dark:shadow-[0_20px_58px_rgba(0,0,0,0.38)]">
              <div className="relative flex flex-col items-center gap-3 sm:flex-row sm:gap-5">
                <div className="relative h-44 w-44 shrink-0 sm:h-52 sm:w-52">
                  <div className="absolute inset-2 rounded-full border border-tg-border bg-tg-hover/55 shadow-inner" />
                  <div className="absolute inset-0 rounded-full border-[3px] border-red-400/70 shadow-[0_0_0_8px_rgba(248,113,113,0.08)]" />
                  <video
                    ref={videoPreviewRef}
                    muted
                    playsInline
                    autoPlay
                    onLoadedData={() => setVideoPreviewReady(true)}
                    onCanPlay={() => setVideoPreviewReady(true)}
                    onPlaying={() => setVideoPreviewReady(true)}
                    className="absolute inset-[10px] h-[calc(100%-20px)] w-[calc(100%-20px)] scale-x-[-1] rounded-full bg-tg-hover object-cover shadow-[0_14px_34px_rgba(15,23,42,0.20)]"
                  />
                  {!videoPreviewReady ? (
                    <div className="pointer-events-none absolute inset-[10px] flex items-center justify-center rounded-full bg-tg-hover/75 px-4 text-center text-xs font-semibold text-tg-muted backdrop-blur-sm">
                      Подключаем камеру…
                    </div>
                  ) : null}
                  <div className="absolute bottom-3 left-1/2 flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-black/48 px-3 py-1 text-xs font-bold text-white backdrop-blur">
                    <span className="h-2 w-2 animate-pulse rounded-full bg-red-500" />
                    REC
                  </div>
                </div>
                <div className="min-w-0 text-center sm:text-left">
                  <p className="text-xs font-black uppercase tracking-[0.22em] text-red-500/90">
                    запись кружка
                  </p>
                  <p className="mt-1 text-2xl font-black text-slate-900 dark:text-slate-50">
                    {formatRecTime(recElapsedMs)}
                  </p>
                  <p className="mt-2 max-w-[18rem] text-sm font-semibold text-slate-500 dark:text-slate-400">
                    Видеокружок БренксЧат
                  </p>
                  <div className="mt-4 flex h-6 items-end justify-center gap-1 sm:justify-start">
                    {Array.from({ length: 22 }).map((_, i) => (
                      <span
                        key={i}
                        className="recording-wave-bar h-full w-1 rounded-full bg-sky-400/75"
                        style={waveStyle(i, 1040)}
                      />
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </div>
        ) : null}
        <div className="composer-shell flex min-h-[50px] w-full max-w-full items-end gap-1 overflow-visible px-1.5 py-1.5 sm:min-h-[56px] sm:gap-1.5 sm:px-2">
          {rec === 'idle' ? (
            <>
              <label className="composer-icon-button flex h-10 w-10 shrink-0 cursor-pointer items-center justify-center sm:h-11 sm:w-11">
                <IconPaperclip className="h-4 w-4 sm:h-[1.15rem] sm:w-[1.15rem]" aria-hidden />
                <input
                  type="file"
                  className="hidden"
                  onChange={(e) => void onFiles(e.target.files)}
                />
              </label>
              <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-visible sm:h-11 sm:w-11">
                <EmojiPicker onPick={insertEmoji} disabled={false} />
              </div>
              <textarea
                ref={textareaRef}
                rows={1}
                value={text}
                onChange={(e) => onChange(e.target.value)}
                onKeyDown={onKeyDown}
                onPaste={onPaste}
                onBlur={flushTyping}
                placeholder="Сообщение"
                aria-label={editTarget ? 'Изменить сообщение' : 'Сообщение'}
                data-testid="message-composer"
                className="composer-textarea tg-soft-scrollbar min-h-[38px] min-w-0 flex-1 resize-none overflow-y-hidden px-3 py-2 text-sm leading-snug outline-none sm:min-h-[44px] sm:px-4 sm:py-3 sm:text-[15px]"
              />
              {!hasText ? (
                <button
                  type="button"
                  onClick={() =>
                    setQuickMedia((cur) => (cur === 'voice' ? 'video' : 'voice'))
                  }
                  title={
                    quickMedia === 'voice'
                      ? 'Переключить на кружок'
                      : 'Переключить на голосовое'
                  }
                  className="composer-mode-button mb-0.5 flex h-10 w-10 shrink-0 items-center justify-center sm:h-11 sm:w-11"
                >
                  {quickMedia === 'voice' ? (
                    <IconVideoCircle className="h-4 w-4 sm:h-[1.15rem] sm:w-[1.15rem]" />
                  ) : (
                    <IconMic className="h-4 w-4 sm:h-[1.15rem] sm:w-[1.15rem]" />
                  )}
                </button>
              ) : null}
            </>
          ) : (
            <div className="flex min-h-[44px] min-w-0 flex-1 items-center gap-2 rounded-[1.35rem] bg-slate-100/70 px-2.5 py-1.5 dark:bg-zinc-900/45 sm:px-3">
              <button
                type="button"
                onClick={cancelRecording}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-white/80 hover:text-red-500 dark:hover:bg-zinc-700/70"
                title="Отменить запись"
              >
                <IconClose className="h-4 w-4" />
              </button>
              {rec === 'video' ? (
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-sky-500/12 text-sky-500 ring-1 ring-sky-400/20">
                  <IconVideoCircle className="h-5 w-5" />
                </span>
              ) : (
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-500/12 text-emerald-500">
                  <IconMic className="h-5 w-5" />
                </span>
              )}
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="h-2.5 w-2.5 shrink-0 animate-pulse rounded-full bg-red-500" />
                  <span className="truncate text-sm font-semibold text-slate-700 dark:text-slate-100">
                    {rec === 'voice' ? 'Голосовое' : 'Кружок'}
                  </span>
                  <span className="font-mono text-xs text-tg-muted">
                    {formatRecTime(recElapsedMs)}
                  </span>
                </div>
                <div className="mt-1 flex h-4 items-end gap-0.5 overflow-hidden">
                  {Array.from({ length: 18 }).map((_, i) => (
                    <span
                      key={i}
                      className="recording-wave-bar h-full w-1 rounded-full bg-tg-accent/70"
                      style={waveStyle(i)}
                    />
                  ))}
                </div>
              </div>
            </div>
          )}
          <button
            type="button"
            onClick={rec === 'idle' ? runMainAction : stopRecording}
            title={mainActionTitle}
            className={`composer-primary-button mb-0.5 flex h-10 w-10 shrink-0 items-center justify-center sm:h-11 sm:w-11 ${
              rec === 'idle' ? mainActionClass : 'bg-tg-accent text-white shadow-lg shadow-sky-500/25 hover:scale-[1.03]'
            }`}
          >
            {hasText ? (
              <IconSend className="h-4 w-4 sm:h-5 sm:w-5" />
            ) : rec !== 'idle' ? (
              <IconSend className="h-4 w-4 sm:h-5 sm:w-5" />
            ) : quickMedia === 'voice' ? (
              <IconMic className="h-4 w-4 sm:h-5 sm:w-5" />
            ) : (
              <IconVideoCircle className="h-4 w-4 sm:h-5 sm:w-5" />
            )}
          </button>
        </div>
      </div>
      {dragOver ? (
        <p className="mt-2 text-center text-xs text-tg-accent">
          Отпустите файл для отправки
        </p>
      ) : null}
    </div>
  );
}
