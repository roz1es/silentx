import { useEffect, useMemo, useState } from 'react';
import type { Chat, Message } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useChatWallpaper } from '@/contexts/ChatWallpaperContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { IconDrawingPin } from '@/components/icons';
import { chatWallpaperClass } from '@/lib/chatWallpaper';
import { useScrollToBottom } from '@/hooks/useScrollToBottom';
import { MessageBubble } from '@/components/MessageBubble';
import { chatParticipantLabel } from '@/lib/userDisplay';

/** Одна галочка — не все прочитали; две — все собеседники видели */
function readReceipt(
  chat: Chat,
  message: Message,
  selfId: string
): 'sent' | 'read' | undefined {
  if (message.senderId !== selfId || message.deleted) return undefined;
  const others = chat.participantIds.filter((id) => id !== selfId);
  if (others.length === 0) return undefined;
  const all = others.every(
    (id) => (chat.lastReadAt?.[id] ?? 0) >= message.createdAt
  );
  return all ? 'read' : 'sent';
}

type Props = {
  onOpenUserProfile?: (userId: string) => void;
};

export function ChatWindow({ onOpenUserProfile }: Props) {
  const { user } = useAuth();
  const { wallpaperId } = useChatWallpaper();
  const wpClass = chatWallpaperClass(wallpaperId);
  const {
    activeChat,
    messages,
    displayMessages,
    messageSearch,
    pinMessage,
    deleteMessage,
    editMessage,
  } = useMessenger();

  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [editDraft, setEditDraft] = useState('');

  useEffect(() => {
    setEditingMessageId(null);
  }, [activeChat?.id]);

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

  const pinnedMessage = useMemo(() => {
    if (!activeChat?.pinnedMessageId) return null;
    return messages.find((m) => m.id === activeChat.pinnedMessageId) ?? null;
  }, [activeChat?.pinnedMessageId, messages]);

  const areaRef = useScrollToBottom<HTMLDivElement>([
    activeChat?.id,
    displayMessages.length,
    activeChat?.lastReadAt,
    messageSearch,
  ]);

  if (!user) return null;

  if (!activeChat) {
    return (
      <div
        className={`${wpClass} flex flex-1 items-center justify-center px-6 text-center`}
      >
        <div>
          <p className="text-lg font-medium text-slate-700 dark:text-slate-200">
            Выберите чат
          </p>
          <p className="mt-2 text-sm text-tg-muted">
            SilentX — как в Telegram: быстро и удобно
          </p>
        </div>
      </div>
    );
  }

  const isGroup =
    activeChat.type === 'group' || activeChat.type === 'channel';

  const pinnedPreview =
    pinnedMessage && !pinnedMessage.deleted
      ? pinnedMessage.text.trim().slice(0, 120) ||
        (pinnedMessage.media?.kind === 'image'
          ? 'Фото'
          : pinnedMessage.media
            ? 'Медиа'
            : 'Сообщение')
      : '';

  return (
    <div
      ref={areaRef}
      className={`${wpClass} scrollbar-thin flex min-h-0 flex-1 flex-col-reverse gap-1 overflow-y-auto px-1 py-2 sm:gap-2 sm:px-2 sm:py-3`}
    >
      {pinnedMessage && pinnedPreview ? (
        <div className="sticky top-0 z-10 mx-auto mb-1 flex w-full max-w-3xl items-start gap-2 rounded-xl border border-amber-200/80 bg-amber-50/95 px-3 py-2 text-sm shadow-sm backdrop-blur-sm dark:border-amber-700/50 dark:bg-amber-950/40">
          <span className="mt-0.5 shrink-0 text-amber-700 dark:text-amber-300" aria-hidden>
            <IconDrawingPin className="h-4 w-4" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-800 dark:text-amber-200">
              Закреплённое
            </p>
            <p className="truncate text-slate-800 dark:text-slate-100">
              {pinnedPreview}
            </p>
          </div>
          <button
            type="button"
            onClick={() => void pinMessage(null)}
            className="shrink-0 rounded-lg px-2 py-1 text-xs text-tg-muted hover:bg-black/5 dark:hover:bg-white/10"
          >
            Снять
          </button>
        </div>
      ) : null}

      {messageSearch.trim() && displayMessages.length === 0 ? (
        <p className="py-8 text-center text-sm text-tg-muted">
          Ничего не найдено
        </p>
      ) : null}

      {[...displayMessages].reverse().map((m) => {
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
              searchQuery={messageSearch}
              onOpenPeerProfile={
                m.senderId !== user.id && onOpenUserProfile
                  ? () => onOpenUserProfile(m.senderId)
                  : undefined
              }
              readReceipt={readReceipt(activeChat, m, user.id)}
              onDelete={
                m.senderId === user.id && !m.deleted
                  ? () => deleteMessage(m.id)
                  : undefined
              }
              onPin={
                !m.deleted
                  ? () =>
                      void pinMessage(
                        activeChat.pinnedMessageId === m.id ? null : m.id
                      )
                  : undefined
              }
              pinActive={activeChat.pinnedMessageId === m.id}
              isEditing={editingMessageId === m.id}
              editDraft={editDraft}
              onEditDraftChange={setEditDraft}
              onStartEdit={
                m.senderId === user.id &&
                !m.deleted &&
                !m.media &&
                !m.imageUrl
                  ? () => {
                      setEditingMessageId(m.id);
                      setEditDraft(m.text);
                    }
                  : undefined
              }
              onCommitEdit={
                m.senderId === user.id &&
                !m.deleted &&
                !m.media &&
                !m.imageUrl
                  ? () => {
                      editMessage(m.id, editDraft);
                      setEditingMessageId(null);
                    }
                  : undefined
              }
              onCancelEdit={
                m.senderId === user.id &&
                !m.deleted &&
                !m.media &&
                !m.imageUrl
                  ? () => setEditingMessageId(null)
                  : undefined
              }
            />
          </div>
        );
      })}
    </div>
  );
}
