import { useMemo, useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import type { Chat } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { IconDrawingPin, IconMegaphone, IconMute, IconSearch } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { chatParticipantLabel } from '@/lib/userDisplay';

function formatListTime(ts: number): string {
  const d = new Date(ts);
  const now = new Date();
  const sameDay =
    d.getDate() === now.getDate() &&
    d.getMonth() === now.getMonth() &&
    d.getFullYear() === now.getFullYear();
  if (sameDay) {
    return new Intl.DateTimeFormat('ru', {
      hour: '2-digit',
      minute: '2-digit',
    }).format(d);
  }
  return new Intl.DateTimeFormat('ru', {
    day: 'numeric',
    month: 'short',
  }).format(d);
}

function label(chat: Chat, selfId: string): string {
  if (chat.displayName) return chat.displayName;
  if (chat.type === 'group' || chat.type === 'channel') return chat.name;
  const other = chat.participants?.find((p) => p.id !== selfId);
  if (other) return chatParticipantLabel(other);
  return chat.name || 'Чат';
}

function listAvatarProps(
  chat: Chat,
  selfId: string
): { username: string; avatarUrl?: string } {
  const name = label(chat, selfId);
  if (chat.type === 'group' || chat.type === 'channel') {
    return { username: name, avatarUrl: chat.avatarUrl };
  }
  const other = chat.participants?.find((p) => p.id !== selfId);
  return {
    username: other ? chatParticipantLabel(other) : name,
    avatarUrl: other?.avatarUrl,
  };
}

function chatMatchesSearch(
  chat: Chat,
  selfId: string,
  raw: string
): boolean {
  const q = raw.trim().toLowerCase();
  if (!q) return true;
  if (q.startsWith('@')) {
    const nick = q.slice(1);
    if (!nick) return true;
    return (
      chat.participants?.some((p) =>
        p.username.toLowerCase().includes(nick)
      ) ?? false
    );
  }
  if (chat.type === 'group' || chat.type === 'channel') {
    if (chat.name.toLowerCase().includes(q)) return true;
    if (chat.displayName?.toLowerCase().includes(q)) return true;
    return (
      chat.participants?.some((p) =>
        Boolean(p.displayName?.trim().toLowerCase().includes(q))
      ) ?? false
    );
  }
  if (chat.displayName?.toLowerCase().includes(q)) return true;
  const other = chat.participants?.find((p) => p.id !== selfId);
  if (other?.displayName?.trim()) {
    return other.displayName.toLowerCase().includes(q);
  }
  return false;
}

export function ChatList() {
  const { user } = useAuth();
  if (!user) return null;
  const {
    chats,
    activeChat,
    selectChat,
    chatSearch,
    setChatSearch,
    deleteChat,
    clearChat,
    setMuted,
    setPinnedTop,
  } = useMessenger();

  const [contextMenu, setContextMenu] = useState<{
    chat: Chat;
    x: number;
    y: number;
  } | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!contextMenu) return;
    const onDoc = (e: MouseEvent) => {
      if (menuRef.current?.contains(e.target as Node)) return;
      setContextMenu(null);
    };
    const onScroll = () => setContextMenu(null);
    document.addEventListener('mousedown', onDoc);
    window.addEventListener('scroll', onScroll, true);
    return () => {
      document.removeEventListener('mousedown', onDoc);
      window.removeEventListener('scroll', onScroll, true);
    };
  }, [contextMenu]);

  const handleContextMenu = (e: React.MouseEvent, chat: Chat) => {
    e.preventDefault();
    setContextMenu({ chat, x: e.clientX, y: e.clientY });
  };

  const handleDelete = async () => {
    if (!contextMenu) return;
    const { chat } = contextMenu;
    const text = chat.type === 'direct' 
      ? 'Удалить чат для вас и собеседника?' 
      : chat.type === 'channel' 
        ? 'Отписаться от канала?' 
        : 'Выйти из группы?';
    if (window.confirm(text)) {
      await deleteChat(chat.id);
    }
    setContextMenu(null);
  };

  const handleClear = async () => {
    if (!contextMenu) return;
    if (window.confirm('Очистить историю чата?')) {
      await clearChat(contextMenu.chat.id);
    }
    setContextMenu(null);
  };

  const handleToggleMute = async () => {
    if (!contextMenu) return;
    await setMuted(contextMenu.chat.id, !contextMenu.chat.muted);
    setContextMenu(null);
  };

  const handleTogglePin = async () => {
    if (!contextMenu) return;
    await setPinnedTop(contextMenu.chat.id, !contextMenu.chat.pinnedToTop);
    setContextMenu(null);
  };

  const filtered = useMemo(() => {
    const raw = chatSearch.trim();
    if (!raw) return chats;
    return chats.filter((c) => chatMatchesSearch(c, user.id, raw));
  }, [chats, chatSearch, user.id]);

  const sorted = useMemo(() => {
    return [...filtered].sort((a, b) => {
      const pa = a.pinnedToTop ? 1 : 0;
      const pb = b.pinnedToTop ? 1 : 0;
      if (pa !== pb) return pb - pa;
      const ta = a.lastMessage?.time ?? 0;
      const tb = b.lastMessage?.time ?? 0;
      return tb - ta;
    });
  }, [filtered]);

  return (
    <div className="flex h-full min-h-0 flex-col border-r border-tg-border bg-tg-panel">
      <div className="shrink-0 px-3 pb-2 pt-3">
        <div className="relative overflow-hidden rounded-[1.35rem] border border-tg-border/80 bg-white shadow-sm dark:bg-slate-900/40">
          <span className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-tg-muted opacity-70">
            <IconSearch className="h-[1.1rem] w-[1.1rem]" />
          </span>
          <input
            value={chatSearch}
            onChange={(e) => setChatSearch(e.target.value)}
            placeholder="Поиск чатов..."
            className="w-full bg-transparent py-3 pl-11 pr-4 text-[15px] outline-none placeholder:text-tg-muted dark:text-slate-100"
          />
        </div>
      </div>
      <div className="scrollbar-thin min-h-0 flex-1 overflow-y-auto">
        {sorted.map((c) => {
          const unread = c.unread[user.id] ?? 0;
          const active = activeChat?.id === c.id;
          const last = c.lastMessage;
          const av = listAvatarProps(c, user.id);
          return (
            <button
              key={c.id}
              type="button"
              onClick={() => void selectChat(c.id)}
              onContextMenu={(e) => handleContextMenu(e, c)}
              className={`flex w-full gap-2 border-b border-tg-border/60 px-2 py-2 text-left transition hover:bg-tg-hover sm:gap-3 sm:px-3 sm:py-2.5 ${
                active ? 'bg-tg-hover/80' : ''
              }`}
            >
              <UserAvatar
                username={av.username}
                avatarUrl={av.avatarUrl}
                size="sm"
                className="shadow-inner sm:size-md"
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-1 sm:gap-2">
                  <span className="flex min-w-0 items-center gap-0.5 text-sm font-medium text-slate-900 dark:text-slate-100 sm:gap-1">
                    {c.pinnedToTop ? (
                      <span
                        className="shrink-0 text-amber-600 dark:text-amber-400"
                        title="Закреплён"
                      >
                        <IconDrawingPin className="h-3 w-3 sm:h-3.5 sm:w-3.5" />
                      </span>
                    ) : null}
                    {c.muted ? (
                      <span className="shrink-0 text-tg-muted" title="Без звука">
                        <IconMute className="h-3 w-3 sm:h-3.5 sm:w-3.5" />
                      </span>
                    ) : null}
                    {c.type === 'channel' ? (
                      <span className="shrink-0 text-tg-accent" title="Канал">
                        <IconMegaphone className="h-3 w-3 sm:h-3.5 sm:w-3.5" />
                      </span>
                    ) : null}
                    <span className="truncate">{label(c, user.id)}</span>
                  </span>
                  {last ? (
                    <span className="shrink-0 text-[10px] text-tg-muted sm:text-[11px]">
                      {formatListTime(last.time)}
                    </span>
                  ) : null}
                </div>
                <div className="mt-0.5 flex items-center justify-between gap-1 sm:gap-2">
                  <span className="truncate text-xs text-tg-muted sm:text-sm">
                    {last?.text ?? 'Нет сообщений'}
                  </span>
                  {unread > 0 ? (
                    <span className="flex h-4 min-w-[1rem] shrink-0 items-center justify-center rounded-full bg-tg-accent px-1 text-[10px] font-semibold text-white sm:h-5 sm:min-w-[1.25rem] sm:px-1.5 sm:text-[11px]">
                      {unread > 99 ? '99+' : unread}
                    </span>
                  ) : null}
                </div>
              </div>
            </button>
          );
        })}
        {sorted.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-tg-muted">
            Чаты не найдены
          </p>
        ) : null}
      </div>

      {/* Контекстное меню */}
      {contextMenu && createPortal(
        <div
          ref={menuRef}
          className="fixed z-[10000] min-w-[200px] rounded-xl border border-tg-border bg-tg-panel py-1 shadow-2xl dark:shadow-black/40"
          style={{ top: contextMenu.y, left: contextMenu.x }}
        >
          <button
            type="button"
            className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
            onClick={handleTogglePin}
          >
            <IconDrawingPin className="h-4 w-4 shrink-0 opacity-70" />
            {contextMenu.chat.pinnedToTop ? 'Открепить' : 'Закрепить'}
          </button>
          <button
            type="button"
            className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
            onClick={handleToggleMute}
          >
            <IconMute className="h-4 w-4 shrink-0 opacity-70" />
            {contextMenu.chat.muted ? 'Включить уведомления' : 'Без звука'}
          </button>
          <button
            type="button"
            className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
            onClick={handleClear}
          >
            <svg className="h-4 w-4 shrink-0 opacity-70" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth="1.65">
              <path strokeLinecap="round" strokeLinejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            Очистить историю
          </button>
          <div className="my-1 border-t border-tg-border/50" />
          <button
            type="button"
            className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm text-red-600 hover:bg-tg-hover dark:text-red-400"
            onClick={handleDelete}
          >
            <svg className="h-4 w-4 shrink-0 opacity-70" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth="1.65">
              <path strokeLinecap="round" strokeLinejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            {contextMenu.chat.type === 'direct' ? 'Удалить чат' : 
             contextMenu.chat.type === 'channel' ? 'Отписаться' : 'Выйти из группы'}
          </button>
        </div>,
        document.body
      )}
    </div>
  );
}
