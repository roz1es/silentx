import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
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
  const [panelPos, setPanelPos] = useState<{
    left: number;
    bottom: number;
    width: number;
  } | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      const target = e.target as Node;
      if (rootRef.current?.contains(target)) return;
      if (panelRef.current?.contains(target)) return;
      setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const update = () => {
      const rect = rootRef.current?.getBoundingClientRect();
      if (!rect) return;
      const width = Math.min(window.innerWidth - 24, 300);
      const left = Math.min(
        Math.max(12, rect.right - width),
        window.innerWidth - width - 12
      );
      setPanelPos({
        left,
        bottom: Math.max(12, window.innerHeight - rect.top + 8),
        width,
      });
    };
    update();
    window.addEventListener('resize', update);
    window.addEventListener('scroll', update, true);
    return () => {
      window.removeEventListener('resize', update);
      window.removeEventListener('scroll', update, true);
    };
  }, [open]);

  const group = GROUPS[tab] ?? GROUPS[0]!;
  const panel =
    open && panelPos
      ? createPortal(
          <div
            ref={panelRef}
            className="fixed z-[10060] overflow-hidden rounded-3xl border border-tg-border/90 bg-tg-panel/98 shadow-[0_18px_54px_rgba(15,23,42,0.22)] backdrop-blur-xl dark:shadow-[0_18px_54px_rgba(0,0,0,0.55)]"
            style={{
              left: panelPos.left,
              bottom: panelPos.bottom,
              width: panelPos.width,
            }}
          >
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
          </div>,
          document.body
        )
      : null;

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
      {panel}
    </div>
  );
}
