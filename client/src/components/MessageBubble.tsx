import { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { Message, User } from '@/types';
import { IconLock, IconPaperclip } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { VoiceMessageBar, VideoNoteCircle } from '@/components/VoiceVideoMedia';
import { participantLabel } from '@/lib/userDisplay';
import { isEmojiOnlyMessage } from '@/lib/emojiOnly';

const QUICK_REACTIONS = ['👍', '❤️', '😂', '🔥', '😮'] as const;

type SenderInfo = {
  username: string;
  displayName?: string;
  avatarUrl?: string;
};

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function HighlightedText({
  text,
  query,
}: {
  text: string;
  query: string;
}) {
  const q = query.trim();
  if (!q) return <>{text}</>;
  try {
    const parts = text.split(new RegExp(`(${escapeRe(q)})`, 'gi'));
    return (
      <>
        {parts.map((part, i) =>
          part.toLowerCase() === q.toLowerCase() ? (
            <mark
              key={i}
              className="rounded-sm bg-amber-200/90 px-0.5 dark:bg-amber-500/35"
            >
              {part}
            </mark>
          ) : (
            <span key={i}>{part}</span>
          )
        )}
      </>
    );
  } catch {
    return <>{text}</>;
  }
}

type Props = {
  message: Message;
  self: User;
  isGroup: boolean;
  sender?: SenderInfo | null;
  peerLabel?: string;
  selfInfo: SenderInfo;
  searchQuery?: string;
  onOpenPeerProfile?: () => void;
  onDelete?: () => void;
  onPin?: () => void;
  onReply?: () => void;
  onForward?: () => void;
  onSelect?: () => void;
  onReact?: (emoji: string) => void;
  onOpenImage?: (src: string) => void;
  replyTo?: Message | null;
  replyLabel?: string;
  /** Это сообщение сейчас закреплено в чате */
  pinActive?: boolean;
  readReceipt?: 'sent' | 'read';
  onStartEdit?: () => void;
  selecting?: boolean;
  selected?: boolean;
};

function formatTime(ts: number): string {
  return new Intl.DateTimeFormat('ru', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(ts));
}

function ReadTicks({ status }: { status: 'sent' | 'read' }) {
  return (
    <span
      className="read-ticks"
      data-status={status}
      title={status === 'read' ? 'Прочитано' : 'Доставлено'}
      aria-label={status === 'read' ? 'Прочитано' : 'Доставлено'}
    >
      <svg
        width="20"
        height="14"
        viewBox="0 0 20 14"
        fill="none"
        aria-hidden
      >
        <polyline
          className="read-tick read-tick-first"
          points="1.7,7.1 5.1,10.5 9.7,4.6"
        />
        <polyline
          className="read-tick read-tick-second"
          points="6.5,7.1 9.9,10.5 18.2,2.4"
        />
      </svg>
    </span>
  );
}

function MenuButton({
  children,
  danger = false,
  onClick,
}: {
  children: React.ReactNode;
  danger?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`block w-full rounded-xl px-3 py-2 text-left transition ${
        danger
          ? 'text-red-600 hover:bg-red-500/10 dark:text-red-400'
          : 'hover:bg-tg-hover'
      }`}
    >
      {children}
    </button>
  );
}

export function MessageBubble({
  message,
  self,
  isGroup,
  sender,
  peerLabel,
  selfInfo,
  searchQuery = '',
  onOpenPeerProfile,
  onDelete,
  onPin,
  onReply,
  onForward,
  onSelect,
  onReact,
  onOpenImage,
  replyTo,
  replyLabel,
  pinActive = false,
  readReceipt,
  onStartEdit,
  selecting = false,
  selected = false,
}: Props) {
  const mine = message.senderId === self.id;
  const menuRef = useRef<HTMLDivElement>(null);
  const longPressTimerRef = useRef<number | null>(null);
  const longPressStartRef = useRef<{ x: number; y: number } | null>(null);
  const longPressOpenedRef = useRef(false);
  const swipeStartRef = useRef<{ x: number; y: number } | null>(null);
  const [swipeX, setSwipeX] = useState(0);
  const [menuPos, setMenuPos] = useState<{ x: number; y: number } | null>(
    null
  );

  const clearLongPress = () => {
    if (longPressTimerRef.current) {
      window.clearTimeout(longPressTimerRef.current);
      longPressTimerRef.current = null;
    }
    longPressStartRef.current = null;
  };

  useEffect(() => {
    if (!menuPos) return;
    const close = () => setMenuPos(null);
    const isInsideMenu = (event: Event) => {
      const target = event.target;
      return target instanceof Node && Boolean(menuRef.current?.contains(target));
    };
    const closeOnOutsidePointer = (event: PointerEvent) => {
      if (!isInsideMenu(event)) close();
    };
    const closeOnOutsideContextMenu = (event: MouseEvent) => {
      if (!isInsideMenu(event)) close();
    };
    const closeForOtherMenu = (event: Event) => {
      const detail = (event as CustomEvent<{ messageId?: string }>).detail;
      if (detail?.messageId !== message.id) close();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    window.addEventListener('pointerdown', closeOnOutsidePointer, true);
    window.addEventListener('contextmenu', closeOnOutsideContextMenu, true);
    window.addEventListener('brenkschat:message-menu-open', closeForOtherMenu);
    window.addEventListener('scroll', close, true);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('pointerdown', closeOnOutsidePointer, true);
      window.removeEventListener('contextmenu', closeOnOutsideContextMenu, true);
      window.removeEventListener(
        'brenkschat:message-menu-open',
        closeForOtherMenu
      );
      window.removeEventListener('scroll', close, true);
      window.removeEventListener('keydown', onKey);
    };
  }, [menuPos, message.id]);

  useEffect(() => clearLongPress, []);

  const showName = useMemo(
    () => !mine && peerLabel && isGroup,
    [mine, peerLabel, isGroup]
  );

  const showLeftAvatar = Boolean(!mine && sender);
  const showRightAvatar = mine && isGroup;

  const leftLabel = sender ? participantLabel(sender) : '?';
  const rightLabel = participantLabel(selfInfo);

  if (message.deleted) return null;

  const media = message.media;
  const legacyImg = message.imageUrl;
  const canEdit =
    mine &&
    !message.deleted &&
    !media &&
    !legacyImg &&
    Boolean(onStartEdit);

  const textTrim = message.text.trim();
  const hasText = textTrim && textTrim !== '\u00a0';
  const emojiLarge = hasText && isEmojiOnlyMessage(message.text);

  const isVoiceOrVideoNote =
    media?.kind === 'voice' || media?.kind === 'video_note';
  const reactionEntries = Object.entries(message.reactions ?? {}).filter(
    ([, ids]) => ids.length > 0
  );
  const replyText =
    replyTo && !replyTo.deleted
      ? replyTo.text.trim() ||
        (replyTo.media?.kind === 'image'
          ? 'Фото'
          : replyTo.media
            ? 'Медиа'
            : 'Сообщение')
      : '';
  const canShowMenu =
    !selecting &&
    Boolean(
      onReply ||
        onForward ||
        onSelect ||
        onPin ||
        canEdit ||
        onDelete ||
        onReact ||
        onOpenPeerProfile
    );

  const showMenuAt = (x: number, y: number) => {
    if (selecting || !canShowMenu) return;
    window.dispatchEvent(
      new CustomEvent('brenkschat:message-menu-open', {
        detail: { messageId: message.id },
      })
    );
    const menuW = 236;
    const menuH = 310;
    setMenuPos({
      x: Math.min(x, window.innerWidth - menuW - 8),
      y: Math.min(y, window.innerHeight - menuH - 8),
    });
  };

  const openMenu = (e: React.MouseEvent<HTMLDivElement>) => {
    if (selecting) {
      e.preventDefault();
      return;
    }
    if (!canShowMenu) return;
    e.preventDefault();
    e.stopPropagation();
    showMenuAt(e.clientX, e.clientY);
  };

  const startLongPress = (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.pointerType === 'mouse' || selecting || !canShowMenu) return;
    clearLongPress();
    longPressOpenedRef.current = false;
    longPressStartRef.current = { x: e.clientX, y: e.clientY };
    swipeStartRef.current = onReply ? { x: e.clientX, y: e.clientY } : null;
    setSwipeX(0);
    longPressTimerRef.current = window.setTimeout(() => {
      longPressTimerRef.current = null;
      longPressOpenedRef.current = true;
      showMenuAt(e.clientX, e.clientY);
    }, 520);
  };

  const moveLongPress = (e: React.PointerEvent<HTMLDivElement>) => {
    const start = longPressStartRef.current;
    if (start) {
      const dx = e.clientX - start.x;
      const dy = e.clientY - start.y;
      if (Math.hypot(dx, dy) > 12) clearLongPress();
    }

    const swipeStart = swipeStartRef.current;
    if (!swipeStart || selecting || !onReply) return;
    const dx = e.clientX - swipeStart.x;
    const dy = e.clientY - swipeStart.y;
    if (Math.abs(dy) > 24 && Math.abs(dy) > Math.abs(dx)) {
      swipeStartRef.current = null;
      setSwipeX(0);
      return;
    }
    if (dx > 8 && Math.abs(dx) > Math.abs(dy) * 1.2) {
      e.preventDefault();
      setSwipeX(Math.min(76, dx * 0.42));
    }
  };

  const finishPointerGesture = () => {
    clearLongPress();
    const shouldReply = swipeX > 34 && Boolean(onReply) && !selecting;
    swipeStartRef.current = null;
    setSwipeX(0);
    if (shouldReply) onReply?.();
  };

  const runMenuAction = (fn?: () => void) => {
    setMenuPos(null);
    fn?.();
  };

  const copyText = () => {
    const text = message.text.trim();
    if (!text) return;
    void navigator.clipboard?.writeText(text).catch(() => {});
  };

  const bubble = (
    <div
      onClickCapture={(e) => {
        if (!longPressOpenedRef.current) return;
        e.preventDefault();
        e.stopPropagation();
        longPressOpenedRef.current = false;
      }}
      onClick={() => {
        if (selecting) onSelect?.();
      }}
      onDoubleClick={(e) => {
        if (selecting || !onReply) return;
        const target = e.target;
        if (
          target instanceof Element &&
          target.closest('button, a, textarea, input')
        ) {
          return;
        }
        e.preventDefault();
        e.stopPropagation();
        setMenuPos(null);
        onReply();
      }}
      onContextMenu={openMenu}
      onPointerDown={startLongPress}
      onPointerMove={moveLongPress}
      onPointerUp={finishPointerGesture}
      onPointerCancel={finishPointerGesture}
      style={{
        transform: swipeX ? `translateX(${swipeX}px)` : undefined,
      }}
      className={`group/bubble relative max-w-[min(80vw,28rem)] rounded-2xl px-2.5 py-1.5 text-[13px] shadow-sm transition sm:px-3 sm:py-2 sm:text-[15px] ${
      selected ? 'ring-2 ring-tg-accent/65' : ''
    } ${selecting ? 'cursor-pointer' : ''} ${
      emojiLarge
        ? 'bg-transparent shadow-none'
          : isVoiceOrVideoNote
            ? 'bg-transparent shadow-none'
          : mine
            ? 'message-bubble-out rounded-br-md text-slate-900 dark:text-slate-50'
            : 'message-bubble-in rounded-bl-md text-slate-900 dark:text-slate-100'
    }`}
    >
      {swipeX > 8 ? (
        <span
          className={`pointer-events-none absolute left-0 top-1/2 flex h-8 w-8 -translate-x-11 -translate-y-1/2 items-center justify-center rounded-full border border-tg-accent/25 bg-tg-accent/12 text-sm font-black text-tg-accent shadow-sm transition-opacity ${
            swipeX > 34 ? 'opacity-100' : 'opacity-60'
          }`}
          aria-hidden
        >
          ↩
        </span>
      ) : null}
      {showName ? (
        <button
          type="button"
          onClick={onOpenPeerProfile}
          className="mb-1 block w-full text-left text-xs font-semibold text-tg-accent hover:underline"
        >
          {peerLabel}
        </button>
      ) : null}

      {replyText ? (
        <div className="mb-1.5 rounded-xl border-l-2 border-tg-accent bg-black/[0.04] px-2 py-1.5 dark:bg-white/[0.06]">
          <p className="truncate text-[11px] font-semibold text-tg-accent">
            {replyLabel ?? 'Ответ'}
          </p>
          <p className="truncate text-xs text-slate-700 dark:text-slate-200">
            {replyText}
          </p>
        </div>
      ) : null}

      {media?.kind === 'video_note' ? (
        <div className="mb-1">
          <VideoNoteCircle dataUrl={media.dataUrl} />
        </div>
      ) : null}

      {media?.kind === 'voice' ? (
        <div className="mb-1">
          <VoiceMessageBar
            dataUrl={media.dataUrl}
            durationMs={media.durationMs}
            mine={mine}
          />
        </div>
      ) : null}

      {media?.kind === 'file' ? (
        <a
          href={media.dataUrl}
          download={media.fileName ?? 'file'}
          onClick={(e) => {
            if (!selecting) return;
            e.preventDefault();
            e.stopPropagation();
            onSelect?.();
          }}
          className="mb-1 flex items-center gap-2 break-all rounded-lg bg-black/5 px-2 py-2 text-sm text-tg-accent underline dark:bg-white/10"
        >
          <IconPaperclip className="h-4 w-4 shrink-0 opacity-80" />
          {media.fileName ?? 'Файл'}
        </a>
      ) : null}

      {media?.kind === 'image' || (legacyImg && !media) ? (
        <button
          type="button"
          onClick={(e) => {
            if (selecting) {
              e.preventDefault();
              e.stopPropagation();
              onSelect?.();
              return;
            }
            onOpenImage?.(media?.kind === 'image' ? media.dataUrl : legacyImg!);
          }}
          className="mb-1 block overflow-hidden rounded-lg focus:outline-none focus:ring-2 focus:ring-tg-accent/40"
          title="Открыть фото"
        >
          <img
            src={media?.kind === 'image' ? media.dataUrl : legacyImg!}
            alt=""
            className="max-h-64 w-full object-cover transition duration-200 hover:scale-[1.01]"
          />
        </button>
      ) : null}

      {hasText ? (
        <p
          className={`whitespace-pre-wrap break-words leading-snug ${
            emojiLarge
              ? 'text-center text-[2rem] leading-none tracking-wide sm:text-[2.35rem] [&_mark]:text-[2rem] sm:[&_mark]:text-[2.35rem]'
              : 'text-[14px] sm:text-[15px]'
          }`}
        >
          <HighlightedText text={message.text} query={searchQuery} />
        </p>
      ) : null}

      <div className="mt-0.5 flex flex-wrap items-center justify-end gap-x-1 text-[10px] text-tg-muted sm:mt-1 sm:text-[11px]">
        {message.encryptionState ? (
          <span
            className={
              message.encryptionState === 'encrypted'
                ? 'text-emerald-600 dark:text-emerald-400'
                : message.encryptionState === 'pending'
                  ? 'text-sky-500 dark:text-sky-300'
                : message.encryptionState === 'recovering'
                  ? 'text-amber-500 dark:text-amber-300'
                  : 'text-red-500'
            }
            title={
              message.encryptionState === 'encrypted'
                ? 'Сквозное шифрование'
                : message.encryptionState === 'pending'
                  ? 'Повторная расшифровка'
                : message.encryptionState === 'recovering'
                  ? 'Ожидается восстановление ключа шифрования'
                  : 'Ошибка расшифровки'
            }
          >
            <IconLock className="h-3 w-3" />
          </span>
        ) : null}
        {message.editedAt ? (
          <span className="opacity-75">изменено</span>
        ) : null}
        <span>{formatTime(message.createdAt)}</span>
        {mine && readReceipt ? <ReadTicks status={readReceipt} /> : null}
      </div>
      {reactionEntries.length > 0 ? (
        <div className="mt-1 flex flex-wrap justify-end gap-1">
          {reactionEntries.map(([emoji, ids]) => {
            const active = ids.includes(self.id);
            return (
              <button
                key={emoji}
                type="button"
                onClick={(e) => {
                  if (selecting) {
                    e.stopPropagation();
                    onSelect?.();
                    return;
                  }
                  onReact?.(emoji);
                }}
                className={`rounded-full px-2 py-0.5 text-xs font-semibold shadow-sm transition hover:scale-105 ${
                  active
                    ? 'bg-tg-accent/90 text-white'
                    : 'bg-white/75 text-slate-700 dark:bg-slate-900/45 dark:text-slate-100'
                }`}
                title="Реакция"
              >
                <span>{emoji}</span>
                <span className="ml-1 tabular-nums">{ids.length}</span>
              </button>
            );
          })}
        </div>
      ) : null}
      {menuPos
        ? createPortal(
            <div
              ref={menuRef}
              className="fixed z-[10020] w-[236px] overflow-hidden rounded-2xl border border-white/70 bg-white/95 p-1.5 text-sm text-slate-800 shadow-2xl shadow-slate-900/20 backdrop-blur-xl animate-msg-in dark:border-white/10 dark:bg-zinc-800/95 dark:text-slate-100 dark:shadow-black/45"
              style={{ left: menuPos.x, top: menuPos.y }}
              onPointerDown={(e) => e.stopPropagation()}
              onClick={(e) => e.stopPropagation()}
              onContextMenu={(e) => {
                e.preventDefault();
                e.stopPropagation();
              }}
            >
              {onReact ? (
                <div className="mb-1 flex items-center justify-between gap-1 rounded-xl bg-tg-hover/70 p-1">
                  {QUICK_REACTIONS.map((emoji) => (
                    <button
                      key={emoji}
                      type="button"
                      onClick={() => runMenuAction(() => onReact(emoji))}
                      className="flex h-8 w-8 items-center justify-center rounded-full text-lg transition hover:scale-110 hover:bg-white/80 dark:hover:bg-white/10"
                      title="Поставить реакцию"
                    >
                      {emoji}
                    </button>
                  ))}
                </div>
              ) : null}
              {onReply ? (
                <MenuButton onClick={() => runMenuAction(onReply)}>
                  Ответить
                </MenuButton>
              ) : null}
              {onForward ? (
                <MenuButton onClick={() => runMenuAction(onForward)}>
                  Переслать
                </MenuButton>
              ) : null}
              {onSelect ? (
                <MenuButton onClick={() => runMenuAction(onSelect)}>
                  Выбрать
                </MenuButton>
              ) : null}
              {onPin ? (
                <MenuButton onClick={() => runMenuAction(onPin)}>
                  {pinActive ? 'Открепить' : 'Закрепить'}
                </MenuButton>
              ) : null}
              {canEdit ? (
                <MenuButton onClick={() => runMenuAction(onStartEdit)}>
                  Изменить
                </MenuButton>
              ) : null}
              {message.text.trim() ? (
                <MenuButton onClick={() => runMenuAction(copyText)}>
                  Копировать текст
                </MenuButton>
              ) : null}
              {!mine && onOpenPeerProfile ? (
                <MenuButton onClick={() => runMenuAction(onOpenPeerProfile)}>
                  Профиль
                </MenuButton>
              ) : null}
              {onDelete ? (
                <MenuButton danger onClick={() => runMenuAction(onDelete)}>
                  Удалить
                </MenuButton>
              ) : null}
            </div>,
            document.body
          )
        : null}
    </div>
  );

  return (
    <div
      className={`group/msg flex w-full animate-msg-in ${
        mine ? 'justify-end' : 'justify-start'
      }`}
    >
      <div
        className={`flex max-w-full items-end gap-2 sm:max-w-[min(92vw,30rem)] ${
          mine ? 'flex-row-reverse' : 'flex-row'
        }`}
      >
        {showLeftAvatar && sender ? (
          <button
            type="button"
            title="Профиль"
            onClick={onOpenPeerProfile}
            className="shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-tg-accent/50"
          >
            <UserAvatar
              username={leftLabel}
              avatarUrl={sender.avatarUrl}
              size="sm"
            />
          </button>
        ) : null}
        {bubble}
        {selecting ? (
          <button
            type="button"
            onClick={onSelect}
            className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 transition ${
              selected
                ? 'border-tg-accent bg-tg-accent text-white'
                : 'border-tg-border bg-tg-panel/80 text-transparent'
            }`}
            title={selected ? 'Убрать из выбора' : 'Выбрать сообщение'}
          >
            <span className="text-xs font-black">✓</span>
          </button>
        ) : null}
        {showRightAvatar ? (
          <div className="shrink-0">
            <UserAvatar
              username={rightLabel}
              avatarUrl={selfInfo.avatarUrl}
              size="sm"
            />
          </div>
        ) : null}
      </div>
    </div>
  );
}
