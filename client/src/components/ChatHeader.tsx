import { useMemo } from 'react';
import type { Chat } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { UserAvatar } from '@/components/UserAvatar';
import { chatParticipantLabel } from '@/lib/userDisplay';

function titleFor(chat: Chat | null, selfId: string): string {
  if (!chat) return 'Silentix';
  if (chat.displayName) return chat.displayName;
  if (chat.type === 'group') return chat.name;
  const other = chat.participantIds.find((id) => id !== selfId);
  return other ?? chat.name;
}

function avatarForChat(
  chat: Chat | null,
  selfId: string
): { username: string; avatarUrl?: string } | null {
  if (!chat) return null;
  const parts = chat.participants ?? [];
  if (chat.type === 'group') {
    return { username: chat.name, avatarUrl: undefined };
  }
  const other = parts.find((p) => p.id !== selfId);
  if (other)
    return {
      username: chatParticipantLabel(other),
      avatarUrl: other.avatarUrl,
    };
  return { username: titleFor(chat, selfId), avatarUrl: undefined };
}

type Props = {
  onGroupInfo?: () => void;
  onPeerProfile?: () => void;
};

export function ChatHeader({ onGroupInfo, onPeerProfile }: Props) {
  const { user } = useAuth();
  if (!user) return null;
  const { activeChat, onlineUserIds, typingNames } = useMessenger();

  const heading = useMemo(
    () => titleFor(activeChat, user.id),
    [activeChat, user.id]
  );

  const av = useMemo(
    () => avatarForChat(activeChat, user.id),
    [activeChat, user.id]
  );

  const otherOnline = useMemo(() => {
    if (!activeChat || activeChat.type === 'group') {
      const inChat = activeChat?.participantIds ?? [];
      return inChat.some((id) => id !== user.id && onlineUserIds.includes(id));
    }
    const other = activeChat.participantIds.find((id) => id !== user.id);
    return other ? onlineUserIds.includes(other) : false;
  }, [activeChat, onlineUserIds, user.id]);

  const typingEntries = Object.entries(typingNames);

  const status = useMemo(() => {
    if (typingEntries.length === 1) {
      return `${typingEntries[0][1]} печатает…`;
    }
    if (typingEntries.length > 1) {
      return `${typingEntries.map(([, n]) => n).join(', ')} печатают…`;
    }
    if (!activeChat) return '';
    if (otherOnline) return 'в сети';
    return 'не в сети';
  }, [typingEntries, activeChat, otherOnline]);

  const titleEl =
    activeChat?.type === 'group' && onGroupInfo ? (
      <button
        type="button"
        onClick={onGroupInfo}
        className="truncate text-left text-base font-semibold text-slate-900 hover:underline dark:text-slate-100"
      >
        {heading}
      </button>
    ) : (
      <h1 className="truncate text-base font-semibold text-slate-900 dark:text-slate-100">
        {heading}
      </h1>
    );

  const directAvatar =
    activeChat && activeChat.type !== 'group' && onPeerProfile ? (
      <button
        type="button"
        onClick={onPeerProfile}
        title="Профиль"
        className="hidden shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-tg-accent/50 sm:flex"
      >
        {av ? (
          <UserAvatar
            username={av.username}
            avatarUrl={av.avatarUrl}
            size="sm"
          />
        ) : null}
      </button>
    ) : activeChat && activeChat.type !== 'group' && av ? (
      <UserAvatar
        username={av.username}
        avatarUrl={av.avatarUrl}
        size="sm"
        className="hidden sm:flex"
      />
    ) : null;

  return (
    <header className="flex h-14 shrink-0 items-center gap-3 border-b border-tg-border bg-tg-panel px-2 pl-3 shadow-sm md:px-4">
      {activeChat?.type === 'group' ? (
        <div className="hidden h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-violet-500/90 to-tg-accent text-sm font-bold text-white sm:flex">
          {heading.slice(0, 1).toUpperCase()}
        </div>
      ) : (
        directAvatar
      )}
      <div className="flex min-w-0 flex-1 flex-col justify-center">
        {titleEl}
        {activeChat ? (
          <p className="truncate text-[11px] text-tg-muted sm:text-xs">{status}</p>
        ) : null}
      </div>
      <div
        className={`h-2.5 w-2.5 shrink-0 rounded-full ${
          typingEntries.length > 0
            ? 'bg-amber-400'
            : otherOnline
              ? 'bg-emerald-500'
              : 'bg-slate-400'
        }`}
        title={typingEntries.length ? 'Печатает' : otherOnline ? 'Онлайн' : 'Оффлайн'}
      />
    </header>
  );
}
