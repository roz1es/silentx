import { useMemo } from 'react';
import type { Chat } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
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
  if (chat.type === 'group') return chat.name;
  const other = chat.participantIds.find((id) => id !== selfId);
  return other ?? chat.name;
}

function listAvatarProps(
  chat: Chat,
  selfId: string
): { username: string; avatarUrl?: string } {
  const name = label(chat, selfId);
  if (chat.type === 'group') {
    return { username: name, avatarUrl: undefined };
  }
  const other = chat.participants?.find((p) => p.id !== selfId);
  return {
    username: other ? chatParticipantLabel(other) : name,
    avatarUrl: other?.avatarUrl,
  };
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
  } = useMessenger();

  const filtered = useMemo(() => {
    const q = chatSearch.trim().toLowerCase();
    if (!q) return chats;
    return chats.filter((c) => label(c, user.id).toLowerCase().includes(q));
  }, [chats, chatSearch, user.id]);

  const sorted = useMemo(() => {
    return [...filtered].sort((a, b) => {
      const ta = a.lastMessage?.time ?? 0;
      const tb = b.lastMessage?.time ?? 0;
      return tb - ta;
    });
  }, [filtered]);

  return (
    <div className="flex h-full min-h-0 flex-col border-r border-tg-border bg-tg-panel">
      <div className="shrink-0 p-3">
        <div className="relative">
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-tg-muted">
            🔍
          </span>
          <input
            value={chatSearch}
            onChange={(e) => setChatSearch(e.target.value)}
            placeholder="Поиск"
            className="w-full rounded-xl border border-tg-border bg-tg-hover py-2 pl-9 pr-3 text-sm outline-none ring-tg-accent/30 focus:ring-2 dark:bg-slate-900/30"
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
              className={`flex w-full gap-3 border-b border-tg-border/60 px-3 py-2.5 text-left transition hover:bg-tg-hover ${
                active ? 'bg-tg-hover/80' : ''
              }`}
            >
              <UserAvatar
                username={av.username}
                avatarUrl={av.avatarUrl}
                size="md"
                className="shadow-inner"
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="truncate font-medium text-slate-900 dark:text-slate-100">
                    {label(c, user.id)}
                  </span>
                  {last ? (
                    <span className="shrink-0 text-[11px] text-tg-muted">
                      {formatListTime(last.time)}
                    </span>
                  ) : null}
                </div>
                <div className="mt-0.5 flex items-center justify-between gap-2">
                  <span className="truncate text-sm text-tg-muted">
                    {last?.text ?? 'Нет сообщений'}
                  </span>
                  {unread > 0 ? (
                    <span className="flex h-5 min-w-[1.25rem] shrink-0 items-center justify-center rounded-full bg-tg-accent px-1.5 text-[11px] font-semibold text-white">
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
    </div>
  );
}
