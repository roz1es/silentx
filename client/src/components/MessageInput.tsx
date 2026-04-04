import { useCallback, useEffect, useRef, useState } from 'react';
import type { MessageMedia } from '@/types';
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
  const startedAtRef = useRef(0);

  const stopStreams = useCallback(() => {
    mediaStreamRef.current?.getTracks().forEach((t) => t.stop());
    mediaStreamRef.current = null;
    recorderRef.current = null;
    chunksRef.current = [];
  }, []);

  useEffect(() => () => stopStreams(), [stopStreams]);

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

  if (!activeChat) {
    return (
      <div className="border-t border-tg-border bg-tg-panel px-4 py-6 text-center text-sm text-tg-muted">
        Выберите чат
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
        <div className="mb-2 flex items-center justify-center gap-3">
          <span className="text-sm font-medium text-red-500">
            {rec === 'voice' ? '🎤 Запись…' : '🎬 Кружок…'}
          </span>
          <button
            type="button"
            onClick={stopRecording}
            className="rounded-full bg-red-500 px-4 py-1.5 text-sm font-semibold text-white"
          >
            Стоп и отправить
          </button>
        </div>
      ) : null}

      {recError ? (
        <p className="mb-2 text-center text-xs text-red-500">{recError}</p>
      ) : null}

      <div className="mx-auto flex max-w-4xl flex-wrap items-end gap-2">
        <label className="flex h-11 w-11 shrink-0 cursor-pointer items-center justify-center rounded-full bg-tg-hover text-lg transition hover:bg-tg-border/80">
          <span aria-hidden>📎</span>
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
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-tg-hover text-lg transition hover:bg-tg-border/80 disabled:opacity-40"
        >
          🎤
        </button>
        <button
          type="button"
          title="Видеокружок"
          disabled={rec !== 'idle'}
          onClick={() => void startVideo()}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-tg-hover text-lg transition hover:bg-tg-border/80 disabled:opacity-40"
        >
          ⭕
        </button>
        <textarea
          rows={1}
          value={text}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={onKeyDown}
          onBlur={flushTyping}
          placeholder="Сообщение..."
          disabled={rec !== 'idle'}
          className="max-h-36 min-h-[44px] flex-1 resize-y rounded-2xl border border-tg-border bg-white px-4 py-2.5 text-[15px] text-slate-900 shadow-inner outline-none transition focus:border-tg-accent disabled:opacity-50 dark:bg-slate-900/40 dark:text-slate-100"
        />
        <button
          type="button"
          onClick={onSend}
          disabled={!text.trim() || rec !== 'idle'}
          className="flex h-11 shrink-0 items-center justify-center rounded-full bg-tg-accent px-5 text-sm font-semibold text-white shadow-md transition hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-40"
        >
          Отпр.
        </button>
      </div>
      {dragOver ? (
        <p className="mt-2 text-center text-xs text-tg-accent">
          Отпустите файл для отправки
        </p>
      ) : null}
    </div>
  );
}
