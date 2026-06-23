import { useEffect } from 'react';
import { createPortal } from 'react-dom';
import { IconClose, IconImage } from '@/components/icons';

export type PhotoViewerItem = {
  id: string;
  src: string;
  label?: string;
  createdAt?: number;
};

type Props = {
  items: PhotoViewerItem[];
  index: number | null;
  onIndexChange: (index: number | null) => void;
};

export function PhotoViewer({ items, index, onIndexChange }: Props) {
  const current = index == null ? null : items[index] ?? null;

  const close = () => onIndexChange(null);
  const showPrevious = () => {
    if (index == null || items.length === 0) return;
    onIndexChange((index - 1 + items.length) % items.length);
  };
  const showNext = () => {
    if (index == null || items.length === 0) return;
    onIndexChange((index + 1) % items.length);
  };

  useEffect(() => {
    if (!current) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close();
      if (event.key === 'ArrowLeft') showPrevious();
      if (event.key === 'ArrowRight') showNext();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [current?.id, index, items.length]);

  if (!current || index == null) return null;

  const dateLabel = current.createdAt
    ? new Intl.DateTimeFormat('ru', {
        day: 'numeric',
        month: 'short',
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(current.createdAt))
    : '';

  return createPortal(
    <div
      className="fixed inset-0 z-[10100] flex items-center justify-center bg-black/78 p-3 backdrop-blur-xl sm:p-5"
      role="dialog"
      aria-modal="true"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) close();
      }}
    >
      <button
        type="button"
        onClick={close}
        className="absolute right-3 top-3 flex h-11 w-11 items-center justify-center rounded-full border border-white/15 bg-black/24 text-white shadow-lg backdrop-blur-xl transition hover:bg-white/18 sm:right-5 sm:top-5"
        title="Закрыть"
      >
        <IconClose className="h-5 w-5" />
      </button>

      <div className="absolute left-3 top-3 flex max-w-[calc(100vw-5rem)] items-center gap-2 rounded-full border border-white/15 bg-black/24 px-3 py-2 text-sm font-medium text-white shadow-lg backdrop-blur-xl sm:left-5 sm:top-5">
        <IconImage className="h-4 w-4 shrink-0" />
        <span className="truncate">
          {current.label || 'Фото'} · {index + 1}/{items.length}
          {dateLabel ? ` · ${dateLabel}` : ''}
        </span>
      </div>

      {items.length > 1 ? (
        <>
          <button
            type="button"
            onClick={showPrevious}
            className="absolute left-2 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full border border-white/15 bg-black/24 text-3xl text-white shadow-lg backdrop-blur-xl transition hover:bg-white/18 sm:left-5"
            title="Предыдущее фото"
          >
            ‹
          </button>
          <button
            type="button"
            onClick={showNext}
            className="absolute right-2 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full border border-white/15 bg-black/24 text-3xl text-white shadow-lg backdrop-blur-xl transition hover:bg-white/18 sm:right-5"
            title="Следующее фото"
          >
            ›
          </button>
        </>
      ) : null}

      <img
        src={current.src}
        alt=""
        className="max-h-[88dvh] max-w-[94vw] rounded-2xl object-contain shadow-[0_30px_100px_rgba(0,0,0,0.55)] sm:max-w-[90vw]"
      />
    </div>,
    document.body
  );
}
