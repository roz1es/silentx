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

function pickAudioMime(): string {
  const types = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4'];
  for (const t of types) {
    if (MediaRecorder.isTypeSupported(t)) return t;
  }
  return '';
}

function pickVideoMime(): string {
  const types = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
  ];
  for (const t of types) {
    if (MediaRecorder.isTypeSupported(t)) return t;
  }
  return '';
}

export function MessageInput() {
  const { user } = useAuth();
  const { sendPayload, notifyTyping, activeChat } = useMessenger();
  const [text, setText] = useState('');
  const [dragOver, setDragOver] = useState(false);
  const [rec, setRec] = useState<'idle' | 'voice' | 'video'>('idle');
  const [recError, setRecError] = useState<string | null>(null);
  const typingSent = useRef(false);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const videoPreviewRef = useRef<HTMLVideoElement | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const startedAtRef = useRef(0);

  const stopStreams = useCallback(() => {
    mediaStreamRef.current?.getTracks().forEach((t) => t.stop());
    mediaStreamRef.current = null;
    recorderRef.current = null;
    chunksRef.current = [];
  }, []);

  useEffect(() => () => stopStreams(), [stopStreams]);

  const INPUT_MAX_PX = 92;

  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    const next = Math.min(el.scrollHeight, INPUT_MAX_PX);
    el.style.height = `${Math.max(next, 44)}px`;
  }, [text, activeChat?.id]);

  const flushTyping = useCallback(() => {
    if (typingSent.current) {
      notifyTyping(false);
      typingSent.current = false;
    }
  }, [notifyTyping]);

  const onSend = useCallback(() => {
    const t = text.trim();
    if (!t) return;
    sendPayload({ text: t });
    setText('');
    flushTyping();
  }, [text, sendPayload, flushTyping]);

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      onSend();
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
      sendPayload({ text: '', media });
      flushTyping();
    },
    [activeChat, sendPayload, flushTyping]
  );

  const onFiles = useCallback(
    async (files: FileList | null) => {
      if (!files?.length || !activeChat) return;
      await sendFile(files[0]);
    },
    [activeChat, sendFile]
  );

  const finishRecording = useCallback(
    async (kind: 'voice' | 'video_note') => {
      const recObj = recorderRef.current;
      const mime =
        kind === 'voice' ? pickAudioMime() : pickVideoMime();
      if (!recObj) return;
      if (recObj.state === 'recording') recObj.requestData();
      await new Promise<void>((resolve) => {
        recObj.onstop = () => resolve();
        recObj.stop();
      });
      const blob = new Blob(chunksRef.current, {
        type: mime || undefined,
      });
      if (videoPreviewRef.current) videoPreviewRef.current.srcObject = null;
      stopStreams();
      setRec('idle');
      const dataUrl = await blobToDataUrl(blob);
      const durationMs = Date.now() - startedAtRef.current;
      const media: MessageMedia = {
        kind: kind === 'voice' ? 'voice' : 'video_note',
        dataUrl,
        mimeType: blob.type,
        durationMs,
      };
      sendPayload({ text: '', media });
      flushTyping();
    },
    [sendPayload, flushTyping, stopStreams]
  );

  const startVoice = async () => {
    setRecError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaStreamRef.current = stream;
      const mime = pickAudioMime();
      const mr = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      recorderRef.current = mr;
      chunksRef.current = [];
      mr.ondataavailable = (e) => {
        if (e.data.size) chunksRef.current.push(e.data);
      };
      startedAtRef.current = Date.now();
      mr.start(200);
      setRec('voice');
    } catch {
      setRecError('Нет доступа к микрофону');
    }
  };

  const startVideo = async () => {
    setRecError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 720 } },
        audio: true,
      });
      mediaStreamRef.current = stream;
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = stream;
        await videoPreviewRef.current.play().catch(() => {});
      }
      const mime = pickVideoMime();
      const mr = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      recorderRef.current = mr;
      chunksRef.current = [];
      mr.ondataavailable = (e) => {
        if (e.data.size) chunksRef.current.push(e.data);
      };
      startedAtRef.current = Date.now();
      mr.start(200);
      setRec('video');
    } catch {
      setRecError('Нет доступа к камере');
    }
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

  return (
    <div
      className={`border-t border-tg-border bg-tg-panel px-3 py-2 transition-colors ${
        dragOver ? 'ring-2 ring-tg-accent/40 ring-inset' : ''
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
      <div
        className={`relative mx-auto mb-2 flex max-w-[200px] justify-center ${
          rec === 'video' ? '' : 'pointer-events-none h-0 overflow-hidden opacity-0'
        }`}
      >
        <video
          ref={videoPreviewRef}
          muted
          playsInline
          className="h-48 w-48 rounded-full object-cover ring-2 ring-tg-accent"
        />
      </div>

      {rec !== 'idle' ? (
        <div className="mb-2 flex flex-col items-center gap-3">
          <div className="flex items-center gap-2 text-sm font-medium text-slate-600 dark:text-slate-300">
            {rec === 'voice' ? (
              <IconMic className="h-4 w-4 shrink-0 text-tg-accent" />
            ) : (
              <IconVideoCircle className="h-4 w-4 shrink-0 text-tg-accent" />
            )}
            <span>
              {rec === 'voice'
                ? 'Запись голосового…'
                : 'Запись видеокружка…'}
            </span>
          </div>
          <div className="flex flex-wrap items-center justify-center gap-2">
            <button
              type="button"
              onClick={stopRecording}
              className="rounded-full bg-tg-accent px-5 py-2 text-sm font-semibold text-white shadow-md transition hover:brightness-105"
            >
              Отправить
            </button>
            <button
              type="button"
              onClick={cancelRecording}
              className="btn-cancel-media"
            >
              <IconClose className="h-4 w-4 shrink-0" />
              Отмена
            </button>
          </div>
        </div>
      ) : null}

      {recError ? (
        <p className="mb-2 text-center text-xs text-red-500">{recError}</p>
      ) : null}

      <div className="mx-auto max-w-[min(96vw,58rem)] px-1 pb-2 sm:px-2 sm:pb-3">
        <div className="flex min-h-[44px] items-end gap-0.5 overflow-visible rounded-[1.85rem] border border-tg-border/90 bg-white px-1 py-1 shadow-[0_2px_12px_rgba(0,0,0,0.06)] dark:border-slate-600/80 dark:bg-slate-900/90 dark:shadow-[0_2px_16px_rgba(0,0,0,0.35)] sm:min-h-[52px] sm:px-1.5 sm:py-1">
          <label className="flex h-10 w-10 shrink-0 cursor-pointer items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-800 sm:h-11 sm:w-10 dark:hover:text-slate-100">
            <IconPaperclip className="h-4 w-4 sm:h-[1.15rem] sm:w-[1.15rem]" aria-hidden />
            <input
              type="file"
              className="hidden"
              onChange={(e) => void onFiles(e.target.files)}
            />
          </label>
          <button
            type="button"
            title="Голосовое"
            disabled={rec !== 'idle'}
            onClick={() => void startVoice()}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover disabled:opacity-40 sm:h-11 sm:w-10"
          >
            <IconMic className="h-4 w-4 sm:h-[1.15rem] sm:w-[1.15rem]" />
          </button>
          <button
            type="button"
            title="Кружок"
            disabled={rec !== 'idle'}
            onClick={() => void startVideo()}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover disabled:opacity-40 sm:h-11 sm:w-10"
          >
            <IconVideoCircle className="h-4 w-4 sm:h-[1.15rem] sm:w-[1.15rem]" />
          </button>
          <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-visible sm:h-11 sm:w-11">
            <EmojiPicker onPick={insertEmoji} disabled={rec !== 'idle'} />
          </div>
          <textarea
            ref={textareaRef}
            rows={1}
            value={text}
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={onKeyDown}
            onBlur={flushTyping}
            placeholder="Сообщение"
            disabled={rec !== 'idle'}
            className="tg-soft-scrollbar min-h-[36px] min-w-0 flex-1 resize-none overflow-y-auto border-0 bg-transparent py-2 pl-1 pr-1 text-sm leading-snug text-slate-900 outline-none ring-0 placeholder:text-tg-muted disabled:opacity-50 dark:text-slate-100 sm:min-h-[44px] sm:py-3 sm:pr-2 sm:text-[15px]"
          />
          <button
            type="button"
            onClick={onSend}
            disabled={!text.trim() || rec !== 'idle'}
            title="Отправить"
            className="mb-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-tg-accent text-white shadow-md transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-35 sm:h-11 sm:w-11"
          >
            <IconSend className="h-4 w-4 sm:h-5 sm:w-5" />
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
