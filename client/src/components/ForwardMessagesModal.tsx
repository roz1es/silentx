import { useMemo, useState } from 'react';
import type { Chat } from '@/types';
import { IconClose, IconSearch } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { chatParticipantLabel } from '@/lib/userDisplay';

type Props = {
  open: boolean;
  chats: Chat[];
  selfId: string;
  count: number;
  onClose: () => void;
  onPick: (chatId: string) => void;
};

function chatTitle(chat: Chat, selfId: string): string {
  if (chat.displayName) return chat.displayName;
  if (chat.type === 'group' || chat.type === 'channel') return chat.name;
  const other = chat.participants?.find((p) => p.id !== selfId);
  return other ? chatParticipantLabel(other) : chat.name || 'Чат';
}

function chatAvatar(chat: Chat, selfId: string) {
  if (chat.type === 'group' || chat.type === 'channel') {
    return { username: chatTitle(chat, selfId), avatarUrl: chat.avatarUrl };
  }
  const other = chat.participants?.find((p) => p.id !== selfId);
  return {
    username: other ? chatParticipantLabel(other) : chatTitle(chat, selfId),
    avatarUrl: other?.avatarUrl,
  };
}

function writable(chat: Chat, selfId: string): boolean {
  return chat.type !== 'channel' || chat.channelOwnerId === selfId;
}

export function ForwardMessagesModal({
  open,
  chats,
  selfId,
  count,
  onClose,
  onPick,
}: Props) {
  const [query, setQuery] = useState('');

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return chats
      .filter((chat) => writable(chat, selfId))
      .filter((chat) => {
        if (!q) return true;
        if (chatTitle(chat, selfId).toLowerCase().includes(q)) return true;
        return (
          chat.participants?.some((p) =>
            `${p.username} ${p.displayName ?? ''}`.toLowerCase().includes(q)
          ) ?? false
        );
      });
  }, [chats, query, selfId]);

  if (!open) return null;

  return (
    <div
      className="brenks-modal-backdrop fixed inset-0 z-[10030] flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="brenks-modal-panel flex max-h-[min(78dvh,590px)] w-full max-w-[26rem] flex-col overflow-hidden rounded-[1.8rem]">
        <div className="flex items-start justify-between gap-3 px-5 pb-3 pt-5">
          <div>
            <h2 className="text-[1.35rem] font-semibold leading-tight text-slate-900 dark:text-slate-100">
              Переслать
            </h2>
            <p className="mt-1 text-sm text-tg-muted">
              {count === 1 ? 'Выберите чат' : `Сообщений: ${count}`}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-white/45 bg-white/35 text-tg-muted shadow-sm backdrop-blur-xl transition hover:bg-white/55 hover:text-slate-900 dark:border-white/10 dark:bg-white/8 dark:hover:bg-white/12 dark:hover:text-slate-100"
            title="Закрыть"
          >
            <IconClose className="h-4 w-4" />
          </button>
        </div>
        <div className="px-5 pb-3">
          <div className="brenks-modal-field relative rounded-[1.35rem]">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-tg-muted">
              <IconSearch className="h-4 w-4" />
            </span>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Поиск чата"
              className="brenks-modal-input w-full bg-transparent py-3 pl-10 pr-3 text-sm outline-none"
            />
          </div>
        </div>
        <div className="brenks-modal-scroll scrollbar-thin mx-2 mb-2 min-h-0 flex-1 overflow-y-auto rounded-[1.35rem] p-1.5">
          {filtered.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-tg-muted">
              Нет подходящих чатов
            </p>
          ) : (
            filtered.map((chat) => {
              const av = chatAvatar(chat, selfId);
              return (
                <button
                  key={chat.id}
                  type="button"
                  onClick={() => onPick(chat.id)}
                  className="brenks-modal-row flex w-full items-center gap-3 rounded-[1.25rem] px-3 py-2.5 text-left transition duration-200"
                >
                  <UserAvatar
                    username={av.username}
                    avatarUrl={av.avatarUrl}
                    size="md"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-semibold">
                      {chatTitle(chat, selfId)}
                    </p>
                    <p className="truncate text-xs text-tg-muted">
                      {chat.type === 'channel'
                        ? 'Канал'
                        : chat.type === 'group'
                          ? 'Группа'
                          : 'Личный чат'}
                    </p>
                  </div>
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
