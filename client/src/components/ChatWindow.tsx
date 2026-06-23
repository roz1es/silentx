import { useEffect, useMemo, useState, type FormEvent } from 'react';
import type { Chat, Message } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useChatWallpaper } from '@/contexts/ChatWallpaperContext';
import { useMessenger } from '@/contexts/MessengerContext';
import {
  IconClose,
  IconDrawingPin,
  IconLock,
  IconSend,
} from '@/components/icons';
import { chatWallpaperClass } from '@/lib/chatWallpaper';
import { useScrollToBottom } from '@/hooks/useScrollToBottom';
import { MessageBubble } from '@/components/MessageBubble';
import { ForwardMessagesModal } from '@/components/ForwardMessagesModal';
import { chatParticipantLabel } from '@/lib/userDisplay';
import { PhotoViewer } from '@/components/PhotoViewer';

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
    chats,
    activeChat,
    messages,
    displayMessages,
    messageSearch,
    pinMessage,
    deleteMessage,
    setReplyTarget,
    setEditTarget,
    reactToMessage,
    forwardMessages,
    e2eeRecoveryRequired,
    restoreE2ee,
    resetE2ee,
  } = useMessenger();

  const [openPhotoIndex, setOpenPhotoIndex] = useState<number | null>(null);
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [forwardOpen, setForwardOpen] = useState(false);
  const [restoreOpen, setRestoreOpen] = useState(false);
  const [restorePassword, setRestorePassword] = useState('');
  const [restoreError, setRestoreError] = useState('');
  const [restoreBusy, setRestoreBusy] = useState(false);
  const [resetBusy, setResetBusy] = useState(false);
  const [showRestorePassword, setShowRestorePassword] = useState(false);

  useEffect(() => {
    setOpenPhotoIndex(null);
    setSelectionMode(false);
    setSelectedIds(new Set());
    setForwardOpen(false);
  }, [activeChat?.id]);

  useEffect(() => {
    if (!e2eeRecoveryRequired) {
      setRestoreOpen(false);
      setRestorePassword('');
      setRestoreError('');
      setShowRestorePassword(false);
    }
  }, [e2eeRecoveryRequired]);

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

  const messageById = useMemo(() => {
    const map = new Map<string, Message>();
    messages.forEach((m) => map.set(m.id, m));
    return map;
  }, [messages]);

  const photoItems = useMemo(
    () =>
      messages
        .filter((m) => !m.deleted && (m.media?.kind === 'image' || m.imageUrl))
        .map((m) => ({
          id: m.id,
          src: m.media?.kind === 'image' ? m.media.dataUrl : m.imageUrl!,
          createdAt: m.createdAt,
          senderId: m.senderId,
          label:
            m.senderId === user?.id
              ? 'Вы'
              : peerById[m.senderId]
                ? chatParticipantLabel({
                    id: m.senderId,
                    username: peerById[m.senderId].username,
                    displayName: peerById[m.senderId].displayName,
                    avatarUrl: peerById[m.senderId].avatarUrl,
                  })
                : 'Фото',
        })),
    [messages, peerById, user?.id]
  );

  const selectedMessages = useMemo(
    () => messages.filter((m) => selectedIds.has(m.id) && !m.deleted),
    [messages, selectedIds]
  );

  const selectedMineCount = selectedMessages.filter(
    (m) => m.senderId === user?.id
  ).length;
  const selectedHasEncrypted = selectedMessages.some(
    (m) => Boolean(m.encryptedText)
  );

  const toggleSelected = (id: string) => {
    setSelectionMode(true);
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const startForward = (id: string) => {
    setSelectedIds(new Set([id]));
    setSelectionMode(false);
    setForwardOpen(true);
  };

  const clearSelection = () => {
    setSelectionMode(false);
    setSelectedIds(new Set());
  };

  const deleteSelectedMine = () => {
    selectedMessages
      .filter((m) => m.senderId === user?.id)
      .forEach((m) => deleteMessage(m.id));
    clearSelection();
  };

  const forwardSelectedTo = (targetChatId: string) => {
    if (selectedHasEncrypted) return;
    const ids = selectedMessages.map((m) => m.id);
    forwardMessages(ids, targetChatId);
    setForwardOpen(false);
    clearSelection();
  };

  const openPhoto = (src: string) => {
    const idx = photoItems.findIndex((p) => p.src === src);
    setOpenPhotoIndex(idx >= 0 ? idx : null);
  };

  const submitRestore = async (event: FormEvent) => {
    event.preventDefault();
    if (!restorePassword) {
      setRestoreError('Введите пароль от аккаунта');
      return;
    }
    setRestoreBusy(true);
    setRestoreError('');
    try {
      await restoreE2ee(restorePassword);
      setRestorePassword('');
      setRestoreOpen(false);
    } catch (error) {
      setRestoreError(
        error instanceof Error
          ? error.message
          : 'Не удалось восстановить ключ'
      );
    } finally {
      setRestoreBusy(false);
    }
  };

  const submitResetKey = async () => {
    if (!restorePassword) {
      setRestoreError('Введите пароль от аккаунта');
      return;
    }
    const confirmed = window.confirm(
      'Сбросить ключ шифрования? Старые защищённые сообщения, которые не открываются этим ключом, останутся недоступны, но новые сообщения снова будут работать.'
    );
    if (!confirmed) return;
    setResetBusy(true);
    setRestoreError('');
    try {
      await resetE2ee(restorePassword);
      setRestorePassword('');
      setShowRestorePassword(false);
      setRestoreOpen(false);
    } catch (error) {
      setRestoreError(
        error instanceof Error ? error.message : 'Не удалось сбросить ключ'
      );
    } finally {
      setResetBusy(false);
    }
  };

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
        className={`${wpClass} chat-wallpaper-animated flex flex-1 items-center justify-center px-6 text-center`}
      >
        <div>
          <p className="text-lg font-medium text-slate-700 dark:text-slate-200">
            Выберите чат
          </p>
          <p className="mt-2 text-sm text-tg-muted">
            БренксЧат — быстро и удобно
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
    <div className={`${wpClass} chat-wallpaper-animated flex min-h-0 flex-1 flex-col`}>
      {pinnedMessage && pinnedPreview ? (
        <div className="z-10 border-b border-tg-border/70 bg-tg-panel/78 px-2 py-2 shadow-[0_8px_24px_rgba(15,23,42,0.08)] backdrop-blur-xl dark:bg-zinc-800/78 dark:shadow-[0_10px_28px_rgba(0,0,0,0.25)]">
          <div className="mx-auto flex w-full max-w-3xl items-center gap-3 rounded-2xl border border-tg-border/80 bg-white/75 px-3 py-2 text-sm shadow-sm dark:bg-zinc-900/55">
          <span className="shrink-0 text-tg-accent" aria-hidden>
            <IconDrawingPin className="h-4 w-4" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[11px] font-semibold uppercase text-tg-accent">
              Закреплено
            </p>
            <p className="truncate text-slate-800 dark:text-slate-100">
              {pinnedPreview}
            </p>
          </div>
          <button
            type="button"
            onClick={() => void pinMessage(null)}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-900 dark:hover:text-slate-100"
            title="Снять закреп"
          >
            <IconClose className="h-4 w-4" />
          </button>
          </div>
        </div>
      ) : null}

      {selectionMode ? (
        <div className="z-20 border-b border-tg-border/70 bg-tg-panel/86 px-2 py-2 shadow-[0_8px_24px_rgba(15,23,42,0.08)] backdrop-blur-xl dark:bg-zinc-800/86">
          <div className="mx-auto flex w-full max-w-3xl items-center gap-2">
            <button
              type="button"
              onClick={clearSelection}
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-900 dark:hover:text-slate-100"
              title="Закрыть выбор"
            >
              <IconClose className="h-4 w-4" />
            </button>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                Выбрано: {selectedMessages.length}
              </p>
              <p className="truncate text-xs text-tg-muted">
                Можно переслать пачкой или удалить свои сообщения
              </p>
            </div>
            <button
              type="button"
              onClick={() => setForwardOpen(true)}
              disabled={
                selectedMessages.length === 0 || selectedHasEncrypted
              }
              className="inline-flex h-9 items-center gap-1.5 rounded-full bg-tg-accent px-3 text-sm font-semibold text-white shadow-sm transition hover:brightness-105 disabled:opacity-40"
              title={
                selectedHasEncrypted
                  ? 'Пересылка защищённых сообщений появится позже'
                  : 'Переслать'
              }
            >
              <IconSend className="h-4 w-4" />
              Переслать
            </button>
            <button
              type="button"
              disabled={selectedMineCount === 0}
              onClick={deleteSelectedMine}
              className="h-9 rounded-full bg-red-500/10 px-3 text-sm font-semibold text-red-600 transition hover:bg-red-500/15 disabled:opacity-40 dark:text-red-400"
            >
              Удалить мои
            </button>
          </div>
        </div>
      ) : null}

      {e2eeRecoveryRequired ? (
        <div className="z-20 border-b border-tg-border/60 bg-white/68 px-2 py-2 shadow-[0_10px_26px_rgba(15,23,42,0.08)] backdrop-blur-2xl dark:bg-zinc-800/70 dark:shadow-[0_14px_34px_rgba(0,0,0,0.24)]">
          <div className="mx-auto flex w-full max-w-3xl items-center gap-3 rounded-2xl border border-tg-border/70 bg-white/72 px-3 py-2.5 text-sm shadow-sm dark:bg-zinc-900/52">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-amber-400/15 text-amber-600 dark:text-amber-300">
              <IconLock className="h-4 w-4" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="font-semibold text-slate-900 dark:text-slate-100">
                Нужно восстановить ключ
              </p>
              <p className="text-xs text-tg-muted">
                Введите пароль один раз, чтобы открыть защищённые сообщения.
              </p>
            </div>
            <button
              type="button"
              onClick={() => setRestoreOpen(true)}
              className="h-9 shrink-0 rounded-full bg-tg-accent px-4 text-sm font-semibold text-white shadow-sm transition hover:brightness-105"
            >
              Восстановить
            </button>
          </div>
        </div>
      ) : null}

      <div
        ref={areaRef}
        className="scrollbar-thin flex min-h-0 flex-1 flex-col-reverse gap-2 overflow-y-auto px-1 py-2 sm:px-2 sm:py-3"
      >
        {messageSearch.trim() && displayMessages.length === 0 ? (
          <p className="py-8 text-center text-sm text-tg-muted">
            Ничего не найдено
          </p>
        ) : null}

        {[...displayMessages]
          .filter((m) => !m.deleted)
          .reverse()
          .map((m) => {
          const sender = peerById[m.senderId];
          const peerLabel = sender
            ? chatParticipantLabel({
                id: m.senderId,
                username: sender.username,
                displayName: sender.displayName,
                avatarUrl: sender.avatarUrl,
              })
            : m.senderId;
          const replyTo = m.replyToMessageId
            ? messageById.get(m.replyToMessageId) ?? null
            : null;
          const replySender = replyTo ? peerById[replyTo.senderId] : null;
          const replyLabel = replyTo
            ? replyTo.senderId === user.id
              ? 'Вы'
              : replySender
                ? chatParticipantLabel({
                    id: replyTo.senderId,
                    username: replySender.username,
                    displayName: replySender.displayName,
                    avatarUrl: replySender.avatarUrl,
                  })
                : 'Ответ'
            : undefined;
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
                replyTo={replyTo}
                replyLabel={replyLabel}
                onReply={
                  !m.deleted
                    ? () => {
                        setEditTarget(null);
                        setReplyTarget(m);
                      }
                    : undefined
                }
                onForward={
                  !m.deleted && !m.encryptedText
                    ? () => startForward(m.id)
                    : undefined
                }
                onSelect={!m.deleted ? () => toggleSelected(m.id) : undefined}
                onReact={!m.deleted ? (emoji) => reactToMessage(m.id, emoji) : undefined}
                onOpenImage={openPhoto}
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
                onStartEdit={
                  m.senderId === user.id &&
                  !m.deleted &&
                  !m.media &&
                  !m.imageUrl
                    ? () => {
                        setReplyTarget(null);
                        setEditTarget(m);
                      }
                    : undefined
                }
                selecting={selectionMode}
                selected={selectedIds.has(m.id)}
              />
            </div>
          );
        })}
      </div>
      <PhotoViewer
        items={photoItems}
        index={openPhotoIndex}
        onIndexChange={setOpenPhotoIndex}
      />
      <ForwardMessagesModal
        open={forwardOpen}
        chats={chats}
        selfId={user.id}
        count={selectedMessages.length}
        onClose={() => setForwardOpen(false)}
        onPick={forwardSelectedTo}
      />
      {restoreOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/28 px-4 backdrop-blur-md dark:bg-black/42">
          <form
            onSubmit={submitRestore}
            className="w-full max-w-sm rounded-[2rem] border border-white/26 bg-white/78 p-5 shadow-[0_24px_80px_rgba(15,23,42,0.24)] backdrop-blur-2xl dark:border-white/10 dark:bg-zinc-900/76"
          >
            <div className="mb-4 flex items-start gap-3">
              <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-amber-400/16 text-amber-600 dark:text-amber-300">
                <IconLock className="h-5 w-5" />
              </span>
              <div className="min-w-0 flex-1">
                <h3 className="text-lg font-semibold text-slate-950 dark:text-white">
                  Восстановление ключа
                </h3>
                <p className="mt-1 text-sm leading-snug text-tg-muted">
                  Пароль нужен только на этом устройстве и не сохраняется.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setRestoreOpen(false)}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-900 dark:hover:text-white"
                title="Закрыть"
              >
                <IconClose className="h-4 w-4" />
              </button>
            </div>
            <label className="block text-sm font-medium text-slate-700 dark:text-slate-200">
              Пароль от аккаунта
              <div className="mt-2 flex h-12 overflow-hidden rounded-2xl border border-tg-border/80 bg-white/86 transition focus-within:border-tg-accent/70 focus-within:ring-4 focus-within:ring-tg-accent/12 dark:bg-zinc-950/48">
                <input
                  type={showRestorePassword ? 'text' : 'password'}
                  value={restorePassword}
                  onChange={(event) => {
                    setRestorePassword(event.target.value);
                    setRestoreError('');
                  }}
                  autoFocus
                  autoComplete="current-password"
                  className="min-w-0 flex-1 bg-transparent px-4 text-base text-slate-950 outline-none dark:text-white"
                  placeholder="Введите пароль"
                />
                <button
                  type="button"
                  onClick={() => setShowRestorePassword((value) => !value)}
                  className="shrink-0 px-4 text-sm font-semibold text-tg-muted transition hover:bg-tg-hover hover:text-slate-900 dark:hover:text-white"
                >
                  {showRestorePassword ? 'Скрыть' : 'Показать'}
                </button>
              </div>
            </label>
            {restoreError ? (
              <p className="mt-3 rounded-2xl border border-red-500/18 bg-red-500/10 px-3 py-2 text-sm text-red-600 dark:text-red-300">
                {restoreError}
              </p>
            ) : null}
            <button
              type="submit"
              disabled={restoreBusy || resetBusy}
              className="mt-4 h-12 w-full rounded-2xl bg-tg-accent text-sm font-semibold text-white shadow-sm transition hover:brightness-105 disabled:cursor-wait disabled:opacity-60"
            >
              {restoreBusy ? 'Восстановление...' : 'Восстановить сообщения'}
            </button>
            {restoreError ? (
              <button
                type="button"
                disabled={restoreBusy || resetBusy}
                onClick={submitResetKey}
                className="mt-2 h-11 w-full rounded-2xl border border-tg-border/70 bg-white/42 text-sm font-semibold text-slate-700 transition hover:bg-white/70 disabled:cursor-wait disabled:opacity-60 dark:bg-white/6 dark:text-slate-200 dark:hover:bg-white/10"
              >
                {resetBusy ? 'Сбрасываю ключ...' : 'Сбросить ключ для новых сообщений'}
              </button>
            ) : null}
          </form>
        </div>
      ) : null}
    </div>
  );
}
