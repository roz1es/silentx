import { useEffect, useRef, useState } from 'react';
import { IconSmile } from '@/components/icons';

const GROUPS: { id: string; label: string; emojis: string[] }[] = [
  {
    id: 'smile',
    label: 'Смайлы',
    emojis: [
      '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '🥲', '😊', '😇', '🙂', '😉',
      '😍', '🥰', '😘', '😗', '😋', '😛', '🤔', '🫡', '😎', '🤩', '🥳',
    ],
  },
  {
    id: 'emotion',
    label: 'Настроение',
    emojis: [
      '😢', '😭', '😤', '😡', '🤯', '😱', '🫶', '🥺', '😴', '🤗', '🤫', '🤐',
    ],
  },
  {
    id: 'hands',
    label: 'Жесты',
    emojis: [
      '👍', '👎', '👌', '🤝', '👏', '🙏', '💪', '✌️', '🤞', '👋', '✋', '🤚',
    ],
  },
  {
    id: 'heart',
    label: 'Сердца',
    emojis: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '💔', '💕', '💖', '✨', '💫',
    ],
  },
  {
    id: 'misc',
    label: 'Ещё',
    emojis: [
      '🔥', '💯', '⭐', '🎉', '🎁', '☕', '⚡', '☀️', '🌙', '🌈', '🎯', '🎵',
    ],
  },
];

type Props = {
  onPick: (emoji: string) => void;
  disabled?: boolean;
};

export function EmojiPicker({ onPick, disabled }: Props) {
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState(0);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, [open]);

  const group = GROUPS[tab] ?? GROUPS[0]!;

  return (
    <div ref={rootRef} className="relative shrink-0">
      <button
        type="button"
        disabled={disabled}
        title="Смайлики"
        onClick={() => setOpen((o) => !o)}
        className="flex h-10 w-10 items-center justify-center rounded-full border border-transparent text-tg-muted transition hover:border-tg-border/80 hover:bg-tg-hover disabled:opacity-40 sm:h-11 sm:w-11"
      >
        <IconSmile className="h-5 w-5 sm:h-6 sm:w-6" />
      </button>
      {open ? (
        <div className="absolute bottom-full right-0 z-50 mb-2 w-[min(100vw-1.5rem,300px)] overflow-hidden rounded-3xl border border-tg-border/90 bg-tg-panel/95 shadow-[0_12px_40px_rgba(0,0,0,0.12)] backdrop-blur-md dark:shadow-[0_12px_40px_rgba(0,0,0,0.45)]">
          <div className="flex gap-0.5 border-b border-tg-border/80 px-2 pt-2">
            {GROUPS.map((g, i) => (
              <button
                key={g.id}
                type="button"
                onClick={() => setTab(i)}
                className={`min-w-0 flex-1 truncate rounded-t-xl px-1.5 py-2 text-[10px] font-semibold transition sm:text-[11px] ${
                  tab === i
                    ? 'bg-tg-hover text-slate-900 dark:text-slate-100'
                    : 'text-tg-muted hover:bg-tg-hover/60'
                }`}
              >
                {g.label}
              </button>
            ))}
          </div>
          <div className="grid max-h-52 grid-cols-7 gap-1 overflow-y-auto p-3 scrollbar-thin sm:grid-cols-8">
            {group.emojis.map((e) => (
              <button
                key={`${group.id}-${e}`}
                type="button"
                className="flex h-10 w-10 items-center justify-center rounded-2xl text-2xl leading-none transition hover:scale-110 hover:bg-tg-hover active:scale-95"
                onClick={() => {
                  onPick(e);
                  setOpen(false);
                }}
              >
                {e}
              </button>
            ))}
          </div>
        </div>
      ) : null}
    </div>
  );
}
