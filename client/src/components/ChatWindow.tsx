import { useMemo } from 'react';
import type { Chat, Message } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { useScrollToBottom } from '@/hooks/useScrollToBottom';
import { MessageBubble } from '@/components/MessageBubble';
import { chatParticipantLabel } from '@/lib/userDisplay';

function readLabel(
  chat: Chat,
  message: Message,
  selfId: string
): string | undefined {
  if (message.senderId !== selfId || message.deleted) return undefined;
  const others = chat.participantIds.filter((id) => id !== selfId);
  if (others.length === 0) return 'просмотрено';
  const all = others.every(
    (id) => (chat.lastReadAt?.[id] ?? 0) >= message.createdAt
  );
  return all ? 'просмотрено' : undefined;
}

type Props = {
  onOpenUserProfile?: (userId: string) => void;
};

export function ChatWindow({ onOpenUserProfile }: Props) {
  const { user } = useAuth();
  const { activeChat, messages, deleteMessage } = useMessenger();

  const peerById = useMemo(() => {
    const map: Record<
      string,
      { username: string; displayName?: string; avatarUrl?: string }
    > = {};
    if (!activeChat) return map;
    activeChat.participants?.forEach((p) => {
      map[p.id] = {
        username: p.username,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
      };
    });
    activeChat.participantIds.forEach((id) => {
      if (!map[id]) map[id] = { username: 'User' };
    });
    return map;
  }, [activeChat]);

  const selfInfo = useMemo(() => {
    if (!user) return { username: 'User' };
    return {
      username: user.username,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
    };
  }, [user]);

  const areaRef = useScrollToBottom<HTMLDivElement>([
    activeChat?.id,
    messages.length,
    activeChat?.lastReadAt,
  ]);

  if (!user) return null;

  if (!activeChat) {
    return (
      <div className="chat-bg flex flex-1 items-center justify-center px-6 text-center">
        <div>
          <p className="text-lg font-medium text-slate-700 dark:text-slate-200">
            Выберите чат
          </p>
          <p className="mt-2 text-sm text-tg-muted">
            Silentix — личные и групповые беседы
          </p>
        </div>
      </div>
    );
  }

  const isGroup = activeChat.type === 'group';

  return (
    <div
      ref={areaRef}
      className="chat-bg scrollbar-thin flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-3 py-4"
    >
      {messages.map((m) => {
        const sender = peerById[m.senderId];
        const peerLabel = sender
          ? chatParticipantLabel({
              id: m.senderId,
              username: sender.username,
              displayName: sender.displayName,
              avatarUrl: sender.avatarUrl,
            })
          : m.senderId;
        return (
          <div key={m.id} className="flex w-full flex-col gap-1">
            <MessageBubble
              message={m}
              self={user}
              isGroup={isGroup}
              sender={sender}
              peerLabel={peerLabel}
              selfInfo={selfInfo}
              onOpenPeerProfile={
                m.senderId !== user.id && onOpenUserProfile
                  ? () => onOpenUserProfile(m.senderId)
                  : undefined
              }
              readLabel={readLabel(activeChat, m, user.id)}
              onDelete={
                m.senderId === user.id && !m.deleted
                  ? () => deleteMessage(m.id)
                  : undefined
              }
            />
          </div>
        );
      })}
    </div>
  );
}
