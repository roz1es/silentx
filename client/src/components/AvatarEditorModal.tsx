import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent,
} from 'react';
import { IconCheck, IconClose } from '@/components/icons';

const PREVIEW_SIZE = 256;
const EXPORT_SIZE = 512;
const MAX_DATA_URL_LENGTH = 860_000;

type Props = {
  open: boolean;
  src: string | null;
  saving?: boolean;
  title?: string;
  onCancel: () => void;
  onSave: (dataUrl: string) => Promise<void> | void;
};

type Size = {
  width: number;
  height: number;
};

type Point = {
  x: number;
  y: number;
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function maxOffset(size: Size | null, zoom: number): Point {
  if (!size) return { x: 0, y: 0 };
  const scale =
    Math.max(PREVIEW_SIZE / size.width, PREVIEW_SIZE / size.height) * zoom;
  return {
    x: Math.max(0, (size.width * scale - PREVIEW_SIZE) / 2),
    y: Math.max(0, (size.height * scale - PREVIEW_SIZE) / 2),
  };
}

function clampOffset(offset: Point, size: Size | null, zoom: number): Point {
  const max = maxOffset(size, zoom);
  return {
    x: clamp(offset.x, -max.x, max.x),
    y: clamp(offset.y, -max.y, max.y),
  };
}

function exportAvatar(
  image: HTMLImageElement,
  size: Size,
  zoom: number,
  offset: Point
): string {
  const canvas = document.createElement('canvas');
  canvas.width = EXPORT_SIZE;
  canvas.height = EXPORT_SIZE;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Не удалось подготовить изображение');

  const scale =
    Math.max(EXPORT_SIZE / size.width, EXPORT_SIZE / size.height) * zoom;
  const ratio = EXPORT_SIZE / PREVIEW_SIZE;
  const width = size.width * scale;
  const height = size.height * scale;
  const x = EXPORT_SIZE / 2 - width / 2 + offset.x * ratio;
  const y = EXPORT_SIZE / 2 - height / 2 + offset.y * ratio;

  ctx.fillStyle = '#f8fafc';
  ctx.fillRect(0, 0, EXPORT_SIZE, EXPORT_SIZE);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(image, x, y, width, height);

  for (const quality of [0.9, 0.82, 0.74, 0.66]) {
    const dataUrl = canvas.toDataURL('image/jpeg', quality);
    if (dataUrl.length <= MAX_DATA_URL_LENGTH || quality === 0.66) {
      return dataUrl;
    }
  }
  return canvas.toDataURL('image/jpeg', 0.66);
}

export function AvatarEditorModal({
  open,
  src,
  saving = false,
  title = 'Настроить фото',
  onCancel,
  onSave,
}: Props) {
  const imageRef = useRef<HTMLImageElement | null>(null);
  const dragRef = useRef<{
    pointerId: number;
    startX: number;
    startY: number;
    offsetX: number;
    offsetY: number;
  } | null>(null);
  const [size, setSize] = useState<Size | null>(null);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState<Point>({ x: 0, y: 0 });
  const [error, setError] = useState('');

  useEffect(() => {
    if (!open) return;
    setZoom(1);
    setOffset({ x: 0, y: 0 });
    setSize(null);
    setError('');
  }, [open, src]);

  useEffect(() => {
    setOffset((current) => clampOffset(current, size, zoom));
  }, [size, zoom]);

  const imageStyle = useMemo(() => {
    if (!size) return undefined;
    const scale =
      Math.max(PREVIEW_SIZE / size.width, PREVIEW_SIZE / size.height) * zoom;
    return {
      width: size.width * scale,
      height: size.height * scale,
      transform: `translate(calc(-50% + ${offset.x}px), calc(-50% + ${offset.y}px))`,
    };
  }, [offset.x, offset.y, size, zoom]);

  if (!open || !src) return null;

  const startDrag = (event: PointerEvent<HTMLDivElement>) => {
    event.currentTarget.setPointerCapture(event.pointerId);
    dragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      offsetX: offset.x,
      offsetY: offset.y,
    };
  };

  const moveDrag = (event: PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const next = {
      x: drag.offsetX + event.clientX - drag.startX,
      y: drag.offsetY + event.clientY - drag.startY,
    };
    setOffset(clampOffset(next, size, zoom));
  };

  const endDrag = (event: PointerEvent<HTMLDivElement>) => {
    if (dragRef.current?.pointerId === event.pointerId) {
      dragRef.current = null;
    }
  };

  const save = async () => {
    if (!imageRef.current || !size) return;
    setError('');
    try {
      await onSave(exportAvatar(imageRef.current, size, zoom, offset));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Не удалось сохранить фото');
    }
  };

  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center bg-slate-950/30 px-4 backdrop-blur-md dark:bg-black/48"
      role="dialog"
      aria-modal="true"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onCancel();
      }}
    >
      <div className="w-full max-w-md overflow-hidden rounded-[2rem] border border-white/28 bg-white/78 shadow-[0_28px_90px_rgba(15,23,42,0.28)] backdrop-blur-2xl dark:border-white/10 dark:bg-zinc-900/78">
        <div className="flex items-center justify-between gap-3 border-b border-tg-border/55 px-5 py-4">
          <div>
            <h3 className="text-lg font-semibold text-slate-950 dark:text-white">
              {title}
            </h3>
            <p className="mt-0.5 text-sm text-tg-muted">
              Перетащите фото и выберите масштаб
            </p>
          </div>
          <button
            type="button"
            onClick={onCancel}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white/55 text-tg-muted transition hover:bg-white hover:text-slate-900 dark:bg-white/8 dark:hover:bg-white/12 dark:hover:text-white"
            title="Закрыть"
          >
            <IconClose className="h-4 w-4" />
          </button>
        </div>

        <div className="px-5 py-5">
          <div className="mx-auto w-[256px] max-w-full">
            <div
              className="relative aspect-square cursor-grab touch-none overflow-hidden rounded-full border border-white/45 bg-slate-200/70 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.55),0_18px_45px_rgba(15,23,42,0.18)] active:cursor-grabbing dark:border-white/10 dark:bg-zinc-800"
              onPointerDown={startDrag}
              onPointerMove={moveDrag}
              onPointerUp={endDrag}
              onPointerCancel={endDrag}
            >
              <img
                ref={imageRef}
                src={src}
                alt=""
                draggable={false}
                onLoad={(event) => {
                  const img = event.currentTarget;
                  setSize({
                    width: img.naturalWidth,
                    height: img.naturalHeight,
                  });
                }}
                className="absolute left-1/2 top-1/2 max-w-none select-none"
                style={imageStyle}
              />
              <div className="pointer-events-none absolute inset-0 rounded-full ring-4 ring-white/45 dark:ring-white/10" />
              <div className="pointer-events-none absolute inset-x-0 top-1/3 border-t border-white/28" />
              <div className="pointer-events-none absolute inset-x-0 bottom-1/3 border-t border-white/28" />
              <div className="pointer-events-none absolute inset-y-0 left-1/3 border-l border-white/28" />
              <div className="pointer-events-none absolute inset-y-0 right-1/3 border-l border-white/28" />
            </div>
          </div>

          <label className="mt-5 block text-sm font-medium text-slate-700 dark:text-slate-200">
            Масштаб
            <input
              type="range"
              min="1"
              max="3"
              step="0.01"
              value={zoom}
              onChange={(event) => setZoom(Number(event.target.value))}
              className="mt-3 w-full accent-sky-400"
            />
          </label>

          <div className="mt-4 grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => {
                setZoom(1);
                setOffset({ x: 0, y: 0 });
              }}
              className="rounded-2xl border border-tg-border/70 bg-white/50 px-4 py-3 text-sm font-semibold text-slate-700 transition hover:bg-white dark:bg-white/6 dark:text-slate-200 dark:hover:bg-white/10"
            >
              Сбросить
            </button>
            <button
              type="button"
              onClick={() => void save()}
              disabled={saving || !size}
              className="inline-flex items-center justify-center gap-2 rounded-2xl bg-tg-accent px-4 py-3 text-sm font-semibold text-white shadow-sm transition hover:brightness-105 disabled:cursor-wait disabled:opacity-60"
            >
              {saving ? null : <IconCheck className="h-4 w-4" />}
              {saving ? 'Сохранение...' : 'Сохранить'}
            </button>
          </div>

          {error ? (
            <p className="mt-3 rounded-2xl border border-red-500/20 bg-red-500/10 px-3 py-2 text-sm text-red-600 dark:text-red-300">
              {error}
            </p>
          ) : null}
        </div>
      </div>
    </div>
  );
}
