import { useMemo, useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import type { Chat } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import {
  IconCheck,
  IconChevronRight,
  IconDrawingPin,
  IconMegaphone,
  IconMute,
  IconSearch,
} from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { chatParticipantLabel } from '@/lib/userDisplay';
import { userSearchQuery } from '@/lib/userSearch';
import * as api from '@/lib/api';
import type { DirectoryUser } from '@/lib/api';

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

function messagePreview(text?: string): string {
  const value = text?.trim();
  if (!value) return 'Нет сообщений';
  if (
    value === 'Защищённое сообщение' ||
    value === 'Защищенное сообщение' ||
    value === 'Новое сообщение' ||
    value === 'Пробуем расшифровать сообщение…' ||
    value === 'Ожидается восстановление ключа шифрования' ||
    value === 'Не удалось расшифровать защищённое сообщение' ||
    value === 'Не удалось расшифровать защищенное сообщение'
  ) {
    return 'Сообщение';
  }
  return value;
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

type NewChatTab = 'direct' | 'group' | 'channel';
type ChatFilter = 'all' | 'unread' | 'direct' | 'group' | 'channel';

type Props = {
  onOpenNewChat?: (tab: NewChatTab) => void;
};

const CHAT_FILTERS: Array<{ id: ChatFilter; label: string }> = [
  { id: 'all', label: 'Все' },
  { id: 'unread', label: 'Новые' },
  { id: 'direct', label: 'Личные' },
  { id: 'group', label: 'Группы' },
  { id: 'channel', label: 'Каналы' },
];

function VerifiedBadge() {
  return (
    <span
      className="inline-flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full border border-amber-200/60 bg-amber-300/90 text-zinc-950 shadow-[0_0_12px_rgba(251,191,36,0.2)]"
      title="Подтвержденный канал"
    >
      <IconCheck className="h-2.5 w-2.5" />
    </span>
  );
}

export function ChatList({ onOpenNewChat }: Props) {
  const { user } = useAuth();
  if (!user) return null;
  const {
    chats,
    activeChat,
    selectChat,
    chatSearch,
    setChatSearch,
    createDirect,
    openSavedChat,
    deleteChat,
    clearChat,
    setMuted,
    setPinnedTop,
    setChatVerified,
    refreshChats,
  } = useMessenger();

  const [contextMenu, setContextMenu] = useState<{
    chat: Chat;
    x: number;
    y: number;
  } | null>(null);
  const [userResult, setUserResult] = useState<DirectoryUser | null>(null);
  const [userSearchLoading, setUserSearchLoading] = useState(false);
  const [userSearchError, setUserSearchError] = useState<string | null>(null);
  const [openingUserId, setOpeningUserId] = useState<string | null>(null);
  const [savedOpening, setSavedOpening] = useState(false);
  const [chatFilter, setChatFilter] = useState<ChatFilter>('all');
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
      await refreshChats();
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

  const handleToggleVerified = async () => {
    if (!contextMenu) return;
    await setChatVerified(contextMenu.chat.id, !contextMenu.chat.verified);
    setContextMenu(null);
  };

  useEffect(() => {
    const raw = chatSearch.trim();
    const query = userSearchQuery(raw);
    if (!query) {
      setUserResult(null);
      setUserSearchLoading(false);
      setUserSearchError(null);
      return;
    }
    let alive = true;
    setUserSearchLoading(true);
    setUserSearchError(null);
    const timer = window.setTimeout(() => {
      api
        .searchUsers(query)
        .then(({ users }) => {
          if (!alive) return;
          setUserResult(users[0] ?? null);
        })
        .catch((err) => {
          if (!alive) return;
          setUserResult(null);
          setUserSearchError(err instanceof Error ? err.message : 'Ошибка поиска');
        })
        .finally(() => {
          if (alive) setUserSearchLoading(false);
        });
    }, 240);
    return () => {
      alive = false;
      window.clearTimeout(timer);
    };
  }, [chatSearch]);

  const openUserSearchResult = async () => {
    if (!userResult) return;
    setOpeningUserId(userResult.id);
    try {
      await createDirect({ userId: userResult.id });
      setChatSearch('');
    } finally {
      setOpeningUserId(null);
    }
  };

  const openSaved = async () => {
    setSavedOpening(true);
    try {
      await openSavedChat();
      setChatSearch('');
    } finally {
      setSavedOpening(false);
    }
  };

  const filtered = useMemo(() => {
    const raw = chatSearch.trim();
    return chats.filter((c) => {
      if (chatFilter === 'unread' && (c.unread[user.id] ?? 0) <= 0) {
        return false;
      }
      if (
        chatFilter !== 'all' &&
        chatFilter !== 'unread' &&
        c.type !== chatFilter
      ) {
        return false;
      }
      if (!raw) return true;
      return chatMatchesSearch(c, user.id, raw);
    });
  }, [chats, chatFilter, chatSearch, user.id]);

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
    <div className="flex h-full min-h-0 flex-col border-r border-white/60 bg-transparent dark:border-white/10">
      <div className="shrink-0 px-3 pb-2 pt-3">
        <div className="relative overflow-hidden rounded-[1.35rem] border border-white/80 bg-white/80 shadow-[0_10px_28px_rgba(15,23,42,0.06)] ring-1 ring-sky-100/70 backdrop-blur-xl dark:border-white/10 dark:bg-zinc-700/45 dark:ring-white/5">
          <span className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-tg-muted opacity-70">
            <IconSearch className="h-[1.1rem] w-[1.1rem]" />
          </span>
          <input
            value={chatSearch}
            onChange={(e) => setChatSearch(e.target.value)}
            placeholder="Поиск чатов, @username или ID"
            className="w-full bg-transparent py-3 pl-11 pr-4 text-[15px] outline-none placeholder:text-tg-muted dark:text-slate-100"
          />
        </div>
        <div className="mt-2 grid grid-cols-3 gap-1.5">
          <button
            type="button"
            onClick={() => void openSaved()}
            disabled={savedOpening}
            className="rounded-2xl border border-white/70 bg-white/58 px-2 py-2 text-xs font-semibold text-slate-700 shadow-sm transition hover:bg-white disabled:opacity-50 dark:border-white/10 dark:bg-zinc-700/35 dark:text-slate-200 dark:hover:bg-zinc-700/65"
          >
            Избранное
          </button>
          <button
            type="button"
            onClick={() => onOpenNewChat?.('group')}
            className="rounded-2xl border border-white/70 bg-white/58 px-2 py-2 text-xs font-semibold text-slate-700 shadow-sm transition hover:bg-white dark:border-white/10 dark:bg-zinc-700/35 dark:text-slate-200 dark:hover:bg-zinc-700/65"
          >
            Группа
          </button>
          <button
            type="button"
            onClick={() => onOpenNewChat?.('channel')}
            className="rounded-2xl border border-white/70 bg-white/58 px-2 py-2 text-xs font-semibold text-slate-700 shadow-sm transition hover:bg-white dark:border-white/10 dark:bg-zinc-700/35 dark:text-slate-200 dark:hover:bg-zinc-700/65"
          >
            Канал
          </button>
        </div>
        <div className="scrollbar-thin mt-2 flex gap-1.5 overflow-x-auto pb-1">
          {CHAT_FILTERS.map((filter) => (
            <button
              key={filter.id}
              type="button"
              onClick={() => setChatFilter(filter.id)}
              className={`shrink-0 rounded-2xl border px-3 py-1.5 text-xs font-semibold transition ${
                chatFilter === filter.id
                  ? 'border-sky-200/80 bg-white text-slate-900 shadow-sm dark:border-white/15 dark:bg-zinc-700/75 dark:text-slate-100'
                  : 'border-white/55 bg-white/42 text-tg-muted hover:bg-white/75 dark:border-white/10 dark:bg-zinc-800/25 dark:hover:bg-zinc-700/45'
              }`}
            >
              {filter.label}
            </button>
          ))}
        </div>
        {userSearchQuery(chatSearch) ? (
          <div className="mt-2">
            {userSearchLoading ? (
              <div className="rounded-2xl border border-white/70 bg-white/52 px-3 py-2 text-sm text-tg-muted dark:border-white/10 dark:bg-zinc-800/35">
                Ищу пользователя…
              </div>
            ) : userResult ? (
              <button
                type="button"
                onClick={() => void openUserSearchResult()}
                disabled={openingUserId === userResult.id}
                className="flex w-full items-center gap-2 rounded-2xl border border-sky-200/70 bg-sky-50/85 px-3 py-2 text-left shadow-sm transition hover:bg-white disabled:opacity-60 dark:border-sky-400/15 dark:bg-zinc-700/45 dark:hover:bg-zinc-700/70"
              >
                <UserAvatar
                  username={chatParticipantLabel(userResult)}
                  avatarUrl={userResult.avatarUrl}
                  size="sm"
                />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                    {chatParticipantLabel(userResult)}
                  </p>
                  <p className="truncate text-xs text-tg-muted">
                    @{userResult.username}
                  </p>
                </div>
                <IconChevronRight className="h-4 w-4 shrink-0 text-tg-muted" />
              </button>
            ) : (
              <div className="rounded-2xl border border-white/70 bg-white/52 px-3 py-2 text-sm text-tg-muted dark:border-white/10 dark:bg-zinc-800/35">
                {userSearchError ?? 'Пользователь не найден'}
              </div>
            )}
          </div>
        ) : null}
      </div>
      <div className="scrollbar-thin min-h-0 flex-1 space-y-1.5 overflow-y-auto px-2 pb-2">
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
              className={`group flex w-full gap-2 rounded-2xl border px-2 py-2 text-left transition-all duration-200 hover:-translate-y-px hover:bg-white/90 hover:shadow-[0_10px_26px_rgba(15,23,42,0.07)] sm:gap-3 sm:px-3 sm:py-2.5 dark:hover:bg-zinc-700/55 ${
                active
                  ? 'border-sky-200/80 bg-white/95 shadow-[0_12px_30px_rgba(14,165,233,0.12)] dark:border-zinc-500/30 dark:bg-zinc-700/45 dark:shadow-[0_8px_18px_rgba(0,0,0,0.12)]'
                  : 'border-transparent bg-white/40 dark:bg-zinc-800/25'
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
                    {c.type === 'channel' && c.verified ? (
                      <VerifiedBadge />
                    ) : null}
                  </span>
                  {last ? (
                    <span className="shrink-0 text-[10px] text-tg-muted sm:text-[11px]">
                      {formatListTime(last.time)}
                    </span>
                  ) : null}
                </div>
                <div className="mt-0.5 flex items-center justify-between gap-1 sm:gap-2">
                  <span className="truncate text-xs text-tg-muted sm:text-sm">
                    {messagePreview(last?.text)}
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
          {user.isAdmin && contextMenu.chat.type === 'channel' ? (
            <button
              type="button"
              className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
              onClick={handleToggleVerified}
            >
              <IconCheck className="h-4 w-4 shrink-0 opacity-70" />
              {contextMenu.chat.verified ? 'Снять галочку' : 'Выдать галочку'}
            </button>
          ) : null}
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
